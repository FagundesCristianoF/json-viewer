//! jsonview-ffi: C ABI bridge for Swift/SwiftUI integration.
//!
//! All strings cross the boundary as null-terminated UTF-8 C strings.
//! Callers MUST free heap strings with `jv_string_free()`.
//! ParseOutput pointers MUST be freed with `jv_parse_free()`.

use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

use jsonview_core::{
    compose as jcompose,
    folding,
    git as jgit,
    model::{Arena, Kind},
    parser,
    path as jpath,
    smells,
    template,
    workspace,
};

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Convert a raw C string pointer to a Rust &str, returning None on null/invalid UTF-8.
unsafe fn cstr_to_str<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok()
}

/// Box a String as a heap-allocated C string. Returns null on interior NUL bytes.
fn string_to_cptr(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Serialize a value to JSON and return as a heap C string.
fn json_to_cptr<T: serde::Serialize>(val: &T) -> *mut c_char {
    match serde_json::to_string(val) {
        Ok(s) => string_to_cptr(s),
        Err(_) => std::ptr::null_mut(),
    }
}

// ---------------------------------------------------------------------------
// ParseOutput opaque type
// ---------------------------------------------------------------------------

pub struct ParseOutput {
    /// Successfully parsed arena, or None on error.
    arena: Option<Arena>,
    /// Original source text (needed for smells' duplicate-key scan).
    source: String,
    /// Error details when arena is None.
    error_msg: Option<CString>,
    error_line: u32,
    error_col: u32,
}

// ---------------------------------------------------------------------------
// Parse API
// ---------------------------------------------------------------------------

/// Parse `text` into a ParseOutput. Always returns a non-null pointer.
/// Free with `jv_parse_free`.
#[no_mangle]
pub extern "C" fn jv_parse(text: *const c_char) -> *mut ParseOutput {
    let src = unsafe {
        match cstr_to_str(text) {
            Some(s) => s.to_owned(),
            None => {
                let out = Box::new(ParseOutput {
                    arena: None,
                    source: String::new(),
                    error_msg: CString::new("null input").ok(),
                    error_line: 0,
                    error_col: 0,
                });
                return Box::into_raw(out);
            }
        }
    };

    let out = match parser::parse(&src) {
        Ok(arena) => ParseOutput {
            arena: Some(arena),
            source: src,
            error_msg: None,
            error_line: 0,
            error_col: 0,
        },
        Err(e) => ParseOutput {
            arena: None,
            source: src,
            error_msg: CString::new(e.message).ok(),
            error_line: e.line as u32,
            error_col: e.col as u32,
        },
    };
    Box::into_raw(Box::new(out))
}

/// Free a ParseOutput previously returned by `jv_parse`.
#[no_mangle]
pub extern "C" fn jv_parse_free(p: *mut ParseOutput) {
    if !p.is_null() {
        unsafe { drop(Box::from_raw(p)) };
    }
}

/// Returns true if parsing failed.
#[no_mangle]
pub extern "C" fn jv_parse_has_error(p: *const ParseOutput) -> bool {
    if p.is_null() {
        return true;
    }
    unsafe { (*p).arena.is_none() }
}

/// Returns the error message C string, or null if no error.
/// The returned pointer is valid until `jv_parse_free` is called.
#[no_mangle]
pub extern "C" fn jv_parse_error_msg(p: *const ParseOutput) -> *const c_char {
    if p.is_null() {
        return std::ptr::null();
    }
    unsafe {
        (*p).error_msg
            .as_ref()
            .map(|cs| cs.as_ptr())
            .unwrap_or(std::ptr::null())
    }
}

/// Returns the 1-based line number of a parse error, or 0 if none.
#[no_mangle]
pub extern "C" fn jv_parse_error_line(p: *const ParseOutput) -> u32 {
    if p.is_null() {
        return 0;
    }
    unsafe { (*p).error_line }
}

/// Returns the 1-based column number of a parse error, or 0 if none.
#[no_mangle]
pub extern "C" fn jv_parse_error_col(p: *const ParseOutput) -> u32 {
    if p.is_null() {
        return 0;
    }
    unsafe { (*p).error_col }
}

/// Returns the total node count in the arena, or 0 on error.
#[no_mangle]
pub extern "C" fn jv_parse_node_count(p: *const ParseOutput) -> usize {
    if p.is_null() {
        return 0;
    }
    unsafe {
        (*p).arena
            .as_ref()
            .map(|a| a.nodes.len())
            .unwrap_or(0)
    }
}

// ---------------------------------------------------------------------------
// Tree JSON serialisation
// ---------------------------------------------------------------------------

fn kind_str(k: Kind) -> &'static str {
    match k {
        Kind::Object => "object",
        Kind::Array => "array",
        Kind::String => "string",
        Kind::Number => "number",
        Kind::Bool => "bool",
        Kind::Null => "null",
    }
}

