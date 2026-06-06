//! JSONPath subset engine over the arena.
//!
//! Supports: `$`, `.key`, `['key']`, `[i]`, `[*]`, `.*`, `..` (recursive
//! descent), and a basic filter `[?(@.field OP literal)]`.

use crate::model::{collect_subtree, Arena, Kind};

#[derive(Debug)]
enum Step {
    Child(String),
    Index(usize),
    Wildcard,
    Descendant(Box<Step>),
    Filter(Filter),
}

#[derive(Debug)]
struct Filter {
    path: Vec<String>,
    op: Op,
    lit: Lit,
}

#[derive(Debug, Clone, Copy)]
enum Op {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}

#[derive(Debug)]
enum Lit {
    Num(f64),
    Str(String),
    Bool(bool),
    Null,
}

/// Evaluate `expr` against the arena, returning matching node indices in
/// document order (deduplicated).
pub fn query(arena: &Arena, expr: &str) -> Result<Vec<usize>, String> {
    let steps = parse(expr)?;
    let mut cur = vec![arena.root];
    for step in &steps {
        cur = apply(arena, step, &cur);
    }
    Ok(dedup(cur))
}

fn dedup(v: Vec<usize>) -> Vec<usize> {
    let mut seen = std::collections::HashSet::new();
    v.into_iter().filter(|x| seen.insert(*x)).collect()
}

fn apply(arena: &Arena, step: &Step, set: &[usize]) -> Vec<usize> {
    match step {
        Step::Child(name) => set
            .iter()
            .filter_map(|&i| child_by_key(arena, i, name))
            .collect(),
        Step::Index(idx) => set
            .iter()
            .filter_map(|&i| child_by_index(arena, i, *idx))
            .collect(),
        Step::Wildcard => set
            .iter()
            .flat_map(|&i| arena.nodes[i].children.clone())
            .collect(),
        Step::Descendant(inner) => {
            let mut expanded = Vec::new();
            for &i in set {
                collect_subtree(arena, i, &mut expanded);
            }
            apply(arena, inner, &expanded)
        }
        Step::Filter(f) => set
            .iter()
            .flat_map(|&i| arena.nodes[i].children.clone())
            .filter(|&c| eval_filter(arena, c, f))
            .collect(),
    }
}

fn child_by_key(arena: &Arena, idx: usize, name: &str) -> Option<usize> {
    let node = &arena.nodes[idx];
    if node.kind != Kind::Object {
        return None;
    }
    node.children
        .clone()
        .find(|&c| arena.nodes[c].key.as_deref() == Some(name))
}

fn child_by_index(arena: &Arena, idx: usize, i: usize) -> Option<usize> {
    let node = &arena.nodes[idx];
    if node.kind != Kind::Array {
        return None;
    }
    let target = node.children.start + i;
    if target < node.children.end {
        Some(target)
    } else {
        None
    }
}

fn eval_filter(arena: &Arena, start: usize, f: &Filter) -> bool {
    let mut node = start;
    for seg in &f.path {
        match child_by_key(arena, node, seg) {
            Some(n) => node = n,
            None => return false,
        }
    }
    compare(&arena.nodes[node].kind, &arena.nodes[node].value, f)
}

fn compare(kind: &Kind, value: &Option<String>, f: &Filter) -> bool {
    match &f.lit {
        Lit::Num(x) => {
            if *kind != Kind::Number {
                return false;
            }
            match value.as_ref().and_then(|s| s.parse::<f64>().ok()) {
                Some(y) => num_ord(y, *x, f.op),
                None => false,
            }
        }
        Lit::Str(s) => {
            if *kind != Kind::String {
                return false;
            }
            let v = value.as_deref().unwrap_or("");
            str_ord(v, s, f.op)
        }
        Lit::Bool(b) => {
            if *kind != Kind::Bool {
                return false;
            }
            let v = value.as_deref() == Some(if *b { "true" } else { "false" });
            match f.op {
                Op::Eq => v,
                Op::Ne => !v,
                _ => false,
            }
        }
        Lit::Null => {
            let is_null = *kind == Kind::Null;
            match f.op {
                Op::Eq => is_null,
                Op::Ne => !is_null,
                _ => false,
            }
        }
    }
}

fn num_ord(a: f64, b: f64, op: Op) -> bool {
    match op {
        Op::Eq => a == b,
        Op::Ne => a != b,
        Op::Lt => a < b,
        Op::Le => a <= b,
        Op::Gt => a > b,
        Op::Ge => a >= b,
    }
}

fn str_ord(a: &str, b: &str, op: Op) -> bool {
    match op {
        Op::Eq => a == b,
        Op::Ne => a != b,
        Op::Lt => a < b,
        Op::Le => a <= b,
        Op::Gt => a > b,
        Op::Ge => a >= b,
    }
}

