//! Data-smell rules over the arena, plus a text-level duplicate-key scan
//! (serde_json silently drops duplicate keys, so the arena cannot see them).

use crate::model::{Arena, Kind};
use std::collections::HashSet;

#[derive(Clone, Debug)]
pub struct Smell {
    /// JSONPath, or `line N` for text-level findings.
    pub path: String,
    pub message: String,
}

/// Scan a parsed arena (plus its source text) for data smells.
pub fn scan(arena: &Arena, text: &str) -> Vec<Smell> {
    let mut out = Vec::new();
    for node in &arena.nodes {
        match node.kind {
            Kind::Null => out.push(Smell {
                path: node.path.clone(),
                message: "null value".to_string(),
            }),
            Kind::Array if node.children.is_empty() => out.push(Smell {
                path: node.path.clone(),
                message: "empty array".to_string(),
            }),
            Kind::Object if node.children.is_empty() => out.push(Smell {
                path: node.path.clone(),
                message: "empty object".to_string(),
            }),
            Kind::Array => {
                let mut kinds = node.children.clone().map(|c| arena.nodes[c].kind);
                if let Some(first) = kinds.next() {
                    if kinds.any(|k| k != first) {
                        out.push(Smell {
                            path: node.path.clone(),
                            message: "array has mixed element types".to_string(),
                        });
                    }
                }
            }
            _ => {}
        }
    }
    for (line, key) in duplicate_keys(text) {
        out.push(Smell {
            path: format!("line {}", line),
            message: format!("duplicate key '{}'", key),
        });
    }
    out
}

enum Frame {
    Obj { keys: HashSet<String>, expect_key: bool },
    Arr,
}

/// Structurally scan JSON text and report `(line, key)` for keys that repeat
/// within the same object. Tolerant of escapes and nesting.
pub fn duplicate_keys(text: &str) -> Vec<(usize, String)> {
    let b = text.as_bytes();
    let mut i = 0;
    let mut line = 1usize;
    let mut stack: Vec<Frame> = Vec::new();
    let mut dups = Vec::new();

    while i < b.len() {
        match b[i] {
            b'\n' => {
                line += 1;
                i += 1;
            }
            b' ' | b'\t' | b'\r' => i += 1,
            b'{' => {
                stack.push(Frame::Obj {
                    keys: HashSet::new(),
                    expect_key: true,
                });
                i += 1;
            }
            b'}' => {
                stack.pop();
                i += 1;
            }
            b'[' => {
                stack.push(Frame::Arr);
                i += 1;
            }
            b']' => {
                stack.pop();
                i += 1;
            }
            b':' => {
                if let Some(Frame::Obj { expect_key, .. }) = stack.last_mut() {
                    *expect_key = false;
                }
                i += 1;
            }
            b',' => {
                if let Some(Frame::Obj { expect_key, .. }) = stack.last_mut() {
                    *expect_key = true;
                }
                i += 1;
            }
            b'"' => {
                let (s, ni, nl) = read_string(b, i, line);
                let is_key = matches!(stack.last(), Some(Frame::Obj { expect_key: true, .. }));
                if is_key {
                    if let Some(Frame::Obj { keys, .. }) = stack.last_mut() {
                        if !keys.insert(s.clone()) {
                            dups.push((line, s));
                        }
                    }
                }
                line = nl;
                i = ni;
            }
            _ => {
                // scalar token (number/true/false/null): consume to next delimiter
                while i < b.len()
                    && !matches!(
                        b[i],
                        b'{' | b'}' | b'[' | b']' | b':' | b',' | b' ' | b'\t' | b'\n' | b'\r' | b'"'
                    )
                {
                    i += 1;
                }
            }
        }
    }
    dups
}

/// Read a JSON string starting at `b[i] == '"'`, decoding escapes.
/// Returns (decoded, next_index, line_after).
fn read_string(b: &[u8], start: usize, mut line: usize) -> (String, usize, usize) {
    let mut i = start + 1;
    let mut s = String::new();
    while i < b.len() {
        match b[i] {
            b'"' => {
                i += 1;
                break;
            }
            b'\n' => {
                line += 1;
                s.push('\n');
                i += 1;
            }
            b'\\' => {
                i += 1;
                match b.get(i) {
                    Some(b'"') => s.push('"'),
                    Some(b'\\') => s.push('\\'),
                    Some(b'/') => s.push('/'),
                    Some(b'n') => s.push('\n'),
                    Some(b't') => s.push('\t'),
                    Some(b'r') => s.push('\r'),
                    Some(b'b') => s.push('\u{0008}'),
                    Some(b'f') => s.push('\u{000C}'),
                    Some(b'u') => {
                        if i + 4 < b.len() {
                            let hex = std::str::from_utf8(&b[i + 1..i + 5]).unwrap_or("");
                            if let Ok(cp) = u32::from_str_radix(hex, 16) {
                                if let Some(c) = char::from_u32(cp) {
                                    s.push(c);
                                }
                            }
                            i += 4;
                        }
                    }
                    _ => {}
                }
                i += 1;
            }
            _ => {
                // copy a full UTF-8 sequence
                let ch_len = utf8_len(b[i]);
                let end = (i + ch_len).min(b.len());
                s.push_str(&String::from_utf8_lossy(&b[i..end]));
                i = end;
            }
        }
    }
    (s, i, line)
}

