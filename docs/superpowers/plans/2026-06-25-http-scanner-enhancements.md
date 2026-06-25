# HTTP Scanner Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add text selection everywhere, a post-scan results search bar, named saved requests, and a two-way curl parameter breakdown editor to the HTTP Scanner.

**Architecture:** Four independent layers built in dependency order — text selection and search are pure view changes; saved requests follow the existing HistoryStore/HistoryEntry pattern; the curl breakdown adds a new `CurlBreakdown` value type that two-way syncs with `curlText` via Combine, with a dedicated `CurlBreakdownView` rendered below the curl editor in the sidebar.

**Tech Stack:** SwiftUI, AppKit (NSTextView for MonoTextView), Combine (debounce pipelines for two-way sync), XCTest.

## Global Constraints

- Target name for `@testable import`: `Brace`
- All source files live under `JsonViewApp/JsonViewApp/Sources/HTTPScanner/` (sub-folders: `Models/`, `Core/`, or directly under `HTTPScanner/`)
- Tests live in `JsonViewApp/JsonViewApp/Tests/BraceTests/`
- Build: `xcodebuild -project JsonViewApp.xcodeproj -scheme JsonViewApp -configuration Debug -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"`
- Test: `xcodebuild test -project JsonViewApp.xcodeproj -scheme JsonViewApp -destination "platform=macOS" 2>&1 | grep -E "error:|passed|failed|Test Suite"`
- Every new `.swift` file must be added to the Xcode project target. Use `xcodeproj` gem (`gem install xcodeproj`) or drag into Xcode. The plan notes this per task.
- `@MainActor final class ScanViewModel` — all VM mutations must happen on main actor
- Existing `HistoryStore.shared` pattern: singleton, `private init()`, atomic file writes, `@Published` array — mirror exactly for `SavedRequestsStore`

---

## Task 1: Text Selection — JSONColorView and Sidebar

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/Shared/JSONColorView.swift`
- Modify: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift`

**Interfaces:**
- Produces: Nothing external — purely additive `.textSelection(.enabled)` modifiers

- [ ] **Step 1: Add `.textSelection(.enabled)` to `JLineView`**

In `JSONColorView.swift`, the `JLineView.body` computed property returns an `HStack`. Add the modifier to the entire `body`:

```swift
var body: some View {
    HStack(spacing: 0) {
        Color.clear.frame(width: CGFloat(line.depth) * indent)
        lineContent
    }
    .font(.system(size: 11, design: .monospaced))
    .lineSpacing(1)
    .textSelection(.enabled)   // ← add this line
}
```

- [ ] **Step 2: Add `.textSelection(.enabled)` to `OptionRow` labels in `ScannerSidebarView`**

Find the `OptionRow` struct (or wherever option name/id text is rendered in `ScannerSidebarView`). It is likely an `HStack` with a `Text(result.displayName ?? result.id)`. Add `.textSelection(.enabled)` to each `Text`:

```swift
// Before:
Text(result.displayName ?? result.id)
    .font(.system(size: 12, weight: .medium))
    .lineLimit(1)

// After:
Text(result.displayName ?? result.id)
    .font(.system(size: 12, weight: .medium))
    .lineLimit(1)
    .textSelection(.enabled)
```

Also add to the secondary ID label if present:
```swift
Text(result.id)
    .font(.system(size: 10, design: .monospaced))
    .foregroundStyle(.tertiary)
    .textSelection(.enabled)
```

- [ ] **Step 3: Add `.textSelection(.enabled)` to the error message in `ScannerSidebarView`**

Find the bottom error block:
```swift
// Before:
Text(err).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)

// After:
Text(err).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
    .textSelection(.enabled)
```

Also add to the parse error label near the curl text editor:
```swift
// Before:
Text(err).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2)

// After:
Text(err).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2)
    .textSelection(.enabled)
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -project JsonViewApp.xcodeproj -scheme JsonViewApp -configuration Debug \
  -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` (the pre-existing `SidebarView.swift` not-found errors appear as warnings in this context but do not block compilation of our files).

- [ ] **Step 5: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/Shared/JSONColorView.swift \
        JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift
git commit -m "feat: enable text selection in JSON viewer and scanner sidebar"
```

---

## Task 2: Results Text Search in Sidebar

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift`

**Interfaces:**
- Consumes: `vm.mergedForDisplay: [OptionResult]`, `vm.results: [OptionResult]`
- Produces: filtered display of `OptionResult` rows based on `@State var resultSearch: String`

- [ ] **Step 1: Add `@State var resultSearch` to `ScannerSidebarView`**

In `ScannerSidebarView`, add alongside the existing `@State` properties:

```swift
@State private var resultSearch: String = ""
```

- [ ] **Step 2: Add a computed `filteredResults` property**

Add inside `ScannerSidebarView` body (or as a computed var):

```swift
private var filteredResults: [OptionResult] {
    guard !resultSearch.isEmpty else { return vm.mergedForDisplay }
    return vm.mergedForDisplay.filter {
        $0.responseBody?.localizedCaseInsensitiveContains(resultSearch) == true ||
        ($0.displayName ?? $0.id).localizedCaseInsensitiveContains(resultSearch)
    }
}
```

- [ ] **Step 3: Replace `vm.mergedForDisplay` with `filteredResults` in the `ForEach`**

Find the `ForEach(vm.mergedForDisplay)` inside the Options section and change it to:

```swift
ForEach(filteredResults) { result in
    OptionRow(result: result, isSelected: vm.selectedResultID == result.id)
        .contentShape(Rectangle())
        .onTapGesture { vm.selectedResultID = result.id }
}
```

- [ ] **Step 4: Add the search bar above the results `ScrollView`**

