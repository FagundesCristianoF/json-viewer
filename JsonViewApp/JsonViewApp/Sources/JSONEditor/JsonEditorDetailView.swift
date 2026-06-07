import SwiftUI
import AppKit

struct JsonEditorDetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ActionBarView()
                VSplitView {
                    HSplitView {
                        EditorView()
                            .frame(minWidth: 300)
                        // Always in hierarchy — keep position when tree is toggled.
                        JSONTreeView()
                            .frame(
                                minWidth: model.showTree ? 220 : 0,
                                idealWidth: model.showTree ? 280 : 0,
                                maxWidth: model.showTree ? 400 : 0
                            )
                    }
                    .frame(minHeight: 200)
                    .background(SplitViewAutosaver(name: "editor-horizontal"))
                    // Always in hierarchy — keep position when issues panel toggled.
                    IssuesView()
                        .frame(
                            minHeight: model.showIssues ? 100 : 0,
                            idealHeight: model.showIssues ? 160 : 0,
                            maxHeight: model.showIssues ? 280 : 0
                        )
                }
                .background(SplitViewAutosaver(name: "editor-vertical"))
            }

            if let msg = model.toast {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.bottom, 36)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.2), value: model.toast)
            }
        }
        .background(FileCommands(model: model))
    }
}

// MARK: - FileCommands (editor key bindings)

struct FileCommands: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> CommandResponderView {
        let view = CommandResponderView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: CommandResponderView, context: Context) {
        nsView.model = model
    }
}

final class CommandResponderView: NSView {
    var model: AppModel?
    override var acceptsFirstResponder: Bool { false }

    @objc func openWorkspace(_ sender: Any?) { openWorkspacePicker() }
    @objc func saveDocument(_ sender: Any?) { model?.save() }
    @objc func performFindPanelAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .editorActivateFind, object: nil)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(openWorkspace(_:))
            || aSelector == #selector(saveDocument(_:))
            || aSelector == #selector(performFindPanelAction(_:)) {
            return true
        }
        return super.responds(to: aSelector)
    }

    private func openWorkspacePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.model?.openWorkspace(url) }
        }
    }
}