/// Returns a JSON array of node objects:
/// `[{"id":0,"key":"name","value":"Alice","kind":"string","path":"$.name","depth":1,"parent":null,"children":[]}]`
/// Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_tree_json(p: *const ParseOutput) -> *mut c_char {
    if p.is_null() {
        return std::ptr::null_mut();
    }
    let arena = unsafe {
        match (*p).arena.as_ref() {
            Some(a) => a,
            None => return std::ptr::null_mut(),
        }
    };

    let parents = arena.parents();
    let nodes: Vec<serde_json::Value> = arena
        .nodes
        .iter()
        .enumerate()
        .map(|(id, n)| {
            let children: Vec<usize> = n.children.clone().collect();
            let parent_val = if id == arena.root {
                serde_json::Value::Null
            } else {
                serde_json::json!(parents[id])
            };
            serde_json::json!({
                "id": id,
                "key": n.key,
                "value": n.value,
                "kind": kind_str(n.kind),
                "path": n.path,
                "depth": n.depth,
                "parent": parent_val,
                "children": children,
            })
        })
        .collect();

    json_to_cptr(&nodes)
}

/// Free a C string previously returned by any `jv_*` function.
#[no_mangle]
pub extern "C" fn jv_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

// ---------------------------------------------------------------------------
// Transforms
// ---------------------------------------------------------------------------

/// Pretty-print `text` with `indent` spaces. Returns null on parse error.
/// Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_format(text: *const c_char, indent: u32) -> *mut c_char {
    let src = unsafe { cstr_to_str(text) };
    match src {
        None => std::ptr::null_mut(),
        Some(s) => parser::format(s, indent as usize)
            .ok()
            .map(string_to_cptr)
            .unwrap_or(std::ptr::null_mut()),
    }
}

/// Minify `text`. Returns null on parse error.
/// Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_minify(text: *const c_char) -> *mut c_char {
    let src = unsafe { cstr_to_str(text) };
    match src {
        None => std::ptr::null_mut(),
        Some(s) => parser::minify(s)
            .ok()
            .map(string_to_cptr)
            .unwrap_or(std::ptr::null_mut()),
    }
}

/// Strip null values and re-format with `indent` spaces. Returns null on error.
/// Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_remove_nulls(text: *const c_char, indent: u32) -> *mut c_char {
    let src = unsafe { cstr_to_str(text) };
    match src {
        None => std::ptr::null_mut(),
        Some(s) => parser::remove_nulls(s, indent as usize)
            .ok()
            .map(string_to_cptr)
            .unwrap_or(std::ptr::null_mut()),
    }
}

// ---------------------------------------------------------------------------
// JSONPath
// ---------------------------------------------------------------------------

/// Evaluate `query` against the parsed arena. Returns a JSON array of matching
/// node IDs: `[3, 7, 12]`. Returns null on error.
/// Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_jsonpath(p: *const ParseOutput, query: *const c_char) -> *mut c_char {
    if p.is_null() {
        return std::ptr::null_mut();
    }
    let arena = unsafe {
        match (*p).arena.as_ref() {
            Some(a) => a,
            None => return std::ptr::null_mut(),
        }
    };
    let expr = unsafe { cstr_to_str(query) };
    match expr {
        None => std::ptr::null_mut(),
        Some(e) => jpath::query(arena, e)
            .ok()
            .map(|ids| json_to_cptr(&ids))
            .unwrap_or(std::ptr::null_mut()),
    }
}

// ---------------------------------------------------------------------------
// Smells
// ---------------------------------------------------------------------------

/// Scan for data smells. Returns a JSON array:
/// `[{"path":"$.a","message":"null value"}]`
/// Returns null on invalid ParseOutput. Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_smells(p: *const ParseOutput) -> *mut c_char {
    if p.is_null() {
        return std::ptr::null_mut();
    }
    let (arena, source) = unsafe {
        match (*p).arena.as_ref() {
            Some(a) => (a, &(*p).source as &str),
            None => return std::ptr::null_mut(),
        }
    };
    let findings = smells::scan(arena, source);
    let arr: Vec<serde_json::Value> = findings
        .iter()
        .map(|s| {
            serde_json::json!({
                "path": s.path,
                "message": s.message,
            })
        })
        .collect();
    json_to_cptr(&arr)
}

// ---------------------------------------------------------------------------
// Workspace
// ---------------------------------------------------------------------------

fn collect_paths(entry: &workspace::Entry, base: &Path, out: &mut Vec<String>) {
    if !entry.is_dir {
        if let Ok(rel) = entry.path.strip_prefix(base) {
            out.push(rel.to_string_lossy().into_owned());
        }
    }
    for child in &entry.children {
        collect_paths(child, base, out);
    }
}

