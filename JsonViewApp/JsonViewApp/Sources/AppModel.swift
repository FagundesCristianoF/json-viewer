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

    // MARK: - Sidebar rename state
    @Published var renamingFileURL: URL? = nil
    @Published var renameText: String = ""

    // MARK: - UI state

    @Published var expandedNodes: Set<Int> = []
    /// Toolbar toggle: flips between .light and .dark (does not affect .system preference).
    var darkMode: Bool {
        get { Preferences.shared.theme == .dark }
        set { Preferences.shared.theme = newValue ? .dark : .light }
    }
    @Published var autoSave: Bool = Preferences.shared.autoSave {
        didSet { Preferences.shared.autoSave = autoSave }
    }
    @Published var formatOnSave: Bool = Preferences.shared.formatOnSave {
        didSet { Preferences.shared.formatOnSave = formatOnSave }
    }
    @Published var formatOnPaste: Bool = Preferences.shared.formatOnPaste {
        didSet { Preferences.shared.formatOnPaste = formatOnPaste }
    }
    @Published var indentSize: Int = Preferences.shared.indentSize {
        didSet { Preferences.shared.indentSize = indentSize }
    }
    @Published var editorFontSize: Double = Preferences.shared.editorFontSize {
        didSet { Preferences.shared.editorFontSize = editorFontSize }
    }
    @Published var uiFontSize: Double = Preferences.shared.uiFontSize {
        didSet { Preferences.shared.uiFontSize = uiFontSize }
    }
    @Published var toast: String? = nil
    @Published var showFind: Bool = false
    @Published var foldRanges: [FoldRange] = []
    @Published var foldedLines: Set<Int> = []
    var pendingUndoableTransform: Bool = false

    // MARK: - Panel visibility

    @Published var showSidebar: Bool = true
    @Published var showTree: Bool = true
    @Published var showIssues: Bool = false

    // MARK: - Compose

    @Published var isRawMode: Bool = false {
        didSet { if oldValue != isRawMode { reparse() } }
    }
    @Published var resolvedCompose: String? = nil

    var isComposeTemplate: Bool { editorText.contains("{{") }

    // MARK: - Capabilities

    var hasFile: Bool { selectedFile != nil }
    var canFormat: Bool { hasFile }
    var canMinify: Bool { hasFile }
    var canRemoveNulls: Bool { hasFile }

    // MARK: - Key Inspector

    @Published var parentKeyQuery: String = ""
    @Published var parentKeyResults: [(key: String, count: Int)] = []

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
                let order = Self.loadFileOrder()
                let tree = Self.buildFileTree(url: url, order: order)
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
        workspaceFiles = Self.buildFileTree(url: url, order: Self.loadFileOrder())
        UserDefaults.standard.set(url.path, forKey: "workspaceRoot")
    }

    // MARK: - File move / reorder

    func moveFile(from source: URL, to targetDir: URL) {
        guard source.deletingLastPathComponent().path != targetDir.path else { return }
        let dest = targetDir.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: source, to: dest)
            let wasSelected = selectedFile == source
            if let root = workspaceRoot { openWorkspace(root) }
            if wasSelected { selectFile(dest) }
        } catch {
            showToast("Move failed: \(error.localizedDescription)")
        }
    }

    func persistFileOrder(for directory: URL, names: [String]) {
        var order = Self.loadFileOrder()
        order[directory.path] = names
        UserDefaults.standard.set(order, forKey: "workspaceFileOrder")
    }

    func filesInDirectory(_ dir: URL) -> [WorkspaceFile] {
        if dir == workspaceRoot { return workspaceFiles }
        return findFilesInDirectory(dir, from: workspaceFiles)
    }

    private func findFilesInDirectory(_ dir: URL, from files: [WorkspaceFile]) -> [WorkspaceFile] {
        for file in files {
            if file.url == dir { return file.children }
            if file.isDirectory {
                let found = findFilesInDirectory(dir, from: file.children)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    func reorderToFirst(sourceURL: URL, in directory: URL, currentFiles: [WorkspaceFile]) {
        var updated = currentFiles
        guard let idx = updated.firstIndex(where: { $0.url == sourceURL }) else { return }
        let item = updated.remove(at: idx)
        updated.insert(item, at: 0)
        reorderChildren(in: directory, to: updated)
    }

    func reorderAfter(sourceURL: URL, afterURL: URL, in directory: URL, currentFiles: [WorkspaceFile]) {
        var updated = currentFiles
        guard let srcIdx = updated.firstIndex(where: { $0.url == sourceURL }) else { return }
        let item = updated.remove(at: srcIdx)
        if let newTgtIdx = updated.firstIndex(where: { $0.url == afterURL }) {
            updated.insert(item, at: min(newTgtIdx + 1, updated.endIndex))
        } else {
            updated.append(item)
        }
        reorderChildren(in: directory, to: updated)
    }

    func reorderChildren(in directoryURL: URL, to newFiles: [WorkspaceFile]) {
        if workspaceRoot == directoryURL {
            workspaceFiles = newFiles
        } else {
            reorderInTree(files: &workspaceFiles, directoryURL: directoryURL, newFiles: newFiles)
        }
        persistFileOrder(for: directoryURL, names: newFiles.map(\.name))
    }

    private func reorderInTree(files: inout [WorkspaceFile], directoryURL: URL, newFiles: [WorkspaceFile]) {
        for i in files.indices {
            if files[i].url == directoryURL {
                files[i].children = newFiles
                return
            }
            if files[i].isDirectory {
                reorderInTree(files: &files[i].children, directoryURL: directoryURL, newFiles: newFiles)
            }
        }
    }

    private static func loadFileOrder() -> [String: [String]] {
        (UserDefaults.standard.dictionary(forKey: "workspaceFileOrder") as? [String: [String]]) ?? [:]
    }

    private static func buildFileTree(url: URL, order: [String: [String]] = [:]) -> [WorkspaceFile] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let items = contents
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { child -> WorkspaceFile? in
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDir {
                    return WorkspaceFile(
                        url: child,
                        name: child.lastPathComponent,
                        isDirectory: true,
                        children: buildFileTree(url: child, order: order)
                    )
                }
                guard child.pathExtension.lowercased() == "json" else { return nil }
                return WorkspaceFile(url: child, name: child.lastPathComponent, isDirectory: false, children: [])
            }

        if let savedNames = order[url.path] {
            var ordered: [WorkspaceFile] = []
            for name in savedNames {
                if let item = items.first(where: { $0.name == name }) { ordered.append(item) }
            }
            let seen = Set(ordered.map(\.url))
            ordered.append(contentsOf: items.filter { !seen.contains($0.url) })
            return ordered
        }
        return items
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
            showToast(String(format: String(localized: "editor.toast.file_read_failed"), error.localizedDescription))
        }
    }

    func reloadCurrentFile() {
        guard let url = selectedFile,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        editorText = text
        isDirty = false
    }

    // MARK: - Parse

    func reparse() {
        let rawText = editorText

        // Only resolve compose for actual templates (files with {{ tokens).
        // Plain JSON files without {{ always return their content unchanged from
        // the Rust compose fn, which would make isResultMode=true for everything
        // and break the textDidChange raw-edit path.
        if let dir = workspaceRoot?.path, rawText.contains("{{") {
            resolvedCompose = RustBridge.compose(rawText, dir: dir, indent: indentSize)
        } else {
            resolvedCompose = nil
        }

        // Editor display text depends on mode
        let displayText = (!isRawMode && resolvedCompose != nil) ? resolvedCompose! : rawText

        // Validation always uses the resolved result when compose succeeded,
        // so that {{...}} template syntax never shows spurious parse errors.
        let validationText = resolvedCompose ?? rawText
        let handle = RustBridge.parseHandle(validationText)
        updateParseResult(handle)

        if let err = handle.error {
            parseError = err
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

        // Update fold ranges from the display text
        foldRanges = RustBridge.foldRanges(displayText)
    }

    // MARK: - Save

    /// `explicit`: true when triggered by the user (Cmd+S), false when triggered
    /// by autoSave on every keystroke. Format-on-save only fires for explicit saves.
    func save(explicit: Bool = true) {
        guard let url = selectedFile else { return }
        if explicit && formatOnSave && parseResult?.error == nil {
            let (stubbed, tokens) = stubComposeTokens(editorText)
            if let formatted = RustBridge.format(stubbed, indent: indentSize) {
                editorText = restoreComposeTokens(formatted, tokens: tokens)
                reparse()
            }
        }
        do {
            try editorText.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            if explicit { showToast(String(localized: "editor.toast.saved")) }
        } catch {
            showToast(String(format: String(localized: "editor.toast.save_failed"), error.localizedDescription))
        }
    }

    /// Format the current editor content without saving.
    func formatInPlace() {
        guard parseResult?.error == nil else { return }
        let (stubbed, tokens) = stubComposeTokens(editorText)
        guard let formatted = RustBridge.format(stubbed, indent: indentSize) else { return }
        editorText = restoreComposeTokens(formatted, tokens: tokens)
        reparse()
    }

    // MARK: - Transforms

    func format() {
        let (stubbed, tokens) = stubComposeTokens(editorText)
        guard let formatted = RustBridge.format(stubbed, indent: indentSize) else {
            showToast(String(localized: "editor.toast.format_failed"))
            return
        }
        applyTransform(restoreComposeTokens(formatted, tokens: tokens))
    }

    func minify() {
        let (stubbed, tokens) = stubComposeTokens(editorText)
        guard let minified = RustBridge.minify(stubbed) else {
            showToast(String(localized: "editor.toast.minify_failed"))
            return
        }
        applyTransform(restoreComposeTokens(minified, tokens: tokens))
    }

    func removeNulls() {
        let (stubbed, tokens) = stubComposeTokens(editorText)
        guard let cleaned = RustBridge.removeNulls(stubbed, indent: indentSize) else {
            showToast(String(localized: "editor.toast.remove_nulls_failed"))
            return
        }
        applyTransform(restoreComposeTokens(cleaned, tokens: tokens))
    }

    func unwrapPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let (stubbed, tokens) = stubComposeTokens(editorText)
        guard let result = RustBridge.unwrapPath(stubbed, path: trimmed, indent: indentSize) else {
            showToast("Unwrap failed — check path and JSON validity")
            return
        }
        applyTransform(restoreComposeTokens(result, tokens: tokens))
    }

    /// Replace `{{token}}` with `"__BRACE_N__"` so the template parses as valid JSON.
    private func stubComposeTokens(_ text: String) -> (String, [String]) {
        var tokens: [String] = []
        var result = text
        var searchRange = result.startIndex..<result.endIndex
        while let openRange = result.range(of: "{{", range: searchRange),
              let closeRange = result.range(of: "}}", range: openRange.upperBound..<result.endIndex) {
            let token = String(result[openRange.upperBound..<closeRange.lowerBound])
            let stub = "__BRACE_\(tokens.count)__"
            tokens.append(token)
            result.replaceSubrange(openRange.lowerBound..<closeRange.upperBound, with: "\"\(stub)\"")
            let offset = result.index(openRange.lowerBound, offsetBy: stub.count + 2)
            searchRange = offset..<result.endIndex
        }
        return (result, tokens)
    }

    private func restoreComposeTokens(_ text: String, tokens: [String]) -> String {
        var result = text
        for (i, token) in tokens.enumerated() {
            result = result.replacingOccurrences(of: "\"__BRACE_\(i)__\"", with: "{{\(token)}}")
        }
        return result
    }

    private func applyTransform(_ newText: String) {
        foldedLines = []
        if !isComposeTemplate { isRawMode = true }
        pendingUndoableTransform = true
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
            jsonPathError = String(localized: "editor.jsonpath.parse_error")
            jsonPathMatches = []
            return
        }
        let ids = RustBridge.jsonPath(handle, query: query)
        if ids.isEmpty {
            jsonPathError = String(localized: "editor.jsonpath.no_matches")
            jsonPathMatches = []
        } else {
            jsonPathError = nil
            jsonPathMatches = Set(ids)
        }
    }

    // MARK: - Key Inspector

    func runParentKeySearch() {
        let q = parentKeyQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let handle = parseResult, handle.error == nil else {
            parentKeyResults = []
            return
        }
        parentKeyResults = RustBridge.keysUnderParent(handle, parentKey: q)
    }

    func renameKey(from oldKey: String, to newKey: String) {
        guard !newKey.trimmingCharacters(in: .whitespaces).isEmpty, oldKey != newKey else { return }
        let escaped = NSRegularExpression.escapedPattern(for: oldKey)
        guard let regex = try? NSRegularExpression(pattern: "\"" + escaped + "\"(\\s*):", options: []) else { return }
        let range = NSRange(editorText.startIndex..., in: editorText)
        let result = regex.stringByReplacingMatches(
            in: editorText, options: [], range: range,
            withTemplate: "\"" + newKey + "\"$1:"
        )
        guard result != editorText else { return }
        editorText = result
        reparse()
        runParentKeySearch()
        if autoSave { save() }
        showToast(String(format: String(localized: "editor.toast.key_renamed"), oldKey, newKey))
    }

    // MARK: - Rename

    func renameFile(_ file: WorkspaceFile, to newName: String) {
        var name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != file.name else { return }
        if !file.isDirectory && !name.hasSuffix(".json") { name += ".json" }
        let dest = file.url.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            showToast("File already exists: \(name)")
            return
        }
        do {
            try FileManager.default.moveItem(at: file.url, to: dest)
            let wasSelected = selectedFile == file.url
            if let root = workspaceRoot { openWorkspace(root) }
            if wasSelected { selectFile(dest) }
        } catch {
            showToast("Rename failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Compose

    func resolveCompose() {
        guard let dir = workspaceRoot?.path else {
            showToast(String(localized: "editor.toast.open_workspace_first"))
            return
        }
        if let result = RustBridge.compose(editorText, dir: dir, indent: indentSize) {
            resolvedCompose = result
        } else {
            showToast(String(localized: "editor.toast.compose_failed"))
        }
    }

    // MARK: - Workspace file creation

    func createFile(named name: String, in directory: URL? = nil) {
        let dir = directory ?? workspaceRoot
        guard let dir else { return }
        var filename = name.trimmingCharacters(in: .whitespaces)
        if filename.isEmpty { filename = "untitled" }
        if !filename.hasSuffix(".json") { filename += ".json" }
        let url = dir.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            showToast("File already exists: \(filename)")
            return
        }
        do {
            try "{\n  \n}".write(to: url, atomically: true, encoding: .utf8)
            if let root = workspaceRoot { openWorkspace(root) }
            selectFile(url)
        } catch {
            showToast("Could not create file: \(error.localizedDescription)")
        }
    }

    func createFolder(named name: String, in directory: URL? = nil) {
        let dir = directory ?? workspaceRoot
        guard let dir else { return }
        let folderName = name.trimmingCharacters(in: .whitespaces)
        guard !folderName.isEmpty else { return }
        let url = dir.appendingPathComponent(folderName)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            if let root = workspaceRoot { openWorkspace(root) }
        } catch {
            showToast("Could not create folder: \(error.localizedDescription)")
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
