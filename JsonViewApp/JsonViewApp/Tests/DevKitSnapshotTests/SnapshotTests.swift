import XCTest
import SnapshotTesting
import SwiftUI
@testable import DevKit

final class SnapshotTests: XCTestCase {

    // Set to true on first run to generate reference images,
    // then set back to false.
    let record = false

    func test_sectionHeader_title_only() {
        let view = NSHostingView(rootView:
            SectionHeader(title: "Parameters")
                .frame(width: 240)
        )
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 28)
        assertSnapshot(of: view, as: .image, record: record)
    }

    func test_sectionHeader_with_icon() {
        let view = NSHostingView(rootView:
            SectionHeader(title: "Curl Command", systemImage: "terminal")
                .frame(width: 240)
        )
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 28)
        assertSnapshot(of: view, as: .image, record: record)
    }

    func test_statusDot_pending() {
        let view = NSHostingView(rootView:
            StatusDot(status: .pending).frame(width: 20, height: 20)
        )
        view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        assertSnapshot(of: view, as: .image, record: record)
    }

    func test_statusDot_matched() {
        let view = NSHostingView(rootView:
            StatusDot(status: .matched).frame(width: 20, height: 20)
        )
        view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        assertSnapshot(of: view, as: .image, record: record)
    }

    func test_statusDot_error() {
        let view = NSHostingView(rootView:
            StatusDot(status: .error("timeout")).frame(width: 20, height: 20)
        )
        view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        assertSnapshot(of: view, as: .image, record: record)
    }

    func test_optionRow_pending() {
        let result = OptionResult(id: "uuid-1", displayName: "Account Alpha")
        let view = NSHostingView(rootView:
            OptionRow(result: result)
                .frame(width: 280)
        )
        view.frame = CGRect(x: 0, y: 0, width: 280, height: 36)
        assertSnapshot(of: view, as: .image, record: record)
    }

    func test_optionRow_matched_with_status_code() {
        var result = OptionResult(id: "uuid-2", displayName: "Account Beta")
        result.status = .matched
        result.statusCode = 200
        let view = NSHostingView(rootView:
            OptionRow(result: result, isSelected: false)
                .frame(width: 280)
        )
        view.frame = CGRect(x: 0, y: 0, width: 280, height: 36)
        assertSnapshot(of: view, as: .image, record: record)
    }

    func test_optionRow_error() {
        var result = OptionResult(id: "uuid-3", displayName: nil)
        result.status = .error("connection refused")
        let view = NSHostingView(rootView:
            OptionRow(result: result)
                .frame(width: 280)
        )
        view.frame = CGRect(x: 0, y: 0, width: 280, height: 36)
        assertSnapshot(of: view, as: .image, record: record)
    }
}
