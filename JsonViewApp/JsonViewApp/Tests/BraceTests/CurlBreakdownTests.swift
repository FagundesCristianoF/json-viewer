import XCTest
@testable import Brace

final class CurlBreakdownTests: XCTestCase {

    func test_parse_url_and_method() throws {
        let curl = "curl -X POST 'https://api.example.com/items?page=1&size=10' -H 'Authorization: Bearer tok'"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertEqual(bd.method, "POST")
        XCTAssertEqual(bd.baseURL, "https://api.example.com/items")
    }

    func test_parse_query_params() throws {
        let curl = "curl 'https://api.example.com/items?page=1&size=10'"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertEqual(bd.queryParams.count, 2)
        XCTAssertEqual(bd.queryParams[0].key, "page")
        XCTAssertEqual(bd.queryParams[0].value, "1")
        XCTAssertEqual(bd.queryParams[1].key, "size")
        XCTAssertEqual(bd.queryParams[1].value, "10")
        XCTAssertTrue(bd.queryParams[0].isEnabled)
    }

    func test_parse_headers() throws {
        let curl = """
        curl -H 'Authorization: Bearer tok' -H 'Content-Type: application/json' https://api.example.com
        """
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertEqual(bd.headers.count, 2)
        let keys = bd.headers.map(\.key)
        XCTAssertTrue(keys.contains("Authorization"))
        XCTAssertTrue(keys.contains("Content-Type"))
    }

    func test_parse_json_body_into_params() throws {
        let curl = #"curl -X POST https://api.com -d '{"accountId":"abc","limit":10}'"#
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertFalse(bd.bodyIsRaw)
        XCTAssertEqual(bd.bodyParams.count, 2)
        let keys = bd.bodyParams.map(\.key).sorted()
        XCTAssertEqual(keys, ["accountId", "limit"])
        // values are raw JSON fragments
        let accountParam = bd.bodyParams.first { $0.key == "accountId" }!
        XCTAssertEqual(accountParam.value, #""abc""#)
        let limitParam = bd.bodyParams.first { $0.key == "limit" }!
        XCTAssertEqual(limitParam.value, "10")
    }

    func test_non_json_body_is_raw() throws {
        let curl = "curl -X POST https://api.com -d 'name=foo&bar=baz'"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertTrue(bd.bodyIsRaw)
        XCTAssertEqual(bd.rawBody, "name=foo&bar=baz")
        XCTAssertTrue(bd.bodyParams.isEmpty)
    }

    func test_no_query_params_when_clean_url() throws {
        let curl = "curl https://api.example.com/items"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertTrue(bd.queryParams.isEmpty)
        XCTAssertEqual(bd.baseURL, "https://api.example.com/items")
    }

    func test_insecure_flag() throws {
        let curl = "curl -k https://self-signed.example.com"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertTrue(bd.insecure)
    }
}

// MARK: - CurlBuilder tests

final class CurlBuilderTests: XCTestCase {

    func test_build_simple_get() {
        let bd = CurlBreakdown(
            method: "GET",
            baseURL: "https://api.example.com/items",
            queryParams: [HTTPParam(key: "page", value: "1"), HTTPParam(key: "size", value: "10")],
            headers: [HTTPParam(key: "Authorization", value: "Bearer tok")],
            bodyParams: [],
            rawBody: "",
            bodyIsRaw: false,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("GET"), "method")
        XCTAssertTrue(curl.contains("page=1"), "query param page")
        XCTAssertTrue(curl.contains("size=10"), "query param size")
        XCTAssertTrue(curl.contains("Authorization"), "header")
        XCTAssertFalse(curl.contains("-d"), "no body for GET")
    }

    func test_build_disabled_query_param_excluded() {
        let bd = CurlBreakdown(
            method: "GET",
            baseURL: "https://api.example.com",
            queryParams: [
                HTTPParam(key: "active", value: "true"),
                HTTPParam(key: "hidden", value: "1", isEnabled: false)
            ],
            headers: [],
            bodyParams: [],
            rawBody: "",
            bodyIsRaw: false,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("active=true"))
        XCTAssertFalse(curl.contains("hidden"))
    }

    func test_build_json_body_from_params() {
        let bd = CurlBreakdown(
            method: "POST",
            baseURL: "https://api.example.com",
            queryParams: [],
            headers: [],
            bodyParams: [
                HTTPParam(key: "accountId", value: #""abc""#),
                HTTPParam(key: "limit", value: "10")
            ],
            rawBody: "",
            bodyIsRaw: false,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("-d") || curl.contains("--data"))
        XCTAssertTrue(curl.contains("accountId"))
        XCTAssertTrue(curl.contains("limit"))
    }

    func test_build_raw_body() {
        let bd = CurlBreakdown(
            method: "POST",
            baseURL: "https://api.example.com",
            queryParams: [],
            headers: [],
            bodyParams: [],
            rawBody: "name=foo&bar=baz",
            bodyIsRaw: true,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("name=foo"))
    }

    func test_build_insecure_flag() {
        let bd = CurlBreakdown(
            method: "GET",
            baseURL: "https://self-signed.example.com",
            queryParams: [],
            headers: [],
            bodyParams: [],
            rawBody: "",
            bodyIsRaw: false,
            insecure: true
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("-k") || curl.contains("--insecure"))
    }

    func test_build_disabled_header_excluded() {
        let bd = CurlBreakdown(
            method: "GET",
            baseURL: "https://api.example.com",
            queryParams: [],
            headers: [
                HTTPParam(key: "Authorization", value: "Bearer tok"),
                HTTPParam(key: "X-Debug", value: "1", isEnabled: false)
            ],
            bodyParams: [],
            rawBody: "",
            bodyIsRaw: false,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("Authorization"))
        XCTAssertFalse(curl.contains("X-Debug"))
    }

    func test_roundtrip_parse_build_parse() throws {
        let original = #"curl -X POST 'https://api.example.com/v1/items?page=1' -H 'Authorization: Bearer token123' -H 'Content-Type: application/json' -d '{"accountId":"abc","limit":5}'"#
        let bd1 = try CurlParser.parseBreakdown(original)
        let rebuilt = CurlBuilder.build(bd1)
        let bd2 = try CurlParser.parseBreakdown(rebuilt)
        XCTAssertEqual(bd1.method, bd2.method)
        XCTAssertEqual(bd1.baseURL, bd2.baseURL)
        XCTAssertEqual(bd1.queryParams.map(\.key).sorted(), bd2.queryParams.map(\.key).sorted())
        XCTAssertEqual(bd1.headers.map(\.key).sorted(), bd2.headers.map(\.key).sorted())
        XCTAssertEqual(bd1.bodyParams.map(\.key).sorted(), bd2.bodyParams.map(\.key).sorted())
    }
}
