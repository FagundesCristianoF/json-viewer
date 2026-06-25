import XCTest
@testable import Brace

final class FiltersTests: XCTestCase {

    private func makeResult(body: String, statusCode: Int = 200) -> OptionResult {
        var r = OptionResult(id: "test", displayName: nil)
        r.responseBody = body
        r.statusCode = statusCode
        r.prettyBody = body
        r.status = .matched
        return r
    }

    private func data(_ body: String) -> Any? {
        try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
    }

    func test_jsonpath_filter_matches() {
        let body = """
        {"items":[{"active":true,"name":"A"},{"active":false,"name":"B"}]}
        """
        let result = makeResult(body: body)
        let args = Filters.FilterArgs(jsonpath: "$.items[?(@.active == true)]", requireGroups: [])
        XCTAssertTrue(Filters.matches(response: result, data: data(body), args: args))
    }

    func test_jsonpath_filter_no_match() {
        let body = """
        {"items":[{"active":false,"name":"B"}]}
        """
        let result = makeResult(body: body)
        let args = Filters.FilterArgs(jsonpath: "$.items[?(@.active == true)]", requireGroups: [])
        XCTAssertFalse(Filters.matches(response: result, data: data(body), args: args))
    }

    func test_require_group_single_rule_match() {
        let body = """
        {"data":[{"id":1},{"id":2}]}
        """
        let result = makeResult(body: body)
        let args = Filters.FilterArgs(jsonpath: nil, requireGroups: [["$.data[*]"]])
        XCTAssertTrue(Filters.matches(response: result, data: data(body), args: args))
    }

    func test_require_group_empty_array_no_match() {
        let body = """
        {"data":[]}
        """
        let result = makeResult(body: body)
        let args = Filters.FilterArgs(jsonpath: nil, requireGroups: [["$.data[*]"]])
        XCTAssertFalse(Filters.matches(response: result, data: data(body), args: args))
    }

    func test_or_within_group_matches_second_rule() {
        let body = """
        {"b":[1,2]}
        """
        let result = makeResult(body: body)
        // group has two OR rules: $.a[*] (no match) OR $.b[*] (match)
        let args = Filters.FilterArgs(jsonpath: nil, requireGroups: [["$.a[*]", "$.b[*]"]])
        XCTAssertTrue(Filters.matches(response: result, data: data(body), args: args))
    }

    func test_and_between_groups_both_must_match() {
        let body = """
        {"a":[1],"b":[2]}
        """
        let result = makeResult(body: body)
        let args = Filters.FilterArgs(jsonpath: nil, requireGroups: [["$.a[*]"], ["$.b[*]"]])
        XCTAssertTrue(Filters.matches(response: result, data: data(body), args: args))
    }

    func test_and_between_groups_one_fails() {
        let body = """
        {"a":[1]}
        """
        let result = makeResult(body: body)
        // group2 requires $.b[*] which doesn't exist
        let args = Filters.FilterArgs(jsonpath: nil, requireGroups: [["$.a[*]"], ["$.b[*]"]])
        XCTAssertFalse(Filters.matches(response: result, data: data(body), args: args))
    }

    func test_no_filters_always_matches() {
        let body = "{}"
        let result = makeResult(body: body)
        let args = Filters.FilterArgs(jsonpath: nil, requireGroups: [])
        XCTAssertTrue(Filters.matches(response: result, data: data(body), args: args))
    }

    func test_require_group_non_200_no_match() {
        let body = """
        {"data":[1]}
        """
        let result = makeResult(body: body, statusCode: 403)
        let args = Filters.FilterArgs(jsonpath: nil, requireGroups: [["$.data[*]"]])
        XCTAssertFalse(Filters.matches(response: result, data: data(body), args: args))
    }
}
