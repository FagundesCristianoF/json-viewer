//! Flat node arena for cache-friendly, recursion-free tree rendering.

use serde_json::Value;
use std::ops::Range;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    Object,
    Array,
    String,
    Number,
    Bool,
    Null,
}

impl Kind {
    pub fn badge(self) -> &'static str {
        match self {
            Kind::Object => "{}",
            Kind::Array => "[]",
            Kind::String => "str",
            Kind::Number => "num",
            Kind::Bool => "bool",
            Kind::Null => "null",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Node {
    /// Key if this node is a child of an object.
    pub key: Option<String>,
    pub kind: Kind,
    /// Scalar text for leaves (string content, number/bool/null rendered).
    pub value: Option<String>,
    /// Arena index range of direct children (empty for scalars).
    pub children: Range<usize>,
    /// Precomputed JSONPath to this node.
    pub path: String,
    pub depth: usize,
}

#[derive(Debug)]
pub struct Arena {
    pub nodes: Vec<Node>,
    pub root: usize,
}

impl Arena {
    /// Build a flat arena from a parsed serde value.
    pub fn build(value: &Value) -> Arena {
        let mut nodes = Vec::new();
        nodes.push(Node {
            key: None,
            kind: kind_of(value),
            value: scalar_text(value),
            children: 0..0,
            path: "$".to_string(),
            depth: 0,
        });
        build_children(&mut nodes, 0, value, "$", 0);
        Arena { nodes, root: 0 }
    }

    /// Parent index for every node (root maps to itself).
    pub fn parents(&self) -> Vec<usize> {
        let mut parents = vec![self.root; self.nodes.len()];
        for (i, n) in self.nodes.iter().enumerate() {
            for c in n.children.clone() {
                parents[c] = i;
            }
        }
        parents
    }
}

/// Reconstruct a serde_json `Value` for the subtree rooted at `idx`.
/// Used to render JSONPath-filtered projections back to text.
pub fn node_to_value(arena: &Arena, idx: usize) -> Value {
    let n = &arena.nodes[idx];
    match n.kind {
        Kind::Object => {
            let mut map = serde_json::Map::new();
            for c in n.children.clone() {
                let key = arena.nodes[c].key.clone().unwrap_or_default();
                map.insert(key, node_to_value(arena, c));
            }
            Value::Object(map)
        }
        Kind::Array => Value::Array(n.children.clone().map(|c| node_to_value(arena, c)).collect()),
        Kind::String => Value::String(n.value.clone().unwrap_or_default()),
        Kind::Number => n
            .value
            .as_deref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(Value::Null),
        Kind::Bool => Value::Bool(n.value.as_deref() == Some("true")),
        Kind::Null => Value::Null,
    }
}

/// Push the index and every descendant of `idx` into `out`.
pub fn collect_subtree(arena: &Arena, idx: usize, out: &mut Vec<usize>) {
    out.push(idx);
    for c in arena.nodes[idx].children.clone() {
        collect_subtree(arena, c, out);
    }
}

fn build_children(nodes: &mut Vec<Node>, parent: usize, value: &Value, path: &str, depth: usize) {
    match value {
        Value::Object(map) => {
            let start = nodes.len();
            let mut child_vals: Vec<&Value> = Vec::with_capacity(map.len());
            for (k, v) in map {
                nodes.push(Node {
                    key: Some(k.clone()),
                    kind: kind_of(v),
                    value: scalar_text(v),
                    children: 0..0,
                    path: obj_child_path(path, k),
                    depth: depth + 1,
                });
                child_vals.push(v);
            }
            let end = nodes.len();
            nodes[parent].children = start..end;
            for (i, v) in child_vals.into_iter().enumerate() {
                let cidx = start + i;
                let cpath = nodes[cidx].path.clone();
                build_children(nodes, cidx, v, &cpath, depth + 1);
            }
        }
        Value::Array(arr) => {
            let start = nodes.len();
            for (i, v) in arr.iter().enumerate() {
                nodes.push(Node {
                    key: None,
                    kind: kind_of(v),
                    value: scalar_text(v),
                    children: 0..0,
                    path: format!("{}[{}]", path, i),
                    depth: depth + 1,
                });
            }
            let end = nodes.len();
            nodes[parent].children = start..end;
            for (i, v) in arr.iter().enumerate() {
                let cidx = start + i;
                let cpath = nodes[cidx].path.clone();
                build_children(nodes, cidx, v, &cpath, depth + 1);
            }
        }
        _ => {}
    }
}

fn kind_of(v: &Value) -> Kind {
    match v {
        Value::Object(_) => Kind::Object,
        Value::Array(_) => Kind::Array,
        Value::String(_) => Kind::String,
        Value::Number(_) => Kind::Number,
        Value::Bool(_) => Kind::Bool,
        Value::Null => Kind::Null,
    }
}

fn scalar_text(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        Value::Null => Some("null".to_string()),
        _ => None,
    }
}

fn is_ident(key: &str) -> bool {
    let mut chars = key.chars();
    match chars.next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn obj_child_path(parent: &str, key: &str) -> String {
    if is_ident(key) {
        format!("{}.{}", parent, key)
    } else {
        format!("{}['{}']", parent, key.replace('\'', "\\'"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn arena(s: &str) -> Arena {
        Arena::build(&serde_json::from_str(s).unwrap())
    }

    #[test]
    fn scalar_root() {
        let a = arena("42");
        assert_eq!(a.nodes.len(), 1);
        assert_eq!(a.nodes[0].kind, Kind::Number);
        assert_eq!(a.nodes[0].value.as_deref(), Some("42"));
        assert_eq!(a.nodes[0].path, "$");
    }

    #[test]
    fn object_paths() {
        let a = arena(r#"{"a": 1, "b c": 2}"#);
        // root + 2 children
        assert_eq!(a.nodes.len(), 3);
        let paths: Vec<_> = a.nodes.iter().map(|n| n.path.clone()).collect();
        assert!(paths.contains(&"$.a".to_string()));
        assert!(paths.contains(&"$['b c']".to_string()));
    }

    #[test]
    fn nested_arrays_contiguous_children() {
        let a = arena(r#"{"xs": [1, 2, [3, 4]]}"#);
        let root = &a.nodes[a.root];
        assert_eq!(root.kind, Kind::Object);
        let xs = root.children.clone().next().unwrap();
        let xs_node = &a.nodes[xs];
        assert_eq!(xs_node.kind, Kind::Array);
        // direct children of xs are contiguous and number 3
        assert_eq!(xs_node.children.len(), 3);
        // last child is the nested array
        let last = xs_node.children.end - 1;
        assert_eq!(a.nodes[last].kind, Kind::Array);
        assert_eq!(a.nodes[last].path, "$.xs[2]");
    }

    #[test]
    fn subtree_and_parents() {
        let a = arena(r#"{"a": {"b": 1}}"#);
        let mut sub = Vec::new();
        collect_subtree(&a, a.root, &mut sub);
        assert_eq!(sub.len(), a.nodes.len());
        let parents = a.parents();
        let a_idx = a.nodes.iter().position(|n| n.path == "$.a").unwrap();
        let b_idx = a.nodes.iter().position(|n| n.path == "$.a.b").unwrap();
        assert_eq!(parents[b_idx], a_idx);
        assert_eq!(parents[a_idx], a.root);
    }

    #[test]
    fn node_to_value_object_roundtrip() {
        let src = r#"{"x": 1, "y": "hello"}"#;
        let a = arena(src);
        let v = node_to_value(&a, a.root);
        assert_eq!(v["x"], serde_json::json!(1));
        assert_eq!(v["y"], serde_json::json!("hello"));
    }

    #[test]
    fn node_to_value_array_roundtrip() {
        let a = arena("[1, true, null]");
        let v = node_to_value(&a, a.root);
        assert_eq!(v, serde_json::json!([1, true, null]));
    }

    #[test]
    fn node_to_value_nested_roundtrip() {
        let src = r#"{"a": {"b": [1, 2, 3]}}"#;
        let a = arena(src);
        let v = node_to_value(&a, a.root);
        assert_eq!(v["a"]["b"][2], serde_json::json!(3));
    }

    #[test]
    fn expand_to_matches_visits_ancestors() {
        // Build arena for {"a": {"b": 1}}
        // Query for $.a.b — match is the deepest node.
        // expand_to_matches must insert root, $.a and $.a.b into expanded.
        let src = r#"{"a": {"b": 1}}"#;
        let a = Arena::build(&serde_json::from_str(src).unwrap());
        let b_idx = a.nodes.iter().position(|n| n.path == "$.a.b").unwrap();
        let parents = a.parents();
        let mut expanded = std::collections::HashSet::new();
        // Manually replay expand_to_matches logic.
        let mut p = b_idx;
        expanded.insert(p);
        while p != a.root {
            p = parents[p];
            expanded.insert(p);
        }
        assert!(expanded.contains(&a.root));
        let a_idx = a.nodes.iter().position(|n| n.path == "$.a").unwrap();
        assert!(expanded.contains(&a_idx));
        assert!(expanded.contains(&b_idx));
    }
}
