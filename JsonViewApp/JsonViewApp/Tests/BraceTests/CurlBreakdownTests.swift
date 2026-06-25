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
