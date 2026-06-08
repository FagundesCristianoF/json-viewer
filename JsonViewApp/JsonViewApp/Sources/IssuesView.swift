import SwiftUI

// MARK: - IssuesView

struct IssuesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                IssuesTabButton(title: "Syntax",  tab: .syntax,  current: model.issuesTab)
                IssuesTabButton(title: "Smells",  tab: .smells,  current: model.issuesTab)
                IssuesTabButton(title: "History", tab: .history, current: model.issuesTab)
                IssuesTabButton(title: "Keys",    tab: .keys,    current: model.issuesTab)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                switch model.issuesTab {
                case .syntax:  SyntaxTabView()
                case .smells:  SmellsTabView()
                case .history: HistoryTabView()
                case .keys:    KeysTabView()
                }
            }
        }
    }
}

// MARK: - Tab Button

private struct IssuesTabButton: View {
    let title: String
    let tab: AppModel.IssuesTab
    let current: AppModel.IssuesTab

    @EnvironmentObject var model: AppModel

    private var isSelected: Bool { current == tab }

    var body: some View {
        Button {
            model.issuesTab = tab
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Syntax Tab

struct SyntaxTabView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let err = model.parseError {
                // Error state
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parse Error")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                        Text(err.message)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                        HStack(spacing: 12) {
                            Label("Line \(err.line)", systemImage: "text.alignleft")
                            Label("Col \(err.col)", systemImage: "arrow.right")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if !model.treeNodes.isEmpty {
                // Valid state
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valid JSON")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                        Text("\(model.treeNodes.count) nodes")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Node kind breakdown
                let counts = kindCounts()
                if !counts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Breakdown")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        ForEach(counts, id: \.0) { kind, count in
                            HStack {
                                NodeKindBadge(kind: kind)
                                Spacer()
                                Text("\(count)")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                // No file loaded
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    message: "No file loaded"
                )
            }
        }
        .padding(12)
    }

    private func kindCounts() -> [(String, Int)] {
        var map: [String: Int] = [:]
        for node in model.treeNodes {
            map[node.kind.rawValue, default: 0] += 1
        }
        return map.sorted { $0.value > $1.value }
    }
}

private struct NodeKindBadge: View {
    let kind: String

    private var color: Color {
        switch kind {
        case "object": return .blue
        case "array":  return .purple
        case "string": return .green
        case "number": return .orange
        case "bool":   return .cyan
        case "null":   return .gray
        default:       return .secondary
        }
    }

    var body: some View {
        Text(kind)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Smells Tab

struct SmellsTabView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.smells.isEmpty {
                EmptyStateView(
                    icon: "checkmark.shield.fill",
                    message: model.treeNodes.isEmpty ? "No file loaded" : "No issues found"
                )
                .padding(12)
            } else {
                // Header count
                HStack {
                    Text("\(model.smells.count) issue\(model.smells.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.smells) { smell in
                        SmellRow(smell: smell)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct SmellRow: View {
    let smell: SmellInfo
    @State private var isHovered = false

    private var icon: String {
        let msg = smell.message.lowercased()
        if msg.contains("duplicate") { return "doc.on.doc" }
        if msg.contains("null")      { return "minus.circle" }
        if msg.contains("empty")     { return "square.dashed" }
        if msg.contains("deep")      { return "arrow.down.to.line" }
        if msg.contains("large") || msg.contains("long") { return "arrow.up.right.and.arrow.down.left" }
        return "exclamationmark.triangle"
    }

    private var iconColor: Color {
        let msg = smell.message.lowercased()
        if msg.contains("duplicate") { return .orange }
        if msg.contains("null")      { return .gray }
        return .yellow
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(iconColor)
                .frame(width: 16, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(smell.message)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                Text(smell.path)
                    .font(.system(size: 10).monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovered = $0 }
    }
}

// MARK: - History Tab

struct HistoryTabView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.gitHistory.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    message: model.selectedFile == nil
                        ? "No file loaded"
                        : "No git history found"
                )
                .padding(12)
            } else {
                HStack {
                    Text("\(model.gitHistory.count) commit\(model.gitHistory.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.gitHistory) { commit in
                        CommitRow(commit: commit)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct CommitRow: View {
    let commit: CommitInfo
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Hash badge
            Text(String(commit.hash.prefix(7)))
                .font(.system(size: 10).monospaced())
                .foregroundColor(.accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.message)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                Text(commit.relative)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Keys Tab

struct KeysTabView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode: KeysMode = .inspector

    enum KeysMode { case inspector, jsonpath }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Key Inspector").tag(KeysMode.inspector)
                Text("JSONPath").tag(KeysMode.jsonpath)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                if mode == .inspector {
                    ParentKeyInspectorView()
                } else {
                    JSONPathView()
                }
            }
        }
    }
}

// MARK: - Parent Key Inspector

private struct ParentKeyInspectorView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search row
            VStack(alignment: .leading, spacing: 5) {
                Text("PARENT KEY")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .tracking(1.5)

                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Text("{")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor.opacity(0.6))
                        TextField("key name", text: $model.parentKeyQuery)
                            .font(.system(size: 12, design: .monospaced))
                            .textFieldStyle(.plain)
                            .focused($fieldFocused)
                            .onSubmit { model.runParentKeySearch() }
                        if !model.parentKeyQuery.isEmpty {
                            Button {
                                model.parentKeyQuery = ""
                                model.parentKeyResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        Text("}")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(fieldFocused ? Color.accentColor.opacity(0.6) : Color(NSColor.separatorColor), lineWidth: fieldFocused ? 1 : 0.5)
                    )

                    Button {
                        model.runParentKeySearch()
                        fieldFocused = false
                    } label: {
                        Text("Search")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.parentKeyQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if model.parentKeyResults.isEmpty && !model.parentKeyQuery.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No keys found under \"\(model.parentKeyQuery)\"")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if !model.parentKeyResults.isEmpty {
                KeyInspectorResultsView(results: model.parentKeyResults)
            } else {
                KeyInspectorHintView()
            }
        }
    }
}

private struct KeyInspectorResultsView: View {
    let results: [(key: String, count: Int)]
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("\(results.count) key\(results.count == 1 ? "" : "s") found")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.accentColor)
                Spacer()
                Text("tap to rename")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // Column headers
            HStack {
                Text("KEY")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("COUNT")
                    .frame(width: 48, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.5))
            .tracking(1)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            Divider().padding(.horizontal, 12)

            VStack(spacing: 0) {
                ForEach(results, id: \.key) { entry in
                    KeyInspectorRow(keyName: entry.key, count: entry.count)
                    Divider().padding(.horizontal, 12).opacity(0.5)
                }
            }
        }
    }
}

