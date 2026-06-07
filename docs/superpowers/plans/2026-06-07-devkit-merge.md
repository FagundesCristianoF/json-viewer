# DevKit Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge `jsonview` (JSON editor, Rust FFI) and `requester` (ParamScan HTTP scanner) into a single macOS SwiftUI app called DevKit, with a toolbar segmented control to switch between modes, a persistent `NavigationSplitView` shell whose sidebar adapts per mode.

**Architecture:** `DevKitModel` owns both `AppModel` (JSON editor state) and `ScanViewModel` (HTTP scanner state) plus an `AppMode` enum. A new `ContentView` wraps both modes in a `NavigationSplitView`; the sidebar and detail areas swap content via `.animation(.easeInOut(0.2))` on mode change. The toolbar shows a centered segmented Picker for mode switching plus mode-specific items.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, macOS 13+, XcodeGen (`project.yml`), Rust FFI (jsonview-ffi), XCTest, swift-snapshot-testing (added via SPM)

---

## File Map

### New files (create)
- `JsonViewApp/JsonViewApp/Sources/Core/AppMode.swift` — `AppMode` enum + `DevKitModel`
- `JsonViewApp/JsonViewApp/Sources/Shared/MonoTextView.swift` — extracted NSTextView wrapper
- `JsonViewApp/JsonViewApp/Sources/Shared/SuggestionTextField.swift` — extracted from requester SidebarView
- `JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorSidebarView.swift` — renamed from SidebarView
- `JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorDetailView.swift` — inner editor layout
- `JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorToolbar.swift` — editor-specific toolbar
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanViewModel.swift` — from requester
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift` — from requester SidebarView (minus SuggestionTextField)
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ConfigPanelView.swift` — from requester
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanResultsView.swift` — from requester ResultsView
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/HistoryView.swift` — from requester
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/CurlParser.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/Filters.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/HistoryStore.swift` — "ParamScan" → "DevKit"
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/HTTPExecutor.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/JSONPathEvaluator.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/OptionsParser.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/RequestBuilder.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/TextNormalizer.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/HistoryEntry.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/OptionEntry.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/ParsedCurl.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/ScanConfig.swift`
- `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/ScanResult.swift`
- `JsonViewApp/JsonViewApp/Tests/DevKitTests/CurlParserTests.swift`
- `JsonViewApp/JsonViewApp/Tests/DevKitTests/OptionsParserTests.swift`
- `JsonViewApp/JsonViewApp/Tests/DevKitTests/FiltersTests.swift`
- `JsonViewApp/JsonViewApp/Tests/DevKitTests/ScanConfigTests.swift`
- `JsonViewApp/JsonViewApp/Tests/DevKitTests/AppModeTests.swift`
- `JsonViewApp/JsonViewApp/Tests/DevKitSnapshotTests/SnapshotTests.swift`

### Modified files
- `JsonViewApp/JsonViewApp/App.swift` — `JsonViewApp` → `DevKitApp`, inject `DevKitModel`, update commands
- `JsonViewApp/JsonViewApp/Sources/ContentView.swift` — replace with `NavigationSplitView` shell
- `JsonViewApp/JsonViewApp/Sources/Theme.swift` — upgrade `SectionHeader` to requester version
- `JsonViewApp/JsonViewApp/Sources/ToolbarView.swift` — repurpose as `DevKitToolbar` (mode toggle + conditional items)
- `JsonViewApp/project.yml` — add new sources, test targets, SPM dependencies

### Deleted (content moved)
- `JsonViewApp/JsonViewApp/Sources/SidebarView.swift` — replaced by `JsonEditorSidebarView.swift`

---

## Task 1: Create AppMode + DevKitModel

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/Core/AppMode.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation
import SwiftUI

enum AppMode: String, CaseIterable {
    case jsonEditor
    case httpScanner

    var label: String {
        switch self {
        case .jsonEditor:  return "JSON Editor"
        case .httpScanner: return "HTTP Scanner"
        }
    }

    var icon: String {
        switch self {
        case .jsonEditor:  return "curlybraces"
        case .httpScanner: return "network"
        }
    }
}

@MainActor
final class DevKitModel: ObservableObject {
    @Published var mode: AppMode = .jsonEditor {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "devKitMode") }
    }

    let editorModel = AppModel()
    let scannerModel = ScanViewModel()

    init() {
        if let raw = UserDefaults.standard.string(forKey: "devKitMode"),
           let saved = AppMode(rawValue: raw) {
            mode = saved
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/Core/AppMode.swift
rtk git commit -m "feat: add AppMode enum and DevKitModel"
```

