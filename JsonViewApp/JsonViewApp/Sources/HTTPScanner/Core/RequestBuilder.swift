import Foundation

enum RequestBuilder {

    // Build final (url, method, headers, body) for one option value
    static func build(curl: ParsedCurl, param: String, value: String) -> (url: String, method: String, headers: [String: String], body: String?) {
        let url = substituteQueryParam(url: curl.url, param: param, value: value)
        var headers = curl.headers
        var body = curl.data

        if let original = curl.data,
           let substituted = substituteJSONBody(body: original, param: param, value: value) {
            body = substituted
            // Ensure Content-Type: application/json if not already set
            let hasJSON = headers.keys.contains(where: {
                $0.lowercased() == "content-type" &&
                (headers[$0] ?? "").lowercased().contains("application/json")
            })
            if !hasJSON {
                let existingKey = headers.keys.first { $0.lowercased() == "content-type" }
                if existingKey == nil {
                    headers["Content-Type"] = "application/json"
                }
            }
        }

        return (url, curl.method, headers, body)
    }

    // MARK: - URL query substitution

    static func substituteQueryParam(url: String, param: String, value: String) -> String {
        guard var components = URLComponents(string: url) else { return url }
        var items = components.queryItems ?? []
        if let idx = items.firstIndex(where: { $0.name == param }) {
            items[idx] = URLQueryItem(name: param, value: value)
        } else {
            items.append(URLQueryItem(name: param, value: value))
        }
        components.queryItems = items
        return components.string ?? url
    }

    // MARK: - JSON body substitution (top-level dict only)

    static func substituteJSONBody(body: String, param: String, value: String) -> String? {
        guard let data = body.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        dict[param] = value
        guard let out = try? JSONSerialization.data(withJSONObject: dict, options: [.withoutEscapingSlashes]),
              let str = String(data: out, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: - SKU/search body mutation

    static func prepareSearchBody(body: String?, query: String, page: Int) -> String? {
        guard let body, let data = body.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return body
        }
        dict["query"] = query
        dict["page"] = page
        let currentPageSize = (dict["pageSize"] as? Int) ?? (dict["pageSize"].flatMap { Int("\($0)") } ?? 0)
        dict["pageSize"] = max(currentPageSize, 50)
        dict.removeValue(forKey: "projections")
        guard let out = try? JSONSerialization.data(withJSONObject: dict, options: [.withoutEscapingSlashes]),
              let str = String(data: out, encoding: .utf8) else { return body }
        return str
    }

    static func setPage(body: String?, page: Int) -> String? {
        guard page != 0, let body,
              let data = body.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return body
        }
        dict["page"] = page
        guard let out = try? JSONSerialization.data(withJSONObject: dict, options: [.withoutEscapingSlashes]),
              let str = String(data: out, encoding: .utf8) else { return body }
        return str
    }
}
