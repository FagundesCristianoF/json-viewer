import Foundation

struct CurlBreakdown: Equatable {
    var method: String
    var baseURL: String
    var queryParams: [HTTPParam]
    var headers: [HTTPParam]
    /// Top-level JSON body keys. Empty when body is not a JSON object.
    var bodyParams: [HTTPParam]
    /// The full body string, kept in sync with bodyParams when not in raw mode.
    var rawBody: String
    /// When true, rawBody is the source of truth; bodyParams are not shown.
    var bodyIsRaw: Bool
    var insecure: Bool
}