---

## Task 2: Upgrade SectionHeader in Theme.swift

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/Theme.swift`

The existing `SectionHeader` is a compact version. Requester's version adds an optional `systemImage` icon and uses uppercased tracking text. Replace with the superset version — existing callers (no `systemImage`) remain compatible.

- [ ] **Step 1: Replace `SectionHeader` in Theme.swift**

Find and replace the entire `// MARK: - Section Header` block in `Theme.swift`:

```swift
// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let img = systemImage {
                Image(systemName: img)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/Theme.swift
rtk git commit -m "feat: upgrade SectionHeader with optional systemImage"
```

---

## Task 3: Extract MonoTextView to Shared

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/Shared/MonoTextView.swift`

`MonoTextView` is defined in requester's `ResultsView.swift`. Extract it so both modes can reuse it.

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import AppKit

struct MonoTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/Shared/MonoTextView.swift
rtk git commit -m "feat: extract MonoTextView to Shared"
```

---

## Task 4: Extract SuggestionTextField to Shared

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/Shared/SuggestionTextField.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

struct SuggestionTextField: View {
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]

    @FocusState private var focused: Bool

    private var matches: [String] {
        let q = text.lowercased()
        if q.isEmpty { return suggestions }
        return suggestions.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .focused($focused)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            focused ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor),
                            lineWidth: focused ? 1.5 : 0.5
                        )
                )

            if focused && !matches.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(matches, id: \.self) { s in
                            Button {
                                text = s
                                focused = false
                            } label: {
                                Text(s)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                }
                .frame(maxHeight: 110)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/Shared/SuggestionTextField.swift
rtk git commit -m "feat: extract SuggestionTextField to Shared"
```

---

## Task 5: Copy JSONColorView + OptionRow to Shared

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/Shared/JSONColorView.swift`
- Create: `JsonViewApp/JsonViewApp/Sources/Shared/OptionRow.swift`

- [ ] **Step 1: Copy JSONColorView**

Copy `/Users/cristianofagundes/Projects/requester/Requester/Views/Components/JSONColorView.swift` verbatim to `JsonViewApp/JsonViewApp/Sources/Shared/JSONColorView.swift`. No modifications needed.

- [ ] **Step 2: Copy OptionRow + StatusDot**

Copy `/Users/cristianofagundes/Projects/requester/Requester/Views/Components/OptionRow.swift` verbatim to `JsonViewApp/JsonViewApp/Sources/Shared/OptionRow.swift`. No modifications needed.

- [ ] **Step 3: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/Shared/
rtk git commit -m "feat: add JSONColorView and OptionRow to Shared"
```

---

## Task 6: Create JsonEditorSidebarView

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorSidebarView.swift`

Copy the full content of `JsonViewApp/JsonViewApp/Sources/SidebarView.swift`, then rename the struct.

- [ ] **Step 1: Create the file**

Copy `SidebarView.swift` content exactly but:
1. Rename `struct SidebarView` → `struct JsonEditorSidebarView`
2. Rename `SidebarView_Previews` → `JsonEditorSidebarView_Previews`
3. In the preview block, use `JsonEditorSidebarView()` instead of `SidebarView()`

- [ ] **Step 2: Delete old SidebarView.swift**

```bash
rm JsonViewApp/JsonViewApp/Sources/SidebarView.swift
```

- [ ] **Step 3: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorSidebarView.swift
rtk git add -u JsonViewApp/JsonViewApp/Sources/SidebarView.swift
rtk git commit -m "feat: rename SidebarView to JsonEditorSidebarView"
```

---

## Task 7: Create JsonEditorDetailView

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorDetailView.swift`

This extracts the inner layout currently in `ContentView.swift` (the `HSplitView` + `IssuesView` + `StatusBarView` sandwich) into its own view, so `ContentView` can compose it cleanly.

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

struct JsonEditorDetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ActionBarView()
                VSplitView {
                    HSplitView {
                        EditorView()
                            .frame(minWidth: 300)
                        if model.showTree {
                            JSONTreeView()
                                .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                        }
                    }
                    .frame(minHeight: 200)
                    if model.showIssues {
                        IssuesView()
                            .frame(minHeight: 100, idealHeight: 160, maxHeight: 280)
                    }
                }
                StatusBarView()
            }

            if let msg = model.toast {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.bottom, 36)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.2), value: model.toast)
            }
        }
        .background(FileCommands(model: model))
    }
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorDetailView.swift
rtk git commit -m "feat: extract JsonEditorDetailView"
```

---

## Task 8: Create JsonEditorToolbar

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorToolbar.swift`

