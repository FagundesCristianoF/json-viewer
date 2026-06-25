import Foundation

enum CurlBuilder {

    static func build(_ bd: CurlBreakdown) -> String {
        var parts: [String] = ["curl"]

        parts += ["-X", bd.method]

        // URL with enabled query params
        let enabledQuery = bd.queryParams.filter(\.isEnabled)
        var urlString = bd.baseURL
        if !enabledQuery.isEmpty {
            var comps = URLComponents(string: bd.baseURL) ?? URLComponents()
            comps.queryItems = enabledQuery.map { URLQueryItem(name: $0.key, value: $0.value) }
            urlString = comps.string ?? bd.baseURL
        }
        parts.append("'\(urlString)'")

        // Enabled headers
        for h in bd.headers where h.isEnabled {
            parts += ["-H", "'\(h.key): \(h.value)'"]
        }

        // Insecure
        if bd.insecure {
            parts.append("-k")
        }

        // Body
        let body = resolvedBody(bd)
        if !body.isEmpty {
            parts += ["-d", "'\(body.replacingOccurrences(of: "'", with: "\\'"))'"]
        }

        return parts.joined(separator: " \\\n  ")
    }

    // MARK: - Private

    private static func resolvedBody(_ bd: CurlBreakdown) -> String {
        if bd.bodyIsRaw { return bd.rawBody }
        let enabled = bd.bodyParams.filter(\.isEnabled)
        guard !enabled.isEmpty else { return bd.rawBody }

        // Rebuild JSON from raw fragment values
        var jsonParts: [String] = []
        for param in enabled {
            let escapedKey = param.key
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            jsonParts.append("\"\(escapedKey)\":\(param.value)")
        }
        return "{\(jsonParts.joined(separator: ","))}"
    }
}
