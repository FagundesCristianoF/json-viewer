import XCTest
@testable import Brace

/// Tests for the reparse() / resolvedCompose behavior fixed in v0.2.7.
///
/// Root cause: jv_compose returns the input unchanged for plain JSON (no {{
/// tokens), making resolvedCompose non-nil for every valid file. This caused
/// textDidChange to always take the compose-writeback path and skip the
/// raw-edit path, so pastes and keystrokes were never saved to model.editorText.
///
/// Fix: only call jv_compose (and set resolvedCompose) when editorText contains "{{".
@MainActor
final class ReparseTests: XCTestCase {

    // MARK: - Helpers

    private func tmpDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BraceReparseTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ content: String, to dir: URL, name: String) {
        try! content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func makeModel(workspaceRoot: URL? = nil) -> AppModel {
        let model = AppModel()
        model.workspaceRoot = workspaceRoot
        return model
    }

    // MARK: - resolvedCompose stays nil for plain JSON

    func test_reparse_plainJSON_noWorkspace_resolvedComposeNil() {
        let model = makeModel()
        model.editorText = #"{"key": "value"}"#
        model.reparse()
        XCTAssertNil(model.resolvedCompose,
            "Plain JSON with no workspace should never set resolvedCompose")
    }

    func test_reparse_plainJSON_withWorkspace_resolvedComposeNil() {
        let dir = tmpDir()
        let model = makeModel(workspaceRoot: dir)
        model.editorText = #"{"key": "value", "count": 42}"#
        model.reparse()
        XCTAssertNil(model.resolvedCompose,
            "Plain JSON without {{ tokens must not set resolvedCompose even with a workspace")
    }

    func test_reparse_emptyObject_resolvedComposeNil() {
        let dir = tmpDir()
        let model = makeModel(workspaceRoot: dir)
        model.editorText = "{}"
        model.reparse()
        XCTAssertNil(model.resolvedCompose)
    }

    func test_reparse_emptyArray_resolvedComposeNil() {
        let dir = tmpDir()
        let model = makeModel(workspaceRoot: dir)
        model.editorText = "[]"
        model.reparse()
        XCTAssertNil(model.resolvedCompose)
    }

    func test_reparse_largeValidJSON_resolvedComposeNil() {
        let dir = tmpDir()
        let model = makeModel(workspaceRoot: dir)
        let json = #"{"items": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}"#
        model.editorText = json
        model.reparse()
        XCTAssertNil(model.resolvedCompose,
            "Large valid JSON without {{ must not set resolvedCompose")
    }

    // MARK: - resolvedCompose set only for real compose templates

    func test_reparse_composeTemplate_resolvedComposeNonNil() {
        let dir = tmpDir()
        write(#"{"id": "X"}"#, to: dir, name: "inner.json")
        let model = makeModel(workspaceRoot: dir)
        model.editorText = #"[{{inner.json}}, {"id": "Y"}]"#
        model.reparse()
        XCTAssertNotNil(model.resolvedCompose,
            "Template with {{ tokens should resolve to a non-nil compose result")
    }

    func test_reparse_composeTemplate_resultContainsResolvedContent() {
        let dir = tmpDir()
        write(#"{"id": "resolved"}"#, to: dir, name: "part.json")
        let model = makeModel(workspaceRoot: dir)
        model.editorText = #"[{{part.json}}]"#
        model.reparse()
        XCTAssertEqual(model.resolvedCompose?.contains("resolved"), true)
    }

    func test_reparse_composeTemplate_noWorkspace_resolvedComposeNil() {
        let model = makeModel(workspaceRoot: nil)
        model.editorText = #"[{{inner.json}}]"#
        model.reparse()
        XCTAssertNil(model.resolvedCompose,
            "Compose template without workspace cannot resolve, so resolvedCompose must be nil")
    }

    // MARK: - isResultMode gate: textDidChange raw-edit path

    func test_reparse_plainJSON_isResultModeFalse() {
        let dir = tmpDir()
        let model = makeModel(workspaceRoot: dir)
        model.editorText = #"{"x": 1}"#
        model.reparse()
        // isResultMode = !isRawMode && resolvedCompose != nil
        // With resolvedCompose == nil this must be false, ensuring raw-edit path in textDidChange.
        let isResultMode = !model.isRawMode && model.resolvedCompose != nil
        XCTAssertFalse(isResultMode,
            "isResultMode must be false for plain JSON — otherwise paste/type edits are lost")
    }

    func test_reparse_composeTemplate_isResultModeTrue() {
        let dir = tmpDir()
        write(#"{"v": 1}"#, to: dir, name: "v.json")
        let model = makeModel(workspaceRoot: dir)
        model.editorText = #"{"data": {{v.json}}}"#
        model.reparse()
        let isResultMode = !model.isRawMode && model.resolvedCompose != nil
        XCTAssertTrue(isResultMode,
            "isResultMode must be true for compose templates so the result view is shown")
    }

    // MARK: - editorText unchanged after reparse on plain JSON

    func test_reparse_doesNotMutateEditorText() {
        let dir = tmpDir()
        let model = makeModel(workspaceRoot: dir)
        let original = #"{"stable": true}"#
        model.editorText = original
        model.reparse()
        XCTAssertEqual(model.editorText, original,
            "reparse() must never mutate editorText")
    }
}
