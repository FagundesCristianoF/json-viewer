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
                        if model.showTree {
                            JSONTreeView()
                                .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                        }
                    }
                    .frame(minHeight: 200)
                    if model.showIssues {
                        IssuesView()
                            .frame(minHeight: 100, idealHeight: 160, maxHeight: 280)
                    }
                }
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
