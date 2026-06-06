//! Virtualized parsed-tree view with JSONPath highlighting.

use crate::app::JsonViewApp;
use crate::model::{Arena, Kind, Node};
use eframe::egui;

const ROW_H: f32 = 18.0;

impl JsonViewApp {
    pub fn ui_tree(&mut self, ctx: &egui::Context) {
        let p = self.pal();
        let frame = egui::Frame::none()
            .fill(p.tree)
            .inner_margin(egui::Margin::symmetric(8.0, 8.0));
        egui::SidePanel::right("tree_panel")
            .frame(frame)
            .resizable(true)
            .default_width(380.0)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    crate::theme::section_label(ui, "Tree");
                    if self.arena.is_some() {
                        ui.with_layout(
                            egui::Layout::right_to_left(egui::Align::Center),
                            |ui| {
                                if ui.small_button("collapse").clicked() {
                                    self.expanded.clear();
                                    if let Some(a) = &self.arena {
                                        self.expanded.insert(a.root);
                                    }
                                }
                                if ui.small_button("expand").clicked() {
                                    if let Some(a) = &self.arena {
                                        self.expanded = (0..a.nodes.len()).collect();
                                    }
                                }
                            },
                        );
                    }
                });
                ui.add_space(4.0);

                if self.arena.is_none() {
                    ui.colored_label(p.kind_color(Kind::Bool), "Invalid JSON — see Issues");
                    return;
                }

                let rows = self.visible_rows();
                let mut toggle: Option<usize> = None;
                let mut copy: Option<String> = None;

                egui::ScrollArea::both()
                    .auto_shrink([false, false])
                    .show_rows(ui, ROW_H, rows.len(), |ui, range| {
                        let a = self.arena.as_ref().unwrap();
                        for r in range {
                            let idx = rows[r];
                            self.draw_row(ui, a, idx, &mut toggle, &mut copy);
                        }
                    });

                if let Some(i) = toggle {
                    if !self.expanded.remove(&i) {
                        self.expanded.insert(i);
                    }
                }
                if let Some(path) = copy {
                    ctx.copy_text(path.clone());
                    self.toast(format!("Copied {}", path));
                }
            });
    }

    fn draw_row(
        &self,
        ui: &mut egui::Ui,
        a: &Arena,
        idx: usize,
        toggle: &mut Option<usize>,
        copy: &mut Option<String>,
    ) {
        let p = self.pal();
        let node = &a.nodes[idx];
        let is_match = self.jp_matches.contains(&idx);
        let is_container = matches!(node.kind, Kind::Object | Kind::Array);

        // Allocate the full row height so we can check clicks anywhere on it.
        let desired = egui::vec2(ui.available_width(), ROW_H);
        let (row_rect, row_resp) = ui.allocate_exact_size(desired, egui::Sense::click());

        // Hover / match background.
        let bg = if is_match {
            Some(p.sel)
        } else if row_resp.hovered() {
            Some(p.hover)
        } else {
            None
        };
        if let Some(color) = bg {
            ui.painter().rect_filled(row_rect, egui::Rounding::ZERO, color);
        }

        // Build contents inside the row rect with a child ui.
        let mut child = ui.child_ui(row_rect, egui::Layout::left_to_right(egui::Align::Center), None);
        child.spacing_mut().item_spacing.x = 6.0;
        child.add_space(node.depth as f32 * 14.0);

        if is_container {
            let icon = if self.expanded.contains(&idx) {
                crate::icons::Icon::ChevronDown
            } else {
                crate::icons::Icon::ChevronRight
            };
            let chevron_rect = egui::Rect::from_min_size(
                child.cursor().min + egui::Vec2::new(0.0, (ROW_H - 12.0) / 2.0),
                egui::Vec2::splat(12.0),
            );
            crate::icons::draw(&child.painter(), icon, chevron_rect, p.dim);
            child.add_space(14.0);
        } else {
            child.add_space(14.0);
        }

        crate::theme::badge(&mut child, node.kind.badge(), p.kind_color(node.kind));

        if let Some(k) = &node.key {
            child.label(egui::RichText::new(k.as_str()).monospace().color(p.text));
            child.label(egui::RichText::new(":").color(p.dim));
        }

        let (body, body_color) = match node.kind {
            Kind::Object => (object_preview(a, node.children.clone()), p.dim),
            Kind::Array => (array_preview(a, node.children.clone()), p.dim),
            Kind::String => (
                format!("\"{}\"", truncate(node.value.as_deref().unwrap_or(""), 60)),
                p.kind_color(Kind::String),
            ),
            _ => (
                node.value.clone().unwrap_or_default(),
                p.kind_color(node.kind),
            ),
        };
        child.label(egui::RichText::new(body).monospace().color(body_color));

        // Full row click: containers toggle, leaves copy path.
        if row_resp.clicked() {
            if is_container {
                *toggle = Some(idx);
            } else {
                *copy = Some(node.path.clone());
            }
        }
        row_resp.on_hover_text(if is_container {
            format!("{}  (click to expand/collapse)", node.path)
        } else {
            format!("{}  (click to copy path)", node.path)
        });
    }
}

/// `{ key1, key2, … }` — show up to 3 object key names.
fn object_preview(a: &Arena, children: std::ops::Range<usize>) -> String {
    let count = children.len();
    if count == 0 {
        return "{}".to_string();
    }
    let keys: Vec<&str> = children
        .take(3)
        .filter_map(|i| a.nodes[i].key.as_deref())
        .collect();
    let preview = keys.join(", ");
    if count > 3 {
        format!("{{ {preview}, … }}")
    } else {
        format!("{{ {preview} }}")
    }
}

/// `[ N items ]` or `[ val, val, … ]` for small arrays.
fn array_preview(a: &Arena, children: std::ops::Range<usize>) -> String {
    let count = children.len();
    if count == 0 {
        return "[]".to_string();
    }
    // For small scalar arrays show the first 3 values inline.
    let all_scalar = children
        .clone()
        .all(|i| !matches!(a.nodes[i].kind, Kind::Object | Kind::Array));
    if all_scalar && count <= 5 {
        let vals: Vec<String> = children
            .take(3)
            .map(|i| {
                let n = &a.nodes[i];
                match n.kind {
                    Kind::String => format!("\"{}\"", truncate(n.value.as_deref().unwrap_or(""), 12)),
                    _ => n.value.clone().unwrap_or_default(),
                }
            })
            .collect();
        let preview = vals.join(", ");
        if count > 3 {
            format!("[ {preview}, … ]")
        } else {
            format!("[ {preview} ]")
        }
    } else {
        format!("[ {count} items ]")
    }
}

fn truncate(s: &str, max: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= max {
        s.to_string()
    } else {
        format!("{}…", chars[..max].iter().collect::<String>())
    }
}

// Silence unused import warning — Node is used in preview fns via a.nodes[i]
#[allow(dead_code)]
fn _use_node(_: &Node) {}
