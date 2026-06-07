//! JSON Compose: resolve `{{filename.json}}` placeholders in a template.
//!
//! A template is any JSON (or JSON-like) text containing `{{path.json}}`
//! tokens. Each token is replaced with the parsed content of that file,
//! resolved relative to a base directory. The result is valid, formatted JSON.
//!
//! Example template:
//!   { "products": [ {{productA.json}}, {{productB.json}} ] }
//!
//! Rules:
//!   - Tokens must be `{{filename}}` where filename may include sub-paths.
//!   - Paths are resolved relative to `base_dir`.
//!   - The referenced file must be valid JSON.
//!   - Circular references are detected and returned as an error.
//!   - The resulting string is re-parsed as JSON (validates the output).

use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// Resolve all `{{...}}` placeholders in `template`, reading files relative
/// to `base_dir`. Returns the formatted JSON string, or an error.
pub fn compose(template: &str, base_dir: &Path, indent: usize) -> Result<String, String> {
    let resolved = resolve(template, base_dir, &mut HashSet::new())?;

    // Validate the result is well-formed JSON.
    let value: serde_json::Value =
        serde_json::from_str(&resolved).map_err(|e| format!("result is not valid JSON: {e}"))?;

    let pad = " ".repeat(indent);
    let mut buf = Vec::new();
    let fmt = serde_json::ser::PrettyFormatter::with_indent(pad.as_bytes());
    let mut ser = serde_json::Serializer::with_formatter(&mut buf, fmt);
    use serde::Serialize;
    value.serialize(&mut ser).map_err(|e| e.to_string())?;
    Ok(String::from_utf8(buf).expect("utf8"))
}

/// Recursively resolve `{{...}}` tokens, tracking `visited` to detect cycles.
fn resolve(template: &str, base_dir: &Path, visited: &mut HashSet<PathBuf>) -> Result<String, String> {
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

            // Resolve the token as a file path.
            let path = base_dir.join(token);
            let canonical = path
                .canonicalize()
                .map_err(|_| format!("file not found: {}", path.display()))?;

            if visited.contains(&canonical) {
                return Err(format!("circular reference: {}", canonical.display()));
            }
            visited.insert(canonical.clone());

            let content = std::fs::read_to_string(&canonical)
                .map_err(|e| format!("cannot read {}: {e}", canonical.display()))?;

            // Recursively resolve nested templates in the included file.
            let file_base = canonical.parent().unwrap_or(base_dir);
            let expanded = resolve(&content, file_base, visited)?;
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
pub fn referenced_files(template: &str) -> Vec<String> {
    let mut files = Vec::new();
    let mut rest = template;
    while let Some(start) = rest.find("{{") {
        rest = &rest[start + 2..];
        if let Some(end) = rest.find("}}") {
            files.push(rest[..end].trim().to_string());
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
        // a.json includes b.json, b.json includes a.json
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
        // token with surrounding spaces inside {{ }}
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
}