// ---- expression parser ----

fn parse(expr: &str) -> Result<Vec<Step>, String> {
    let s = expr.trim();
    let b = s.as_bytes();
    let mut i = 0;
    if b.first() != Some(&b'$') {
        return Err("path must start with $".to_string());
    }
    i += 1;
    let mut steps = Vec::new();
    while i < b.len() {
        match b[i] {
            b'.' => {
                if b.get(i + 1) == Some(&b'.') {
                    i += 2;
                    if b.get(i) == Some(&b'*') {
                        steps.push(Step::Descendant(Box::new(Step::Wildcard)));
                        i += 1;
                    } else if b.get(i) == Some(&b'[') {
                        let (st, ni) = parse_bracket(b, i)?;
                        i = ni;
                        steps.push(Step::Descendant(Box::new(st)));
                    } else {
                        let (name, ni) = read_ident(b, i)?;
                        i = ni;
                        steps.push(Step::Descendant(Box::new(Step::Child(name))));
                    }
                } else {
                    i += 1;
                    if b.get(i) == Some(&b'*') {
                        steps.push(Step::Wildcard);
                        i += 1;
                    } else {
                        let (name, ni) = read_ident(b, i)?;
                        i = ni;
                        steps.push(Step::Child(name));
                    }
                }
            }
            b'[' => {
                let (st, ni) = parse_bracket(b, i)?;
                i = ni;
                steps.push(st);
            }
            other => return Err(format!("unexpected character '{}' at {}", other as char, i)),
        }
    }
    Ok(steps)
}

fn read_ident(b: &[u8], mut i: usize) -> Result<(String, usize), String> {
    let start = i;
    while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
        i += 1;
    }
    if start == i {
        return Err(format!("expected name at {}", start));
    }
    Ok((String::from_utf8_lossy(&b[start..i]).into_owned(), i))
}

fn parse_bracket(b: &[u8], i: usize) -> Result<(Step, usize), String> {
    // b[i] == '['
    let mut j = i + 1;
    while b.get(j) == Some(&b' ') {
        j += 1;
    }
    match b.get(j) {
        Some(&b'*') => {
            j += 1;
            j = expect_close(b, j)?;
            Ok((Step::Wildcard, j))
        }
        Some(&b'?') => parse_filter(b, i),
        Some(&q) if q == b'\'' || q == b'"' => {
            j += 1;
            let start = j;
            while j < b.len() && b[j] != q {
                j += 1;
            }
            if j >= b.len() {
                return Err("unterminated quoted key".to_string());
            }
            let name = String::from_utf8_lossy(&b[start..j]).into_owned();
            j += 1; // closing quote
            j = expect_close(b, j)?;
            Ok((Step::Child(name), j))
        }
        Some(c) if c.is_ascii_digit() => {
            let start = j;
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
            let num: usize = std::str::from_utf8(&b[start..j])
                .unwrap()
                .parse()
                .map_err(|_| "invalid index".to_string())?;
            j = expect_close(b, j)?;
            Ok((Step::Index(num), j))
        }
        _ => Err("invalid bracket selector".to_string()),
    }
}

fn expect_close(b: &[u8], mut j: usize) -> Result<usize, String> {
    while b.get(j) == Some(&b' ') {
        j += 1;
    }
    if b.get(j) != Some(&b']') {
        return Err("expected ']'".to_string());
    }
    Ok(j + 1)
}

fn parse_filter(b: &[u8], i: usize) -> Result<(Step, usize), String> {
    // from b[i]=='[' find the closing ']'
    let mut end = i + 1;
    while end < b.len() && b[end] != b']' {
        end += 1;
    }
    if end >= b.len() {
        return Err("expected ']' for filter".to_string());
    }
    let inner = std::str::from_utf8(&b[i + 1..end]).unwrap().trim();
    if !inner.starts_with("?(") || !inner.ends_with(')') {
        return Err("malformed filter, expected [?(...)]".to_string());
    }
    let body = &inner[2..inner.len() - 1];
    let f = parse_filter_body(body)?;
    Ok((Step::Filter(f), end + 1))
}

