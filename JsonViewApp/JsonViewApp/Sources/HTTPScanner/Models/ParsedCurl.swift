import Foundation

struct ParsedCurl {
    var url: String
    var method: String = "GET"
    var headers: [String: String] = [:]
    var data: String? = nil
    var insecure: Bool = false
    var allowRedirects: Bool = true
}