fn utf8_len(byte: u8) -> usize {
    if byte < 0x80 {
        1
    } else if byte >> 5 == 0b110 {
        2
    } else if byte >> 4 == 0b1110 {
        3
    } else if byte >> 3 == 0b11110 {
        4
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Arena;

    fn arena(s: &str) -> Arena {
        Arena::build(&serde_json::from_str(s).unwrap())
    }

    #[test]
    fn null_smell() {
        let a = arena(r#"{"a": null}"#);
        let s = scan(&a, r#"{"a": null}"#);
        assert!(s.iter().any(|x| x.path == "$.a" && x.message == "null value"));
    }

    #[test]
    fn empty_containers() {
        let a = arena(r#"{"arr": [], "obj": {}}"#);
        let s = scan(&a, r#"{"arr": [], "obj": {}}"#);
        assert!(s.iter().any(|x| x.message == "empty array"));
        assert!(s.iter().any(|x| x.message == "empty object"));
    }

    #[test]
    fn mixed_array() {
        let a = arena(r#"{"xs": [1, "two", true]}"#);
        let s = scan(&a, r#"{"xs": [1, "two", true]}"#);
        assert!(s.iter().any(|x| x.message == "array has mixed element types"));
    }

    #[test]
    fn homogeneous_array_clean() {
        let a = arena(r#"{"xs": [1, 2, 3]}"#);
        let s = scan(&a, r#"{"xs": [1, 2, 3]}"#);
        assert!(!s.iter().any(|x| x.message.contains("mixed")));
    }

    #[test]
    fn duplicate_key_detected() {
        let text = "{\n  \"a\": 1,\n  \"a\": 2\n}";
        let dups = duplicate_keys(text);
        assert_eq!(dups.len(), 1);
        assert_eq!(dups[0].1, "a");
        assert_eq!(dups[0].0, 3);
    }

    #[test]
    fn dup_key_only_within_same_object() {
        // same key name in sibling objects is NOT a duplicate
        let text = r#"{"x": {"id": 1}, "y": {"id": 2}}"#;
        assert!(duplicate_keys(text).is_empty());
    }

    #[test]
    fn string_with_brace_not_confused() {
        let text = r#"{"a": "} { not structural", "a": 2}"#;
        let dups = duplicate_keys(text);
        assert_eq!(dups.len(), 1);
        assert_eq!(dups[0].1, "a");
    }

    #[test]
    fn clean_json_no_smells() {
        let text = r#"{"name": "Alice", "score": 100}"#;
        let a = arena(text);
        assert!(scan(&a, text).is_empty());
    }

    #[test]
    fn nested_null_reported() {
        let text = r#"{"a": {"b": null}}"#;
        let a = arena(text);
        let s = scan(&a, text);
        assert!(s.iter().any(|x| x.path == "$.a.b"));
    }

    #[test]
    fn dup_key_in_nested_object() {
        let text = "{\n  \"outer\": {\n    \"k\": 1,\n    \"k\": 2\n  }\n}";
        let dups = duplicate_keys(text);
        assert_eq!(dups.len(), 1);
        assert_eq!(dups[0].1, "k");
    }

    #[test]
    fn dup_key_in_root_and_nested() {
        let text = r#"{"a": 1, "b": {"a": 2, "a": 3}, "a": 4}"#;
        let dups = duplicate_keys(text);
        assert_eq!(dups.len(), 2);
    }

    #[test]
    fn array_of_objects_no_false_dup() {
        let text = r#"[{"id": 1}, {"id": 2}, {"id": 3}]"#;
        assert!(duplicate_keys(text).is_empty());
    }

    #[test]
    fn mixed_vs_clean_sibling_arrays() {
        let text = r#"{"mixed": [1, "a"], "clean": [1, 2, 3]}"#;
        let a = arena(text);
        let s = scan(&a, text);
        assert!(s.iter().any(|x| x.path == "$.mixed" && x.message.contains("mixed")));
        assert!(!s.iter().any(|x| x.path == "$.clean"));
    }

    #[test]
    fn empty_string_value_is_clean() {
        let text = r#"{"s": ""}"#;
        let a = arena(text);
        assert!(scan(&a, text).is_empty());
    }

    #[test]
    fn unicode_key_dup() {
        let text = "{\"é\": 1, \"é\": 2}";
        let dups = duplicate_keys(text);
        assert_eq!(dups.len(), 1);
        assert_eq!(dups[0].1, "é");
    }

    #[test]
    fn escaped_quote_in_key_not_confused() {
        let text = r#"{"a\"b": 1, "a\"b": 2}"#;
        let dups = duplicate_keys(text);
        assert_eq!(dups.len(), 1);
    }
}
