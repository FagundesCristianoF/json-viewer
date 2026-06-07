import SwiftUI
import AppKit

// MARK: - DevKit Root

struct ContentView: View {
    @EnvironmentObject var devKit: DevKitModel
    @ObservedObject private var prefs = Preferences.shared

    private var preferredScheme: ColorScheme? {
        switch prefs.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
                .animation(.easeInOut(duration: 0.2), value: devKit.mode)
                .clipped()
        } detail: {
            detailContent
                .frame(minWidth: 420)
                .animation(.easeInOut(duration: 0.2), value: devKit.mode)
        }
        .toolbar {
            DevKitToolbar()
        }
        .environmentObject(devKit.editorModel)
        .preferredColorScheme(preferredScheme)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch devKit.mode {
        case .jsonEditor:
            JsonEditorSidebarView()
                .environmentObject(devKit.editorModel)
        case .httpScanner:
            ScannerSidebarView()
                .environmentObject(devKit.scannerModel)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch devKit.mode {
        case .jsonEditor:
            JsonEditorDetailView()
                .environmentObject(devKit.editorModel)
        case .httpScanner:
            ScannerDetailView()
                .environmentObject(devKit.scannerModel)
        }
    }
}

// MARK: - Scanner Detail (config panel + results split)

struct ScannerDetailView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var showHistory = false

    var body: some View {
        HSplitView {
            ConfigPanelView()
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
                .environmentObject(vm)
            ResultsView()
                .frame(minWidth: 300)
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
    @ObservedObject var devKit: DevKitModel

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
