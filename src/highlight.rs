//! Lexical JSON syntax highlighting for the editor's TextEdit layouter.
//!
//! Tolerant: it colors tokens even while the document is mid-edit / invalid.
//! Skips work on very large buffers so typing stays instant.

use crate::model::Kind;
use crate::theme::Palette;
use eframe::egui::{
    text::{LayoutJob, LayoutSection, TextFormat},
    Color32, FontId,
};

/// Above this size, highlighting is disabled (plain text) to keep large
/// files fast. Tokenizing megabytes per keystroke would stall the editor.
const MAX_HIGHLIGHT_BYTES: usize = 200_000;

pub fn layout_job(text: &str, pal: &Palette, font: FontId, wrap_width: f32) -> LayoutJob {
    let mut job = LayoutJob::default();
    job.wrap.max_width = wrap_width;

    if text.len() > MAX_HIGHLIGHT_BYTES {
        job.append(text, 0.0, fmt(font, pal.text));
        return job;
    }

    let b = text.as_bytes();
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        match c {
            b'"' => {
                let end = string_end(b, i);
                let color = if is_key(b, end) {
                    pal.kind_color(Kind::Object)
                } else {
                    pal.kind_color(Kind::String)
                };
                job.append(&text[i..end], 0.0, fmt(font.clone(), color));
                i = end;
            }
            b'-' | b'0'..=b'9' => {
                let start = i;
                while i < b.len()
                    && matches!(b[i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9')
                {
                    i += 1;
                }
                job.append(&text[start..i], 0.0, fmt(font.clone(), pal.kind_color(Kind::Number)));
            }
            b't' | b'f' => {
                let (word, end) = word(b, i);
                let color = if word == "true" || word == "false" {
                    pal.kind_color(Kind::Bool)
                } else {
                    pal.text
                };
                job.append(&text[i..end], 0.0, fmt(font.clone(), color));
                i = end;
            }
            b'n' => {
                let (word, end) = word(b, i);
                let color = if word == "null" {
                    pal.kind_color(Kind::Null)
                } else {
                    pal.text
                };
                job.append(&text[i..end], 0.0, fmt(font.clone(), color));
                i = end;
            }
            b'{' | b'}' | b'[' | b']' | b':' | b',' => {
                job.append(&text[i..i + 1], 0.0, fmt(font.clone(), pal.dim));
                i += 1;
            }
            _ => {
                // whitespace or stray text: copy a UTF-8 char as plain
                let len = utf8_len(c).min(b.len() - i);
                job.append(&text[i..i + len], 0.0, fmt(font.clone(), pal.text));
                i += len;
            }
        }
    }
    job
}

/// Same as `layout_job` but overlays a highlight background on all occurrences of `search`.
pub fn layout_job_search(
    text: &str,
    pal: &Palette,
    font: FontId,
    wrap_width: f32,
    search: &str,
) -> LayoutJob {
    let mut job = layout_job(text, pal, font, wrap_width);
    if search.is_empty() {
        return job;
    }

    let lower_text = text.to_lowercase();
    let lower_search = search.to_lowercase();
    let match_bg = if pal.dark {
        Color32::from_rgba_unmultiplied(0xff, 0xcc, 0x00, 70)
    } else {
        Color32::from_rgba_unmultiplied(0xff, 0xcc, 0x00, 110)
    };

    let highlights: Vec<(usize, usize)> = lower_text
        .match_indices(lower_search.as_str())
        .map(|(s, _)| (s, s + lower_search.len()))
        .collect();

    if highlights.is_empty() {
        return job;
    }

    let old_sections = std::mem::take(&mut job.sections);
    for section in old_sections {
        split_section(&mut job.sections, section, &highlights, match_bg);
    }
    job
}

fn split_section(
    out: &mut Vec<LayoutSection>,
    orig: LayoutSection,
    highlights: &[(usize, usize)],
    bg: Color32,
) {
    let mut cursor = orig.byte_range.start;
    let end = orig.byte_range.end;

    for &(h_start, h_end) in highlights {
        if h_end <= cursor || h_start >= end {
            continue;
        }
        let ol_start = h_start.max(cursor);
        let ol_end = h_end.min(end);

        if cursor < ol_start {
            out.push(LayoutSection {
                leading_space: 0.0,
                byte_range: cursor..ol_start,
                format: orig.format.clone(),
            });
        }
        let mut fmt = orig.format.clone();
        fmt.background = bg;
        out.push(LayoutSection {
            leading_space: 0.0,
            byte_range: ol_start..ol_end,
            format: fmt,
        });
        cursor = ol_end;
    }

    if cursor < end {
        out.push(LayoutSection {
            leading_space: 0.0,
            byte_range: cursor..end,
            format: orig.format,
        });
    }
}

fn fmt(font: FontId, color: Color32) -> TextFormat {
    TextFormat {
        font_id: font,
        color,
        ..Default::default()
    }
}

/// Index just past the closing quote of a string starting at `b[i] == '"'`.
fn string_end(b: &[u8], start: usize) -> usize {
    let mut i = start + 1;
    while i < b.len() {
        match b[i] {
            b'\\' => i += 2,
            b'"' => return i + 1,
            _ => i += 1,
        }
    }
    b.len()
}

/// Whether the string ending at `end` is an object key (next token is `:`).
fn is_key(b: &[u8], end: usize) -> bool {
    let mut j = end;
    while j < b.len() && matches!(b[j], b' ' | b'\t' | b'\r' | b'\n') {
        j += 1;
    }
    b.get(j) == Some(&b':')
}

fn word(b: &[u8], start: usize) -> (&str, usize) {
    let mut i = start;
    while i < b.len() && b[i].is_ascii_alphabetic() {
        i += 1;
    }
    (std::str::from_utf8(&b[start..i]).unwrap_or(""), i)
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
    use crate::theme::palette;

    #[test]
    fn produces_sections() {
        let job = layout_job(r#"{"a": 1, "b": true}"#, &palette(false), FontId::monospace(12.0), 400.0);
        // many distinct colored runs: braces, key, number, key, bool, etc.
        assert!(job.sections.len() > 5);
    }

    #[test]
    fn large_input_single_section() {
        let big = "\"x\"".repeat(MAX_HIGHLIGHT_BYTES);
        let job = layout_job(&big, &palette(true), FontId::monospace(12.0), 400.0);
        assert_eq!(job.sections.len(), 1);
    }

    #[test]
    fn key_vs_value_string() {
        // both strings present; tokenizer must not panic and must color them
        let job = layout_job(r#"{"key": "value"}"#, &palette(false), FontId::monospace(12.0), 400.0);
        assert!(!job.sections.is_empty());
        // covers the full text length
        let total: usize = job.sections.iter().map(|s| s.byte_range.len()).sum();
        assert_eq!(total, r#"{"key": "value"}"#.len());
    }
}
