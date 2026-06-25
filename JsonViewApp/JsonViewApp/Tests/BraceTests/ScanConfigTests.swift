import XCTest
@testable import Brace

final class ScanConfigTests: XCTestCase {

    func test_isFilterMode_false_when_all_empty() {
        let config = ScanConfig()
        XCTAssertFalse(config.isFilterMode)
    }

    func test_isFilterMode_true_when_jsonpath_set() {
        var config = ScanConfig()
        config.jsonpath = "$.items[*]"
        XCTAssertTrue(config.isFilterMode)
    }

    func test_isFilterMode_true_when_requireGroups_set() {
        var config = ScanConfig()
        config.requireGroups = [FilterGroup(rules: [FilterRule(path: "$.data")])]
        XCTAssertTrue(config.isFilterMode)
    }

    func test_effectiveJsonpath_nil_when_empty() {
        var config = ScanConfig()
        config.jsonpath = ""
        XCTAssertNil(config.effectiveJsonpath)
    }

    func test_effectiveJsonpath_value_when_set() {
        var config = ScanConfig()
        config.jsonpath = "$.items"
        XCTAssertEqual(config.effectiveJsonpath, "$.items")
    }

    func test_effectiveRequireGroups_filters_empty_paths() {
        var config = ScanConfig()
        config.requireGroups = [
            FilterGroup(rules: [FilterRule(path: "$.data"), FilterRule(path: "")]),
            FilterGroup(rules: [FilterRule(path: "")])
        ]
        XCTAssertEqual(config.effectiveRequireGroups, [["$.data"]])
    }

    func test_effectiveSearchQuery_nil_when_empty() {
        var config = ScanConfig()
        config.query = ""
        XCTAssertNil(config.effectiveSearchQuery)
    }

    func test_codable_roundTrip() throws {
        var config = ScanConfig()
        config.param = "userId"
        config.jsonpath = "$.users[*]"
        config.workers = 8
        config.timeout = 15.0
        config.requireGroups = [FilterGroup(rules: [FilterRule(path: "$.data[*]")])]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ScanConfig.self, from: data)

        XCTAssertEqual(decoded.param, "userId")
        XCTAssertEqual(decoded.jsonpath, "$.users[*]")
        XCTAssertEqual(decoded.workers, 8)
        XCTAssertEqual(decoded.timeout, 15.0)
        XCTAssertEqual(decoded.requireGroups.count, 1)
        XCTAssertEqual(decoded.requireGroups[0].rules[0].path, "$.data[*]")
    }

    func test_legacy_requireResultsPath_migrates_to_group() throws {
        let legacy = """
        {"param":"x","optionIdPath":"id","optionNamePath":"n","jsonpath":"","requireResultsPath":"$.items[*]","query":"","workers":4,"timeout":10}
        """
        let decoded = try JSONDecoder().decode(ScanConfig.self, from: legacy.data(using: .utf8)!)
        XCTAssertEqual(decoded.requireGroups.count, 1)
        XCTAssertEqual(decoded.requireGroups[0].rules[0].path, "$.items[*]")
    }
}
