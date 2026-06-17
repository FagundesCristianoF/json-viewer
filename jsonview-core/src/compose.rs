//! JSON Compose: resolve `{{filename.json}}` placeholders in a template.
//!
//! A template is any JSON (or JSON-like) text containing `{{path.json}}`
//! tokens. Each token is replaced with the parsed content of that file,
//! resolved relative to a base directory. The result is valid, formatted JSON.
//!
//! ## Basic include
//!   { "products": [ {{productA.json}}, {{productB.json}} ] }
//!
//! ## Include with arguments
//!   { "people": [ {{person.json, id: "X", age: 30}} ] }
//!
//!   person.json:
//!   { "id": {{ @id }}, "age": {{ @age }} }
//!
//! Rules:
//!   - Token format: `{{filename}}` or `{{filename, key: value, ...}}`
//!   - Arg references in included files: `{{ @argName }}`
//!   - Arg values are raw JSON (strings must be quoted: `id: "X"`, numbers: `n: 5`)
//!   - Paths are resolved relative to `base_dir`.
//!   - The referenced file must be valid JSON after arg substitution.
//!   - Circular references are detected and returned as an error.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

/// Resolve all `{{...}}` placeholders in `template`, reading files relative
/// to `base_dir`. Returns the formatted JSON string, or an error.
pub fn compose(template: &str, base_dir: &Path, _indent: usize) -> Result<String, String> {
    let resolved = resolve(template, base_dir, &mut HashSet::new(), &HashMap::new())?;

    // Validate result is well-formed JSON without reformatting,
    // so original spacing and key order from source files are preserved.
    serde_json::from_str::<serde_json::Value>(&resolved)
        .map_err(|e| format!("result is not valid JSON: {e}"))?;

    Ok(resolved)
}

// ---------------------------------------------------------------------------
// Token parsing
// ---------------------------------------------------------------------------

/// Parse a compose token into a filename and optional args map.
///
/// Token formats:
///   `inner.json`
///   `inner.json, id: "X", count: 5`
fn parse_token(token: &str) -> Result<(String, HashMap<String, String>), String> {
    match token.find(',') {
        None => Ok((token.to_string(), HashMap::new())),
        Some(pos) => {
            let filename = token[..pos].trim().to_string();
            let args = parse_args(token[pos + 1..].trim())?;
            Ok((filename, args))
        }
    }
}

/// Parse `key: value, key2: value2` into a map.
/// Values are raw JSON — strings must be quoted, e.g. `id: "X"`.
fn parse_args(s: &str) -> Result<HashMap<String, String>, String> {
    let mut map = HashMap::new();
    let bytes = s.as_bytes();
    let mut i = 0;

    while i < bytes.len() {
        // skip leading whitespace / commas (commas separate pairs)
        while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\n' | b'\r') {
            i += 1;
        }
        if i >= bytes.len() {
            break;
        }

        // read key up to ':'
        let key_start = i;
        while i < bytes.len() && bytes[i] != b':' {
            i += 1;
        }
        if i >= bytes.len() {
            return Err(format!(
                "expected ':' after key near '{}'",
                &s[key_start..]
            ));
        }
        let key = s[key_start..i].trim().to_string();
        i += 1; // skip ':'

        // skip whitespace after ':'
        while i < bytes.len() && bytes[i] == b' ' {
            i += 1;
        }

        // read JSON value — stop at top-level comma (depth == 0)
        let val_start = i;
        let mut depth: i32 = 0;
        let mut in_str = false;
        let mut escape = false;
        while i < bytes.len() {
            let b = bytes[i];
            if escape {
                escape = false;
            } else if in_str {
                if b == b'\\' {
                    escape = true;
                } else if b == b'"' {
                    in_str = false;
                }
            } else {
                match b {
                    b'"' => in_str = true,
                    b'{' | b'[' => depth += 1,
                    b'}' | b']' => {
                        if depth == 0 {
                            break;
                        }
                        depth -= 1;
                    }
                    b',' if depth == 0 => break,
                    _ => {}
                }
            }
            i += 1;
        }
        let value = s[val_start..i].trim().to_string();
        if value.is_empty() {
            return Err(format!("missing value for arg '{key}'"));
        }
        map.insert(key, value);

        // skip comma between pairs
        if i < bytes.len() && bytes[i] == b',' {
            i += 1;
        }
    }
    Ok(map)
}

// ---------------------------------------------------------------------------
// Arg substitution
// ---------------------------------------------------------------------------

