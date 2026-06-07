#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Opaque handle for a parsed JSON document (arena + error info).
// Always freed with jv_parse_free().
// ---------------------------------------------------------------------------
typedef struct JvParseOutput JvParseOutput;

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

/// Parse `text` (null-terminated UTF-8). Always returns a non-null handle.
/// Check jv_parse_has_error() before using tree/path APIs.
JvParseOutput *jv_parse(const char *text);

/// Free a handle returned by jv_parse().
void jv_parse_free(JvParseOutput *p);

/// Returns true if parsing failed.
bool jv_parse_has_error(const JvParseOutput *p);

/// Returns the parse error message, or NULL if no error.
/// Pointer is valid until jv_parse_free() is called — do NOT free it.
const char *jv_parse_error_msg(const JvParseOutput *p);

/// Returns the 1-based line number of a parse error, or 0 if none.
uint32_t jv_parse_error_line(const JvParseOutput *p);

/// Returns the 1-based column number of a parse error, or 0 if none.
uint32_t jv_parse_error_col(const JvParseOutput *p);

/// Returns the total number of nodes in the arena, or 0 on error.
size_t jv_parse_node_count(const JvParseOutput *p);

// ---------------------------------------------------------------------------
// Tree
// ---------------------------------------------------------------------------

/// Returns a heap-allocated JSON array of node objects:
///   [{"id":0,"key":"name","value":"Alice","kind":"string",
///     "path":"$.name","depth":1,"parent":null,"children":[1,2]}]
/// Caller MUST free with jv_string_free().
/// Returns NULL on error.
char *jv_tree_json(const JvParseOutput *p);

/// Free any heap string returned by a jv_* function.
void jv_string_free(char *s);

// ---------------------------------------------------------------------------
// Transforms — all return heap strings; caller frees with jv_string_free().
// Returns NULL on parse error.
// ---------------------------------------------------------------------------

/// Pretty-print `text` with `indent` spaces.
char *jv_format(const char *text, uint32_t indent);

/// Compact single-line form.
char *jv_minify(const char *text);

/// Remove all null values (object keys and array elements) and re-format.
char *jv_remove_nulls(const char *text, uint32_t indent);

// ---------------------------------------------------------------------------
// JSONPath
// ---------------------------------------------------------------------------

/// Evaluate JSONPath `query` against a parsed document.
/// Returns a JSON array of matching node IDs: [3, 7, 12]
/// Returns NULL on error. Caller frees with jv_string_free().
char *jv_jsonpath(const JvParseOutput *p, const char *query);

// ---------------------------------------------------------------------------
// Smells (data quality warnings)
// ---------------------------------------------------------------------------

/// Scan for data smells (nulls, empty containers, mixed arrays, duplicate keys).
/// Returns a JSON array: [{"path":"$.a","message":"null value"}]
/// Returns NULL on invalid input. Caller frees with jv_string_free().
char *jv_smells(const JvParseOutput *p);

// ---------------------------------------------------------------------------
// Workspace
// ---------------------------------------------------------------------------

/// List all JSON files under `dir` as relative path strings.
/// Returns a JSON array: ["a.json","sub/b.json"]
/// Returns NULL on error. Caller frees with jv_string_free().
char *jv_workspace_files(const char *dir);

// ---------------------------------------------------------------------------
// Git history
// ---------------------------------------------------------------------------

/// Return up to `max_entries` git log entries for the given absolute file path.
/// The file's parent directory is used as the workspace root.
/// Returns a JSON array:
///   [{"hash":"abc1234","message":"fix typo","timestamp":1712345678,"relative":"2 min ago"}]
/// Returns NULL on error. Caller frees with jv_string_free().
char *jv_git_history(const char *path, uint32_t max_entries);

// ---------------------------------------------------------------------------
// Compose / Template
// ---------------------------------------------------------------------------

/// Resolve {{filename.json}} placeholders in `text` relative to `dir`.
/// Returns formatted JSON with `indent` spaces, or NULL on error.
/// Caller frees with jv_string_free().
char *jv_compose(const char *text, const char *dir, uint32_t indent);

/// Extract {{varName}} variable names from a template (excludes file tokens).
/// Returns a JSON array of strings: ["productName","version"]
/// Caller frees with jv_string_free().
char *jv_template_vars(const char *text);

/// Substitute {{varName}} tokens using a JSON object vars_json: {"varName":"value"}.
/// Returns the rendered string, or NULL on error.
/// Caller frees with jv_string_free().
char *jv_render_vars(const char *text, const char *vars_json);

// ---------------------------------------------------------------------------
// Folding
// ---------------------------------------------------------------------------

/// Scan `text` for foldable brace/bracket ranges.
/// Returns a JSON array: [{"start":0,"end":5}] (0-based line numbers).
/// Caller frees with jv_string_free().
char *jv_fold_ranges(const char *text);

#ifdef __cplusplus
} // extern "C"
#endif