Extract the editor-specific toolbar items from `ToolbarView.swift`. These will be conditionally shown when mode is `.jsonEditor`.

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

// Editor-specific toolbar buttons shown when mode == .jsonEditor
struct JsonEditorToolbarItems: ToolbarContent {
    @EnvironmentObject var model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.showSidebar.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")
        }

        ToolbarItemGroup(placement: .automatic) {
            Button { model.darkMode.toggle() } label: {
                Image(systemName: model.darkMode ? "sun.max" : "moon")
            }
            .help(model.darkMode ? "Light Mode" : "Dark Mode")

            Button { model.showTree.toggle() } label: {
                Image(systemName: "list.bullet.indent")
            }
            .help("Toggle Tree")

            JsonEditorIssuesToggle()
        }
    }
}

private struct JsonEditorIssuesToggle: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button { model.showIssues.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "exclamationmark.triangle")
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                IssuesBadge(
                    errorCount: model.parseError != nil ? 1 : 0,
                    smellCount: model.smells.count
                )
            }
        }
        .help("Toggle Issues")
    }
}

private struct IssuesBadge: View {
    let errorCount: Int
    let smellCount: Int
    var count: Int { errorCount + smellCount }
    var body: some View {
        if count > 0 {
            Text("\(min(count, 99))")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.red, in: Capsule())
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/JSONEditor/JsonEditorToolbar.swift
rtk git commit -m "feat: extract JsonEditorToolbar"
```

---

## Task 9: Copy HTTPScanner Core files

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/*.swift` (8 files)

- [ ] **Step 1: Create directory and copy all Core files**

Copy the following files verbatim from `/Users/cristianofagundes/Projects/requester/Requester/Core/` to `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/`:

- `CurlParser.swift` — no changes
- `Filters.swift` — no changes
- `HTTPExecutor.swift` — no changes
- `JSONPathEvaluator.swift` — no changes
- `OptionsParser.swift` — no changes
- `RequestBuilder.swift` — no changes
- `TextNormalizer.swift` — no changes

- [ ] **Step 2: Copy and modify HistoryStore.swift**

Copy `HistoryStore.swift` but change `"ParamScan"` to `"DevKit"` in the `fileURL` computed property:

```swift
// Change this line:
let dir = support.appendingPathComponent("ParamScan", isDirectory: true)
// To:
let dir = support.appendingPathComponent("DevKit", isDirectory: true)
```

- [ ] **Step 3: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/Core/
rtk git commit -m "feat: copy HTTPScanner Core files from requester"
```

---

## Task 10: Copy HTTPScanner Models files

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/*.swift` (5 files)

- [ ] **Step 1: Copy all Model files verbatim**

Copy these from `/Users/cristianofagundes/Projects/requester/Requester/Models/` to `JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/`:

- `HistoryEntry.swift`
- `OptionEntry.swift`
- `ParsedCurl.swift`
- `ScanConfig.swift`
- `ScanResult.swift`

No modifications needed.

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/Models/
rtk git commit -m "feat: copy HTTPScanner Models from requester"
```

---

## Task 11: Copy ScanViewModel

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanViewModel.swift`

- [ ] **Step 1: Copy verbatim**

Copy `/Users/cristianofagundes/Projects/requester/Requester/ViewModels/ScanViewModel.swift` verbatim to `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanViewModel.swift`. No modifications needed.

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanViewModel.swift
rtk git commit -m "feat: copy ScanViewModel from requester"
```

---

## Task 12: Create ScannerSidebarView

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift`

Copy requester `SidebarView.swift` but:
1. Rename `struct SidebarView` → `struct ScannerSidebarView`
2. Remove the `SuggestionTextField` struct definition (it now lives in `Shared/`)
3. Remove the `SidebarDisclosureStyle` struct definition — move it to this file's bottom as it's scanner-specific
4. Remove the `SectionHeader` usage in favor of the shared one (already compatible)

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ScannerSidebarView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var showCurlImporter = false
    @State private var showOptionsImporter = false
    @State private var curlExpanded = true
    @State private var optionsExpanded = true

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Curl section
            DisclosureGroup(isExpanded: $curlExpanded) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if vm.curlText.isEmpty {
                            Text("curl -X POST 'https://…' \\\n  -H 'Authorization: Bearer …' \\\n  -d '{\"accountId\":\"…\"}'")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 8).padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $vm.curlText)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(4)
                            .frame(minHeight: 120, maxHeight: 200)
                            .onChange(of: vm.curlText) { _ in vm.validateCurl() }
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .padding(.horizontal, 8).padding(.bottom, 6)

