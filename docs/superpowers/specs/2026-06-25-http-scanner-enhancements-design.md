# HTTP Scanner Enhancements — Design Spec
_2026-06-25_

## Overview

Four independent enhancements to the HTTP Scanner:

1. **Saved Requests** — user-curated named snapshots of the full scanner state
2. **Results Text Search** — post-scan filter of the result list by response body text
3. **Text Selection** — selectable text throughout the scanner UI
4. **Curl Parameter Breakdown** — structured editor for query params, headers, and body with two-way sync to the curl text

---

## 1. Saved Requests

### What is saved

A `SavedRequest` captures the complete scanner state needed to reproduce a run:

```swift
struct SavedRequest: Codable, Identifiable {
    var id: UUID
    var name: String
    var curlText: String
    var optionsText: String
    var config: ScanConfig
    var createdAt: Date
}
```

### Persistence

`SavedRequestsStore.shared` — mirrors the existing `HistoryStore` pattern:
- File: `~/Library/Application Support/Brace/saved_requests.json`
- No entry cap (unlike history's 50)
- Atomic writes via `Data.write(to:options:.atomic)`
- `@Published var items: [SavedRequest]` sorted by `createdAt` descending
- Ops: `add(_:)`, `update(id:name:curlText:optionsText:config:)`, `delete(id:)`

### ViewModel additions

```swift
@Published var currentSavedRequestID: UUID?   // set on load, cleared on divergence
```

`hasPendingChanges: Bool` — computed: `currentSavedRequestID != nil` AND `(curlText, optionsText, config)` differ from the stored snapshot for that ID. Used to determine toolbar icon state.

When the user edits `curlText`, `optionsText`, or `config` after loading a saved request, `currentSavedRequestID` is not automatically cleared — `hasPendingChanges` captures the dirty state without losing the association (needed for "Update" action).

### Save trigger — toolbar

New bookmark button in `ScannerToolbarItems`, left of the Run button. Three states:

| State | Icon | Tap action |
|---|---|---|
| No active saved request | `bookmark` (outline) | Popover: name TextField + Save button |
| Active, no pending changes | `bookmark.fill` | Popover: request name label + "Rename" + "Delete" |
| Active, pending changes | `bookmark.fill` with badge dot | Popover: "Update [name]" + "Save as new…" |

### Sidebar section

New `DisclosureGroup("Saved", ...)` at the very top of `ScannerSidebarView`, above the Curl section. Hidden entirely when `SavedRequestsStore.shared.items` is empty.

Each row: name label. States:
- Active (currently loaded): accent color name + filled bookmark indicator
- Default: secondary name

Interactions:
- **Single tap** → load: sets `curlText`, `optionsText`, `config`, `currentSavedRequestID`
- **Right-click menu** → Load / Rename / Overwrite with current / Delete
- **Rename**: inline `TextField` replacing the name label, confirmed on Return or blur
- **Delete**: direct removal, no confirmation (destructive but recoverable via re-save)
- **Overwrite**: calls `store.update(id:...)` with current VM state

---

## 2. Results Text Search

A `TextField` search bar pinned inside `ScannerSidebarView`, below the options/results section header, visible only when `vm.results` is non-empty.

```swift
@State private var resultSearch: String = ""
```

Filtering logic: applied to the displayed result list. An entry is shown if `resultSearch` is empty OR `entry.responseBody?.localizedCaseInsensitiveContains(resultSearch) == true`.

This is a **view-level filter only** — no re-fetch, no mutation of `vm.results`. It applies on top of the existing `vm.matchingEntries` / all-results display logic.

Clear button (×) appears when `resultSearch` is non-empty. Placeholder: `"Search responses…"`.

---

## 3. Text Selection

### JSONColorView

Add `.textSelection(.enabled)` to each `Text` leaf in `JLineView`. This enables per-line selection within the colored tree view. Cross-line selection remains available via the existing "Raw" toggle (`MonoTextView` uses `NSTextView` with `isSelectable = true`).

No structural changes to `JSONColorView` or `JLineView` — the modifier is additive.

### FilteredResultsView

Already has `.textSelection(.enabled)` on the results `Text`. No change needed.

### Sidebar

Add `.textSelection(.enabled)` to:
- Option name and ID labels in `OptionRow`
- Error message text in the sidebar
- Result row labels in the sidebar list

---

## 4. Curl Parameter Breakdown (two-way sync)

### Data model

```swift
struct HTTPParam: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var key: String
    var value: String
    var isEnabled: Bool = true
}

struct CurlBreakdown: Equatable {
    var method: String            // GET, POST, etc.
    var baseURL: String           // URL without query string
    var queryParams: [HTTPParam]
    var headers: [HTTPParam]
    var bodyParams: [HTTPParam]   // top-level JSON keys (empty if body is not JSON)
    var rawBody: String           // full body string (kept in sync with bodyParams)
    var bodyIsRaw: Bool           // true when user switched to raw body edit mode
    var insecure: Bool
}
```

### CurlParser extension

`CurlParser.parseBreakdown(_ curlText: String) -> CurlBreakdown?` — extends the existing `CurlParser` to produce a `CurlBreakdown`. Steps:
1. Parse via existing logic to get `ParsedCurl`
2. Split URL into `baseURL` + `queryParams` (using `URLComponents`)
3. Map headers array → `[HTTPParam]`
4. If `data` is valid JSON object: extract top-level keys → `bodyParams`; set `rawBody = data`
5. If `data` is non-JSON or empty: `bodyParams = []`, `rawBody = data`, `bodyIsRaw = true`

### CurlBuilder (new file)

`CurlBuilder.build(_ breakdown: CurlBreakdown) -> String` — serializes back to a curl string:

```
curl -X {METHOD} "{baseURL}?{enabled queryParams}" \
  {enabled headers as -H "K: V"} \
  {--insecure if insecure} \
  -d '{body}'
```

Body reconstruction:
- If `bodyIsRaw`: use `rawBody` directly
- If not raw: rebuild JSON from enabled `bodyParams` (preserving original JSON values as-is; non-enabled keys omitted)

Disabled params (`isEnabled = false`) are excluded from the output. GET with no body omits the `-d` flag.

### ViewModel additions

```swift
@Published var curlBreakdown: CurlBreakdown? = nil
private var lastBuiltCurl: String = ""   // loop guard
```

**Loop-safe two-way sync via Combine:**

```
curlText changes:
  if curlText == lastBuiltCurl → skip (our own write)
  else → parse → update curlBreakdown

curlBreakdown changes:
  build → newCurl
  lastBuiltCurl = newCurl
  curlText = newCurl
```

Both pipelines use a short debounce (150ms on curlText changes; immediate on breakdown changes).

### UI — CurlBreakdownView

Rendered inside the existing "Curl Command" `DisclosureGroup`, below the `TextEditor` and file importer button. Only shown when `vm.curlBreakdown != nil`.

Four collapsible sub-sections (each a `DisclosureGroup`):

**URL**
- Single `TextField` bound to `breakdown.baseURL`. Edit → triggers breakdown → curl rebuild.

**Query Params** (badge shows enabled count)
- Table of rows: `Toggle` · key `TextField` · `=` separator · value `TextField` · delete `Button`
- "Add param" button appends blank `HTTPParam`

**Headers** (badge shows enabled count)
- Same row structure as Query Params

**Body** (badge: "JSON" when parsed as JSON, "Raw" when raw)
- Section header contains a "Raw" toggle that sets `breakdown.bodyIsRaw`
- Raw mode: single `TextEditor` bound to `breakdown.rawBody`; on commit → attempt JSON parse → update `bodyParams` if valid
- Table mode: rows same as Query/Headers; `HTTPParam.value` stores the raw JSON fragment (e.g. `"\"hello\""`, `"42"`, `"true"`, `"{...}"`); editing a row value replaces that fragment and rebuilds `rawBody` as a JSON object

### File structure changes

| File | Change |
|---|---|
| `Models/HTTPParam.swift` | New |
| `Models/CurlBreakdown.swift` | New |
| `Core/CurlBuilder.swift` | New |
| `Core/CurlParser.swift` | Add `parseBreakdown` |
| `ScanViewModel.swift` | Add `curlBreakdown`, `lastBuiltCurl`, Combine pipelines |
| `ScannerSidebarView.swift` | Add `CurlBreakdownView`, results search bar, saved section |
| `ConfigPanelView.swift` | No change |
| `ScanResultsView.swift` | `.textSelection` additions |
| `Shared/JSONColorView.swift` | `.textSelection` on `JLineView` |
| `Core/SavedRequestsStore.swift` | New |
| `Models/SavedRequest.swift` | New |
| `HTTPScanner/ScannerToolbarItems.swift` or `ToolbarView.swift` | Bookmark button |

---

## Out of scope

- Sync saved requests to iCloud or remote
- Import/export saved requests as files
- Grouping or tagging saved requests
- Multi-line body param values (only top-level JSON key-value pairs are split)
