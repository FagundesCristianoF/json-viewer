import Foundation

enum HTTPExecutor {

    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: String
        var data: Any? { // parsed JSON, cached lazily
            guard let d = body.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: d)
        }
    }

    struct FetchResult {
        let optionId: String
        let displayName: String?
        let response: Response?
        let error: Error?
        let pageScanned: Int?
    }

    // MARK: - Single page fetch

    static func fetchPage(
        curl: ParsedCurl,
        param: String,
        optionId: String,
        timeout: Double,
        body: String?,
        session: URLSession
    ) async throws -> Response {
        let (url, method, headers, _) = RequestBuilder.build(curl: curl, param: param, value: optionId)

        guard let parsedURL = URL(string: url) else {
            throw URLError(.badURL, userInfo: [NSURLErrorFailingURLStringErrorKey: url])
        }
        var req = URLRequest(url: parsedURL, timeoutInterval: timeout)
        req.httpMethod = method
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let b = body { req.httpBody = b.data(using: .utf8) }

        let (data, urlResponse) = try await session.data(for: req)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let statusCode = http.statusCode
        var responseHeaders: [String: String] = [:]
        http.allHeaderFields.forEach { k, v in responseHeaders["\(k)"] = "\(v)" }
        let bodyStr = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return Response(statusCode: statusCode, headers: responseHeaders, body: bodyStr)
    }

    // MARK: - Full fetch with pagination (for product filters)

    static func fetch(
        curl: ParsedCurl,
        param: String,
        option: OptionEntry,
        config: ScanConfig,
        session: URLSession
    ) async -> FetchResult {
        let searchQuery = config.effectiveSearchQuery

        do {
            var body = curl.data
            if let q = searchQuery {
                body = RequestBuilder.prepareSearchBody(body: body, query: q, page: 0)
            }

            let resp = try await fetchPage(
                curl: curl,
                param: param,
                optionId: option.id,
                timeout: config.timeout,
                body: body,
                session: session
            )

            return FetchResult(optionId: option.id, displayName: option.displayName, response: resp, error: nil, pageScanned: nil)

        } catch {
            return FetchResult(optionId: option.id, displayName: option.displayName, response: nil, error: error, pageScanned: nil)
        }
    }

    // MARK: - Session factory

    static func makeSession(insecure: Bool) -> URLSession {
        if insecure {
            let config = URLSessionConfiguration.ephemeral
            return URLSession(configuration: config, delegate: InsecureDelegate(), delegateQueue: nil)
        }
        return URLSession(configuration: .ephemeral)
    }
}

// MARK: - TLS bypass delegate

private class InsecureDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
