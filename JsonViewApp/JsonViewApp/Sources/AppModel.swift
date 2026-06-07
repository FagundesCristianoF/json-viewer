import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {

    // MARK: - Workspace

    @Published var workspaceRoot: URL? = nil
    @Published var workspaceFiles: [WorkspaceFile] = []

    // MARK: - Current file

    @Published var selectedFile: URL? = nil
    @Published var editorText: String = "" {
        didSet { isDirty = true }
    }
    @Published var isDirty: Bool = false

    // MARK: - Parse state

    @Published var parseResult: ParseHandle? = nil
    @Published var parseError: ParseErrorInfo? = nil
    @Published var treeNodes: [NodeInfo] = []
    @Published var smells: [SmellInfo] = []

    // MARK: - JSONPath

    @Published var jsonPathQuery: String = ""
    @Published var jsonPathMatches: Set<Int> = []
    @Published var jsonPathError: String? = nil

    // MARK: - UI state

    @Published var expandedNodes: Set<Int> = []
    @Published var darkMode: Bool = UserDefaults.standard.bool(forKey: "darkMode") {
        didSet { UserDefaults.standard.set(darkMode, forKey: "darkMode") }
    }
    @Published var autoSave: Bool = true
    @Published var indentSize: Int = 2
    @Published var toast: String? = nil
    @Published var showFind: Bool = false
    @Published var foldRanges: [FoldRange] = []
    @Published var foldedLines: Set<Int> = []

    // MARK: - Panel visibility

    @Published var showSidebar: Bool = true
    @Published var showTree: Bool = true
    @Published var showIssues: Bool = false

    // MARK: - Compose

    @Published var isRawMode: Bool = false
    @Published var resolvedCompose: String? = nil

    // MARK: - Issues tab

    enum IssuesTab { case syntax, smells, history, keys }
    @Published var issuesTab: IssuesTab = .syntax

    // MARK: - Git history

    @Published var gitHistory: [CommitInfo] = []

    // MARK: - Toast timer

    private var toastTask: Task<Void, Never>? = nil
    nonisolated(unsafe) private var foldObserver: NSObjectProtocol? = nil

    // MARK: - Init

    init() {
        // Restore workspace
        if let path = UserDefaults.standard.string(forKey: "workspaceRoot") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                let tree = Self.buildFileTree(url: url)
                workspaceRoot = url
                workspaceFiles = tree
            }
        }

        // Listen for fold toggle from gutter
        foldObserver = NotificationCenter.default.addObserver(
            forName: .jsonViewToggleFold,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let line = note.userInfo?["line"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.foldedLines.contains(line) {
                    self.foldedLines.remove(line)
                } else {
                    self.foldedLines.insert(line)
                }
            }
        }
    }

    // MARK: - Workspace

    func openWorkspace(_ url: URL) {
        workspaceRoot = url
        workspaceFiles = Self.buildFileTree(url: url)
        UserDefaults.standard.set(url.path, forKey: "workspaceRoot")
    }

    private static func buildFileTree(url: URL) -> [WorkspaceFile] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { child -> WorkspaceFile? in
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDir {
                    return WorkspaceFile(
                        url: child,
                        name: child.lastPathComponent,
                        isDirectory: true,
                        children: buildFileTree(url: child)
                    )
                }
                guard child.pathExtension.lowercased() == "json" else { return nil }
                return WorkspaceFile(url: child, name: child.lastPathComponent, isDirectory: false, children: [])
            }
    }

    // MARK: - File selection

    func selectFile(_ url: URL) {
        updateParseResult(nil)

        selectedFile = url
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Suppress dirty flag on load
            editorText = text
            isDirty = false
            reparse()
            loadGitHistory()
        } catch {
            showToast("Failed to read file: \(error.localizedDescription)")
        }
    }

    // MARK: - Parse

    func reparse() {
        let rawText = editorText

        // Always resolve compose when workspace available (needed to show/hide toggle)
        if let dir = workspaceRoot?.path {
            resolvedCompose = RustBridge.compose(rawText, dir: dir, indent: indentSize)
        } else {
            resolvedCompose = nil
        }

        // Parse the text that is currently visible in the editor
        let activeText = (!isRawMode && resolvedCompose != nil) ? resolvedCompose! : rawText
        let handle = RustBridge.parseHandle(activeText)
        updateParseResult(handle)

        if let err = handle.error {
            // Only surface raw-mode errors as parse errors; result errors are shown differently
            parseError = isRawMode ? err : nil
            treeNodes = []
            smells = []
        } else {
            parseError = nil
            treeNodes = handle.nodes
            smells = RustBridge.smells(handle)
        }

        // Re-run JSONPath if active
        if !jsonPathQuery.isEmpty {
            runJsonPath()
        }

        // Update fold ranges from the active text
        foldRanges = RustBridge.foldRanges(activeText)
    }

    // MARK: - Save

    func save() {
        guard let url = selectedFile else { return }
        do {
            try editorText.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            showToast("Saved")
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Transforms

    func format() {
        guard let formatted = RustBridge.format(editorText, indent: indentSize) else {
            showToast("Format failed — invalid JSON")
            return
        }
        applyTransform(formatted)
    }

    func minify() {
        guard let minified = RustBridge.minify(editorText) else {
            showToast("Minify failed — invalid JSON")
            return
        }
        applyTransform(minified)
    }

    func removeNulls() {
        guard let cleaned = RustBridge.removeNulls(editorText, indent: indentSize) else {
            showToast("Remove nulls failed — invalid JSON")
            return
        }
        applyTransform(cleaned)
    }

    private func applyTransform(_ newText: String) {
        foldedLines = []        // clear folds — line positions change after transform
        isRawMode = true        // switch to raw so result is immediately visible
        editorText = newText
        reparse()
        if autoSave { save() }
    }

    // MARK: - JSONPath

    func runJsonPath() {
        let query = jsonPathQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            jsonPathMatches = []
            jsonPathError = nil
            return
        }
        guard let handle = parseResult, handle.error == nil else {
            jsonPathError = "Cannot run query — document has parse errors"
            jsonPathMatches = []
            return
        }
        let ids = RustBridge.jsonPath(handle, query: query)
        if ids.isEmpty {
            jsonPathError = "No matches"
            jsonPathMatches = []
        } else {
            jsonPathError = nil
            jsonPathMatches = Set(ids)
        }
    }

    // MARK: - Compose

    func resolveCompose() {
        guard let dir = workspaceRoot?.path else {
            showToast("Open a workspace folder first")
            return
        }
        if let result = RustBridge.compose(editorText, dir: dir, indent: indentSize) {
            resolvedCompose = result
        } else {
            showToast("Compose resolve failed")
        }
    }

    // MARK: - Git history

    private func loadGitHistory() {
        guard let path = selectedFile?.path else { return }
        Task {
            let commits = RustBridge.gitHistory(path)
            await MainActor.run { self.gitHistory = commits }
        }
    }

    // MARK: - Toast

    func showToast(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                toast = nil
            }
        }
    }

    // MARK: - Cleanup

    // Nonisolated storage so deinit can free without crossing actor boundary.
    nonisolated(unsafe) private var _handleForCleanup: ParseHandle? = nil

    private func updateParseResult(_ h: ParseHandle?) {
        _handleForCleanup?.free()
        parseResult = h
        _handleForCleanup = h
    }

    deinit {
        _handleForCleanup?.free()
        if let obs = foldObserver { NotificationCenter.default.removeObserver(obs) }
    }
}
