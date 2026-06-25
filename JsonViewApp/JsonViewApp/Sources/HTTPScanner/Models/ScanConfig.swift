import Foundation

struct FilterRule: Codable, Equatable, Hashable {
    var path: String
}

struct FilterGroup: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var rules: [FilterRule]

    init(rules: [FilterRule] = [FilterRule(path: "")]) {
        self.id = UUID()
        self.rules = rules
    }
}

struct ScanConfig: Equatable {
    var param: String = "accountId"
    var optionIdPath: String = "id"
    var optionNamePath: String = "displayName"
    var jsonpath: String = ""
    var requireGroups: [FilterGroup] = []
    var query: String = ""
    var workers: Int = 12
    var timeout: Double = 30.0

    var isFilterMode: Bool {
        !jsonpath.isEmpty || !requireGroups.isEmpty || !query.isEmpty
    }

    var effectiveJsonpath: String? { jsonpath.isEmpty ? nil : jsonpath }
    var effectiveSearchQuery: String? { query.isEmpty ? nil : query }

    // outer = AND, inner = OR; empty paths filtered out
    var effectiveRequireGroups: [[String]] {
        requireGroups.compactMap { group in
            let paths = group.rules.map(\.path).filter { !$0.isEmpty }
            return paths.isEmpty ? nil : paths
        }
    }
}

// MARK: - Codable (migrates legacy requireResultsPath → first group)

extension ScanConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case param, optionIdPath, optionNamePath, jsonpath
        case requireGroups, requireResultsPath
        case query, workers, timeout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        param          = try c.decodeIfPresent(String.self, forKey: .param)          ?? "accountId"
        optionIdPath   = try c.decodeIfPresent(String.self, forKey: .optionIdPath)   ?? "id"
        optionNamePath = try c.decodeIfPresent(String.self, forKey: .optionNamePath) ?? "displayName"
        jsonpath       = try c.decodeIfPresent(String.self, forKey: .jsonpath)       ?? ""
        query          = try c.decodeIfPresent(String.self, forKey: .query)          ?? ""
        workers        = try c.decodeIfPresent(Int.self,    forKey: .workers)        ?? 12
        timeout        = try c.decodeIfPresent(Double.self, forKey: .timeout)        ?? 30.0

        if let groups = try c.decodeIfPresent([FilterGroup].self, forKey: .requireGroups) {
            requireGroups = groups
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .requireResultsPath), !legacy.isEmpty {
            requireGroups = [FilterGroup(rules: [FilterRule(path: legacy)])]
        } else {
            requireGroups = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(param,         forKey: .param)
        try c.encode(optionIdPath,  forKey: .optionIdPath)
        try c.encode(optionNamePath,forKey: .optionNamePath)
        try c.encode(jsonpath,      forKey: .jsonpath)
        try c.encode(requireGroups, forKey: .requireGroups)
        try c.encode(query,         forKey: .query)
        try c.encode(workers,       forKey: .workers)
        try c.encode(timeout,       forKey: .timeout)
    }
}
