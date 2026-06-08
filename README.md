# DevKit

A native macOS developer toolkit for working with JSON and HTTP APIs. Built with SwiftUI and a Rust core for performance.

![macOS](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift)
![Rust](https://img.shields.io/badge/Rust-1.75%2B-000000?logo=rust)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## Features

### JSON Editor

- **Syntax-aware editor** with line numbers, folding, and gutter controls
- **Parse errors** highlighted inline with line and column
- **Pretty-print / Minify / Remove nulls** transforms
- **Auto-save** on every change (optional)
- **Fold/unfold** individual objects and arrays from the gutter

### JSON Tree View

- Hierarchical node browser alongside the editor
- Color-coded type badges (object, array, string, number, bool, null)
- Click any node to jump to its position in the editor

### JSONPath

- Query the parsed document with JSONPath expressions (`$.store.book[*].author`)
- Matching nodes highlighted in the tree view and editor

### Compose

- Template system: embed `{{filename.json}}` placeholders in a JSON file
- Resolves references relative to the open workspace folder
- Variable substitution: `{{varName}}` tokens filled from a key-value map
- Toggle between raw template view and resolved result

### Data Smells

- Automatic scan for common data quality issues:
  - Null values
  - Empty strings and arrays
  - Duplicate keys
  - Deeply nested structures
- All findings listed in the Issues panel with clickable navigation

### Issues Panel

- **Syntax** tab — parse errors with location
- **Smells** tab — data quality findings
- **History** tab — git log for the open file
- **Keys** tab — flat list of all keys in the document

### HTTP Scanner

- Send GET, POST, PUT, PATCH, DELETE requests
- Configure headers, query parameters, and request body
- Response viewer with syntax highlighting
- Request history with status codes and timing
- Export requests as cURL commands

### Workspace

- Open any folder as a workspace
- File tree in the sidebar filtered to `.json` files
- Workspace root persists across launches

### Git Integration

- Per-file commit history in the Issues panel
- Timestamps shown as relative human-readable strings

### Preferences

- Light / Dark / System theme
- Configurable indent size (2 or 4 spaces)
- Auto-save toggle
- Custom history directory for HTTP Scanner

---

## Installation

### Homebrew (recommended)

```bash
brew install --cask devkit
```

### Manual

Download the latest DMG from [Releases](https://github.com/FagundesCristianoF/json-viewer/releases), open it, and drag **DevKit.app** to `/Applications`.

---

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac

---

## Architecture

DevKit is split into three layers:

```
JsonViewApp/          ← SwiftUI macOS app
  Sources/
    JSONEditor/       ← Editor, tree, toolbar, issues panel
    HTTPScanner/      ← HTTP request UI and history
    Core/             ← AppModel, Preferences, Settings
    Shared/           ← Reusable UI components

jsonview-core/        ← Rust library (pure logic, no FFI)
  src/
    parser.rs         ← JSON parser → Arena model
    model.rs          ← Node/Arena types
    path.rs           ← JSONPath evaluator
    smells.rs         ← Data smell scanner
    compose.rs        ← Template / file composition
    template.rs       ← Variable substitution
    folding.rs        ← Fold range scanner
    git.rs            ← Git log reader
    workspace.rs      ← Directory tree walker

jsonview-ffi/         ← C ABI bridge (Rust → Swift)
  src/lib.rs          ← #[no_mangle] extern "C" functions
```

Swift calls into Rust via `RustBridge.swift`, which wraps the C ABI exposed by `jsonview-ffi`. All strings cross the boundary as null-terminated UTF-8; heap strings are freed with `jv_string_free`.

---

## Building from Source

### Prerequisites

- Xcode 16+
- Rust 1.75+ (`rustup install stable`)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Steps

```bash
git clone https://github.com/FagundesCristianoF/json-viewer.git
cd json-viewer

# Build the Rust FFI library
cargo build --release -p jsonview-ffi

# Generate the Xcode project
cd JsonViewApp
xcodegen generate

# Open in Xcode
open DevKit.xcodeproj
```

> The Xcode project links against `target/release/libjsonview_ffi.a`. If you move the repo, update `OTHER_LDFLAGS` in `project.yml` accordingly.

---

## Publishing a Release

Requires `secrets.yml` (gitignored) with:

```yaml
APPLE_ID: you@example.com
APPLE_APP_PASSWORD: xxxx-xxxx-xxxx-xxxx
APPLE_TEAM_ID: XXXXXXXXXX
APPLE_IDENTITY: "Developer ID Application: Your Name (TEAMID)"
```

Then run:

```bash
bash scripts/publish.sh 0.2.0
```

This will:
1. Build the Rust FFI in release mode
2. Build `DevKit.app` with Xcode (Release configuration)
3. Notarize with Apple
4. Staple the notarization ticket
5. Package as a DMG
6. Create a GitHub release and upload the DMG
7. Update `homebrew/devkit.rb` with the new version and sha256

---

## Contributing

Contributions are welcome. Please open an issue before starting significant work.

### Project setup

Follow the **Building from Source** steps above.

### Where things live

| What | Where |
|------|-------|
| SwiftUI views | `JsonViewApp/JsonViewApp/Sources/` |
| Rust logic | `jsonview-core/src/` |
| FFI bridge | `jsonview-ffi/src/lib.rs` |
| Xcode project spec | `JsonViewApp/project.yml` |
| App icon generator | `gen_icon.py` |
| Homebrew cask | `homebrew/devkit.rb` |
| Publish script | `scripts/publish.sh` |

### Workflow

1. Fork the repository
2. Create a branch: `git checkout -b feat/your-feature`
3. Make changes and add tests where applicable
4. Run tests: `cargo test` (Rust) and Xcode Test Navigator (Swift)
5. Open a pull request against `master`

### Rust core changes

After editing `jsonview-core` or `jsonview-ffi`, rebuild before running the app:

```bash
cargo build --release -p jsonview-ffi
```

### Adding an FFI function

1. Implement logic in `jsonview-core/src/`
2. Expose via `#[no_mangle] pub extern "C" fn jv_*` in `jsonview-ffi/src/lib.rs`
3. Wrap in `JsonViewApp/JsonViewApp/Sources/RustBridge.swift`

### Code style

- Swift: follow existing SwiftUI patterns, use `JVColor` tokens from `Theme.swift`
- Rust: `cargo fmt` and `cargo clippy` before committing
- No force-unwraps in Swift without a comment explaining why

---

## License

MIT — see [LICENSE](LICENSE).
