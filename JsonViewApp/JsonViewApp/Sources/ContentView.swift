import SwiftUI
import AppKit

// MARK: - Geometry preference for detail column leading edge

private struct DetailLeadingXKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Brace Root

struct ContentView: View {
    @EnvironmentObject var devKit: BraceModel
    @ObservedObject private var prefs = Preferences.shared
    // Tracks the detail column's leading x in root coordinates so the action
    // bar can match it — the macOS 27 sidebar is a window-level overlay and
    // bleeds over any content that starts to its left.
    @State private var detailLeadingX: CGFloat = 0

    private var preferredScheme: ColorScheme? {
        switch prefs.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
            } detail: {
                detailContent
                    .frame(minWidth: 300)
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar {
                BraceToolbar()
            }

            // Action bar and status bar live outside NavigationSplitView to avoid
            // sidebar chrome rounded corner bleeding over them. Leading padding
            // dynamically matches the detail column so the sidebar never covers content.
            if devKit.mode == .jsonEditor {
                ActionBarView()
                    .environmentObject(devKit.editorModel)
                    .padding(.leading, detailLeadingX)
                StatusBarView()
                    .environmentObject(devKit.editorModel)
            }
        }
        .coordinateSpace(name: "root")
        .environmentObject(devKit.editorModel)
        .preferredColorScheme(preferredScheme)
    }

    // Both views stay in the hierarchy permanently — switching destroys/recreates
    // JsonEditorDetailView which triggers makeNSView + full tokenize on main thread,
    // causing a hang proportional to JSON file size.
    private var sidebarContent: some View {
        ZStack {
            JsonEditorSidebarView()
                .environmentObject(devKit.editorModel)
                .opacity(devKit.mode == .jsonEditor ? 1 : 0)
                .allowsHitTesting(devKit.mode == .jsonEditor)
            ScannerSidebarView()
                .environmentObject(devKit.scannerModel)
                .opacity(devKit.mode == .httpScanner ? 1 : 0)
                .allowsHitTesting(devKit.mode == .httpScanner)
        }
    }

    private var detailContent: some View {
        ZStack {
            JsonEditorDetailView()
                .environmentObject(devKit.editorModel)
                .opacity(devKit.mode == .jsonEditor ? 1 : 0)
                .allowsHitTesting(devKit.mode == .jsonEditor)
            ScannerDetailView()
                .environmentObject(devKit.scannerModel)
                .opacity(devKit.mode == .httpScanner ? 1 : 0)
                .allowsHitTesting(devKit.mode == .httpScanner)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: DetailLeadingXKey.self,
                    value: geo.frame(in: .named("root")).minX
                )
            }
        )
        .onPreferenceChange(DetailLeadingXKey.self) { x in
            detailLeadingX = x
        }
    }
}

// MARK: - Scanner Detail (config panel + results split)

struct ScannerDetailView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var showHistory = false

    var body: some View {
        HStack(spacing: 0) {
            ConfigPanelView()
                .frame(width: 300)
                .environmentObject(vm)
            Divider()
            ResultsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environmentObject(vm)
        }
        .toolbar {
            ScannerToolbarItems(showHistory: $showHistory)
        }
        .popover(isPresented: $showHistory, arrowEdge: .bottom) {
            HistoryView(isPresented: $showHistory)
                .environmentObject(vm)
        }
    }
}

// MARK: - AppCommands (menu bar)

struct AppCommands: Commands {
    @ObservedObject var devKit: BraceModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                devKit.editorModel.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(devKit.editorModel.selectedFile == nil || devKit.mode != .jsonEditor)
        }

        CommandGroup(after: .saveItem) {
            Button("Open Workspace…") {
                openWorkspacePicker(model: devKit.editorModel)
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(devKit.mode != .jsonEditor)

            Button(String(localized: "menu.delete_file")) {
                guard let url = devKit.editorModel.selectedFile else { return }
                let name = url.lastPathComponent
                let alert = NSAlert()
                alert.messageText = String(format: String(localized: "sidebar.delete.confirm.title"), name)
                alert.informativeText = String(localized: "sidebar.delete.confirm.message")
                alert.addButton(withTitle: String(localized: "sidebar.delete"))
                alert.addButton(withTitle: String(localized: "action.cancel"))
                alert.alertStyle = .warning
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    devKit.editorModel.selectedFile = nil
                    devKit.editorModel.editorText = ""
                    devKit.editorModel.isDirty = false
                    if let root = devKit.editorModel.workspaceRoot {
                        devKit.editorModel.openWorkspace(root)
                    }
                } catch {
                    devKit.editorModel.showToast("Delete failed: \(error.localizedDescription)")
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(devKit.editorModel.selectedFile == nil || devKit.mode != .jsonEditor)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find…") {
                NotificationCenter.default.post(name: .editorActivateFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(devKit.mode != .jsonEditor)
        }

        CommandMenu("Scan") {
            Button("Run") { devKit.scannerModel.run() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(devKit.scannerModel.isRunning || devKit.mode != .httpScanner)
            Button("Stop") { devKit.scannerModel.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!devKit.scannerModel.isRunning)
        }
    }

    private func openWorkspacePicker(model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in model.openWorkspace(url) }
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let editorActivateFind = Notification.Name("JsonView.editorActivateFind")
}
