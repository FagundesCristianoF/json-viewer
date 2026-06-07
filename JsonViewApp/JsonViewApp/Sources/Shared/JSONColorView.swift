import SwiftUI

// MARK: ── JSON Node

private indirect enum JNode {
    case object([(String, JNode)])
    case array([JNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    static func from(_ value: Any) -> JNode {
        switch value {
        case let d as [String: Any]:
            return .object(d.keys.sorted().map { ($0, from(d[$0]!)) })
        case let a as [Any]:
            return .array(a.map { from($0) })
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let d = n.doubleValue
            if d.truncatingRemainder(dividingBy: 1) == 0 && !d.isInfinite && abs(d) < 1e15 {
                return .number(String(Int64(d)))
            }
            return .number(n.stringValue)
        default:
            return .null
        }
    }
}

// MARK: ── Flat line

private struct JLine: Identifiable {
    enum Content {
        case open(obj: Bool, count: Int, closeComma: Bool)
        case close(obj: Bool)
        case str(String)
        case num(String)
        case boo(Bool)
        case nul
    }
    let id: String
    let depth: Int
    let key: String?
    let content: Content
    var comma: Bool
}

private func jEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .replacingOccurrences(of: "\n", with: "\\n")
     .replacingOccurrences(of: "\r", with: "\\r")
     .replacingOccurrences(of: "\t", with: "\\t")
}

private func flatten(_ node: JNode, id: String, depth: Int, key: String?, comma: Bool) -> [JLine] {
    switch node {
    case .object(let pairs):
        var r = [JLine(id: id, depth: depth, key: key,
                       content: .open(obj: true, count: pairs.count, closeComma: comma), comma: false)]
        for (i, (k, v)) in pairs.enumerated() {
            r += flatten(v, id: "\(id).\(k)", depth: depth + 1, key: k, comma: i < pairs.count - 1)
        }
        r.append(JLine(id: id + "∎", depth: depth, key: nil, content: .close(obj: true), comma: comma))
        return r

    case .array(let items):
        var r = [JLine(id: id, depth: depth, key: key,
                       content: .open(obj: false, count: items.count, closeComma: comma), comma: false)]
        for (i, v) in items.enumerated() {
            r += flatten(v, id: "\(id)[\(i)]", depth: depth + 1, key: nil, comma: i < items.count - 1)
        }
        r.append(JLine(id: id + "∎", depth: depth, key: nil, content: .close(obj: false), comma: comma))
        return r

    case .string(let s):  return [JLine(id: id, depth: depth, key: key, content: .str(s), comma: comma)]
    case .number(let n):  return [JLine(id: id, depth: depth, key: key, content: .num(n), comma: comma)]
    case .bool(let b):    return [JLine(id: id, depth: depth, key: key, content: .boo(b), comma: comma)]
    case .null:           return [JLine(id: id, depth: depth, key: key, content: .nul,    comma: comma)]
    }
}

// MARK: ── Expand state

final class JExpandState: ObservableObject {
    @Published var collapsed: Set<String> = []
    func isCollapsed(_ id: String) -> Bool { collapsed.contains(id) }
    func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }
    func collapseAll(_ ids: [String]) { collapsed = Set(ids) }
    func expandAll() { collapsed = [] }
}

// MARK: ── Main view

struct JSONColorView: View {
    let text: String

