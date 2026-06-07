import Foundation

struct OptionEntry: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String?

    func toOutputDict() -> [String: Any?] {
        ["id": id, "displayName": displayName as Any?]
    }

    func toOutputJSON() -> String {
        let dn = displayName.map { "\"\($0.jsonEscaped)\"" } ?? "null"
        return "{\"id\":\"\(id.jsonEscaped)\",\"displayName\":\(dn)}"
    }
}

private extension String {
    var jsonEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
