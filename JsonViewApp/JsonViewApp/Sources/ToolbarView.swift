import SwiftUI
import AppKit

// MARK: - Brace Toolbar (mode toggle + per-mode items)

struct BraceToolbar: ToolbarContent {
    @EnvironmentObject var devKit: BraceModel

    var body: some ToolbarContent {
        // Mode toggle — centered, always visible
        ToolbarItem(placement: .principal) {
            Picker("", selection: $devKit.mode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .help("Switch mode")
        }

        // JSON Editor mode items
        if devKit.mode == .jsonEditor {
            JsonEditorToolbarItems()
        }
    }
}

// MARK: - Scanner Toolbar Items

struct ScannerToolbarItems: ToolbarContent {
    @EnvironmentObject var vm: ScanViewModel
    @Binding var showHistory: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("History")
            .badge(vm.history.isEmpty ? 0 : min(vm.history.count, 99))
        }

        if vm.isRunning {
            ToolbarItem(placement: .primaryAction) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
                    .padding(.leading, 8)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    vm.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: .command)
                .tint(.red)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.run()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(
                    vm.curlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    vm.optionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .contextMenu {
                    Button {
                        vm.forceRun()
                    } label: {
                        Label("Force Run (ignore cache)", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Action Bar (below toolbar, above content)

struct ActionBarView: View {
    @EnvironmentObject var model: AppModel
    @State private var showReplace = false

    private var hasFile: Bool { model.selectedFile != nil }

    var body: some View {
        HStack(spacing: 4) {
            actionButton("doc.plaintext",  tip: "Format JSON")  { model.format() }
                .disabled(!hasFile)
            actionButton("arrow.down.right.and.arrow.up.left", tip: "Minify JSON") { model.minify() }
                .disabled(!hasFile)
            actionButton("minus.circle",   tip: "Remove Nulls") { model.removeNulls() }
                .disabled(!hasFile)

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 4)

            Button { showReplace.toggle() } label: {
                Label("Replace", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Find & Replace")
            .popover(isPresented: $showReplace, arrowEdge: .bottom) {
                ReplacePopover().environmentObject(model)
            }

            Spacer()

            JsonPathField()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .bottom) { HairlineDivider() }
    }

    @ViewBuilder
    private func actionButton(_ icon: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(tip)
    }
}

// MARK: - JSONPath Field

private struct JsonPathField: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            NoFocusRingTextField(placeholder: "JSONPath…", text: $model.jsonPathQuery) {
                model.runJsonPath()
            }
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 160)
            .onChange(of: model.jsonPathQuery) { newValue in
                if newValue.isEmpty {
                    model.jsonPathMatches = []
                    model.jsonPathError = nil
                }
            }

            JsonPathStatus()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct JsonPathStatus: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group {
            if !model.jsonPathMatches.isEmpty {
                Text("\(model.jsonPathMatches.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            } else if let err = model.jsonPathError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            }
        }
    }
}

// MARK: - Replace Popover

private struct ReplacePopover: View {
    @EnvironmentObject var model: AppModel
    @State private var findText = ""
    @State private var replaceText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find & Replace")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 6) {
                LabeledField(label: "Find", text: $findText, placeholder: "Search…")
                LabeledField(label: "Replace", text: $replaceText, placeholder: "Replacement…")
            }

            HStack {
                Spacer()
                Button("Replace All") {
                    guard !findText.isEmpty else { return }
                    model.editorText = model.editorText
                        .replacingOccurrences(of: findText, with: replaceText)
                    model.reparse()
                    if model.autoSave { model.save() }
                }
                .disabled(findText.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }
}

// MARK: - No-focus-ring text field (suppresses blue rounded-rect focus ring)

private struct NoFocusRingTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    private static let fieldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.fieldFont
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NoFocusRingTextField
        init(_ parent: NoFocusRingTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
