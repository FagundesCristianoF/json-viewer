import XCTest
@testable import DevKit

final class ScanConfigTests: XCTestCase {

    func test_isFilterMode_false_when_all_empty() {
        var config = ScanConfig()
        config.jsonpath = ""
        config.requireResultsPath = ""
        XCTAssertFalse(config.isFilterMode)
    }

    func test_isFilterMode_true_when_jsonpath_set() {
        var config = ScanConfig()
        config.jsonpath = "$.items[*]"
        XCTAssertTrue(config.isFilterMode)
    }

    func test_isFilterMode_true_when_requireResultsPath_set() {
        var config = ScanConfig()
        config.requireResultsPath = "$.data"
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

    func test_effectiveRequireResultsPath_nil_when_empty() {
        var config = ScanConfig()
        config.requireResultsPath = ""
        XCTAssertNil(config.effectiveRequireResultsPath)
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

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ScanConfig.self, from: data)

        XCTAssertEqual(decoded.param, "userId")
        XCTAssertEqual(decoded.jsonpath, "$.users[*]")
        XCTAssertEqual(decoded.workers, 8)
        XCTAssertEqual(decoded.timeout, 15.0)
    }
}