                    if let err = vm.parseError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                            Text(err).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2)
                        }
                        .padding(.horizontal, 10).padding(.bottom, 6)
                    }

                    HStack {
                        Spacer()
                        Button { vm.curlText = ""; vm.parseError = nil } label: {
                            Image(systemName: "xmark.circle").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(String(localized: "action.clear"))
                        Button { showCurlImporter = true } label: {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(String(localized: "action.import_file"))
                    }
                    .padding(.horizontal, 10).padding(.bottom, 6)
                }
            } label: {
                SectionHeader(title: String(localized: "section.curl_command"), systemImage: "terminal")
                    .contentShape(Rectangle())
            }
            .disclosureGroupStyle(SidebarDisclosureStyle())

            Divider().padding(.horizontal, 8)

            // MARK: Options section
            DisclosureGroup(isExpanded: $optionsExpanded) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if vm.optionsText.isEmpty {
                            Text("[{\"id\":\"uuid-1\",\"displayName\":\"Account 1\"},…]")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 8).padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $vm.optionsText)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(4)
                            .frame(minHeight: 60, maxHeight: 120)
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .padding(.horizontal, 8).padding(.bottom, 4)

                    HStack {
                        Text("\(vm.optionCount) option\(vm.optionCount == 1 ? "" : "s")")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button { vm.optionsText = "" } label: {
                            Image(systemName: "xmark.circle").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear")
                        Button { showOptionsImporter = true } label: {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Import from file")
                    }
                    .padding(.horizontal, 10).padding(.bottom, 4)

                    VStack(spacing: 3) {
                        HStack(spacing: 6) {
                            Text("ID path")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            SuggestionTextField(
                                placeholder: "id",
                                text: $vm.config.optionIdPath,
                                suggestions: vm.pathSuggestions
                            )
                        }
                        HStack(spacing: 6) {
                            Text("Name path")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            SuggestionTextField(
                                placeholder: "displayName",
                                text: $vm.config.optionNamePath,
                                suggestions: vm.pathSuggestions
                            )
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 4)

                    if !vm.mergedForDisplay.isEmpty {
                        Divider().padding(.horizontal, 8).padding(.vertical, 2)
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(vm.mergedForDisplay) { result in
                                    OptionRow(result: result, isSelected: vm.selectedResultID == result.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { vm.selectedResultID = result.id }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxHeight: 320)
                    }
                }
            } label: {
                SectionHeader(title: String(localized: "section.options"), systemImage: "list.bullet")
                    .contentShape(Rectangle())
            }
            .disclosureGroupStyle(SidebarDisclosureStyle())

            Spacer()

            if let err = vm.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $showCurlImporter, allowedContentTypes: [.text, .plainText]) { result in
            if case .success(let url) = result { vm.importCurlFile(url) }
        }
        .fileImporter(isPresented: $showOptionsImporter, allowedContentTypes: [.json, .text]) { result in
            if case .success(let url) = result { vm.importOptionsFile(url) }
        }
    }
}

// MARK: - Disclosure style

struct SidebarDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            configuration.label
                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { configuration.isExpanded.toggle() } }
            if configuration.isExpanded { configuration.content }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScannerSidebarView.swift
rtk git commit -m "feat: add ScannerSidebarView (from requester SidebarView)"
```

---

## Task 13: Copy HTTPScanner view files

**Files:**
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ConfigPanelView.swift`
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanResultsView.swift`
- Create: `JsonViewApp/JsonViewApp/Sources/HTTPScanner/HistoryView.swift`

- [ ] **Step 1: Copy ConfigPanelView verbatim**

Copy `/Users/cristianofagundes/Projects/requester/Requester/Views/ConfigPanelView.swift` to `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ConfigPanelView.swift`. No changes needed.

- [ ] **Step 2: Create ScanResultsView**

Copy `/Users/cristianofagundes/Projects/requester/Requester/Views/ResultsView.swift` to `JsonViewApp/JsonViewApp/Sources/HTTPScanner/ScanResultsView.swift`.

Remove the `MonoTextView` struct definition from this file entirely (it now lives in `Shared/MonoTextView.swift`). Keep all other structs: `ResultsView`, `ProgressHeader`, `ResponseDetailView`, `ErrorDetailView`, `FilteredResultsView`, `UnfilteredResultsHint`, `EmptySelectionView`, `NoMatchesView`, `EmptyStateView`.

- [ ] **Step 3: Copy HistoryView verbatim**

Copy `/Users/cristianofagundes/Projects/requester/Requester/Views/HistoryView.swift` to `JsonViewApp/JsonViewApp/Sources/HTTPScanner/HistoryView.swift`. No changes needed.

- [ ] **Step 4: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/HTTPScanner/
rtk git commit -m "feat: copy HTTPScanner view files from requester"
```