    @StateObject private var expandState = JExpandState()
    @State private var allLines: [JLine] = []
    @State private var containerIDs: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Collapse all") { expandState.collapseAll(containerIDs) }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Expand all") { expandState.expandAll() }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("\(allLines.count) lines")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { line in
                        let collapsed: Bool = {
                            if case .open = line.content { return expandState.isCollapsed(line.id) }
                            return false
                        }()
                        JLineView(line: line, isCollapsed: collapsed, onToggle: { expandState.toggle(line.id) })
                    }
                }
                .padding(8)
            }
        }
        .onAppear { rebuild() }
        .onChange(of: text) { _ in rebuild() }
    }

    private func rebuild() {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            allLines = []; containerIDs = []; return
        }
        let lines = flatten(JNode.from(obj), id: "r", depth: 0, key: nil, comma: false)
        allLines = lines
        containerIDs = lines.compactMap { if case .open = $0.content { return $0.id }; return nil }
    }

    private var visibleLines: [JLine] {
        guard !expandState.collapsed.isEmpty else { return allLines }
        var result: [JLine] = []
        var i = allLines.startIndex
        while i < allLines.endIndex {
            let line = allLines[i]
            result.append(line)
            if case .open = line.content, expandState.isCollapsed(line.id) {
                i = allLines.index(after: i)
                while i < allLines.endIndex && allLines[i].depth > line.depth {
                    i = allLines.index(after: i)
                }
                if i < allLines.endIndex { i = allLines.index(after: i) }
            } else {
                i = allLines.index(after: i)
            }
        }
        return result
    }
}

// MARK: ── Line view

private struct JLineView: View {
    let line: JLine
    let isCollapsed: Bool
    let onToggle: () -> Void

    private let indent: CGFloat = 14
    private let chevW:  CGFloat = 12

    private static let keyC = Color(nsColor: .systemBlue)
    private static let strC = Color(nsColor: .systemOrange)
    private static let numC = Color(nsColor: .systemPurple)
    private static let booC = Color(nsColor: .systemTeal)

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(line.depth) * indent)
            lineContent
        }
        .font(.system(size: 11, design: .monospaced))
        .lineSpacing(1)
    }

    @ViewBuilder
    private var lineContent: some View {
        switch line.content {
        case .open(let obj, let count, let cc):
            Button(action: onToggle) {
                HStack(spacing: 2) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: chevW)
                    keyLabel
                    Text(obj ? "{" : "[").foregroundStyle(.primary)
                    if isCollapsed {
                        if count > 0 {
                            Text(" \(count) \(obj ? (count == 1 ? "key" : "keys") : (count == 1 ? "item" : "items")) ")
                                .foregroundStyle(.tertiary).italic()
                        }
                        Text(obj ? "}" : "]").foregroundStyle(.primary)
                        if cc { Text(",").foregroundStyle(.secondary) }
                    }
                }
            }
            .buttonStyle(.plain)

        case .close(let obj):
            HStack(spacing: 0) {
                Color.clear.frame(width: chevW)
                Text(obj ? "}" : "]").foregroundStyle(.primary)
                if line.comma { Text(",").foregroundStyle(.secondary) }
            }

        case .str(let s):
            HStack(spacing: 0) {
                Color.clear.frame(width: chevW)
                keyLabel
                (Text("\"").foregroundColor(Self.strC) +
                 Text(jEscape(s)).foregroundColor(Self.strC) +
                 Text("\"").foregroundColor(Self.strC))
                if line.comma { Text(",").foregroundStyle(.secondary) }
            }

        case .num(let n):
            HStack(spacing: 0) {
                Color.clear.frame(width: chevW)
                keyLabel
                Text(n).foregroundColor(Self.numC)
                if line.comma { Text(",").foregroundStyle(.secondary) }
            }

        case .boo(let b):
            HStack(spacing: 0) {
                Color.clear.frame(width: chevW)
                keyLabel
                Text(b ? "true" : "false").foregroundColor(Self.booC)
                if line.comma { Text(",").foregroundStyle(.secondary) }
            }

        case .nul:
            HStack(spacing: 0) {
                Color.clear.frame(width: chevW)
                keyLabel
                Text("null").foregroundStyle(.tertiary)
                if line.comma { Text(",").foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder
    private var keyLabel: some View {
        if let k = line.key {
            (Text("\"").foregroundColor(Self.keyC) +
             Text(jEscape(k)).foregroundColor(Self.keyC) +
             Text("\": ").foregroundColor(.secondary))
        }
    }
}
