import XCTest
@testable import Brace

/// Guards the editor find experience: match counting, case sensitivity,
/// first-match jump, next/prev stepping, and wrap-around.
final class TextSearchTests: XCTestCase {

    private let sample = "foo Foo FOO bar foo"
    //                    0123456789...
    // "foo" occurrences (case-insensitive): 0, 4, 8, 16  → 4
    // "foo" occurrences (case-sensitive):   0, 16        → 2

    // MARK: - count

    func test_count_caseInsensitive_matchesAllCasings() {
        XCTAssertEqual(TextSearch.count(in: sample, query: "foo", caseSensitive: false), 4)
    }

    func test_count_caseSensitive_matchesExactCasingOnly() {
        XCTAssertEqual(TextSearch.count(in: sample, query: "foo", caseSensitive: true), 2)
        XCTAssertEqual(TextSearch.count(in: sample, query: "Foo", caseSensitive: true), 1)
        XCTAssertEqual(TextSearch.count(in: sample, query: "FOO", caseSensitive: true), 1)
    }

    func test_count_emptyQuery_isZero() {
        XCTAssertEqual(TextSearch.count(in: sample, query: "", caseSensitive: false), 0)
    }

    func test_count_noMatch_isZero() {
        XCTAssertEqual(TextSearch.count(in: sample, query: "zzz", caseSensitive: false), 0)
    }

    func test_count_overlappingCandidates_areNonOverlapping() {
        // "aa" in "aaaa" → matches at 0 and 2 (non-overlapping) = 2
        XCTAssertEqual(TextSearch.count(in: "aaaa", query: "aa", caseSensitive: false), 2)
    }

    // MARK: - first

    func test_first_landsOnTopmostMatch() {
        let m = TextSearch.match(in: sample, query: "foo", selection: NSRange(location: 12, length: 0),
                                 direction: .first, caseSensitive: false)
        XCTAssertEqual(m, NSRange(location: 0, length: 3))
    }

    func test_first_respectsCaseSensitivity() {
        // Case-sensitive "FOO" first match is at index 8, not 0.
        let m = TextSearch.match(in: sample, query: "FOO", selection: NSRange(location: 0, length: 0),
                                 direction: .first, caseSensitive: true)
        XCTAssertEqual(m, NSRange(location: 8, length: 3))
    }

    // MARK: - next

    func test_next_advancesPastCurrentSelection() {
        // Selection covers the first "foo" (0..<3); next should be index 4.
        let m = TextSearch.match(in: sample, query: "foo", selection: NSRange(location: 0, length: 3),
                                 direction: .next, caseSensitive: false)
        XCTAssertEqual(m, NSRange(location: 4, length: 3))
    }

    func test_next_wrapsAroundToTop() {
        // After the last match (index 16), next wraps to index 0.
        let m = TextSearch.match(in: sample, query: "foo", selection: NSRange(location: 16, length: 3),
                                 direction: .next, caseSensitive: false)
        XCTAssertEqual(m, NSRange(location: 0, length: 3))
    }

    // MARK: - previous

    func test_previous_stepsBackBeforeSelection() {
        // From a caret at index 8, previous match is at index 4.
        let m = TextSearch.match(in: sample, query: "foo", selection: NSRange(location: 8, length: 0),
                                 direction: .previous, caseSensitive: false)
        XCTAssertEqual(m, NSRange(location: 4, length: 3))
    }

    func test_previous_wrapsAroundToBottom() {
        // From the very top, previous wraps to the last match (index 16).
        let m = TextSearch.match(in: sample, query: "foo", selection: NSRange(location: 0, length: 0),
                                 direction: .previous, caseSensitive: false)
        XCTAssertEqual(m, NSRange(location: 16, length: 3))
    }

    // MARK: - edge cases

    func test_match_emptyQuery_isNil() {
        XCTAssertNil(TextSearch.match(in: sample, query: "", selection: NSRange(location: 0, length: 0),
                                      direction: .first, caseSensitive: false))
    }

    func test_match_emptyText_isNil() {
        XCTAssertNil(TextSearch.match(in: "", query: "foo", selection: NSRange(location: 0, length: 0),
                                      direction: .first, caseSensitive: false))
    }

    func test_match_noMatch_isNil() {
        XCTAssertNil(TextSearch.match(in: sample, query: "zzz", selection: NSRange(location: 0, length: 0),
                                      direction: .next, caseSensitive: false))
    }

    func test_next_selectionAtEnd_wrapsNotCrash() {
        let m = TextSearch.match(in: sample, query: "foo",
                                 selection: NSRange(location: (sample as NSString).length, length: 0),
                                 direction: .next, caseSensitive: false)
        XCTAssertEqual(m, NSRange(location: 0, length: 3))
    }
}
