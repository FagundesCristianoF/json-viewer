import XCTest
@testable import DevKit

final class OptionsParserTests: XCTestCase {

    func test_parse_array_of_objects() {
        let json = """
        [{"id":"abc","displayName":"Option A"},{"id":"def","displayName":"Option B"}]
        """
        let results = OptionsParser.parse(json)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "abc")
        XCTAssertEqual(results[0].displayName, "Option A")
        XCTAssertEqual(results[1].id, "def")
    }

    func test_parse_custom_id_path() {
        let json = """
        [{"uuid":"x1","name":"First"},{"uuid":"x2","name":"Second"}]
        """
        let results = OptionsParser.parse(json, idPath: "uuid", namePath: "name")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "x1")
        XCTAssertEqual(results[0].displayName, "First")
    }

    func test_parse_empty_json_returns_empty() {
        XCTAssertEqual(OptionsParser.parse("").count, 0)
        XCTAssertEqual(OptionsParser.parse("[]").count, 0)
    }

    func test_parse_invalid_json_object_returns_empty() {
        // Strings starting with { or [ but invalid JSON → empty
        XCTAssertEqual(OptionsParser.parse("{bad json}").count, 0)
        XCTAssertEqual(OptionsParser.parse("[bad json]").count, 0)
    }

    func test_parse_missing_id_field_skips_entry() {
        let json = """
        [{"displayName":"No ID here"},{"id":"valid","displayName":"Valid"}]
        """
        let results = OptionsParser.parse(json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "valid")
    }
}
