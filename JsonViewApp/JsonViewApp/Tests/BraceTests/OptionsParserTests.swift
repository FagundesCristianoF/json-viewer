import XCTest
@testable import Brace

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

    // MARK: - JSONPath ID path (wildcard into nested array)

    func test_parse_jsonpath_wildcard_id_path() {
        // Reported case: options object wrapping an array, ids pulled via $.accounts[*].id
        let json = """
        {"accounts":[{"id":"123"},{"id":"456"}]}
        """
        let results = OptionsParser.parse(json, idPath: "$.accounts[*].id", namePath: "displayName")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "123")
        XCTAssertEqual(results[1].id, "456")
    }

    func test_parse_jsonpath_wildcard_id_and_name() {
        let json = """
        {"accounts":[{"id":"123","label":"Acme"},{"id":"456","label":"Globex"}]}
        """
        let results = OptionsParser.parse(json, idPath: "$.accounts[*].id", namePath: "$.accounts[*].label")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "123")
        XCTAssertEqual(results[0].displayName, "Acme")
        XCTAssertEqual(results[1].displayName, "Globex")
    }

    // MARK: - Smart-quote regression guard

    // macOS "smart quotes" rewrite " into “ ” which is invalid JSON. The app
    // disables quote substitution at the input layer (App.swift); the parser
    // stays strict and rejects curly-quote JSON rather than silently guessing.
    func test_parse_curly_quotes_are_invalid_json() {
        let json = "{\u{201C}accounts\u{201D}: [{\u{201C}id\u{201D}: \u{201C}123\u{201D}}]}"
        let results = OptionsParser.parse(json, idPath: "$.accounts[*].id", namePath: "displayName")
        XCTAssertEqual(results.count, 0)
    }
}
