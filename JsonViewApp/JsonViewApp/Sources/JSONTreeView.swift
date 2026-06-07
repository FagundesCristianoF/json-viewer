import SwiftUI

// Free functions kept for backward compat — delegate to Theme tokens
func kindColor(_ kind: NodeKind) -> Color { JVColor.kind(kind) }
func kindLabel(_ kind: NodeKind) -> String { JVColor.kindLabel(kind) }

// MARK: - JSONTreeView

struct JSONTreeView: View {
    @EnvironmentObject var model: AppModel
    @State private var searchText: String = ""

    private var rootNodes: [NodeInfo] {
        model.treeNodes.filter { $0.parent == nil }
    }

    private var nodeMap: [Int: NodeInfo] {
        Dictionary(uniqueKeysWithValues: model.treeNodes.map { ($0.nodeId, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text("TREE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.8)

                Spacer()

                Button {
                    expandAll(nodes: model.treeNodes)
                } label: {
                    Image(systemName: "chevron.down.square")
                        .help("Expand All")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button {
                    model.expandedNodes = []
                } label: {
                    Image(systemName: "chevron.right.square")
                        .help("Collapse All")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))
                TextField("Filter keys…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.background.opacity(0.6))

            Divider()

            // Tree body
            if model.treeNodes.isEmpty {
                Spacer()
                Text(model.parseError != nil ? "Parse error" : "No JSON loaded")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                let map = nodeMap
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleRoots(roots: rootNodes, map: map), id: \.nodeId) { node in
                            NodeRowView(node: node, nodeMap: map, searchText: searchText)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Visible roots filtered by search

    private func visibleRoots(roots: [NodeInfo], map: [Int: NodeInfo]) -> [NodeInfo] {
        guard !searchText.isEmpty else { return roots }
        return roots.filter { nodeMatchesSearch($0, map: map) }
    }

    private func nodeMatchesSearch(_ node: NodeInfo, map: [Int: NodeInfo]) -> Bool {
        let q = searchText.lowercased()
        if node.key?.lowercased().contains(q) == true { return true }
        if node.value?.lowercased().contains(q) == true { return true }
        // Check descendants
        for childId in node.children {
            if let child = map[childId], nodeMatchesSearch(child, map: map) { return true }
        }
        return false
    }

    // MARK: - Expand all

    private func expandAll(nodes: [NodeInfo]) {
        let expandable = nodes.filter { !$0.children.isEmpty }.map { $0.nodeId }
        model.expandedNodes.formUnion(expandable)
    }
}

// MARK: - NodeRowView

struct NodeRowView: View {
    let node: NodeInfo
    let nodeMap: [Int: NodeInfo]
    let searchText: String

    @EnvironmentObject var model: AppModel

    private var isExpanded: Bool {
        model.expandedNodes.contains(node.nodeId)
    }
    private var isMatched: Bool {
        model.jsonPathMatches.contains(node.nodeId)
    }
    private var hasChildren: Bool {
        !node.children.isEmpty
    }
    private var indentWidth: CGFloat {
        CGFloat(node.depth) * 16
    }
    private var visibleChildren: [NodeInfo] {
        node.children.compactMap { nodeMap[$0] }.filter { child in
            guard !searchText.isEmpty else { return true }
            return childMatchesSearch(child)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row
            HStack(spacing: 4) {
                // Indent spacer
                Spacer()
                    .frame(width: max(0, indentWidth))

                // Chevron
                if hasChildren {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpand() }
                } else {
                    Spacer().frame(width: 12)
                }

                // Key label
                if let key = node.key {
                    Text(key)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(":")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                // Kind badge
                Text(kindLabel(node.kind))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(kindColor(node.kind).opacity(0.15))
                    .foregroundStyle(kindColor(node.kind))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                // Value preview
                if let value = node.value, !hasChildren {
                    Text(value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(kindColor(node.kind))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if hasChildren {
                    Text(node.kind == .array
                         ? "\(node.children.count) item\(node.children.count == 1 ? "" : "s")"
                         : "\(node.children.count) key\(node.children.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.trailing, 8)
            .background(rowBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                if hasChildren { toggleExpand() }
                scrollEditorToNode()
            }

            // Children
            if isExpanded && hasChildren {
                ForEach(visibleChildren, id: \.nodeId) { child in
                    NodeRowView(node: child, nodeMap: nodeMap, searchText: searchText)
                }
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var rowBackground: some View {
        if isMatched {
            Color.yellow.opacity(0.22)
                .overlay(
                    Rectangle()
                        .frame(width: 3)
                        .foregroundStyle(Color.yellow.opacity(0.8)),
                    alignment: .leading
                )
        } else {
            Color.clear
        }
    }

    // MARK: - Actions

    private func toggleExpand() {
        if isExpanded {
            model.expandedNodes.remove(node.nodeId)
        } else {
            model.expandedNodes.insert(node.nodeId)
        }
    }

    private func scrollEditorToNode() {
        // Post notification so the editor can scroll to the node's path.
        // The editor layer listens for JSONTreeScrollToPath and handles cursor placement.
        NotificationCenter.default.post(
            name: .jsonTreeScrollToNode,
            object: nil,
            userInfo: ["nodeId": node.nodeId, "path": node.path]
        )
    }

    // MARK: - Search helper

    private func childMatchesSearch(_ node: NodeInfo) -> Bool {
        let q = searchText.lowercased()
        if node.key?.lowercased().contains(q) == true { return true }
        if node.value?.lowercased().contains(q) == true { return true }
        for childId in node.children {
            if let child = nodeMap[childId], childMatchesSearch(child) { return true }
        }
        return false
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let jsonTreeScrollToNode = Notification.Name("JSONTreeScrollToNode")
}
