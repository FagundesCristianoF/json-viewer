import XCTest
@testable import Brace

final class ComposeWriteBackTests: XCTestCase {

    // MARK: - Helpers

    private func tmpDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BraceComposeTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ content: String, to dir: URL, name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - buildComposeSourceMap

    func test_sourceMap_singleToken_mapsToFile() {
        let dir = tmpDir()
        write(#"{"id":"X"}"#, to: dir, name: "A.json")
        let template = #"[{{A.json}},{"id":"Y"}]"#
        let map = buildComposeSourceMap(template: template, workspaceRoot: dir)
        XCTAssertEqual(map["0"], dir.appendingPathComponent("A.json"))
    }

    func test_sourceMap_multipleTokens_bothMapped() {
        let dir = tmpDir()
        write(#"{"id":"A"}"#, to: dir, name: "A.json")
        write(#"{"id":"B"}"#, to: dir, name: "B.json")
        let template = #"[{{A.json}},{{B.json}}]"#
        let map = buildComposeSourceMap(template: template, workspaceRoot: dir)
        XCTAssertEqual(map["0"], dir.appendingPathComponent("A.json"))
        XCTAssertEqual(map["1"], dir.appendingPathComponent("B.json"))
    }

    func test_sourceMap_nestedKey_mapsCorrectPath() {
        let dir = tmpDir()
        write(#"{"v":1}"#, to: dir, name: "inner.json")
        let template = #"{"data":{{inner.json}}}"#
        let map = buildComposeSourceMap(template: template, workspaceRoot: dir)
        XCTAssertEqual(map["data"], dir.appendingPathComponent("inner.json"))
    }

    func test_sourceMap_noTokens_isEmpty() {
        let dir = tmpDir()
        let template = #"{"a":1,"b":2}"#
        let map = buildComposeSourceMap(template: template, workspaceRoot: dir)
        XCTAssertTrue(map.isEmpty)
    }

    func test_sourceMap_tokenWithWhitespace_trimmed() {
        let dir = tmpDir()
        write(#"1"#, to: dir, name: "val.json")
        let template = #"[{{  val.json  }}]"#
        let map = buildComposeSourceMap(template: template, workspaceRoot: dir)
        XCTAssertEqual(map["0"], dir.appendingPathComponent("val.json"))
    }

    // MARK: - diffJSON

    func test_diff_noChange_empty() {
        let old = try! JSONSerialization.jsonObject(with: #"{"id":"X"}"#.data(using: .utf8)!)
        let new = try! JSONSerialization.jsonObject(with: #"{"id":"X"}"#.data(using: .utf8)!)
        XCTAssertTrue(diffJSON(old: old, new: new).isEmpty)
    }

    func test_diff_changedLeaf_detected() {
        let old = try! JSONSerialization.jsonObject(with: #"{"id":"X"}"#.data(using: .utf8)!)
        let new = try! JSONSerialization.jsonObject(with: #"{"id":"Z"}"#.data(using: .utf8)!)
        let changes = diffJSON(old: old, new: new)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].path, ["id"])
        XCTAssertEqual(changes[0].newValue as? String, "Z")
    }

    func test_diff_nestedChange_correctPath() {
        let old = try! JSONSerialization.jsonObject(with: #"[{"id":"X"},{"id":"Y"}]"#.data(using: .utf8)!)
        let new = try! JSONSerialization.jsonObject(with: #"[{"id":"Z"},{"id":"Y"}]"#.data(using: .utf8)!)
        let changes = diffJSON(old: old, new: new)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].path, ["0", "id"])
        XCTAssertEqual(changes[0].newValue as? String, "Z")
    }

    func test_diff_multipleChanges_allDetected() {
        let old = try! JSONSerialization.jsonObject(with: #"[{"id":"X"},{"id":"Y"}]"#.data(using: .utf8)!)
        let new = try! JSONSerialization.jsonObject(with: #"[{"id":"A"},{"id":"B"}]"#.data(using: .utf8)!)
        let changes = diffJSON(old: old, new: new)
        XCTAssertEqual(changes.count, 2)
    }

    // MARK: - applyComposeWriteBack

    func test_writeBack_simpleValue_updatesSourceFile() throws {
        let dir = tmpDir()
        let aURL = write(#"{"id":"X"}"#, to: dir, name: "A.json")
        let template = #"[{{A.json}},{"id":"Y"}]"#
        let oldResult = #"[{"id":"X"},{"id":"Y"}]"#
        let newResult = #"[{"id":"Z"},{"id":"Y"}]"#

        let modified = applyComposeWriteBack(
            oldResult: oldResult,
            newResult: newResult,
            template: template,
            workspaceRoot: dir,
            indent: 2
        )

        XCTAssertTrue(modified.contains(aURL))
        let updated = try String(contentsOf: aURL, encoding: .utf8)
        let json = try JSONSerialization.jsonObject(with: updated.data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["id"] as? String, "Z")
    }

    func test_writeBack_unchangedResult_noFilesModified() {
        let dir = tmpDir()
        write(#"{"id":"X"}"#, to: dir, name: "A.json")
        let template = #"[{{A.json}}]"#
        let result = #"[{"id":"X"}]"#

        let modified = applyComposeWriteBack(
            oldResult: result,
            newResult: result,
            template: template,
            workspaceRoot: dir,
            indent: 2
        )

        XCTAssertTrue(modified.isEmpty)
    }

    func test_writeBack_multipleFiles_onlyAffectedModified() throws {
        let dir = tmpDir()
        let aURL = write(#"{"id":"A"}"#, to: dir, name: "A.json")
        let bURL = write(#"{"id":"B"}"#, to: dir, name: "B.json")
        let template = #"[{{A.json}},{{B.json}}]"#
        let oldResult = #"[{"id":"A"},{"id":"B"}]"#
        let newResult = #"[{"id":"X"},{"id":"B"}]"#  // only A changes

        let modified = applyComposeWriteBack(
            oldResult: oldResult,
            newResult: newResult,
            template: template,
            workspaceRoot: dir,
            indent: 2
        )

        XCTAssertTrue(modified.contains(aURL))
        XCTAssertFalse(modified.contains(bURL))

        let aJson = try JSONSerialization.jsonObject(with: Data(contentsOf: aURL)) as! [String: Any]
        let bJson = try JSONSerialization.jsonObject(with: Data(contentsOf: bURL)) as! [String: Any]
        XCTAssertEqual(aJson["id"] as? String, "X")
        XCTAssertEqual(bJson["id"] as? String, "B")  // unchanged
    }

    func test_writeBack_nestedKey_updatesCorrectly() throws {
        let dir = tmpDir()
        let aURL = write(#"{"name":"Alice","age":30}"#, to: dir, name: "A.json")
        let template = #"{"user":{{A.json}}}"#
        let oldResult = #"{"user":{"name":"Alice","age":30}}"#
        let newResult = #"{"user":{"name":"Bob","age":30}}"#

        applyComposeWriteBack(
            oldResult: oldResult,
            newResult: newResult,
            template: template,
            workspaceRoot: dir,
            indent: 2
        )

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: aURL)) as! [String: Any]
        XCTAssertEqual(json["name"] as? String, "Bob")
        XCTAssertEqual(json["age"] as? Int, 30)  // unchanged
    }

    // MARK: - Completion trigger detection (pure logic)

    func test_completion_triggered_on_doubleBrace() {
        // Verify the detection logic: last 2 chars == "{{"
        let text = #"{"ref": {{"# as NSString
        let loc = text.length
        let last2 = text.substring(with: NSRange(location: loc - 2, length: 2))
        XCTAssertEqual(last2, "{{")
    }

    func test_completion_notTriggered_on_singleBrace() {
        let text = #"{"ref": {"# as NSString
        let loc = text.length
        let last2 = text.substring(with: NSRange(location: loc - 2, length: 2))
        XCTAssertNotEqual(last2, "{{")
    }
}