private struct KeyInspectorRow: View {
    let keyName: String
    let count: Int
    @EnvironmentObject var model: AppModel
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isHovered = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Key name
                Text("\"\(keyName)\"")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                // Count pill
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(NSColor.windowBackgroundColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())

                // Rename button (visible on hover or renaming)
                if isHovered && !isRenaming {
                    Button {
                        newName = keyName
                        isRenaming = true
                        renameFocused = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
                    .overlay(
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: isHovered ? 2 : 0),
                        alignment: .leading
                    )
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                newName = keyName
                isRenaming = true
                renameFocused = true
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            // Inline rename panel
            if isRenaming {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9))
                        .foregroundColor(.accentColor.opacity(0.5))

                    TextField("new name", text: $newName)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.plain)
                        .focused($renameFocused)
                        .onSubmit { applyRename() }

                    Button("Apply") { applyRename() }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Cancel") {
                        isRenaming = false
                        newName = ""
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isRenaming)
    }

    private func applyRename() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.renameKey(from: keyName, to: trimmed)
        isRenaming = false
    }
}

private struct KeyInspectorHintView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find all child keys nested under a parent key name, across any depth.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach([
                    ("car",     "finds all keys inside every \"car\" object"),
                    ("address", "aggregates fields across all address objects"),
                    ("meta",    "inventories all metadata keys"),
                ], id: \.0) { key, desc in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\"\(key)\"")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .frame(width: 72, alignment: .leading)
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
    }
}

// MARK: - JSONPath View (extracted from old KeysTabView)

private struct JSONPathView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("JSONPath Query")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    TextField("$.store.book[*].author", text: $model.jsonPathQuery)
                        .font(.system(size: 11).monospaced())
                        .textFieldStyle(.plain)
                        .onSubmit { model.runJsonPath() }

                    if !model.jsonPathQuery.isEmpty {
                        Button {
                            model.jsonPathQuery = ""
                            model.jsonPathMatches = []
                            model.jsonPathError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Run") { model.runJsonPath() }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.jsonPathQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
            }

            if let err = model.jsonPathError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundColor(.orange)
                    Text(err).font(.system(size: 11)).foregroundColor(.orange)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            } else if !model.jsonPathMatches.isEmpty {
                KeysResultsView(matchIds: model.jsonPathMatches)
            } else if model.jsonPathQuery.isEmpty {
                KeysHintView()
            }
        }
        .padding(12)
    }
}

private struct KeysResultsView: View {
    let matchIds: Set<Int>
    @EnvironmentObject var model: AppModel

    private var matchedNodes: [NodeInfo] {
        model.treeNodes.filter { matchIds.contains($0.nodeId) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(matchIds.count) match\(matchIds.count == 1 ? "" : "es")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    let paths = matchedNodes.map(\.path).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(paths, forType: .string)
                } label: {
                    Label("Copy Paths", systemImage: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 1) {
                ForEach(matchedNodes) { node in
                    KeyResultRow(node: node)
                }
            }
        }
    }
}

private struct KeyResultRow: View {
    let node: NodeInfo
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NodeKindBadge(kind: node.kind.rawValue)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.path)
                    .font(.system(size: 10).monospaced())
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let val = node.value {
                    Text(val)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovered = $0 }
    }
}

private struct KeysHintView: View {
    private let examples = [
        ("$.*",                      "All top-level values"),
        ("$.store.book[*].title",    "All book titles"),
        ("$..price",                 "All price fields (recursive)"),
        ("$.items[?(@.active==true)]", "Filter by boolean field"),
        ("$[0]",                     "First array element"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Examples")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(examples, id: \.0) { query, desc in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(query)
                            .font(.system(size: 10).monospaced())
                            .foregroundColor(.accentColor)
                            .frame(minWidth: 180, alignment: .leading)
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}

// MARK: - Shared Empty State

private struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
