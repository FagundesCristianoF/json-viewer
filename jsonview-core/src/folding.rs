//! JSON editor code-folding: scan fold ranges, build collapsed display text.

use std::collections::{HashMap, HashSet};

#[derive(Clone, Debug)]
pub struct FoldRange {
    pub start_line: usize,
    pub end_line: usize,
    pub open_char: char, // '{' or '['
}

/// Scan text and return all multi-line foldable `{…}` / `[…]` blocks.
pub fn scan_fold_ranges(text: &str) -> Vec<FoldRange> {
    let lines: Vec<&str> = text.lines().collect();
    let mut ranges = Vec::new();
    let mut stack: Vec<(usize, char)> = Vec::new();

    for (line_idx, &line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        // Opening bracket at end of line
        match trimmed.chars().last() {
            Some('{') => stack.push((line_idx, '{')),
            Some('[') => stack.push((line_idx, '[')),
            _ => {}
        }
        // Closing bracket at start of line
        match trimmed.chars().next() {
            Some('}') | Some(']') => {
                if let Some((start_line, open_char)) = stack.pop() {
                    if line_idx > start_line + 1 {
                        ranges.push(FoldRange { start_line, end_line: line_idx, open_char });
                    }
                }
            }
            _ => {}
        }
    }
    ranges
}

/// Build a display string collapsing folded ranges to a single summary line.
/// Returns `(display_text, display_line → real_line mapping)`.
pub fn build_display_text(
    text: &str,
    folded: &HashSet<usize>,
    ranges: &[FoldRange],
) -> (String, Vec<usize>) {
    let lines: Vec<&str> = text.lines().collect();

    // start_line → FoldRange for every folded range
    let folded_map: HashMap<usize, &FoldRange> = ranges
        .iter()
        .filter(|r| folded.contains(&r.start_line))
        .map(|r| (r.start_line, r))
        .collect();

    let mut result = String::with_capacity(text.len());
    let mut real_line_map: Vec<usize> = Vec::new();
    let mut skip_until: Option<usize> = None;

    for (line_idx, &line) in lines.iter().enumerate() {
        if let Some(end) = skip_until {
            if line_idx <= end {
                continue;
            }
            skip_until = None;
        }

        if let Some(range) = folded_map.get(&line_idx) {
            let close = if range.open_char == '{' { '}' } else { ']' };
            let end_str = lines.get(range.end_line).unwrap_or(&"");
            let trailing = if end_str.trim_end().ends_with(',') { "," } else { "" };
            result.push_str(line.trim_end());
            result.push_str(" … ");
            result.push(close);
            result.push_str(trailing);
            result.push('\n');
            real_line_map.push(line_idx);
            skip_until = Some(range.end_line);
        } else {
            result.push_str(line);
            result.push('\n');
            real_line_map.push(line_idx);
        }
    }

    (result, real_line_map)
}

/// Map a real line number to the corresponding display line number (first match).
pub fn real_to_display_line(real_line: usize, map: &[usize]) -> usize {
    map.iter()
        .position(|&r| r == real_line)
        .unwrap_or(real_line)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_object_ranges() {
        let text = "{\n  \"a\": 1,\n  \"b\": 2\n}\n";
        let ranges = scan_fold_ranges(text);
        assert_eq!(ranges.len(), 1);
        assert_eq!(ranges[0].start_line, 0);
        assert_eq!(ranges[0].end_line, 3);
    }

    #[test]
    fn single_line_object_not_foldable() {
        let text = "{ \"a\": 1 }\n";
        assert!(scan_fold_ranges(text).is_empty());
    }

    #[test]
    fn build_display_collapses_range() {
        let text = "{\n  \"a\": 1\n}\n";
        let ranges = scan_fold_ranges(text);
        let mut folded = HashSet::new();
        folded.insert(0);
        let (display, map) = build_display_text(text, &folded, &ranges);
        assert_eq!(display.lines().count(), 1);
        assert!(display.contains("… }"));
        assert_eq!(map[0], 0);
    }

    #[test]
    fn unfold_shows_full_text() {
        let text = "{\n  \"a\": 1\n}\n";
        let ranges = scan_fold_ranges(text);
        let folded = HashSet::new();
        let (display, _) = build_display_text(text, &folded, &ranges);
        assert_eq!(display.lines().count(), text.lines().count());
    }
}