/// Replace `{{ @key }}` placeholders with values from `args`.
/// Non-`@` tokens are kept verbatim for the file-include pass.
/// `{{ @key }}` with no matching entry in `args` is left as-is
/// (allows standalone resolution of inner files without errors).
fn substitute_args(template: &str, args: &HashMap<String, String>) -> Result<String, String> {
    if args.is_empty() || !template.contains("{{") {
        return Ok(template.to_string());
    }
    let mut result = String::with_capacity(template.len());
    let bytes = template.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if i + 1 < bytes.len() && bytes[i] == b'{' && bytes[i + 1] == b'{' {
            let start = i + 2;
            let end = template[start..]
                .find("}}")
                .ok_or_else(|| "unclosed '{{' in template".to_string())?;
            let token = template[start..start + end].trim();
            if let Some(key) = token.strip_prefix('@') {
                let key = key.trim();
                match args.get(key) {
                    Some(val) => result.push_str(val),
                    None => {
                        // Unresolved arg — leave token intact so the caller can
                        // display or diagnose it.
                        result.push_str("{{");
                        result.push_str(&template[start..start + end]);
                        result.push_str("}}");
                    }
                }
            } else {
                result.push_str("{{");
                result.push_str(&template[start..start + end]);
                result.push_str("}}");
            }
            i = start + end + 2;
        } else {
            result.push(bytes[i] as char);
            i += 1;
        }
    }
    Ok(result)
}

// ---------------------------------------------------------------------------
// Recursive resolution
// ---------------------------------------------------------------------------

/// Recursively resolve `{{...}}` tokens, tracking `visited` to detect cycles.
/// `parent_args` are the args passed from the parent include site.
fn resolve(
    template: &str,
    base_dir: &Path,
    visited: &mut HashSet<PathBuf>,
    parent_args: &HashMap<String, String>,
) -> Result<String, String> {
    // Apply parent args first (substitutes {{ @key }} references)
    let template = substitute_args(template, parent_args)?;

    let mut result = String::with_capacity(template.len());
    let bytes = template.as_bytes();
    let mut i = 0;

    while i < bytes.len() {
        // Look for opening "{{"
        if i + 1 < bytes.len() && bytes[i] == b'{' && bytes[i + 1] == b'{' {
            // Find closing "}}"
            let start = i + 2;
            let end = template[start..]
                .find("}}")
                .ok_or_else(|| format!("unclosed '{{{{' at position {i}"))?;
            let token = template[start..start + end].trim();
            i = start + end + 2; // skip past "}}"

            // Skip arg references that weren't resolved (inner file standalone mode)
            if token.starts_with('@') {
                result.push_str("{{");
                result.push_str(token);
                result.push_str("}}");
                continue;
            }

            let (filename, args) = parse_token(token)?;
            let path = base_dir.join(&filename);
            let canonical = path
                .canonicalize()
                .map_err(|_| format!("file not found: {}", path.display()))?;

            if visited.contains(&canonical) {
                return Err(format!("circular reference: {}", canonical.display()));
            }
            visited.insert(canonical.clone());

            let content = std::fs::read_to_string(&canonical)
                .map_err(|e| format!("cannot read {}: {e}", canonical.display()))?;

            // Recursively resolve nested templates, passing the current token's args.
            let file_base = canonical.parent().unwrap_or(base_dir);
            let expanded = resolve(&content, file_base, visited, &args)?;
            visited.remove(&canonical);

            result.push_str(&expanded);
        } else {
            result.push(bytes[i] as char);
            i += 1;
        }
    }

    Ok(result)
}

