import Foundation

enum ResultStatus {
    case pending
    case running
    case matched
    case notMatched
    case error(String)
    case skipped(String)

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .matched: return "Matched"
        case .notMatched: return "No match"
        case .error(let e): return "Error: \(e)"
        case .skipped(let r): return "Skipped: \(r)"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .pending, .running: return false
        default: return true
        }
    }
}

struct OptionResult: Identifiable {
    let id: String          // option id
    let displayName: String?
    var status: ResultStatus = .pending
    var statusCode: Int?
    var responseBody: String?
    var responseHeaders: [String: String] = [:]
    var pageScanned: Int?
    var prettyBody: String?  // cached once when response is set

    var label: String { displayName ?? id }

    var isJSON: Bool {
        let ct = responseHeaders["Content-Type"] ?? responseHeaders["content-type"] ?? ""
        return ct.lowercased().contains("application/json")
    }
}

struct ScanProgress {
    var current: Int = 0
    var total: Int = 0
    var fraction: Double { total > 0 ? Double(current) / Double(total) : 0 }
}