Insert this block immediately before the `ScrollView` that contains the results `LazyVStack`, inside the `if !vm.mergedForDisplay.isEmpty` guard:

```swift
if !vm.results.isEmpty {
    HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        TextField("Search responses…", text: $resultSearch)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
        if !resultSearch.isEmpty {
            Button { resultSearch = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))

    Divider().padding(.horizontal, 8)
}
```

- [ ] **Step 5: Clear `resultSearch` when a new scan starts**

In `ScanViewModel.run(force:)`, we can't directly clear view state. Instead, expose a publisher or reset signal. The simplest approach: reset `resultSearch` in `ScannerSidebarView` by observing `vm.isRunning`:

```swift
// Inside the ScrollView or wrapping VStack, add:
.onChange(of: vm.isRunning) { running in
    if running { resultSearch = "" }
}
```

Place this `.onChange` on the outer `VStack` of `ScannerSidebarView.body`.

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -project JsonViewApp.xcodeproj -scheme JsonViewApp -configuration Debug \
  -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift
git commit -m "feat: add post-scan full-text search filter in scanner sidebar"
```

---

## Task 3: SavedRequest Model + SavedRequestsStore

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/SavedRequest.swift`
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/SavedRequestsStore.swift`
- Modify: `JsonViewApp/JsonViewApp/Sources/Core/Preferences.swift`
- Create: `JsonViewApp/JsonViewApp/Tests/BraceTests/SavedRequestsStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct SavedRequest: Codable, Identifiable` with fields `id: UUID`, `name: String`, `curlText: String`, `optionsText: String`, `config: ScanConfig`, `createdAt: Date`
  - `final class SavedRequestsStore` with `static let shared`, `@Published var items: [SavedRequest]`, `func add(name:curlText:optionsText:config:) -> SavedRequest`, `func update(id:name:curlText:optionsText:config:)`, `func delete(id:)`

- [ ] **Step 1: Add `savedRequestsFileURL` to `Preferences`**

In `Preferences.swift`, add alongside `historyFileURL`:

```swift
var savedRequestsFileURL: URL {
    historyDirectory.appendingPathComponent("saved_requests.json")
}
```

- [ ] **Step 2: Create `SavedRequest.swift`**

```swift
import Foundation

struct SavedRequest: Codable, Identifiable {
    let id: UUID
    var name: String
    var curlText: String
    var optionsText: String
    var config: ScanConfig
    let createdAt: Date

    init(name: String, curlText: String, optionsText: String, config: ScanConfig) {
        self.id = UUID()
        self.name = name
        self.curlText = curlText
        self.optionsText = optionsText
        self.config = config
        self.createdAt = Date()
    }
}
```

Add to Xcode project target (drag into `Models/` group in Xcode navigator).

- [ ] **Step 3: Create `SavedRequestsStore.swift`**

```swift
import Foundation
import Combine

final class SavedRequestsStore: ObservableObject {

    static let shared = SavedRequestsStore()

    @Published private(set) var items: [SavedRequest] = []

    private var fileURL: URL {
        Preferences.shared.savedRequestsFileURL
    }

    private init() { load() }

    // MARK: - Public API

    @discardableResult
    func add(name: String, curlText: String, optionsText: String, config: ScanConfig) -> SavedRequest {
        let entry = SavedRequest(name: name, curlText: curlText, optionsText: optionsText, config: config)
        items.insert(entry, at: 0)
        save()
        return entry
    }

    func update(id: UUID, name: String, curlText: String, optionsText: String, config: ScanConfig) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].name = name
        items[idx].curlText = curlText
        items[idx].optionsText = optionsText
        items[idx].config = config
        save()
    }

    func rename(id: UUID, name: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].name = name
        save()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func item(id: UUID) -> SavedRequest? {
        items.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SavedRequest].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        Preferences.shared.ensureHistoryDirectoryExists()
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

Add to Xcode project target (drag into `Core/` group in Xcode navigator).

- [ ] **Step 4: Write tests for `SavedRequestsStore`**

```swift
// Tests/BraceTests/SavedRequestsStoreTests.swift
import XCTest
@testable import Brace

final class SavedRequestsStoreTests: XCTestCase {

    // Use a temp file to isolate from the real store
    private var tempURL: URL!
    private var store: SavedRequestsStore!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        // We test via the public API since SavedRequestsStore uses Preferences.shared
        // for its file URL; accept that unit tests use the real path but clean up.
    }

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
```

Add to Xcode project test target.

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -project JsonViewApp.xcodeproj -scheme JsonViewApp \
  -destination "platform=macOS" \
  -only-testing:BraceTests/SavedRequestsStoreTests \
  2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test Suite 'SavedRequestsStoreTests' passed`

- [ ] **Step 6: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/Core/Preferences.swift \
        JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/SavedRequest.swift \
        JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/SavedRequestsStore.swift \
        JsonViewApp/JsonViewApp/Tests/BraceTests/SavedRequestsStoreTests.swift
git commit -m "feat: SavedRequest model and SavedRequestsStore"
```

---

## Task 4: ScanViewModel — Saved Requests Integration

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanViewModel.swift`

**Interfaces:**
- Consumes: `SavedRequestsStore.shared`, `SavedRequest`
- Produces:
  - `@Published var savedRequests: [SavedRequest]` — mirrors store
  - `@Published var currentSavedRequestID: UUID?`
  - `var hasPendingChanges: Bool`
  - `func loadSavedRequest(_ entry: SavedRequest)`
  - `func saveCurrentRequest(name: String) -> SavedRequest`
  - `func updateCurrentSavedRequest()`
  - `func deleteSavedRequest(id: UUID)`
  - `func renameSavedRequest(id: UUID, name: String)`

- [ ] **Step 1: Add saved request state to `ScanViewModel`**

Inside `ScanViewModel`, add these published properties in the `// MARK: - Inputs` section:

```swift
// MARK: - Saved Requests
@Published var savedRequests: [SavedRequest] = SavedRequestsStore.shared.items
@Published var currentSavedRequestID: UUID? = nil

var hasPendingChanges: Bool {
    guard let id = currentSavedRequestID,
          let saved = SavedRequestsStore.shared.item(id: id) else { return false }
    return saved.curlText != curlText ||
           saved.optionsText != optionsText ||
           saved.config != config
}
```

- [ ] **Step 2: Add saved request methods to `ScanViewModel`**

Add after the History section:

```swift
// MARK: - Saved Requests

func loadSavedRequest(_ entry: SavedRequest) {
    curlText = entry.curlText
    optionsText = entry.optionsText
    config = entry.config
    currentSavedRequestID = entry.id
    validateCurl()
}

@discardableResult
func saveCurrentRequest(name: String) -> SavedRequest {
    let saved = SavedRequestsStore.shared.add(
        name: name,
        curlText: curlText,
        optionsText: optionsText,
        config: config
    )
    savedRequests = SavedRequestsStore.shared.items
    currentSavedRequestID = saved.id
    return saved
}

func updateCurrentSavedRequest() {
    guard let id = currentSavedRequestID else { return }
    SavedRequestsStore.shared.update(
        id: id,
        name: SavedRequestsStore.shared.item(id: id)?.name ?? "Untitled",
        curlText: curlText,
        optionsText: optionsText,
        config: config
    )
    savedRequests = SavedRequestsStore.shared.items
}

func deleteSavedRequest(id: UUID) {
    SavedRequestsStore.shared.delete(id: id)
    savedRequests = SavedRequestsStore.shared.items
    if currentSavedRequestID == id { currentSavedRequestID = nil }
}

func renameSavedRequest(id: UUID, name: String) {
    SavedRequestsStore.shared.rename(id: id, name: name)
    savedRequests = SavedRequestsStore.shared.items
}

func overwriteSavedRequest(id: UUID) {
    SavedRequestsStore.shared.update(
        id: id,
        name: SavedRequestsStore.shared.item(id: id)?.name ?? "Untitled",
        curlText: curlText,
        optionsText: optionsText,
        config: config
    )
    savedRequests = SavedRequestsStore.shared.items
    currentSavedRequestID = id
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project JsonViewApp.xcodeproj -scheme JsonViewApp -configuration Debug \
  -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanViewModel.swift
git commit -m "feat: ScanViewModel saved requests — load/save/update/delete/rename"
```

---