/// Parse `{{...}}` tokens out of a template string — returns a list of
/// referenced filenames (in order, possibly with duplicates).
/// Excludes `{{ @arg }}` references.
pub fn referenced_files(template: &str) -> Vec<String> {
    let mut files = Vec::new();
    let mut rest = template;
    while let Some(start) = rest.find("{{") {
        rest = &rest[start + 2..];
        if let Some(end) = rest.find("}}") {
            let token = rest[..end].trim();
            if !token.starts_with('@') {
                if let Ok((filename, _)) = parse_token(token) {
                    files.push(filename);
                }
            }
            rest = &rest[end + 2..];
        } else {
            break;
        }
    }
    files
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tmpdir(name: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!(
            "jsonview_compose_{}_{}_{}",
            std::process::id(),
            format!("{:?}", std::thread::current().id())
                .chars()
                .filter(|c| c.is_alphanumeric())
                .collect::<String>(),
            name,
        ));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        p
    }

    #[test]
    fn basic_substitution() {
        let dir = tmpdir("basic");
        fs::write(dir.join("a.json"), r#"{"x": 1}"#).unwrap();
        let tmpl = r#"{"items": [{{a.json}}]}"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["items"][0]["x"], serde_json::json!(1));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn multiple_tokens() {
        let dir = tmpdir("multi");
        fs::write(dir.join("a.json"), r#"{"id": "a"}"#).unwrap();
        fs::write(dir.join("b.json"), r#"{"id": "b"}"#).unwrap();
        let tmpl = r#"[{{a.json}}, {{b.json}}]"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v[0]["id"], serde_json::json!("a"));
        assert_eq!(v[1]["id"], serde_json::json!("b"));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn nested_inclusion() {
        let dir = tmpdir("nested");
        fs::write(dir.join("inner.json"), r#"{"v": 42}"#).unwrap();
        fs::write(dir.join("outer.json"), r#"{"inner": {{inner.json}}}"#).unwrap();
        let tmpl = r#"{"data": {{outer.json}}}"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["inner"]["v"], serde_json::json!(42));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn missing_file_errors() {
        let dir = tmpdir("missing");
        let tmpl = r#"{"x": {{nope.json}}}"#;
        let err = compose(tmpl, &dir, 2).unwrap_err();
        assert!(err.contains("not found") || err.contains("nope.json"));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn unclosed_token_errors() {
        let dir = tmpdir("unclosed");
        let tmpl = r#"{"x": {{nope}"#;
        let err = compose(tmpl, &dir, 2).unwrap_err();
        assert!(err.contains("unclosed"));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn referenced_files_list() {
        let tmpl = r#"[{{a.json}}, {{b/c.json}}]"#;
        assert_eq!(referenced_files(tmpl), vec!["a.json", "b/c.json"]);
    }

    #[test]
    fn circular_reference_detected() {
        let dir = tmpdir("circular");
        fs::write(dir.join("a.json"), r#"{"b": {{b.json}}}"#).unwrap();
        fs::write(dir.join("b.json"), r#"{"a": {{a.json}}}"#).unwrap();
        let tmpl = r#"{"root": {{a.json}}}"#;
        let err = compose(tmpl, &dir, 2).unwrap_err();
        assert!(err.contains("circular"), "expected circular error, got: {err}");
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn token_whitespace_trimmed() {
        let dir = tmpdir("ws");
        fs::write(dir.join("a.json"), r#"1"#).unwrap();
        let tmpl = r#"[{{  a.json  }}]"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v[0], serde_json::json!(1));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn result_is_valid_json() {
        let dir = tmpdir("valid");
        fs::write(dir.join("x.json"), r#"{"k": "v"}"#).unwrap();
        let tmpl = r#"{"data": {{x.json}}}"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&out).is_ok());
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn invalid_included_file_errors() {
        let dir = tmpdir("invalid_inner");
        fs::write(dir.join("bad.json"), r#"{ not json }"#).unwrap();
        let tmpl = r#"{"x": {{bad.json}}}"#;
        let err = compose(tmpl, &dir, 2).unwrap_err();
        assert!(!err.is_empty());
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn referenced_files_deduplicates_tokens() {
        let tmpl = r#"[{{a.json}}, {{a.json}}, {{b.json}}]"#;
        assert_eq!(referenced_files(tmpl), vec!["a.json", "a.json", "b.json"]);
    }

    #[test]
    fn referenced_files_empty_when_none() {
        assert!(referenced_files(r#"{"plain": 1}"#).is_empty());
    }

    // -----------------------------------------------------------------------
    // Args tests
    // -----------------------------------------------------------------------

    #[test]
    fn args_string_substitution() {
        let dir = tmpdir("args_str");
        fs::write(dir.join("item.json"), r#"{"id": {{ @id }}}"#).unwrap();
        let tmpl = r#"[{{item.json, id: "X"}}]"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v[0]["id"], serde_json::json!("X"));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn args_number_substitution() {
        let dir = tmpdir("args_num");
        fs::write(dir.join("item.json"), r#"{"count": {{ @count }}}"#).unwrap();
        let tmpl = r#"{"result": {{item.json, count: 42}}}"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["result"]["count"], serde_json::json!(42));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn args_multiple_params() {
        let dir = tmpdir("args_multi");
        fs::write(
            dir.join("person.json"),
            r#"{"id": {{ @id }}, "name": {{ @name }}}"#,
        )
        .unwrap();
        let tmpl = r#"[{{person.json, id: 1, name: "Alice"}}, {{person.json, id: 2, name: "Bob"}}]"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v[0]["id"], serde_json::json!(1));
        assert_eq!(v[0]["name"], serde_json::json!("Alice"));
        assert_eq!(v[1]["name"], serde_json::json!("Bob"));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn args_no_space_around_colon() {
        let dir = tmpdir("args_nospace");
        fs::write(dir.join("x.json"), r#"{{ @v }}"#).unwrap();
        let tmpl = r#"[{{x.json, v:99}}]"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v[0], serde_json::json!(99));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn args_same_file_different_args() {
        let dir = tmpdir("args_reuse");
        fs::write(dir.join("tag.json"), r#"{"tag": {{ @t }}}"#).unwrap();
        let tmpl = r#"[{{tag.json, t: "a"}}, {{tag.json, t: "b"}}]"#;
        let out = compose(tmpl, &dir, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v[0]["tag"], serde_json::json!("a"));
        assert_eq!(v[1]["tag"], serde_json::json!("b"));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn arg_refs_excluded_from_referenced_files() {
        let tmpl = r#"[{{a.json}}, {{ @id }}]"#;
        assert_eq!(referenced_files(tmpl), vec!["a.json"]);
    }

    #[test]
    fn args_with_included_file_no_args_ignored() {
        // File uses @arg but token provides none — @arg kept as-is, resolve fails at validation
        let dir = tmpdir("args_missing");
        fs::write(dir.join("inner.json"), r#"{"id": {{ @id }}}"#).unwrap();
        // Include without args — @id stays in output, invalid JSON
        let tmpl = r#"{"x": {{inner.json}}}"#;
        let err = compose(tmpl, &dir, 2).unwrap_err();
        assert!(!err.is_empty(), "should fail on unresolved @arg");
        fs::remove_dir_all(&dir).ok();
    }
}
