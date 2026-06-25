import Foundation

enum CurlParseError: Error, LocalizedError {
    case empty
    case shlex(String)
    case noURL
    case missingValue(String)
    case badHeader(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "Empty curl command"
        case .shlex(let e): return "Could not parse curl (shlex): \(e)"
        case .noURL: return "No URL found in curl (expected http(s)://... or --url)"
        case .missingValue(let f): return "\(f) missing value"
        case .badHeader(let h): return "Header must be 'Name: value', got: \(h)"
        }
    }
}

enum CurlParser {

    static func parse(_ input: String) throws -> ParsedCurl {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CurlParseError.empty }

        // Remove line continuations
        text = text.replacingOccurrences(of: #"\\\s*\n\s*"#, with: " ", options: .regularExpression)

        // Remove leading $ prompt
        if let m = text.range(of: #"^\s*\$\s*"#, options: .regularExpression) {
            text = String(text[m.upperBound...])
        }

        // Remove leading "curl"
        if text.lowercased().hasPrefix("curl") {
            text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }

        let parts: [String]
        do {
            parts = try shlexSplit(text)
        } catch {
            throw CurlParseError.shlex(error.localizedDescription)
        }

        var url: String? = nil
        var method = "GET"
        var headers: [String: String] = [:]
        var data: String? = nil
        var cookieParts: [String] = []
        var insecure = false
        var allowRedirects = true
        var useGetWithData = false

        var i = 0
        while i < parts.count {
            let p = parts[i]

            switch p {
            case "-X", "--request":
                guard i + 1 < parts.count else { throw CurlParseError.missingValue(p) }
                method = parts[i + 1].uppercased(); i += 2

            case "-H", "--header":
                guard i + 1 < parts.count else { throw CurlParseError.missingValue(p) }
                let raw = stripWrappingQuotes(parts[i + 1])
                guard let colon = raw.firstIndex(of: ":") else { throw CurlParseError.badHeader(raw) }
                let name = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .init(charactersIn: " "))
                headers[name] = value; i += 2

            case "-b", "--cookie":
                guard i + 1 < parts.count else { throw CurlParseError.missingValue(p) }
                cookieParts.append(stripWrappingQuotes(parts[i + 1]).trimmingCharacters(in: .whitespaces)); i += 2

            case "-d", "--data", "--data-binary", "--data-raw":
                guard i + 1 < parts.count else { throw CurlParseError.missingValue(p) }
                data = parts[i + 1]
                if method == "GET" { method = "POST" }
                i += 2

            case "--data-urlencode":
                guard i + 1 < parts.count else { throw CurlParseError.missingValue(p) }
                let v = parts[i + 1]
                data = data.map { "\($0)&\(v)" } ?? v; i += 2

            case "-G", "--get":
                useGetWithData = true; i += 1

            case "-k", "--insecure":
                insecure = true; i += 1

            case "-L", "--location":
                allowRedirects = true; i += 1

            case "--url":
                guard i + 1 < parts.count else { throw CurlParseError.missingValue(p) }
                url = parts[i + 1]; i += 2

            // Flags that take a value but should be silently consumed (not treated as URL)
            case "--proxy", "-x",
                 "--proxy-user", "--proxy-header",
                 "--connect-to", "--resolve",
                 "--cert", "--key", "--cacert", "--capath",
                 "--max-time", "-m", "--retry", "--retry-delay",
                 "--output", "-o", "--user-agent", "-A",
                 "--referer", "-e", "--interface",
                 "--limit-rate", "--max-filesize",
                 "--noproxy", "--socks5", "--socks4",
                 "-u", "--user",
                 "--compressed":  // --compressed takes no value but safe to consume
                if p == "--compressed" {
                    i += 1  // no value
                } else if i + 1 < parts.count {
                    i += 2  // skip flag + its value
                } else {
                    i += 1
                }

            default:
                let lower = p.lowercased()
                if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
                    url = p; i += 1
                } else if p.hasPrefix("-") {
                    i += 1  // unknown flag — skip flag only; value (if any) handled as next token
                } else {
                    i += 1
                }
            }
        }

        guard let resolvedURL = url else { throw CurlParseError.noURL }

        var finalURL = resolvedURL
        var finalData = data

        // -G: append data to query string
        if useGetWithData, let d = data {
            let sep = finalURL.contains("?") ? "&" : "?"
            finalURL = "\(finalURL)\(sep)\(d)"
            finalData = nil
            method = "GET"
        }

        // Merge cookies
        if !cookieParts.isEmpty {
            let merged = cookieParts.joined(separator: "; ")
            let existingKey = headers.keys.first { $0.lowercased() == "cookie" }
            if let key = existingKey {
                let existing = headers.removeValue(forKey: key) ?? ""
                headers["Cookie"] = "\(existing); \(merged)"
            } else {
                headers["Cookie"] = merged
            }
        }

        return ParsedCurl(
            url: finalURL,
            method: method,
            headers: headers,
            data: finalData,
            insecure: insecure,
            allowRedirects: allowRedirects
        )
    }

    // MARK: - Breakdown

    static func parseBreakdown(_ input: String) throws -> CurlBreakdown {
        let parsed = try parse(input)

        // Split URL into base + query params
        var baseURL = parsed.url
        var queryParams: [HTTPParam] = []
        if var components = URLComponents(string: parsed.url) {
            queryParams = (components.queryItems ?? []).map {
                HTTPParam(key: $0.name, value: $0.value ?? "")
            }
            components.query = nil
            baseURL = components.string ?? parsed.url
        }

        // Headers dict → ordered array
        let headers: [HTTPParam] = parsed.headers
            .sorted { $0.key < $1.key }
            .map { HTTPParam(key: $0.key, value: $0.value) }

        // Body
        let rawBody = parsed.data ?? ""
        var bodyParams: [HTTPParam] = []
        var bodyIsRaw = true

        if !rawBody.isEmpty,
           let data = rawBody.data(using: .utf8),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            bodyIsRaw = false
            bodyParams = dict.keys.sorted().compactMap { key -> HTTPParam? in
                guard let val = dict[key] else { return nil }
                let fragment: String
                if let str = val as? String {
                    fragment = "\"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
                } else if let num = val as? NSNumber {
                    if CFGetTypeID(num) == CFBooleanGetTypeID() {
                        fragment = num.boolValue ? "true" : "false"
                    } else {
                        fragment = num.stringValue
                    }
                } else if val is NSNull {
                    fragment = "null"
                } else if let encoded = try? JSONSerialization.data(withJSONObject: val),
                          let str = String(data: encoded, encoding: .utf8) {
                    fragment = str
                } else {
                    return nil
                }
                return HTTPParam(key: key, value: fragment)
            }
        }

        return CurlBreakdown(
            method: parsed.method,
            baseURL: baseURL,
            queryParams: queryParams,
            headers: headers,
            bodyParams: bodyParams,
            rawBody: rawBody,
            bodyIsRaw: bodyIsRaw,
            insecure: parsed.insecure
        )
    }

    // MARK: - Helpers

    private static func stripWrappingQuotes(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2,
              let first = t.first, let last = t.last,
              first == last, (first == "'" || first == "\"") else { return t }
        return String(t.dropFirst().dropLast())
    }

    // POSIX shlex tokenizer
    private static func shlexSplit(_ s: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var idx = s.startIndex

        while idx < s.endIndex {
            let c = s[idx]
            let next = s.index(after: idx)

            if inSingle {
                if c == "'" { inSingle = false }
                else { current.append(c) }
            } else if inDouble {
                if c == "\\" && next < s.endIndex {
                    let nc = s[next]
                    if ["\"", "\\", "$", "`", "\n"].contains(nc) {
                        current.append(nc); idx = s.index(after: next); continue
                    } else { current.append(c) }
                } else if c == "\"" { inDouble = false }
                else { current.append(c) }
            } else {
                if c == "'" { inSingle = true }
                else if c == "\"" { inDouble = true }
                else if c == "\\" && next < s.endIndex {
                    current.append(s[next]); idx = s.index(after: next); continue
                } else if c.isWhitespace {
                    if !current.isEmpty { tokens.append(current); current = "" }
                } else { current.append(c) }
            }
            idx = s.index(after: idx)
        }

        if inSingle || inDouble {
            throw CurlParseError.shlex("Unterminated quote")
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