## Task 5: Saved Requests Sidebar Section

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift`

**Interfaces:**
- Consumes: `vm.savedRequests`, `vm.currentSavedRequestID`, `vm.hasPendingChanges`, `vm.loadSavedRequest(_:)`, `vm.deleteSavedRequest(id:)`, `vm.renameSavedRequest(id:name:)`, `vm.overwriteSavedRequest(id:)`

- [ ] **Step 1: Add saved section state to `ScannerSidebarView`**

Add to the existing `@State` properties:

```swift
@State private var savedExpanded = true
@State private var renamingID: UUID? = nil
@State private var renameText: String = ""
```

- [ ] **Step 2: Add the `savedSection` computed view**

Add inside `ScannerSidebarView` as a `@ViewBuilder` computed property:

```swift
@ViewBuilder
private var savedSection: some View {
    if !vm.savedRequests.isEmpty {
        DisclosureGroup(isExpanded: $savedExpanded) {
            VStack(spacing: 1) {
                ForEach(vm.savedRequests) { entry in
                    savedRow(entry)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        } label: {
            SectionHeader(title: "Saved", systemImage: "bookmark.fill")
                .contentShape(Rectangle())
        }
        .disclosureGroupStyle(SidebarDisclosureStyle())

        Divider().padding(.horizontal, 8)
    }
}
```

- [ ] **Step 3: Add `savedRow` helper view**

```swift
@ViewBuilder
private func savedRow(_ entry: SavedRequest) -> some View {
    let isActive = vm.currentSavedRequestID == entry.id

    HStack(spacing: 8) {
        Image(systemName: isActive ? "bookmark.fill" : "bookmark")
            .font(.system(size: 11))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .frame(width: 16)

        if renamingID == entry.id {
            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit {
                    vm.renameSavedRequest(id: entry.id, name: renameText.isEmpty ? entry.name : renameText)
                    renamingID = nil
                }
                .onExitCommand { renamingID = nil }
        } else {
            Text(entry.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .textSelection(.enabled)
        }

        Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
    .cornerRadius(4)
    .contentShape(Rectangle())
    .onTapGesture {
        vm.loadSavedRequest(entry)
    }
    .contextMenu {
        Button("Load") { vm.loadSavedRequest(entry) }
        Button("Rename") {
            renameText = entry.name
            renamingID = entry.id
        }
        Button("Overwrite with current") { vm.overwriteSavedRequest(id: entry.id) }
        Divider()
        Button("Delete", role: .destructive) { vm.deleteSavedRequest(id: entry.id) }
    }
}
```

- [ ] **Step 4: Insert `savedSection` at the top of `ScannerSidebarView.body`**

The body is a `VStack(spacing: 0)`. Insert `savedSection` as the very first child, before the curl `DisclosureGroup`:

```swift
var body: some View {
    VStack(spacing: 0) {
        savedSection    // ← insert here

        // MARK: Curl section
        DisclosureGroup(isExpanded: $curlExpanded) {
            // ... existing curl content
```

- [ ] **Step 5: Build and verify**

```bash
xcodebuild -project JsonViewApp.xcodeproj -scheme JsonViewApp -configuration Debug \
  -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift
git commit -m "feat: Saved Requests sidebar section with load/rename/overwrite/delete"
```

---

## Task 6: Saved Requests Toolbar Bookmark Button

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/ToolbarView.swift`

**Interfaces:**
- Consumes: `vm.currentSavedRequestID`, `vm.hasPendingChanges`, `vm.savedRequests`, `vm.saveCurrentRequest(name:)`, `vm.updateCurrentSavedRequest()`, `vm.renameSavedRequest(id:name:)`

- [ ] **Step 1: Add `showSavePopover` state to `ScannerToolbarItems`**

`ScannerToolbarItems` is a `ToolbarContent` struct. It currently takes `@Binding var showHistory: Bool`. Add save popover state. Since `ToolbarContent` can't hold `@State`, add the popover state to the parent view that renders `ScannerToolbarItems`, OR convert the bookmark button into its own View struct.

Create a `SaveBookmarkButton` view struct:

```swift
// In ToolbarView.swift, add after ScannerToolbarItems:

struct SaveBookmarkButton: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var showPopover = false
    @State private var saveName = ""

    private var currentSaved: SavedRequest? {
        guard let id = vm.currentSavedRequestID else { return nil }
        return vm.savedRequests.first { $0.id == id }
    }

    var body: some View {
        Button { showPopover.toggle() } label: {
            Image(systemName: bookmarkIcon)
                .foregroundStyle(vm.currentSavedRequestID != nil ? Color.accentColor : Color.primary)
        }
        .help(helpText)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            savePopoverContent
        }
    }

    private var bookmarkIcon: String {
        guard vm.currentSavedRequestID != nil else { return "bookmark" }
        return vm.hasPendingChanges ? "bookmark.fill" : "bookmark.fill"
    }

    private var helpText: String {
        if let saved = currentSaved {
            return vm.hasPendingChanges ? "Update or save "\(saved.name)"" : "Saved: \(saved.name)"
        }
        return "Save current request"
    }

    @ViewBuilder
    private var savePopoverContent: some View {
        if let saved = currentSaved {
            if vm.hasPendingChanges {
                pendingChangesPopover(saved: saved)
            } else {
                activeRequestPopover(saved: saved)
            }
        } else {
            newSavePopover
        }
    }

    private var newSavePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Request")
                .font(.system(size: 13, weight: .semibold))
            TextField("Name", text: $saveName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onAppear { saveName = "" }
                .onSubmit { commitSave() }
            HStack {
                Spacer()
                Button("Save") { commitSave() }
                    .buttonStyle(.borderedProminent)
                    .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func pendingChangesPopover(saved: SavedRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unsaved changes")
                .font(.system(size: 13, weight: .semibold))
            Text(""\(saved.name)" has pending changes.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Update "\(saved.name)"") {
                    vm.updateCurrentSavedRequest()
                    showPopover = false
                }
                .buttonStyle(.borderedProminent)
                Button("Save as new…") {
                    showPopover = false
                    // Briefly reset currentSavedRequestID so next tap opens newSavePopover
                    vm.currentSavedRequestID = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showPopover = true
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    @ViewBuilder
    private func activeRequestPopover(saved: SavedRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(saved.name)
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Button("Rename…") {
                    // Inline rename via sidebar is preferred; close popover
                    showPopover = false
                }
                .buttonStyle(.bordered)
                Button("Delete", role: .destructive) {
                    vm.deleteSavedRequest(id: saved.id)
                    showPopover = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 220)
    }

    private func commitSave() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        vm.saveCurrentRequest(name: name)
        showPopover = false
    }
}
```

- [ ] **Step 2: Add `SaveBookmarkButton` as a `ToolbarItem` in `ScannerToolbarItems`**

In `ScannerToolbarItems.body`, add a new `ToolbarItem` in the `.navigation` placement after the history button:

```swift
ToolbarItem(placement: .navigation) {
    SaveBookmarkButton()
}
```

The existing history button ToolbarItem remains unchanged.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project JsonViewApp.xcodeproj -scheme JsonViewApp -configuration Debug \
  -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/ToolbarView.swift
git commit -m "feat: toolbar bookmark button to save/update/manage named requests"
```

---

## Task 7: HTTPParam + CurlBreakdown Models + CurlParser.parseBreakdown

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/HTTPParam.swift`
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/CurlBreakdown.swift`
- Modify: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/CurlParser.swift`
- Create: `JsonViewApp/JsonViewApp/Tests/BraceTests/CurlBreakdownTests.swift`

**Interfaces:**
- Produces:
  - `struct HTTPParam: Identifiable, Codable, Equatable` — `id: UUID`, `key: String`, `value: String`, `isEnabled: Bool`
  - `struct CurlBreakdown: Equatable` — `method`, `baseURL`, `queryParams`, `headers`, `bodyParams`, `rawBody`, `bodyIsRaw`, `insecure`
  - `CurlParser.parseBreakdown(_ input: String) throws -> CurlBreakdown`

- [ ] **Step 1: Create `HTTPParam.swift`**

```swift
import Foundation

struct HTTPParam: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var key: String
    var value: String
    var isEnabled: Bool = true

    init(key: String, value: String, isEnabled: Bool = true) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}
```

Add to Xcode project target (drag into `Models/` group).

- [ ] **Step 2: Create `CurlBreakdown.swift`**

```swift
import Foundation

struct CurlBreakdown: Equatable {
    var method: String
    var baseURL: String
    var queryParams: [HTTPParam]
    var headers: [HTTPParam]
    /// Top-level JSON body keys. Empty when body is not a JSON object.
    var bodyParams: [HTTPParam]
    /// The full body string, kept in sync with bodyParams when not in raw mode.
    var rawBody: String
    /// When true, rawBody is the source of truth; bodyParams are not shown.
    var bodyIsRaw: Bool
    var insecure: Bool
}
```

Add to Xcode project target (drag into `Models/` group).

- [ ] **Step 3: Write failing tests for `CurlParser.parseBreakdown`**

```swift
// Tests/BraceTests/CurlBreakdownTests.swift
import XCTest
@testable import Brace

final class CurlBreakdownTests: XCTestCase {

    func test_parse_url_and_method() throws {
        let curl = "curl -X POST 'https://api.example.com/items?page=1&size=10' -H 'Authorization: Bearer tok'"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertEqual(bd.method, "POST")
        XCTAssertEqual(bd.baseURL, "https://api.example.com/items")
    }

    func test_parse_query_params() throws {
        let curl = "curl 'https://api.example.com/items?page=1&size=10'"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertEqual(bd.queryParams.count, 2)
        XCTAssertEqual(bd.queryParams[0].key, "page")
        XCTAssertEqual(bd.queryParams[0].value, "1")
        XCTAssertEqual(bd.queryParams[1].key, "size")
        XCTAssertEqual(bd.queryParams[1].value, "10")
        XCTAssertTrue(bd.queryParams[0].isEnabled)
    }

    func test_parse_headers() throws {
        let curl = """
        curl -H 'Authorization: Bearer tok' -H 'Content-Type: application/json' https://api.example.com
        """
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertEqual(bd.headers.count, 2)
        let keys = bd.headers.map(\.key)
        XCTAssertTrue(keys.contains("Authorization"))
        XCTAssertTrue(keys.contains("Content-Type"))
    }

    func test_parse_json_body_into_params() throws {
        let curl = #"curl -X POST https://api.com -d '{"accountId":"abc","limit":10}'"#
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertFalse(bd.bodyIsRaw)
        XCTAssertEqual(bd.bodyParams.count, 2)
        let keys = bd.bodyParams.map(\.key).sorted()
        XCTAssertEqual(keys, ["accountId", "limit"])
        // values are raw JSON fragments
        let accountParam = bd.bodyParams.first { $0.key == "accountId" }!
        XCTAssertEqual(accountParam.value, #""abc""#)
        let limitParam = bd.bodyParams.first { $0.key == "limit" }!
        XCTAssertEqual(limitParam.value, "10")
    }

    func test_non_json_body_is_raw() throws {
        let curl = "curl -X POST https://api.com -d 'name=foo&bar=baz'"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertTrue(bd.bodyIsRaw)
        XCTAssertEqual(bd.rawBody, "name=foo&bar=baz")
        XCTAssertTrue(bd.bodyParams.isEmpty)
    }

    func test_no_query_params_when_clean_url() throws {
        let curl = "curl https://api.example.com/items"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertTrue(bd.queryParams.isEmpty)
        XCTAssertEqual(bd.baseURL, "https://api.example.com/items")
    }

    func test_insecure_flag() throws {
        let curl = "curl -k https://self-signed.example.com"
        let bd = try CurlParser.parseBreakdown(curl)
        XCTAssertTrue(bd.insecure)
    }
}
```

Add to Xcode project test target.

- [ ] **Step 4: Run tests — expect failure (method not defined yet)**

```bash
xcodebuild test -project JsonViewApp.xcodeproj -scheme JsonViewApp \
  -destination "platform=macOS" \
  -only-testing:BraceTests/CurlBreakdownTests \
  2>&1 | grep -E "error:|failed"
```

Expected: compile error — `'CurlParser' has no member 'parseBreakdown'`

- [ ] **Step 5: Implement `CurlParser.parseBreakdown`**

In `CurlParser.swift`, add this method to the `enum CurlParser`:

```swift
static func parseBreakdown(_ input: String) throws -> CurlBreakdown {
    let parsed = try parse(input)

    // Split URL into base + query params
    var baseURL = parsed.url
    var queryParams: [HTTPParam] = []
    if var components = URLComponents(string: parsed.url) {
        queryParams = (components.queryItems ?? []).map {
            HTTPParam(key: $0.name, value: $0.value ?? "")
        }
        components.query = nil
        baseURL = components.string ?? parsed.url
    }

    // Headers dict → ordered array
    let headers: [HTTPParam] = parsed.headers
        .sorted { $0.key < $1.key }
        .map { HTTPParam(key: $0.key, value: $0.value) }

    // Body
    let rawBody = parsed.data ?? ""
    var bodyParams: [HTTPParam] = []
    var bodyIsRaw = true

    if !rawBody.isEmpty,
       let data = rawBody.data(using: .utf8),
       let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        bodyIsRaw = false
        bodyParams = dict.keys.sorted().compactMap { key -> HTTPParam? in
            guard let val = dict[key] else { return nil }
            // Serialize each value back to a JSON fragment string
            let fragment: String
            if let str = val as? String {
                fragment = "\"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
            } else if let num = val as? NSNumber {
                if CFGetTypeID(num) == CFBooleanGetTypeID() {
                    fragment = num.boolValue ? "true" : "false"
                } else {
                    fragment = num.stringValue
                }
            } else if val is NSNull {
                fragment = "null"
            } else if let encoded = try? JSONSerialization.data(withJSONObject: val),
                      let str = String(data: encoded, encoding: .utf8) {
                fragment = str
            } else {
                return nil
            }
            return HTTPParam(key: key, value: fragment)
        }
    }

    return CurlBreakdown(
        method: parsed.method,
        baseURL: baseURL,
        queryParams: queryParams,
        headers: headers,
        bodyParams: bodyParams,
        rawBody: rawBody,
        bodyIsRaw: bodyIsRaw,
        insecure: parsed.insecure
    )
}
```

- [ ] **Step 6: Run tests — expect pass**

```bash
xcodebuild test -project JsonViewApp.xcodeproj -scheme JsonViewApp \
  -destination "platform=macOS" \
  -only-testing:BraceTests/CurlBreakdownTests \
  2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test Suite 'CurlBreakdownTests' passed`

- [ ] **Step 7: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/HTTPParam.swift \
        JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/CurlBreakdown.swift \
        JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/CurlParser.swift \
        JsonViewApp/JsonViewApp/Tests/BraceTests/CurlBreakdownTests.swift
git commit -m "feat: HTTPParam, CurlBreakdown models, CurlParser.parseBreakdown"
```

---

## Task 8: CurlBuilder

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/CurlBuilder.swift`
- Modify: `JsonViewApp/JsonViewApp/Tests/BraceTests/CurlBreakdownTests.swift`

**Interfaces:**
- Produces: `enum CurlBuilder` with `static func build(_ breakdown: CurlBreakdown) -> String`

- [ ] **Step 1: Write failing tests for `CurlBuilder.build`**

Append to `CurlBreakdownTests.swift`:

```swift
// MARK: - CurlBuilder tests

final class CurlBuilderTests: XCTestCase {

    func test_build_simple_get() {
        let bd = CurlBreakdown(
            method: "GET",
            baseURL: "https://api.example.com/items",
            queryParams: [HTTPParam(key: "page", value: "1"), HTTPParam(key: "size", value: "10")],
            headers: [HTTPParam(key: "Authorization", value: "Bearer tok")],
            bodyParams: [],
            rawBody: "",
            bodyIsRaw: false,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("GET"), "method")
        XCTAssertTrue(curl.contains("page=1"), "query param page")
        XCTAssertTrue(curl.contains("size=10"), "query param size")
        XCTAssertTrue(curl.contains("Authorization"), "header")
        XCTAssertFalse(curl.contains("-d"), "no body for GET")
    }

    func test_build_disabled_query_param_excluded() {
        var bd = CurlBreakdown(
            method: "GET",
            baseURL: "https://api.example.com",
            queryParams: [
                HTTPParam(key: "active", value: "true"),
                HTTPParam(key: "hidden", value: "1", isEnabled: false)
            ],
            headers: [],
            bodyParams: [],
            rawBody: "",
            bodyIsRaw: false,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("active=true"))
        XCTAssertFalse(curl.contains("hidden"))
    }

    func test_build_json_body_from_params() {
        let bd = CurlBreakdown(
            method: "POST",
            baseURL: "https://api.example.com",
            queryParams: [],
            headers: [],
            bodyParams: [
                HTTPParam(key: "accountId", value: #""abc""#),
                HTTPParam(key: "limit", value: "10")
            ],
            rawBody: "",
            bodyIsRaw: false,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("-d") || curl.contains("--data"))
        XCTAssertTrue(curl.contains("accountId"))
        XCTAssertTrue(curl.contains("limit"))
    }

    func test_build_raw_body() {
        let bd = CurlBreakdown(
            method: "POST",
            baseURL: "https://api.example.com",
            queryParams: [],
            headers: [],
            bodyParams: [],
            rawBody: "name=foo&bar=baz",
            bodyIsRaw: true,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("name=foo"))
    }

    func test_build_insecure_flag() {
        let bd = CurlBreakdown(
            method: "GET",
            baseURL: "https://self-signed.example.com",
            queryParams: [],
            headers: [],
            bodyParams: [],
            rawBody: "",
            bodyIsRaw: false,
            insecure: true
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("-k") || curl.contains("--insecure"))
    }

    func test_build_disabled_header_excluded() {
        let bd = CurlBreakdown(
            method: "GET",
            baseURL: "https://api.example.com",
            queryParams: [],
            headers: [
                HTTPParam(key: "Authorization", value: "Bearer tok"),
                HTTPParam(key: "X-Debug", value: "1", isEnabled: false)
            ],
            bodyParams: [],
            rawBody: "",
            bodyIsRaw: false,
            insecure: false
        )
        let curl = CurlBuilder.build(bd)
        XCTAssertTrue(curl.contains("Authorization"))
        XCTAssertFalse(curl.contains("X-Debug"))
    }

    func test_roundtrip_parse_build_parse() throws {
        let original = #"curl -X POST 'https://api.example.com/v1/items?page=1' -H 'Authorization: Bearer token123' -H 'Content-Type: application/json' -d '{"accountId":"abc","limit":5}'"#
        let bd1 = try CurlParser.parseBreakdown(original)
        let rebuilt = CurlBuilder.build(bd1)
        let bd2 = try CurlParser.parseBreakdown(rebuilt)
        XCTAssertEqual(bd1.method, bd2.method)
        XCTAssertEqual(bd1.baseURL, bd2.baseURL)
        XCTAssertEqual(bd1.queryParams.map(\.key).sorted(), bd2.queryParams.map(\.key).sorted())
        XCTAssertEqual(bd1.headers.map(\.key).sorted(), bd2.headers.map(\.key).sorted())
        XCTAssertEqual(bd1.bodyParams.map(\.key).sorted(), bd2.bodyParams.map(\.key).sorted())
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
xcodebuild test -project JsonViewApp.xcodeproj -scheme JsonViewApp \
  -destination "platform=macOS" \
  -only-testing:BraceTests/CurlBuilderTests \
  2>&1 | grep -E "error:|failed"
```

Expected: compile error — `cannot find 'CurlBuilder' in scope`

- [ ] **Step 3: Create `CurlBuilder.swift`**

```swift
import Foundation

enum CurlBuilder {

    static func build(_ bd: CurlBreakdown) -> String {
        var parts: [String] = ["curl"]

        if bd.method != "GET" {
            parts += ["-X", bd.method]
        }

        // URL with enabled query params
        let enabledQuery = bd.queryParams.filter(\.isEnabled)
        var urlString = bd.baseURL
        if !enabledQuery.isEmpty {
            var comps = URLComponents(string: bd.baseURL) ?? URLComponents()
            comps.queryItems = enabledQuery.map { URLQueryItem(name: $0.key, value: $0.value) }
            urlString = comps.string ?? bd.baseURL
        }
        parts.append("'\(urlString)'")

        // Enabled headers
        for h in bd.headers where h.isEnabled {
            parts += ["-H", "'\(h.key): \(h.value)'"]
        }

        // Insecure
        if bd.insecure {
            parts.append("-k")
        }

        // Body
        let body = resolvedBody(bd)
        if !body.isEmpty {
            parts += ["-d", "'\(body.replacingOccurrences(of: "'", with: "\\'"))'"]
        }

        return parts.joined(separator: " \\\n  ")
    }

    // MARK: - Private

    private static func resolvedBody(_ bd: CurlBreakdown) -> String {
        if bd.bodyIsRaw { return bd.rawBody }
        let enabled = bd.bodyParams.filter(\.isEnabled)
        guard !enabled.isEmpty else { return bd.rawBody }

        // Rebuild JSON from raw fragment values
        var jsonParts: [String] = []
        for param in enabled {
            let escapedKey = param.key
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            jsonParts.append("\"\(escapedKey)\":\(param.value)")
        }
        return "{\(jsonParts.joined(separator: ","))}"
    }
}
```

Add to Xcode project target (drag into `Core/` group).

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -project JsonViewApp.xcodeproj -scheme JsonViewApp \
  -destination "platform=macOS" \
  -only-testing:BraceTests/CurlBuilderTests \
  2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test Suite 'CurlBuilderTests' passed`

- [ ] **Step 5: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/CurlBuilder.swift \
        JsonViewApp/JsonViewApp/Tests/BraceTests/CurlBreakdownTests.swift
git commit -m "feat: CurlBuilder — serializes CurlBreakdown back to curl string"
```

---

## Task 9: ScanViewModel — Two-Way Curl Breakdown Sync

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanViewModel.swift`

**Interfaces:**
- Consumes: `CurlParser.parseBreakdown(_:)`, `CurlBuilder.build(_:)`
- Produces:
  - `@Published var curlBreakdown: CurlBreakdown? = nil`
  - Combine pipelines: `curlText` changes → re-parse breakdown; `curlBreakdown` changes → rebuild curl text

- [ ] **Step 1: Add `curlBreakdown` and `lastBuiltCurl` to `ScanViewModel`**

In the `// MARK: - Inputs` section, add:

```swift
@Published var curlBreakdown: CurlBreakdown? = nil
private var lastBuiltCurl: String = ""
```

- [ ] **Step 2: Wire the two-way Combine pipelines in `init()`**

In `ScanViewModel.init()`, add after the existing `$config` pipeline:

```swift
// curlText → breakdown: re-parse when user edits the curl text directly
$curlText
    .dropFirst()
    .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
    .sink { [weak self] text in
        guard let self else { return }
        // Skip if this change came from our own breakdown→curl write
        guard text != self.lastBuiltCurl else { return }
        self.curlBreakdown = try? CurlParser.parseBreakdown(text)
    }
    .store(in: &cancellables)

// breakdown → curlText: rebuild curl when user edits the breakdown
$curlBreakdown
    .dropFirst()
    .compactMap { $0 }
    .sink { [weak self] bd in
        guard let self else { return }
        let built = CurlBuilder.build(bd)
        self.lastBuiltCurl = built
        self.curlText = built
    }
    .store(in: &cancellables)
```

- [ ] **Step 3: Leave `validateCurl()` unchanged**

Do NOT add breakdown parsing to `validateCurl()` — it fires synchronously on every keystroke, which would cause `curlBreakdown` to change → rebuild curl → reset the `TextEditor` mid-type. The debounced `$curlText` Combine pipeline (Step 2) handles the parse at the right time. `validateCurl()` stays as-is: only updates `parsedCurl` and `parseError`.

- [ ] **Step 4: Add `updateBreakdownBody(rawBody:)` helper for body raw-mode edits**

When the user edits the raw body text area, we need to sync bodyParams:

```swift
func updateBreakdownRawBody(_ raw: String) {
    guard curlBreakdown != nil else { return }
    curlBreakdown!.rawBody = raw
    // Attempt to parse JSON body params
    if let data = raw.data(using: .utf8),
       let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        curlBreakdown!.bodyParams = dict.keys.sorted().compactMap { key -> HTTPParam? in
            guard let val = dict[key] else { return nil }
            let fragment: String
            if let str = val as? String {
                fragment = "\"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
            } else if let num = val as? NSNumber {
                fragment = CFGetTypeID(num) == CFBooleanGetTypeID() ?
                    (num.boolValue ? "true" : "false") : num.stringValue
            } else if val is NSNull {
                fragment = "null"
            } else if let enc = try? JSONSerialization.data(withJSONObject: val),
                      let s = String(data: enc, encoding: .utf8) {
                fragment = s
            } else { return nil }
            return HTTPParam(key: key, value: fragment)
        }
        curlBreakdown!.bodyIsRaw = false
    }
    // (If not valid JSON, bodyIsRaw stays true and bodyParams remain unchanged)
}
```

- [ ] **Step 5: Build and verify**

```bash
xcodebuild -project JsonViewApp.xcodeproj -scheme JsonViewApp -configuration Debug \
  -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanViewModel.swift
git commit -m "feat: two-way curl breakdown ↔ curlText sync via Combine"
```

---

## Task 10: CurlBreakdownView UI

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/CurlBreakdownView.swift`
- Modify: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift`

**Interfaces:**
- Consumes: `vm.curlBreakdown: CurlBreakdown?`, `vm.updateBreakdownRawBody(_:)`
- Produces: `struct CurlBreakdownView: View` rendered below the curl `TextEditor`

- [ ] **Step 1: Create `CurlBreakdownView.swift`**

```swift
import SwiftUI

struct CurlBreakdownView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var urlExpanded = true
    @State private var queryExpanded = true
    @State private var headersExpanded = true
    @State private var bodyExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                urlSection
                Divider().padding(.horizontal, 8)
                querySection
                Divider().padding(.horizontal, 8)
                headersSection
                Divider().padding(.horizontal, 8)
                bodySection
            }
        }
    }

    // MARK: - URL Section

    @ViewBuilder
    private var urlSection: some View {
        HStack {
            Text("URL")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            Spacer()
        }
        if let bd = vm.curlBreakdown {
            TextField("https://…", text: Binding(
                get: { bd.baseURL },
                set: { vm.curlBreakdown?.baseURL = $0 }
            ))
            .font(.system(size: 11, design: .monospaced))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .textSelection(.enabled)
        }
    }

    // MARK: - Query Params

    @ViewBuilder
    private var querySection: some View {
        let count = vm.curlBreakdown?.queryParams.filter(\.isEnabled).count ?? 0
        paramSection(
            title: "Query",
            badge: count > 0 ? "\(count)" : nil,
            isExpanded: $queryExpanded,
            params: Binding(
                get: { vm.curlBreakdown?.queryParams ?? [] },
                set: { vm.curlBreakdown?.queryParams = $0 }
            )
        )
    }

    // MARK: - Headers

    @ViewBuilder
    private var headersSection: some View {
        let count = vm.curlBreakdown?.headers.filter(\.isEnabled).count ?? 0
        paramSection(
            title: "Headers",
            badge: count > 0 ? "\(count)" : nil,
            isExpanded: $headersExpanded,
            params: Binding(
                get: { vm.curlBreakdown?.headers ?? [] },
                set: { vm.curlBreakdown?.headers = $0 }
            )
        )
    }

    // MARK: - Body

    @ViewBuilder
    private var bodySection: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { bodyExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(bodyExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.15), value: bodyExpanded)
                        Text("Body")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if vm.curlBreakdown != nil {
                    Toggle("Raw", isOn: Binding(
                        get: { vm.curlBreakdown?.bodyIsRaw ?? true },
                        set: { vm.curlBreakdown?.bodyIsRaw = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            if bodyExpanded, let bd = vm.curlBreakdown {
                if bd.bodyIsRaw {
                    TextEditor(text: Binding(
                        get: { bd.rawBody },
                        set: { vm.updateBreakdownRawBody($0) }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .frame(minHeight: 60, maxHeight: 120)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                } else {
                    paramRows(
                        params: Binding(
                            get: { vm.curlBreakdown?.bodyParams ?? [] },
                            set: { vm.curlBreakdown?.bodyParams = $0 }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Reusable param section

    @ViewBuilder
    private func paramSection(
        title: String,
        badge: String?,
        isExpanded: Binding<Bool>,
        params: Binding<[HTTPParam]>
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                            .animation(.easeInOut(duration: 0.15), value: isExpanded.wrappedValue)
                        Text(title)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    params.wrappedValue.append(HTTPParam(key: "", value: ""))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            if isExpanded.wrappedValue {
                paramRows(params: params)
            }
        }
    }

    // MARK: - Param rows

    @ViewBuilder
    private func paramRows(params: Binding<[HTTPParam]>) -> some View {
        VStack(spacing: 2) {
            ForEach(params.wrappedValue.indices, id: \.self) { i in
                paramRow(
                    param: params[i],
                    onDelete: { params.wrappedValue.remove(at: i) }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func paramRow(param: Binding<HTTPParam>, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Toggle("", isOn: param.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()

            TextField("key", text: param.key)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .textSelection(.enabled)

            Text("=")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            TextField("value", text: param.value)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .textSelection(.enabled)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
```

Add to Xcode project target (drag into `HTTPScanner/` group in Xcode navigator).

- [ ] **Step 2: Wire `CurlBreakdownView` into `ScannerSidebarView`**

Inside the Curl `DisclosureGroup` content, after the file importer `HStack`, add:

```swift
// After the existing HStack with clear + import buttons:
if vm.curlBreakdown != nil {
    CurlBreakdownView()
        .padding(.bottom, 4)
}
```

This goes inside the curl `DisclosureGroup` closure, after:
```swift
.padding(.horizontal, 10).padding(.bottom, 6)
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project JsonViewApp.xcodeproj -scheme JsonViewApp -configuration Debug \
  -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -project JsonViewApp.xcodeproj -scheme JsonViewApp \
  -destination "platform=macOS" \
  2>&1 | grep -E "passed|failed|Test Suite 'All'"
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 5: Commit**

```bash
git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/CurlBreakdownView.swift \
        JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift
git commit -m "feat: CurlBreakdownView — URL/query/headers/body editor with two-way sync"
```

---

## Final: Push and publish

```bash
git push origin master
bash scripts/publish.sh 0.2.12
```
