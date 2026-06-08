import XCTest
@testable import DevKit

final class CurlParserTests: XCTestCase {

    func test_parse_simple_GET() throws {
        let curl = "curl https://api.example.com/users"
        let result = try CurlParser.parse(curl)
        XCTAssertEqual(result.url, "https://api.example.com/users")
        XCTAssertEqual(result.method, "GET")
    }

    func test_parse_POST_with_data() throws {
        let curl = """
        curl -X POST https://api.example.com/search \
          -H 'Content-Type: application/json' \
          -d '{"accountId":"123"}'
        """
        let result = try CurlParser.parse(curl)
        XCTAssertEqual(result.method, "POST")
        XCTAssertEqual(result.url, "https://api.example.com/search")
        XCTAssertNotNil(result.data)
    }

    func test_parse_with_auth_header() throws {
        let curl = """
        curl https://api.example.com/data \
          -H 'Authorization: Bearer token123'
        """
        let result = try CurlParser.parse(curl)
        let authValue = result.headers["Authorization"]
        XCTAssertNotNil(authValue)
        XCTAssertTrue(authValue?.contains("Bearer") ?? false)
    }

    func test_parse_invalid_throws() {
        XCTAssertThrowsError(try CurlParser.parse("not a curl command"))
    }

    func test_parse_empty_throws() {
        XCTAssertThrowsError(try CurlParser.parse(""))
    }
}
