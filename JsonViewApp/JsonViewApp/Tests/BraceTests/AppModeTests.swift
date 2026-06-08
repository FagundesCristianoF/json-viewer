import XCTest
@testable import DevKit

final class AppModeTests: XCTestCase {

    func test_allCases_count() {
        XCTAssertEqual(AppMode.allCases.count, 2)
    }

    func test_rawValues() {
        XCTAssertEqual(AppMode.jsonEditor.rawValue, "jsonEditor")
        XCTAssertEqual(AppMode.httpScanner.rawValue, "httpScanner")
    }

    func test_roundTrip_fromRawValue() {
        XCTAssertEqual(AppMode(rawValue: "jsonEditor"), .jsonEditor)
        XCTAssertEqual(AppMode(rawValue: "httpScanner"), .httpScanner)
        XCTAssertNil(AppMode(rawValue: "unknown"))
    }

    func test_labels_nonEmpty() {
        for mode in AppMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
        }
    }

    func test_icons_nonEmpty() {
        for mode in AppMode.allCases {
            XCTAssertFalse(mode.icon.isEmpty)
        }
    }
}
