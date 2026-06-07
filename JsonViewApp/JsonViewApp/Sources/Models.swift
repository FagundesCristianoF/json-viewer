import Foundation

// MARK: - Workspace

struct WorkspaceFile: Identifiable, Hashable {
    var id: URL { url }
    var url: URL
    var name: String
    var isDirectory: Bool
    var children: [WorkspaceFile]

    static func == (lhs: WorkspaceFile, rhs: WorkspaceFile) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - Parse Error

struct ParseErrorInfo {
    var message: String
    var line: Int
    var col: Int
}

// MARK: - Node Kind

enum NodeKind: String, Codable {
    case object
    case array
    case string
    case number
    case bool
    case null
}

// MARK: - NodeInfo (decoded from jv_tree_json)

struct NodeInfo: Codable {
    var nodeId: Int
    var key: String?
    var value: String?
    var kind: NodeKind
    var path: String
    var depth: Int
    var parent: Int?
    var children: [Int]

    enum CodingKeys: String, CodingKey {
        case nodeId = "id"
        case key
        case value
        case kind
        case path
        case depth
        case parent
        case children
    }
}

extension NodeInfo: Identifiable {
    var id: Int { nodeId }
}

// MARK: - SmellInfo (decoded from jv_smells)

struct SmellInfo: Codable, Identifiable {
    var path: String
    var message: String

    var id: String { path + message }
}

// MARK: - CommitInfo (decoded from jv_git_history)

struct CommitInfo: Codable, Identifiable {
    var hash: String
    var message: String
    var timestamp: Int64
    var relative: String

    var id: String { hash }
}

// MARK: - FoldRange (decoded from jv_fold_ranges)

struct FoldRange: Codable, Identifiable {
    var start: Int
    var end: Int

    var id: String { "\(start)-\(end)" }
}
