//! serde_json wrapper: text -> arena, plus beautify/minify.

use crate::model::Arena;
use serde::Serialize;
use serde_json::Value;

#[derive(Clone, Debug)]
pub struct ParseError {
    pub message: String,
    pub line: usize,
    pub col: usize,
}

fn conv(e: serde_json::Error) -> ParseError {
    ParseError {
        message: e.to_string(),
        line: e.line(),
        col: e.column(),
    }
}

/// Parse text into a flat arena, or a structured syntax error.
pub fn parse(text: &str) -> Result<Arena, ParseError> {
    let value: Value = serde_json::from_str(text).map_err(conv)?;
    Ok(Arena::build(&value))
}

/// Pretty-print with the given indent width.
pub fn format(text: &str, indent: usize) -> Result<String, ParseError> {
    let value: Value = serde_json::from_str(text).map_err(conv)?;
    let pad = " ".repeat(indent);
    let mut buf = Vec::new();
    let fmt = serde_json::ser::PrettyFormatter::with_indent(pad.as_bytes());
    let mut ser = serde_json::Serializer::with_formatter(&mut buf, fmt);
    value.serialize(&mut ser).map_err(conv)?;
    Ok(String::from_utf8(buf).expect("serde_json emits utf8"))
}

/// Compact single-line form.
pub fn minify(text: &str) -> Result<String, ParseError> {
    let value: Value = serde_json::from_str(text).map_err(conv)?;
    serde_json::to_string(&value).map_err(conv)
}

/// Remove all null values (recursively) and re-format.
/// Object keys whose value is null are dropped entirely.
/// Array elements that are null are removed.
pub fn remove_nulls(text: &str, indent: usize) -> Result<String, ParseError> {
    let value: Value = serde_json::from_str(text).map_err(conv)?;
    let cleaned = strip_nulls(value);
    let pad = " ".repeat(indent);
    let mut buf = Vec::new();
    let fmt = serde_json::ser::PrettyFormatter::with_indent(pad.as_bytes());
    let mut ser = serde_json::Serializer::with_formatter(&mut buf, fmt);
    cleaned.serialize(&mut ser).map_err(conv)?;
    Ok(String::from_utf8(buf).expect("serde_json emits utf8"))
}

fn strip_nulls(v: Value) -> Value {
    match v {
        Value::Object(map) => Value::Object(
            map.into_iter()
                .filter(|(_, v)| !v.is_null())
                .map(|(k, v)| (k, strip_nulls(v)))
                .collect(),
        ),
        Value::Array(arr) => Value::Array(
            arr.into_iter()
                .filter(|v| !v.is_null())
                .map(strip_nulls)
                .collect(),
        ),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_ok() {
        assert!(parse(r#"{"a":1}"#).is_ok());
    }

    #[test]
    fn parse_err_has_location() {
        let e = parse("{\n  \"a\": ,\n}").unwrap_err();
        assert_eq!(e.line, 2);
        assert!(e.col > 0);
    }

    #[test]
    fn format_indent() {
        let out = format(r#"{"a":[1,2]}"#, 2).unwrap();
        assert_eq!(out, "{\n  \"a\": [\n    1,\n    2\n  ]\n}");
        let out4 = format(r#"{"a":1}"#, 4).unwrap();
        assert_eq!(out4, "{\n    \"a\": 1\n}");
    }

    #[test]
    fn minify_compact() {
        let out = minify("{\n  \"a\": 1\n}").unwrap();
        assert_eq!(out, r#"{"a":1}"#);
    }

    #[test]
    fn remove_nulls_object() {
        let out = remove_nulls(r#"{"a": 1, "b": null, "c": "x"}"#, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v.get("b").is_none());
        assert_eq!(v["a"], serde_json::json!(1));
    }

    #[test]
    fn remove_nulls_array() {
        let out = remove_nulls(r#"[1, null, 2, null, 3]"#, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v, serde_json::json!([1, 2, 3]));
    }

    #[test]
    fn remove_nulls_nested() {
        let out = remove_nulls(r#"{"a": {"x": null, "y": 2}}"#, 2).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["a"].get("x").is_none());
        assert_eq!(v["a"]["y"], serde_json::json!(2));
    }
}