/// List JSON files in `dir` (relative paths). Returns a JSON array of strings.
/// Returns null on error. Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_workspace_files(dir: *const c_char) -> *mut c_char {
    let dir_str = unsafe { cstr_to_str(dir) };
    match dir_str {
        None => std::ptr::null_mut(),
        Some(d) => {
            let root = Path::new(d);
            match workspace::read_tree(root) {
                Ok(tree) => {
                    let mut paths: Vec<String> = Vec::new();
                    collect_paths(&tree, root, &mut paths);
                    json_to_cptr(&paths)
                }
                Err(_) => std::ptr::null_mut(),
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Git history
// ---------------------------------------------------------------------------

/// Return up to `max_entries` git log entries for `path` (absolute file path).
/// The parent directory is used as the workspace root.
/// Returns a JSON array: `[{"hash":"abc","message":"fix","timestamp":1234567890,"relative":"2 min ago"}]`
/// Returns null on error. Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_git_history(path: *const c_char, max_entries: u32) -> *mut c_char {
    let path_str = unsafe { cstr_to_str(path) };
    match path_str {
        None => std::ptr::null_mut(),
        Some(p) => {
            let file_path = Path::new(p);
            let workspace_dir = file_path.parent().unwrap_or(file_path);
            match jgit::log(workspace_dir, file_path, max_entries as usize) {
                Ok(entries) => {
                    let arr: Vec<serde_json::Value> = entries
                        .iter()
                        .map(|c| {
                            serde_json::json!({
                                "hash": c.hash,
                                "message": c.message,
                                "timestamp": c.timestamp,
                                "relative": c.relative,
                            })
                        })
                        .collect();
                    json_to_cptr(&arr)
                }
                Err(_) => std::ptr::null_mut(),
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Compose / Template
// ---------------------------------------------------------------------------

/// Resolve `{{filename.json}}` placeholders in `text` relative to `dir` and
/// return formatted JSON with `indent` spaces. Returns null on error.
/// Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_compose(
    text: *const c_char,
    dir: *const c_char,
    indent: u32,
) -> *mut c_char {
    let src = unsafe { cstr_to_str(text) };
    let dir_str = unsafe { cstr_to_str(dir) };
    match (src, dir_str) {
        (Some(s), Some(d)) => jcompose::compose(s, Path::new(d), indent as usize)
            .ok()
            .map(string_to_cptr)
            .unwrap_or(std::ptr::null_mut()),
        _ => std::ptr::null_mut(),
    }
}

/// Extract `{{varName}}` variable names from a template (excludes file tokens).
/// Returns a JSON array of strings. Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_template_vars(text: *const c_char) -> *mut c_char {
    let src = unsafe { cstr_to_str(text) };
    match src {
        None => std::ptr::null_mut(),
        Some(s) => json_to_cptr(&template::find_variables(s)),
    }
}

/// Substitute `{{varName}}` tokens in `text` using the JSON object `vars_json`
/// (`{"varName": "value"}`). Returns the rendered string or null on error.
/// Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_render_vars(
    text: *const c_char,
    vars_json: *const c_char,
) -> *mut c_char {
    let src = unsafe { cstr_to_str(text) };
    let vars_str = unsafe { cstr_to_str(vars_json) };
    match (src, vars_str) {
        (Some(s), Some(v)) => {
            let map: serde_json::Map<String, serde_json::Value> =
                match serde_json::from_str(v) {
                    Ok(m) => m,
                    Err(_) => return std::ptr::null_mut(),
                };
            let vars: HashMap<String, String> = map
                .into_iter()
                .map(|(k, val)| {
                    let s = match &val {
                        serde_json::Value::String(s) => s.clone(),
                        other => other.to_string(),
                    };
                    (k, s)
                })
                .collect();
            template::render_vars(s, &vars)
                .ok()
                .map(string_to_cptr)
                .unwrap_or(std::ptr::null_mut())
        }
        _ => std::ptr::null_mut(),
    }
}

// ---------------------------------------------------------------------------
// Folding
// ---------------------------------------------------------------------------

/// Scan `text` for foldable brace/bracket ranges. Returns a JSON array:
/// `[{"start":0,"end":5}]` (0-based line numbers).
/// Caller must free with `jv_string_free`.
#[no_mangle]
pub extern "C" fn jv_fold_ranges(text: *const c_char) -> *mut c_char {
    let src = unsafe { cstr_to_str(text) };
    match src {
        None => std::ptr::null_mut(),
        Some(s) => {
            let ranges = folding::scan_fold_ranges(s);
            let arr: Vec<serde_json::Value> = ranges
                .iter()
                .map(|r| {
                    serde_json::json!({
                        "start": r.start_line,
                        "end": r.end_line,
                    })
                })
                .collect();
            json_to_cptr(&arr)
        }
    }
}
