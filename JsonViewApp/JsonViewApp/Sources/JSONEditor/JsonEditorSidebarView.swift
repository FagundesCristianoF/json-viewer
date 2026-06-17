import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Tries both data-representation and loadItem fallback so drops work
// regardless of how the NSItemProvider was registered.
private func loadDroppedURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
    provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
        if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
            completion(url); return
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            switch item {
            case let data as Data:   completion(URL(dataRepresentation: data, relativeTo: nil))
            case let url  as URL:    completion(url)
            case let ns   as NSURL:  completion(ns as URL)
            default:                 completion(nil)
            }
        }
    }
}

// MARK: - SidebarDoubleClickDetector
// Installs one app-level monitor for the whole sidebar. On double-click fires onDoubleClick.
// Using a single background monitor avoids per-row overlays that break List row selection.

private final class SidebarMonitorView: NSView {
    var onDoubleClick: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        guard let win = window else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self,
                  event.clickCount == 2,
                  event.window === win else { return event }
            // Only fire when click is inside this view's frame (the sidebar area)
            let frameInWindow = self.convert(self.bounds, to: nil)
            if frameInWindow.contains(event.locationInWindow) {
                self.onDoubleClick?()
            }
            return event
        }
    }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}

private struct SidebarDoubleClickDetector: NSViewRepresentable {
    let onDoubleClick: () -> Void
    func makeNSView(context: Context) -> SidebarMonitorView {
        let v = SidebarMonitorView(); v.onDoubleClick = onDoubleClick; return v
    }
    func updateNSView(_ nsView: SidebarMonitorView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

// MARK: - JsonEditorSidebarView

struct JsonEditorSidebarView: View {
    @EnvironmentObject var model: AppModel
    @State private var searchText = ""
    @State private var dropTargetDir: URL? = nil
    @State private var sidebarSelection: WorkspaceFile? = nil

    var filteredFiles: [WorkspaceFile] {
        guard !searchText.isEmpty else { return model.workspaceFiles }
        return model.workspaceFiles.flatMap { filterFiles($0, query: searchText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.workspaceRoot != nil {
                searchBar
                Divider()
                newItemBar
                Divider()
                fileList
            } else {
                emptyState
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .background(SidebarDoubleClickDetector {
            guard searchText.isEmpty,
                  let url = model.selectedFile,
                  let file = findFile(url: url, in: model.workspaceFiles) else { return }
            beginRename(file: file)
        })
        .clipped()
        // Context menu on the entire sidebar — fires for right-clicks on empty space
        // (item-level context menus take precedence when clicking on a file/folder row)
        .contextMenu {
            if model.workspaceRoot != nil {
                Button(String(localized: "sidebar.new_file_here")) { promptNewFile() }
                Button(String(localized: "sidebar.new_folder_here")) { promptNewFolder() }
                Divider()
            }
            Button(String(localized: "sidebar.button.open_workspace")) { openWorkspacePanel() }
        }
        .onChange(of: model.selectedFile) { url in
            guard let url else { sidebarSelection = nil; return }
            sidebarSelection = findFile(url: url, in: model.workspaceFiles)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("FILES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)
            Spacer()
            if let root = model.workspaceRoot {
                Text(root.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(dropTargetDir == root ? .primary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 80)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(dropTargetDir == model.workspaceRoot ? Color.accentColor.opacity(0.12) : Color(NSColor.windowBackgroundColor).opacity(0))
        .background(.bar)
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: Binding(
                get: { model.workspaceRoot != nil && dropTargetDir == model.workspaceRoot },
                set: { dropTargetDir = ($0 ? model.workspaceRoot : nil) }
            )
        ) { providers in
            guard let root = model.workspaceRoot else { return false }
            for provider in providers {
                loadDroppedURL(from: provider) { url in
                    guard let url else { return }
                    Task { @MainActor in model.moveFile(from: url, to: root) }
                }
            }
            return true
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField("Filter files", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - New Item Bar

    private var newItemBar: some View {
        HStack(spacing: 6) {
            Button { promptNewFile() } label: {
                Label(String(localized: "sidebar.tooltip.new_file"), systemImage: "doc.badge.plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(String(localized: "sidebar.tooltip.new_file"))

            Button { promptNewFolder() } label: {
                Label(String(localized: "sidebar.tooltip.new_folder"), systemImage: "folder.badge.plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(String(localized: "sidebar.tooltip.new_folder"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - File List

    private var fileList: some View {
        List(selection: $sidebarSelection) {
            if searchText.isEmpty {
                FileTreeLevel(
                    files: model.workspaceFiles,
                    parentDir: model.workspaceRoot!,
                    dropTargetDir: $dropTargetDir,
                    onPromptNewFile: promptNewFile(in:),
                    onPromptNewFolder: promptNewFolder(in:)
                )
                .environmentObject(model)

                rootDropZone
            } else {
                ForEach(filteredFiles) { file in
                    if !file.isDirectory {
                        FileRowView(file: file, isSelected: model.selectedFile == file.url, fontSize: model.uiFontSize)
                            .tag(file)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectFile(file.url) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: sidebarSelection) { file in
            guard let file, !file.isDirectory else { return }
            if model.selectedFile != file.url { model.selectFile(file.url) }
        }
    }

    private var rootDropZone: some View {
        let root = model.workspaceRoot!
        let isTargeted = dropTargetDir == root
        return HStack(spacing: 6) {
            Image(systemName: "arrow.up.to.line")
                .font(.system(size: 10))
                .foregroundColor(isTargeted ? .accentColor : Color.secondary.opacity(0.6))
            Text(String(localized: "sidebar.move_to_root"))
                .font(.system(size: 11))
                .foregroundColor(isTargeted ? .accentColor : Color.secondary.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isTargeted ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: Binding(
                get: { dropTargetDir == root },
                set: { dropTargetDir = $0 ? root : nil }
            )
        ) { providers in
            for provider in providers {
                loadDroppedURL(from: provider) { url in
                    guard let url else { return }
                    Task { @MainActor in model.moveFile(from: url, to: root) }
                }
            }
            return true
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No workspace open")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Button("Open Workspace") { openWorkspacePanel() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Helpers

    private func findFile(url: URL, in files: [WorkspaceFile]) -> WorkspaceFile? {
        for file in files {
            if file.url == url { return file }
            if file.isDirectory, let found = findFile(url: url, in: file.children) { return found }
        }
        return nil
    }

    private func openWorkspacePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            model.openWorkspace(url)
        }
    }

    func beginRename(file: WorkspaceFile) {
        model.renameText = file.url.deletingPathExtension().lastPathComponent
        model.renamingFileURL = file.url
    }

    func promptNewFile(in directory: URL? = nil) {
        guard let dir = directory ?? model.workspaceRoot else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "sidebar.new_file.title")
        alert.informativeText = String(localized: "sidebar.new_file.prompt")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        tf.placeholderString = "filename"
        alert.accessoryView = tf
        alert.addButton(withTitle: String(localized: "action.create"))
        alert.addButton(withTitle: String(localized: "action.cancel"))
        alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var name = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !name.lowercased().hasSuffix(".json") { name += ".json" }
        model.createFile(named: name, in: dir)
    }

    func promptNewFolder(in directory: URL? = nil) {
        guard let dir = directory ?? model.workspaceRoot else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "sidebar.new_folder.title")
        alert.informativeText = String(localized: "sidebar.new_folder.prompt")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        tf.placeholderString = String(localized: "sidebar.new_folder.placeholder")
        alert.accessoryView = tf
        alert.addButton(withTitle: String(localized: "action.create"))
        alert.addButton(withTitle: String(localized: "action.cancel"))
        alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.createFolder(named: tf.stringValue, in: dir)
    }

    private func filterFiles(_ file: WorkspaceFile, query: String) -> [WorkspaceFile] {
        if file.isDirectory {
            let filteredChildren = file.children.flatMap { filterFiles($0, query: query) }
            if !filteredChildren.isEmpty {
                return [WorkspaceFile(url: file.url, name: file.name, isDirectory: true, children: filteredChildren)]
            }
            return []
        }
        return file.name.lowercased().contains(query) ? [file] : []
    }
}

// MARK: - FileTreeLevel

struct FileTreeLevel: View {
    let files: [WorkspaceFile]
    let parentDir: URL
    @Binding var dropTargetDir: URL?
    let onPromptNewFile: (URL) -> Void
    let onPromptNewFolder: (URL) -> Void
    @State private var insertFirstTargeted = false
    @EnvironmentObject var model: AppModel

    var body: some View {
        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
            Group {
                if file.isDirectory {
                    directoryRow(file)
                } else {
                    fileRow(file)
                }
            }
            .overlay(alignment: .top) {
                if index == 0 {
                    ZStack(alignment: .top) {
                        Color.accentColor
                            .frame(height: 2)
                            .opacity(insertFirstTargeted ? 1 : 0)
                        Color.clear
                            .frame(height: 10)
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.fileURL], isTargeted: $insertFirstTargeted) { providers in
                                dropToFirst(providers: providers)
                            }
                    }
                }
            }
        }
    }

    private func dropToFirst(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            loadDroppedURL(from: provider) { url in
                guard let url else { return }
                Task { @MainActor in
                    if url.deletingLastPathComponent() == parentDir {
                        model.reorderToFirst(sourceURL: url, in: parentDir, currentFiles: files)
                    } else {
                        let destURL = parentDir.appendingPathComponent(url.lastPathComponent)
                        model.moveFile(from: url, to: parentDir)
                        // workspaceFiles is now refreshed; reorder the moved file to first
                        let current = model.filesInDirectory(parentDir)
                        model.reorderToFirst(sourceURL: destURL, in: parentDir, currentFiles: current)
                    }
                }
            }
        }
        return true
    }

    private func directoryRow(_ file: WorkspaceFile) -> some View {
        DirectoryRowView(
            file: file,
            dropTargetDir: $dropTargetDir,
            onPromptNewFile: onPromptNewFile,
            onPromptNewFolder: onPromptNewFolder
        )
        .environmentObject(model)
    }

    private func fileRow(_ file: WorkspaceFile) -> some View {
        Group {
            if model.renamingFileURL == file.url {
                RenameRowView(
                    file: file,
                    text: Binding(get: { model.renameText }, set: { model.renameText = $0 }),
                    fontSize: model.uiFontSize,
                    onCommit: { commitRename(file) },
                    onCancel: { model.renamingFileURL = nil }
                )
            } else {
                FileRowView(file: file, isSelected: model.selectedFile == file.url, fontSize: model.uiFontSize)
            }
        }
        .tag(file)
        .contentShape(Rectangle())
        .onDrag {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                visibility: .all
            ) { completion in
                completion(file.url.dataRepresentation, nil)
                return nil
            }
            return provider
        }
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: Binding(
                get: { dropTargetDir == parentDir },
                set: { dropTargetDir = $0 ? parentDir : nil }
            )
        ) { providers in
            for provider in providers {
                loadDroppedURL(from: provider) { url in
                    guard let url, url != file.url else { return }
                    Task { @MainActor in
                        if url.deletingLastPathComponent() == parentDir {
                            model.reorderAfter(sourceURL: url, afterURL: file.url,
                                               in: parentDir, currentFiles: files)
                        } else {
                            model.moveFile(from: url, to: parentDir)
                        }
                    }
                }
            }
            return true
        }
        .contextMenu {
            Button(String(localized: "sidebar.rename")) { beginRename(file) }
            Divider()
            Button(String(localized: "sidebar.new_file_here")) {
                onPromptNewFile(file.url.deletingLastPathComponent())
            }
            Button(String(localized: "sidebar.new_folder_here")) {
                onPromptNewFolder(file.url.deletingLastPathComponent())
            }
            Divider()
            Button(String(localized: "sidebar.reveal_in_finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Button(String(localized: "sidebar.copy_path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
            Divider()
            Button(String(localized: "sidebar.delete"), role: .destructive) {
                confirmAndDelete(file: file)
            }
        }
    }

    private func beginRename(_ file: WorkspaceFile) {
        model.renameText = file.url.deletingPathExtension().lastPathComponent
        model.renamingFileURL = file.url
    }

    private func commitRename(_ file: WorkspaceFile) {
        var name = model.renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { model.renamingFileURL = nil; return }
        if !name.lowercased().hasSuffix(".json") { name += ".json" }
        model.renamingFileURL = nil
        model.renameFile(file, to: name)
    }

    static func confirmAndDelete(file: WorkspaceFile, model: AppModel) {
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "sidebar.delete.confirm.title"), file.name)
        alert.informativeText = String(localized: "sidebar.delete.confirm.message")
        alert.addButton(withTitle: String(localized: "sidebar.delete"))
        alert.addButton(withTitle: String(localized: "action.cancel"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        } catch {
            model.showToast("Delete failed: \(error.localizedDescription)")
            return
        }
        if model.selectedFile == file.url {
            model.selectedFile = nil
            model.editorText = ""
            model.isDirty = false
        }
        if let root = model.workspaceRoot { model.openWorkspace(root) }
    }

    private func confirmAndDelete(file: WorkspaceFile) {
        Self.confirmAndDelete(file: file, model: model)
    }
}

// MARK: - DirectoryRowView

struct DirectoryRowView: View {
    let file: WorkspaceFile
    @Binding var dropTargetDir: URL?
    let onPromptNewFile: (URL) -> Void
    let onPromptNewFolder: (URL) -> Void
    @State private var isExpanded = false
    @EnvironmentObject var model: AppModel

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            FileTreeLevel(
                files: file.children,
                parentDir: file.url,
                dropTargetDir: $dropTargetDir,
                onPromptNewFile: onPromptNewFile,
                onPromptNewFolder: onPromptNewFolder
            )
            .environmentObject(model)
        } label: {
            FileRowView(file: file, isSelected: false, fontSize: model.uiFontSize)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(dropTargetDir == file.url ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .simultaneousGesture(TapGesture().onEnded { isExpanded.toggle() })
                .onDrop(
                    of: [UTType.fileURL],
                    isTargeted: Binding(
                        get: { dropTargetDir == file.url },
                        set: { dropTargetDir = $0 ? file.url : nil }
                    )
                ) { providers in
                    handleDrop(providers: providers, into: file.url)
                }
        }
        .contextMenu {
            Button(String(localized: "sidebar.new_file_here")) { onPromptNewFile(file.url) }
            Button(String(localized: "sidebar.new_folder_here")) { onPromptNewFolder(file.url) }
            Divider()
            Button(String(localized: "sidebar.reveal_in_finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Button(String(localized: "sidebar.copy_path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider], into targetDir: URL) -> Bool {
        for provider in providers {
            loadDroppedURL(from: provider) { url in
                guard let url else { return }
                Task { @MainActor in model.moveFile(from: url, to: targetDir) }
            }
        }
        return true
    }
}

// MARK: - WorkspaceFile + OutlineGroup support

extension WorkspaceFile {
    var optionalChildren: [WorkspaceFile]? {
        isDirectory && !children.isEmpty ? children : nil
    }
}

// MARK: - RenameRowView

private struct RenameRowView: View {
    let file: WorkspaceFile
    @Binding var text: String
    let fontSize: Double
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 16, height: 16)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .focused($focused)
                .onSubmit(onCommit)
                .onExitCommand(perform: onCancel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .onAppear { focused = true }
    }
}

// MARK: - FileRowView

struct FileRowView: View {
    let file: WorkspaceFile
    let isSelected: Bool
    var fontSize: Double = Preferences.shared.uiFontSize

    private var isJSON: Bool {
        file.url.pathExtension.lowercased() == "json"
    }

    private var icon: NSImage {
        if file.isDirectory {
            return NSWorkspace.shared.icon(for: .folder)
        }
        return NSWorkspace.shared.icon(forFile: file.url.path)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
                .opacity(isJSON || file.isDirectory ? 1.0 : 0.45)

            Text(file.name)
                .font(.system(size: fontSize))
                .foregroundColor(labelColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
    }

    private var labelColor: Color {
        if isSelected { return .white }
        if !isJSON && !file.isDirectory { return Color.secondary }
        return Color(NSColor.labelColor)
    }
}

// MARK: - Preview

#if DEBUG
struct JsonEditorSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        let model = AppModel()
        JsonEditorSidebarView()
            .environmentObject(model)
            .frame(width: 240, height: 500)
    }
}
#endif
