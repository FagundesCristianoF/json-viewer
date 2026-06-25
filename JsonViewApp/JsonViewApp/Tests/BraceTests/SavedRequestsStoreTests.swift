import XCTest
@testable import Brace

@MainActor
final class SavedRequestsStoreTests: XCTestCase {

    func test_add_and_retrieve() {
        let store = SavedRequestsStore.shared
        let initialCount = store.items.count
        let saved = store.add(name: "Test", curlText: "curl example.com",
                              optionsText: "[]", config: ScanConfig())
        XCTAssertEqual(store.items.count, initialCount + 1)
        XCTAssertEqual(store.items.first?.name, "Test")
        // Clean up
        store.delete(id: saved.id)
    }

    func test_update_changes_fields() {
        let store = SavedRequestsStore.shared
        let saved = store.add(name: "Original", curlText: "curl a.com",
                              optionsText: "[]", config: ScanConfig())
        store.update(id: saved.id, name: "Updated", curlText: "curl b.com",
                     optionsText: "[]", config: ScanConfig())
        XCTAssertEqual(store.item(id: saved.id)?.name, "Updated")
        XCTAssertEqual(store.item(id: saved.id)?.curlText, "curl b.com")
        store.delete(id: saved.id)
    }

    func test_rename_changes_name_only() {
        let store = SavedRequestsStore.shared
        let saved = store.add(name: "Before", curlText: "curl x.com",
                              optionsText: "[]", config: ScanConfig())
        store.rename(id: saved.id, name: "After")
        XCTAssertEqual(store.item(id: saved.id)?.name, "After")
        XCTAssertEqual(store.item(id: saved.id)?.curlText, "curl x.com")
        store.delete(id: saved.id)
    }

    func test_delete_removes_item() {
        let store = SavedRequestsStore.shared
        let saved = store.add(name: "ToDelete", curlText: "curl del.com",
                              optionsText: "[]", config: ScanConfig())
        store.delete(id: saved.id)
        XCTAssertNil(store.item(id: saved.id))
    }

    func test_add_inserts_at_front() {
        let store = SavedRequestsStore.shared
        let first = store.add(name: "First", curlText: "curl 1.com",
                              optionsText: "[]", config: ScanConfig())
        let second = store.add(name: "Second", curlText: "curl 2.com",
                               optionsText: "[]", config: ScanConfig())
        XCTAssertEqual(store.items.first?.id, second.id)
        store.delete(id: first.id)
        store.delete(id: second.id)
    }
}
