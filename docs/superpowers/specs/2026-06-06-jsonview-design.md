# jsonview — Design Spec

**Date:** 2026-06-06
**Status:** Approved for planning
**Platform:** macOS (native)
**Stack:** Rust + egui (eframe)

## Goal

A fast, native macOS JSON workspace app. Organize JSON files in a folder
tree (Insomnia-style), view them as a parsed tree, query with JSONPath,
beautify/minify, and surface issues (syntax errors + data smells).

## Non-Goals (v1)

- JSON Schema validation (deferred to a later version)
- Web/cross-platform builds
- Editing the JSON via the tree view (editing is text-only in the editor pane)
- Live filesystem watching (refresh on selection + manual refresh button)

## Design Drivers

"Really fast" means three concrete things:

1. **Big files** — open/parse 100MB+ JSON without lag.
2. **Instant UI** — zero-latency typing, scrolling, live JSONPath results.
3. **Fast launch** — static release binary, sub-100ms cold start.

## Storage Model

- User picks a **workspace directory**. The sidebar mirrors it 1:1.
- Folders = real directories. JSON documents = real `.json` files.
- Unlimited nesting.
- All sidebar operations mutate the real filesystem (transparent to Finder/git).
- Last-opened workspace path persisted in
  `~/Library/Application Support/jsonview/config.json`.

## Layout

```
┌────────────┬───────────────────┬──────────────┐
│ Sidebar    │ Editor            │ Tree         │
│ ▾ FolderA  │ (selected .json)  │ (parsed,     │
│   doc1     │  editable, mono   │  virtualized,│
│   ▾ Sub    │                   │  matches hl) │
│     doc2   ├───────────────────┴──────────────┤
│ + folder   │ JSONPath:[ $.x ] (◉hl ○filter)   │
│ + json     │ Issues [Syntax 1] [Smells 3]     │
└────────────┴──────────────────────────────────┘
```

Toolbar: `[Open ws] [Format] [Minify] | JSONPath:[ … ] (◉hl ○filter) (N hits)`

## Features

### Workspace sidebar
- Mirror workspace dir as a tree (folders + `.json` files).
- Operations: new folder, new json, rename, delete, move (drag).
- Right-click context menu + toolbar buttons.
- Manual refresh button (re-read tree from disk).

### Editor pane
- Monospace editable text of the selected file.
- Live re-parse on change.
- Save with Cmd+S → writes editor content to selected file.

### Tree pane
- Parsed JSON shown as a collapsible tree.
- Virtualized rendering (only visible rows drawn).
- Type badges per node (object/array/string/number/bool/null).
- JSONPath matches highlighted; click a node → copy its path.

### JSONPath
- Subset engine: `$.a.b`, `[0]`, `[*]`, `..` (recursive descent),
  basic filter `[?(@.x == ...)]`.
- Two modes: **highlight** (mark matches) and **filter** (show only
  matching subtree). Toggle in toolbar. Live hit count.

### Beautify / Minify
- Format: pretty-print with configurable indent → editor.
- Minify: compact single-line → editor.

### Issues
- **Syntax**: invalid JSON → message + line/col, click to jump.
- **Smells**: null values, empty array/object, type-inconsistent arrays
  (items of differing kinds), duplicate keys.
- Tabbed panel with count badges.

## Architecture

Each module is a single file with one clear responsibility and unit tests
for pure logic.

| Module          | Responsibility                                              | Depends on      |
|-----------------|-------------------------------------------------------------|-----------------|
| `workspace.rs`  | Filesystem tree model + CRUD (folder/json create/rename/delete/move) | std::fs |
| `model.rs`      | Flat node arena: `Node { key, kind, span, children: Range }` | —              |
| `parser.rs`     | serde_json wrap → arena; syntax error → line/col            | serde_json      |
| `path.rs`       | JSONPath subset → matching node indices                     | model           |
| `smells.rs`     | Smell rules → issue list                                    | model           |
| `config.rs`     | Load/save last workspace path                               | std::fs, serde  |
| `app.rs`        | egui state + update loop, wires modules to UI               | all             |
| `ui/sidebar.rs` | Render workspace tree + ops                                 | workspace, app  |
| `ui/editor.rs`  | Editable text pane + save                                   | app             |
| `ui/tree.rs`    | Virtualized parsed-tree view + highlight                    | model, app      |
| `ui/issues.rs`  | Tabbed issues panel                                         | parser, smells  |

### Data model

`model.rs` uses a flat arena for cache-friendly, recursion-free rendering:

```
enum Kind { Object, Array, String, Number, Bool, Null }
struct Node {
    key: Option<String>,   // key if child of object
    kind: Kind,
    value: Option<String>, // scalar text for leaves
    children: Range<usize>, // indices into arena for container children
    path: String,          // precomputed JSONPath to this node
}
struct Arena { nodes: Vec<Node>, root: usize }
```

Tree view flattens currently-expanded nodes into a visible-row list each
frame; egui `show_rows` draws only the on-screen slice.

## Data Flow

1. Select file in sidebar → read from disk → `parser` → `Arena`.
2. `Arena` → tree render + `smells` scan → Issues panel.
3. JSONPath input → `path` engine → set of matching node indices →
   highlight or filter the tree.
4. Editor change → re-parse (debounced) → refresh arena/issues.
5. Cmd+S → write editor text to selected file.

## Performance Notes

- Parse: `serde_json` first (≈1s/100MB). Swap to `simd-json` if profiling
  demands it — isolated behind `parser.rs`.
- Arena uses indices, not pointers → no deep recursion, cache friendly.
- Tree render virtualized → constant cost regardless of document size.
- Debounce re-parse on editor keystrokes to keep typing instant.
- Release build, LTO on, stripped binary for fast launch.

## Error Handling

- Parse errors → surfaced in Issues (Syntax tab), never panic.
- Filesystem errors (rename/delete/move) → non-blocking toast/banner.
- Invalid JSONPath expression → inline error next to the input, no crash.

## Testing

- Unit tests for pure logic: `parser`, `path`, `smells`, `workspace` CRUD,
  `config`.
- UI verified manually.

## Dependencies

- `eframe` / `egui` — GUI
- `serde_json`, `serde` — parse + config
- `directories` — locate config dir
- (later, optional) `simd-json` — faster large-file parsing
