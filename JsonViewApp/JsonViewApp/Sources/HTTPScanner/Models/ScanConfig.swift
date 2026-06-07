import Foundation

struct ScanConfig: Codable {
    var param: String = "accountId"
    var optionIdPath: String = "id"
    var optionNamePath: String = "displayName"
    var jsonpath: String = ""
    var requireResultsPath: String = ""
    var query: String = ""
    var workers: Int = 12
    var timeout: Double = 30.0

    var isFilterMode: Bool {
        !jsonpath.isEmpty || !requireResultsPath.isEmpty
    }

    var effectiveRequireResultsPath: String? { requireResultsPath.isEmpty ? nil : requireResultsPath }
    var effectiveJsonpath: String? { jsonpath.isEmpty ? nil : jsonpath }
    var effectiveSearchQuery: String? { query.isEmpty ? nil : query }
}
