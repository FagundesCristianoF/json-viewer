import XCTest
@testable import DevKit

final class FiltersTests: XCTestCase {

    private func makeResult(body: String, statusCode: Int = 200) -> OptionResult {
        var r = OptionResult(id: "test", displayName: nil)
        r.responseBody = body
        r.statusCode = statusCode
        r.prettyBody = body
        r.status = .matched
        return r
    }

    func test_jsonpath_filter_matches() {
        let body = """
        {"items":[{"active":true,"name":"A"},{"active":false,"name":"B"}]}
        """
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: "$.items[?(@.active == true)]", requireResultsPath: nil)
        XCTAssertTrue(Filters.matches(response: result, data: data, args: args))
    }

    func test_jsonpath_filter_no_match() {
        let body = """
        {"items":[{"active":false,"name":"B"}]}
        """
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: "$.items[?(@.active == true)]", requireResultsPath: nil)
        XCTAssertFalse(Filters.matches(response: result, data: data, args: args))
    }

    func test_require_results_path_match() {
        let body = """
        {"data":[{"id":1},{"id":2}]}
        """
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: nil, requireResultsPath: "$.data[*]")
        XCTAssertTrue(Filters.matches(response: result, data: data, args: args))
    }

    func test_require_results_path_empty_array_no_match() {
        let body = """
        {"data":[]}
        """
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: nil, requireResultsPath: "$.data[*]")
        XCTAssertFalse(Filters.matches(response: result, data: data, args: args))
    }

    func test_no_filters_always_matches() {
        let body = "{}"
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: nil, requireResultsPath: nil)
        XCTAssertTrue(Filters.matches(response: result, data: data, args: args))
    }
}
