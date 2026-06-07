import Foundation

// MARK: - ParseHandle

/// Wraps the opaque JvParseOutput* handle and its derived data.
struct ParseHandle {
    /// Node count from the arena (0 on error).
    let nodeCount: Int
    /// Parse error info, nil when parse succeeded.
    let error: ParseErrorInfo?
    /// Decoded tree nodes, empty on error.
    let nodes: [NodeInfo]

    /// Opaque pointer — kept alive for path/smells queries.
    fileprivate let ptr: OpaquePointer

    fileprivate init(ptr: OpaquePointer) {
        self.ptr = ptr
        let hasError = jv_parse_has_error(ptr)
        if hasError {
            let msg = jv_parse_error_msg(ptr).map { String(cString: $0) } ?? "Unknown parse error"
            let line = Int(jv_parse_error_line(ptr))
            let col  = Int(jv_parse_error_col(ptr))
            self.error = ParseErrorInfo(message: msg, line: line, col: col)
            self.nodeCount = 0
            self.nodes = []
        } else {
            self.error = nil
            self.nodeCount = Int(jv_parse_node_count(ptr))
            if let raw = jv_tree_json(ptr) {
                let json = String(cString: raw)
                jv_string_free(raw)
                self.nodes = (try? JSONDecoder().decode([NodeInfo].self, from: Data(json.utf8))) ?? []
            } else {
                self.nodes = []
            }
        }
    }

    func free() {
        jv_parse_free(ptr)
    }
}

// MARK: - RustBridge

enum RustBridge {

    // MARK: Parse

    /// Parse text, returning a handle. Caller must call handle.free() when done.
    static func parseHandle(_ text: String) -> ParseHandle {
        let ptr = text.withCString { jv_parse($0)! }
        return ParseHandle(ptr: ptr)
    }

    // MARK: Transforms

    static func format(_ text: String, indent: Int = 2) -> String? {
        text.withCString { cText -> String? in
            guard let raw = jv_format(cText, UInt32(indent)) else { return nil }
            defer { jv_string_free(raw) }
            return String(cString: raw)
        }
    }

    static func minify(_ text: String) -> String? {
        text.withCString { cText -> String? in
            guard let raw = jv_minify(cText) else { return nil }
            defer { jv_string_free(raw) }
            return String(cString: raw)
        }
    }

    static func removeNulls(_ text: String, indent: Int = 2) -> String? {
        text.withCString { cText -> String? in
            guard let raw = jv_remove_nulls(cText, UInt32(indent)) else { return nil }
            defer { jv_string_free(raw) }
            return String(cString: raw)
        }
    }

    // MARK: JSONPath

    /// Evaluate a JSONPath query against an already-parsed handle.
    static func jsonPath(_ handle: ParseHandle, query: String) -> [Int] {
        query.withCString { cQuery -> [Int] in
            guard let raw = jv_jsonpath(handle.ptr, cQuery) else { return [] }
            defer { jv_string_free(raw) }
            let json = String(cString: raw)
            return (try? JSONDecoder().decode([Int].self, from: Data(json.utf8))) ?? []
        }
    }

    // MARK: Smells

    static func smells(_ handle: ParseHandle) -> [SmellInfo] {
        guard let raw = jv_smells(handle.ptr) else { return [] }
        defer { jv_string_free(raw) }
        let json = String(cString: raw)
        return (try? JSONDecoder().decode([SmellInfo].self, from: Data(json.utf8))) ?? []
    }

    // MARK: Workspace

    static func workspaceFiles(_ dir: String) -> [String] {
        dir.withCString { cDir -> [String] in
            guard let raw = jv_workspace_files(cDir) else { return [] }
            defer { jv_string_free(raw) }
            let json = String(cString: raw)
            return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        }
    }

    // MARK: Git History

    static func gitHistory(_ path: String, maxEntries: Int = 50) -> [CommitInfo] {
        path.withCString { cPath -> [CommitInfo] in
            guard let raw = jv_git_history(cPath, UInt32(maxEntries)) else { return [] }
            defer { jv_string_free(raw) }
            let json = String(cString: raw)
            return (try? JSONDecoder().decode([CommitInfo].self, from: Data(json.utf8))) ?? []
        }
    }

    // MARK: Compose / Template

    static func compose(_ text: String, dir: String, indent: Int = 2) -> String? {
        text.withCString { cText -> String? in
            dir.withCString { cDir -> String? in
                guard let raw = jv_compose(cText, cDir, UInt32(indent)) else { return nil }
                defer { jv_string_free(raw) }
                return String(cString: raw)
            }
        }
    }

    static func templateVars(_ text: String) -> [String] {
        text.withCString { cText -> [String] in
            guard let raw = jv_template_vars(cText) else { return [] }
            defer { jv_string_free(raw) }
            let json = String(cString: raw)
            return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        }
    }

    static func renderVars(_ text: String, vars: [String: String]) -> String? {
        guard let varsData = try? JSONEncoder().encode(vars),
              let varsJson = String(data: varsData, encoding: .utf8) else { return nil }
        return text.withCString { cText -> String? in
            varsJson.withCString { cVars -> String? in
                guard let raw = jv_render_vars(cText, cVars) else { return nil }
                defer { jv_string_free(raw) }
                return String(cString: raw)
            }
        }
    }

    // MARK: Folding

    static func foldRanges(_ text: String) -> [FoldRange] {
        text.withCString { cText -> [FoldRange] in
            guard let raw = jv_fold_ranges(cText) else { return [] }
            defer { jv_string_free(raw) }
            let json = String(cString: raw)
            return (try? JSONDecoder().decode([FoldRange].self, from: Data(json.utf8))) ?? []
        }
    }
}