---

## Task 14: Create merged ContentView

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/ContentView.swift`

Replace the existing content entirely.

- [ ] **Step 1: Write new ContentView.swift**

```swift
import SwiftUI
import AppKit

// MARK: - DevKit Root

struct ContentView: View {
    @EnvironmentObject var devKit: DevKitModel

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 360)
                .animation(.easeInOut(duration: 0.2), value: devKit.mode)
        } detail: {
            detailContent
                .animation(.easeInOut(duration: 0.2), value: devKit.mode)
        }
        .toolbar {
            DevKitToolbar()
        }
        .preferredColorScheme(devKit.editorModel.darkMode ? .dark : .light)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch devKit.mode {
        case .jsonEditor:
            JsonEditorSidebarView()
                .environmentObject(devKit.editorModel)
        case .httpScanner:
            ScannerSidebarView()
                .environmentObject(devKit.scannerModel)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch devKit.mode {
        case .jsonEditor:
            JsonEditorDetailView()
                .environmentObject(devKit.editorModel)
        case .httpScanner:
            ScannerDetailView()
                .environmentObject(devKit.scannerModel)
        }
    }
}

// MARK: - Scanner Detail (config panel + results split)

struct ScannerDetailView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var showHistory = false

    var body: some View {
        HSplitView {
            ConfigPanelView()
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
                .environmentObject(vm)
            ResultsView()
                .frame(minWidth: 300)
                .environmentObject(vm)
        }
        .toolbar {
            ScannerToolbarItems(showHistory: $showHistory)
                .environmentObject(vm)
        }
        .popover(isPresented: $showHistory, arrowEdge: .bottom) {
            HistoryView(isPresented: $showHistory)
                .environmentObject(vm)
        }
    }
}

// MARK: - AppCommands (menu bar)

