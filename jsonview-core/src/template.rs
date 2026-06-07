//! Template system: `{{varName}}` variable substitution + `.template.json` file management.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Extract unique variable names from `{{token}}` placeholders that have no dot
/// (distinguishing them from file includes like `{{file.json}}`).
pub fn find_variables(template: &str) -> Vec<String> {
    let mut vars: Vec<String> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut rest = template;
    while let Some(start) = rest.find("{{") {
        rest = &rest[start + 2..];
        if let Some(end) = rest.find("}}") {
            let token = rest[..end].trim();
            if !token.contains('.') && !token.is_empty() && seen.insert(token.to_string()) {
                vars.push(token.to_string());
            }
            rest = &rest[end + 2..];
        } else {
            break;
        }
    }
    vars
}

/// Substitute `{{varName}}` tokens with values from `vars`.
/// File tokens (`{{file.json}}`) are kept as-is for `compose::compose` to handle later.
/// Returns error if a variable token has no matching entry in `vars`.
pub fn render_vars(template: &str, vars: &HashMap<String, String>) -> Result<String, String> {
    let mut result = String::with_capacity(template.len());
    let mut rest = template;
    while let Some(start) = rest.find("{{") {
        result.push_str(&rest[..start]);
        rest = &rest[start + 2..];
        if let Some(end) = rest.find("}}") {
            let token = rest[..end].trim();
            if !token.contains('.') && !token.is_empty() {
                let val = vars
                    .get(token)
                    .ok_or_else(|| format!("missing variable: {token}"))?;
                result.push_str(val);
            } else {
                result.push_str("{{");
                result.push_str(&rest[..end]);
                result.push_str("}}");
            }
            rest = &rest[end + 2..];
        } else {
            return Err("unclosed '{{' in template".to_string());
        }
    }
    result.push_str(rest);
    Ok(result)
}

/// List all `*.template.json` files directly under `dir` (non-recursive).
pub fn list_templates(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut templates: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.ends_with(".template.json"))
                .unwrap_or(false)
        })
        .collect();
    templates.sort();
    templates
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_vars_not_files() {
        let tmpl = r#"{"name": {{productName}}, "src": {{data.json}}}"#;
        assert_eq!(find_variables(tmpl), vec!["productName"]);
    }

    #[test]
    fn deduplicates_vars() {
        let tmpl = "{{x}} and {{x}} again";
        assert_eq!(find_variables(tmpl), vec!["x"]);
    }

    #[test]
    fn renders_vars() {
        let tmpl = r#"{"n": {{name}}, "v": {{value}}}"#;
        let mut vars = HashMap::new();
        vars.insert("name".to_string(), r#""hello""#.to_string());
        vars.insert("value".to_string(), "42".to_string());
        let out = render_vars(tmpl, &vars).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["n"], "hello");
        assert_eq!(v["v"], 42);
    }

    #[test]
    fn preserves_file_tokens() {
        let tmpl = r#"{"x": {{file.json}}, "v": {{myVar}}}"#;
        let mut vars = HashMap::new();
        vars.insert("myVar".to_string(), "1".to_string());
        let out = render_vars(tmpl, &vars).unwrap();
        assert!(out.contains("{{file.json}}"));
    }

    #[test]
    fn error_on_missing_var() {
        let tmpl = "{{missingVar}}";
        let vars = HashMap::new();
        assert!(render_vars(tmpl, &vars).is_err());
    }

    #[test]
    fn unclosed_token_errors() {
        let vars = HashMap::new();
        assert!(render_vars("{{unclosed", &vars).is_err());
    }

    #[test]
    fn no_vars_passthrough() {
        let tmpl = r#"{"a": 1}"#;
        let out = render_vars(tmpl, &HashMap::new()).unwrap();
        assert_eq!(out, tmpl);
    }

    #[test]
    fn find_variables_empty_template() {
        assert!(find_variables("{}").is_empty());
    }

    #[test]
    fn find_variables_preserves_order() {
        let tmpl = "{{c}} {{a}} {{b}}";
        assert_eq!(find_variables(tmpl), vec!["c", "a", "b"]);
    }

    #[test]
    fn list_templates_finds_only_template_json() {
        let dir = std::env::temp_dir().join(format!(
            "jsonview_tmpl_{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        std::fs::write(dir.join("foo.template.json"), "{}").unwrap();
        std::fs::write(dir.join("bar.template.json"), "{}").unwrap();
        std::fs::write(dir.join("regular.json"), "{}").unwrap();
        std::fs::write(dir.join("notes.txt"), "x").unwrap();

        let templates = list_templates(&dir);
        assert_eq!(templates.len(), 2);
        assert!(templates.iter().all(|p| p.to_string_lossy().ends_with(".template.json")));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn list_templates_empty_dir() {
        let dir = std::env::temp_dir().join(format!(
            "jsonview_tmpl_empty_{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        assert!(list_templates(&dir).is_empty());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn list_templates_nonexistent_dir_empty() {
        let dir = std::path::Path::new("/tmp/jsonview_does_not_exist_xyz");
        assert!(list_templates(dir).is_empty());
    }
}