fn parse_filter_body(s: &str) -> Result<Filter, String> {
    let s = s.trim();
    let rest = s
        .strip_prefix('@')
        .ok_or_else(|| "filter must start with @".to_string())?;
    let mut path = Vec::new();
    let mut rest = rest;
    while let Some(r) = rest.strip_prefix('.') {
        let end = r
            .find(|c: char| !(c.is_alphanumeric() || c == '_'))
            .unwrap_or(r.len());
        if end == 0 {
            break;
        }
        path.push(r[..end].to_string());
        rest = &r[end..];
    }
    let rest = rest.trim_start();
    let (op, after) = if let Some(x) = rest.strip_prefix("==") {
        (Op::Eq, x)
    } else if let Some(x) = rest.strip_prefix("!=") {
        (Op::Ne, x)
    } else if let Some(x) = rest.strip_prefix("<=") {
        (Op::Le, x)
    } else if let Some(x) = rest.strip_prefix(">=") {
        (Op::Ge, x)
    } else if let Some(x) = rest.strip_prefix('<') {
        (Op::Lt, x)
    } else if let Some(x) = rest.strip_prefix('>') {
        (Op::Gt, x)
    } else {
        return Err("expected comparison operator".to_string());
    };
    let lit = parse_lit(after.trim())?;
    Ok(Filter { path, op, lit })
}

fn parse_lit(s: &str) -> Result<Lit, String> {
    match s {
        "true" => return Ok(Lit::Bool(true)),
        "false" => return Ok(Lit::Bool(false)),
        "null" => return Ok(Lit::Null),
        _ => {}
    }
    let bytes = s.as_bytes();
    if bytes.len() >= 2
        && ((bytes[0] == b'\'' && bytes[bytes.len() - 1] == b'\'')
            || (bytes[0] == b'"' && bytes[bytes.len() - 1] == b'"'))
    {
        return Ok(Lit::Str(s[1..s.len() - 1].to_string()));
    }
    if let Ok(n) = s.parse::<f64>() {
        return Ok(Lit::Num(n));
    }
    Err(format!("invalid literal: {}", s))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Arena;

    fn arena(s: &str) -> Arena {
        Arena::build(&serde_json::from_str(s).unwrap())
    }

    fn paths(a: &Arena, expr: &str) -> Vec<String> {
        query(a, expr)
            .unwrap()
            .into_iter()
            .map(|i| a.nodes[i].path.clone())
            .collect()
    }

    #[test]
    fn child_and_index() {
        let a = arena(r#"{"a": {"b": [10, 20, 30]}}"#);
        assert_eq!(paths(&a, "$.a.b[1]"), vec!["$.a.b[1]"]);
    }

    #[test]
    fn wildcard() {
        let a = arena(r#"{"a": 1, "b": 2}"#);
        let mut p = paths(&a, "$.*");
        p.sort();
        assert_eq!(p, vec!["$.a", "$.b"]);
    }

    #[test]
    fn array_wildcard() {
        let a = arena(r#"{"xs": [1, 2, 3]}"#);
        assert_eq!(paths(&a, "$.xs[*]"), vec!["$.xs[0]", "$.xs[1]", "$.xs[2]"]);
    }

    #[test]
    fn recursive_descent() {
        let a = arena(r#"{"a": {"id": 1}, "b": {"c": {"id": 2}}}"#);
        let mut p = paths(&a, "$..id");
        p.sort();
        assert_eq!(p, vec!["$.a.id", "$.b.c.id"]);
    }

    #[test]
    fn bracket_key() {
        let a = arena(r#"{"weird key": 5}"#);
        assert_eq!(paths(&a, "$['weird key']"), vec!["$['weird key']"]);
    }

    #[test]
    fn filter_numeric() {
        let a = arena(r#"{"items": [{"price": 5}, {"price": 15}, {"price": 25}]}"#);
        let p = paths(&a, "$.items[?(@.price > 10)]");
        assert_eq!(p, vec!["$.items[1]", "$.items[2]"]);
    }

    #[test]
    fn filter_string_eq() {
        let a = arena(r#"[{"t": "x"}, {"t": "y"}]"#);
        let p = paths(&a, "$[?(@.t == 'y')]");
        assert_eq!(p, vec!["$[1]"]);
    }

    #[test]
    fn filter_self_scalar() {
        let a = arena(r#"[1, 5, 9]"#);
        let p = paths(&a, "$[?(@ >= 5)]");
        assert_eq!(p, vec!["$[1]", "$[2]"]);
    }

    #[test]
    fn bad_expr_errs() {
        let a = arena("{}");
        assert!(query(&a, "x.y").is_err());
        assert!(query(&a, "$.a[").is_err());
    }

    #[test]
    fn filtered_projection_roundtrip() {
        // Simulates filtered_json: query → node_to_value → format.
        let src = r#"{"store": {"book": [{"title": "A", "price": 5}, {"title": "B", "price": 20}]}}"#;
        let a = arena(src);
        let hits = query(&a, "$.store.book[?(@.price > 10)]").unwrap();
        assert_eq!(hits.len(), 1);
        let v = crate::model::node_to_value(&a, hits[0]);
        assert_eq!(v["title"], serde_json::json!("B"));
    }

    #[test]
    fn query_empty_when_no_match() {
        let a = arena(r#"{"a": 1}"#);
        let hits = query(&a, "$.z").unwrap();
        assert!(hits.is_empty());
    }
}