struct AppCommands: Commands {
    @ObservedObject var devKit: DevKitModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                devKit.editorModel.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(devKit.editorModel.selectedFile == nil || devKit.mode != .jsonEditor)
        }

        CommandGroup(after: .saveItem) {
            Button("Open Workspace…") {
                openWorkspacePicker(model: devKit.editorModel)
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(devKit.mode != .jsonEditor)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find…") {
                NotificationCenter.default.post(name: .editorActivateFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(devKit.mode != .jsonEditor)
        }

        CommandMenu("Scan") {
            Button("Run") { devKit.scannerModel.run() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(devKit.scannerModel.isRunning || devKit.mode != .httpScanner)
            Button("Stop") { devKit.scannerModel.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!devKit.scannerModel.isRunning)
        }
    }

    private func openWorkspacePicker(model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in model.openWorkspace(url) }
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let editorActivateFind = Notification.Name("JsonView.editorActivateFind")
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/ContentView.swift
rtk git commit -m "feat: replace ContentView with DevKit NavigationSplitView shell"
```

---

## Task 15: Update ToolbarView with DevKitToolbar + mode toggle

**Files:**
- Modify: `JsonViewApp/JsonViewApp/Sources/ToolbarView.swift`

Replace the entire file. Keep all existing structs (`ActionBarView`, `JsonPathField`, `NoFocusRingTextField`, `ReplacePopover`, etc.) under `// MARK: - JSON Editor Action Bar`. Add the new `DevKitToolbar` and `ScannerToolbarItems` at the top.

- [ ] **Step 1: Add DevKitToolbar at the top of ToolbarView.swift**

Insert before the `// MARK: - Toolbar Items` block:

```swift
// MARK: - DevKit Toolbar (mode toggle + per-mode items)

struct DevKitToolbar: ToolbarContent {
    @EnvironmentObject var devKit: DevKitModel

    var body: some ToolbarContent {
        // Mode toggle — centered, always visible
        ToolbarItem(placement: .principal) {
            Picker("", selection: $devKit.mode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .help("Switch mode")
        }

        // JSON Editor mode items
        if devKit.mode == .jsonEditor {
            JsonEditorToolbarItems()
                .environmentObject(devKit.editorModel)
        }
    }
}

// MARK: - Scanner Toolbar Items

struct ScannerToolbarItems: ToolbarContent {
    @EnvironmentObject var vm: ScanViewModel
    @Binding var showHistory: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("History")
            .badge(vm.history.isEmpty ? 0 : min(vm.history.count, 99))
        }

        if vm.isRunning {
            ToolbarItem(placement: .primaryAction) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
                    .padding(.leading, 8)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    vm.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: .command)
                .tint(.red)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.run()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(
                    vm.curlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    vm.optionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .contextMenu {
                    Button {
                        vm.forceRun()
                    } label: {
                        Label("Force Run (ignore cache)", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Remove the old `ToolbarItems` struct** from `ToolbarView.swift` (the one that was previously used in `ContentView` — it's now replaced by `JsonEditorToolbarItems` in `JsonEditorToolbar.swift`).

- [ ] **Step 3: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Sources/ToolbarView.swift
rtk git commit -m "feat: add DevKitToolbar with mode toggle segmented control"
```

---

## Task 16: Update App.swift

**Files:**
- Modify: `JsonViewApp/JsonViewApp/App.swift`

- [ ] **Step 1: Replace App.swift**

```swift
import SwiftUI

@main
struct DevKitApp: App {
    @StateObject private var devKit = DevKitModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(devKit)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            AppCommands(devKit: devKit)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/App.swift
rtk git commit -m "feat: update App.swift to DevKitApp with DevKitModel"
```

---

## Task 17: Update project.yml

**Files:**
- Modify: `JsonViewApp/project.yml`

- [ ] **Step 1: Replace project.yml with new version**

```yaml
name: DevKit
options:
  bundleIdPrefix: com.fagundes
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "16"

packages:
  swift-snapshot-testing:
    url: https://github.com/pointfreeco/swift-snapshot-testing
    from: 1.17.0

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "13.0"
    PRODUCT_BUNDLE_IDENTIFIER: com.fagundes.devkit
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: VP83767PVX

targets:
  DevKit:
    type: application
    platform: macOS
    sources:
      - path: JsonViewApp
        excludes:
          - "**/*.md"
          - "Tests/**"
    resources:
      - JsonViewApp/Resources
      - JsonViewApp/Assets.xcassets
    settings:
      base:
        INFOPLIST_FILE: JsonViewApp/Info.plist
        PRODUCT_NAME: DevKit
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        OTHER_LDFLAGS:
          - "-L/Users/cristianofagundes/Projects/jsonview/target/release"
          - "-ljsonview_ffi"
          - "-lc++"
          - "-framework Foundation"
          - "-framework Security"
        LIBRARY_SEARCH_PATHS: "/Users/cristianofagundes/Projects/jsonview/target/release"
        SWIFT_OBJC_BRIDGING_HEADER: JsonViewApp/JsonViewApp-Bridging-Header.h
    preBuildScripts:
      - name: Build Rust FFI
        script: |
          export PATH="$PATH:$HOME/.cargo/bin"
          cd /Users/cristianofagundes/Projects/jsonview
          cargo build --release -p jsonview-ffi 2>&1
        basedOnDependencyAnalysis: false

  DevKitTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: JsonViewApp/Tests/DevKitTests
    dependencies:
      - target: DevKit
    settings:
      base:
        SWIFT_VERSION: "5.9"

  DevKitSnapshotTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: JsonViewApp/Tests/DevKitSnapshotTests
    dependencies:
      - target: DevKit
      - package: swift-snapshot-testing
    settings:
      base:
        SWIFT_VERSION: "5.9"
```

- [ ] **Step 2: Run xcodegen**

```bash
cd JsonViewApp && xcodegen generate
```

Expected output: `⚙️  Generating plists...` then `✅  Created at JsonViewApp.xcodeproj`

- [ ] **Step 3: Commit**

```bash
rtk git add JsonViewApp/project.yml JsonViewApp/JsonViewApp.xcodeproj/
rtk git commit -m "feat: update project.yml for DevKit with test targets and SPM"
```

---

## Task 18: Build and fix compile errors

**Files:** Various (fix whatever the compiler reports)

- [ ] **Step 1: Build**

```bash
cd JsonViewApp && xcodebuild -scheme DevKit -configuration Debug \
  -destination "platform=macOS" build 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED"
```

- [ ] **Step 2: Fix errors**

Common expected errors and fixes:

**`ToolbarItems` not found** → Remove any remaining references to the old `ToolbarItems` struct; it's been replaced by `DevKitToolbar` and `JsonEditorToolbarItems`.

**`SidebarView` not found** → Update any remaining references to use `JsonEditorSidebarView`.

**`MonoTextView` redeclaration** → Ensure `MonoTextView` only exists in `Shared/MonoTextView.swift`, not in `ScanResultsView.swift`.

**`SectionHeader` ambiguous** → Ensure old `SectionHeader` definition in `Theme.swift` is fully replaced (only one definition).

**`FileCommands` not found in `JsonEditorDetailView`** → `FileCommands` is defined in the old `ContentView.swift`. Move it to `JsonEditorDetailView.swift` since only the editor uses it. Add the `CommandResponderView` class and `FileCommands` struct at the bottom of `JsonEditorDetailView.swift`:

```swift
// MARK: - FileCommands (editor key bindings)

struct FileCommands: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> CommandResponderView {
        let view = CommandResponderView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: CommandResponderView, context: Context) {
        nsView.model = model
    }
}

final class CommandResponderView: NSView {
    var model: AppModel?
    override var acceptsFirstResponder: Bool { false }

    @objc func openWorkspace(_ sender: Any?) { openWorkspacePicker() }
    @objc func saveDocument(_ sender: Any?) { model?.save() }
    @objc func performFindPanelAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .editorActivateFind, object: nil)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(openWorkspace(_:))
            || aSelector == #selector(saveDocument(_:))
            || aSelector == #selector(performFindPanelAction(_:)) {
            return true
        }
        return super.responds(to: aSelector)
    }

    private func openWorkspacePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.model?.openWorkspace(url) }
        }
    }
}
```

- [ ] **Step 3: Re-build until clean**

```bash
cd JsonViewApp && xcodebuild -scheme DevKit -configuration Debug \
  -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
rtk git add -A
rtk git commit -m "fix: resolve compile errors after DevKit merge"
```

---

## Task 19: Write unit tests

**Files:**
- Create: `JsonViewApp/JsonViewApp/Tests/DevKitTests/AppModeTests.swift`
- Create: `JsonViewApp/JsonViewApp/Tests/DevKitTests/ScanConfigTests.swift`
- Create: `JsonViewApp/JsonViewApp/Tests/DevKitTests/CurlParserTests.swift`
- Create: `JsonViewApp/JsonViewApp/Tests/DevKitTests/OptionsParserTests.swift`
- Create: `JsonViewApp/JsonViewApp/Tests/DevKitTests/FiltersTests.swift`

- [ ] **Step 1: Create AppModeTests.swift**

```swift
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
```

- [ ] **Step 2: Create ScanConfigTests.swift**

```swift
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
```

- [ ] **Step 3: Create CurlParserTests.swift**

```swift
import XCTest
@testable import DevKit

final class CurlParserTests: XCTestCase {

    func test_parse_simple_GET() throws {
        let curl = "curl https://api.example.com/users"
        let result = try CurlParser.parse(curl)
        XCTAssertEqual(result.url, "https://api.example.com/users")
        XCTAssertEqual(result.method, "GET")
    }

    func test_parse_POST_with_data() throws {
        let curl = """
        curl -X POST https://api.example.com/search \
          -H 'Content-Type: application/json' \
          -d '{"accountId":"123"}'
        """
        let result = try CurlParser.parse(curl)
        XCTAssertEqual(result.method, "POST")
        XCTAssertEqual(result.url, "https://api.example.com/search")
        XCTAssertNotNil(result.data)
    }

    func test_parse_with_auth_header() throws {
        let curl = """
        curl https://api.example.com/data \
          -H 'Authorization: Bearer token123'
        """
        let result = try CurlParser.parse(curl)
        let authHeader = result.headers.first { $0.name.lowercased() == "authorization" }
        XCTAssertNotNil(authHeader)
        XCTAssertTrue(authHeader?.value.contains("Bearer") ?? false)
    }

    func test_parse_invalid_throws() {
        XCTAssertThrowsError(try CurlParser.parse("not a curl command"))
    }

    func test_parse_empty_throws() {
        XCTAssertThrowsError(try CurlParser.parse(""))
    }
}
```

- [ ] **Step 4: Create OptionsParserTests.swift**

```swift
import XCTest
@testable import DevKit

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

    func test_parse_invalid_json_returns_empty() {
        XCTAssertEqual(OptionsParser.parse("not json").count, 0)
    }

    func test_parse_missing_id_field_skips_entry() {
        let json = """
        [{"displayName":"No ID here"},{"id":"valid","displayName":"Valid"}]
        """
        let results = OptionsParser.parse(json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "valid")
    }
}
```

- [ ] **Step 5: Create FiltersTests.swift**

```swift
import XCTest
@testable import DevKit

final class FiltersTests: XCTestCase {

    private func makeResult(body: String, statusCode: Int = 200) -> OptionResult {
        var r = OptionResult(id: "test", displayName: nil)
        r.responseBody = body
        r.statusCode = statusCode
        r.prettyBody = body
        r.status = .matched
        return r
    }

    func test_jsonpath_filter_matches() {
        let body = """
        {"items":[{"active":true,"name":"A"},{"active":false,"name":"B"}]}
        """
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: "$.items[?(@.active == true)]", requireResultsPath: nil)
        XCTAssertTrue(Filters.matches(response: result, data: data, args: args))
    }

    func test_jsonpath_filter_no_match() {
        let body = """
        {"items":[{"active":false,"name":"B"}]}
        """
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: "$.items[?(@.active == true)]", requireResultsPath: nil)
        XCTAssertFalse(Filters.matches(response: result, data: data, args: args))
    }

    func test_require_results_path_match() {
        let body = """
        {"data":[{"id":1},{"id":2}]}
        """
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: nil, requireResultsPath: "$.data[*]")
        XCTAssertTrue(Filters.matches(response: result, data: data, args: args))
    }

    func test_require_results_path_empty_array_no_match() {
        let body = """
        {"data":[]}
        """
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: nil, requireResultsPath: "$.data[*]")
        XCTAssertFalse(Filters.matches(response: result, data: data, args: args))
    }

    func test_no_filters_always_matches() {
        let body = "{}"
        let result = makeResult(body: body)
        let data = try? JSONSerialization.jsonObject(with: body.data(using: .utf8)!)
        let args = Filters.FilterArgs(jsonpath: nil, requireResultsPath: nil)
        XCTAssertTrue(Filters.matches(response: result, data: data, args: args))
    }
}
```

- [ ] **Step 6: Run tests**

```bash
cd JsonViewApp && xcodebuild test -scheme DevKitTests \
  -destination "platform=macOS" 2>&1 | grep -E "Test Suite|passed|failed|error:"
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Tests/DevKitTests/
rtk git commit -m "test: add unit tests for AppMode, ScanConfig, CurlParser, OptionsParser, Filters"
```

---

## Task 20: Write snapshot tests

**Files:**
- Create: `JsonViewApp/JsonViewApp/Tests/DevKitSnapshotTests/SnapshotTests.swift`

- [ ] **Step 1: Create SnapshotTests.swift**

```swift
import XCTest
import SnapshotTesting
import SwiftUI
@testable import DevKit

final class SnapshotTests: XCTestCase {

    // Record mode: set to true on first run to generate reference images,
    // then set back to false for CI.
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
```

- [ ] **Step 2: Run snapshot tests in record mode first**

Edit the test file temporarily: set `let record = true`, then run:

```bash
cd JsonViewApp && xcodebuild test -scheme DevKitSnapshotTests \
  -destination "platform=macOS" 2>&1 | grep -E "Test Suite|passed|failed|error:|Recorded"
```

Expected: Tests "fail" with "Recorded snapshot" messages — this is correct, it's generating reference images.

- [ ] **Step 3: Switch back to verify mode**

Set `let record = false` in `SnapshotTests.swift`, then run again:

```bash
cd JsonViewApp && xcodebuild test -scheme DevKitSnapshotTests \
  -destination "platform=macOS" 2>&1 | grep -E "passed|failed"
```

Expected: All snapshot tests pass.

- [ ] **Step 4: Commit**

```bash
rtk git add JsonViewApp/JsonViewApp/Tests/DevKitSnapshotTests/
rtk git add JsonViewApp/JsonViewApp/Tests/DevKitSnapshotTests/__Snapshots__/
rtk git commit -m "test: add snapshot tests for shared UI components"
```

---

## Task 21: Final verification

- [ ] **Step 1: Full clean build**

```bash
cd JsonViewApp && xcodebuild -scheme DevKit -configuration Release \
  -destination "platform=macOS" build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run all unit tests**

```bash
cd JsonViewApp && xcodebuild test -scheme DevKitTests \
  -destination "platform=macOS" 2>&1 | grep -E "Test Suite|passed|failed"
```

Expected: All tests pass.

- [ ] **Step 3: Final commit**

```bash
rtk git add -A
rtk git commit -m "feat: complete DevKit merge — jsonview + requester unified app"
```
