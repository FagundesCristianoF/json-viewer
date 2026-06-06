//! Git history panel — two-column layout: commit list + content preview.

use crate::app::JsonViewApp;
use eframe::egui;

impl JsonViewApp {
    /// Renders the body of the History tab (called from ui_bottom when that tab is active).
    pub fn ui_history_body(&mut self, ui: &mut egui::Ui) {
        let p = self.pal();

        if self.history.is_empty() {
            ui.add_space(8.0);
            ui.label(
                egui::RichText::new(self.t("history.no_commits"))
                    .color(p.dim)
                    .size(12.0),
            );
            return;
        }

        // Split: left list (~220px) | right preview (rest)
        let available = ui.available_size();
        let list_w = 220.0_f32.min(available.x * 0.4);

        ui.horizontal(|ui| {
            // ── Commit list ──────────────────────────────────────────
            egui::ScrollArea::vertical()
                .id_source("history_list")
                .max_height(available.y - 4.0)
                .max_width(list_w)
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    ui.set_min_width(list_w);
                    let history = self.history.clone();
                    for commit in &history {
                        let selected = self.history_selected.as_deref() == Some(&commit.hash);
                        let row_h = 40.0;
                        let (row_rect, resp) = ui.allocate_exact_size(
                            egui::vec2(list_w - 8.0, row_h),
                            egui::Sense::click(),
                        );

                        // Background
                        let bg = if selected {
                            Some(p.sel)
                        } else if resp.hovered() {
                            Some(p.hover)
                        } else {
                            None
                        };
                        if let Some(color) = bg {
                            ui.painter().rect_filled(row_rect, egui::Rounding::same(4.0), color);
                        }

                        let mut child = ui.child_ui(
                            row_rect,
                            egui::Layout::top_down(egui::Align::LEFT),
                            None,
                        );
                        child.add_space(4.0);
                        child.horizontal(|ui| {
                            ui.add_space(6.0);
                            ui.label(
                                egui::RichText::new(&commit.hash)
                                    .monospace()
                                    .size(11.0)
                                    .color(p.accent),
                            );
                            ui.add_space(4.0);
                            ui.label(
                                egui::RichText::new(&commit.relative)
                                    .size(10.0)
                                    .color(p.dim),
                            );
                        });
                        child.horizontal(|ui| {
                            ui.add_space(6.0);
                            let msg = truncate(&commit.message, 32);
                            ui.label(
                                egui::RichText::new(msg)
                                    .size(11.5)
                                    .color(if selected { p.text } else { p.dim }),
                            );
                        });

                        if resp.clicked() {
                            if selected {
                                // Deselect
                                self.history_selected = None;
                                self.history_preview = None;
                            } else {
                                // Load preview from git
                                let preview = self.ws_root.as_ref()
                                    .and_then(|ws| self.selected.as_ref().map(|f| (ws.clone(), f.clone())))
                                    .and_then(|(ws, file)| {
                                        crate::git::show(&ws, &commit.hash, &file).ok()
                                    });
                                self.history_selected = Some(commit.hash.clone());
                                self.history_preview = preview;
                            }
                        }
                    }
                });

            ui.separator();

            // ── Content preview ──────────────────────────────────────
            let preview_w = ui.available_width();
            ui.vertical(|ui| {
                if let Some(preview) = &self.history_preview {
                    let restore_label = self.t("history.restore");
                    if ui.small_button(restore_label).clicked() {
                        self.editor_text = preview.clone();
                        self.dirty = true;
                        self.needs_parse = true;
                        self.last_edit = Some(std::time::Instant::now());
                        self.history_preview = None;
                        self.history_selected = None;
                        self.toast(self.t("toast.restored"));
                    }
                    ui.add_space(4.0);
                    let preview_text = self.history_preview.clone().unwrap_or_default();
                    egui::ScrollArea::both()
                        .id_source("history_preview")
                        .auto_shrink([false, false])
                        .show(ui, |ui| {
                            ui.set_min_width(preview_w - 8.0);
                            let mut text = preview_text;
                            ui.add(
                                egui::TextEdit::multiline(&mut text)
                                    .font(egui::TextStyle::Monospace)
                                    .desired_width(f32::INFINITY)
                                    .interactive(false),
                            );
                        });
                } else {
                    ui.add_space(8.0);
                    ui.label(
                        egui::RichText::new("Select a commit to preview")
                            .color(p.dim)
                            .size(12.0),
                    );
                }
            });
        });
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        format!("{}…", s.chars().take(max).collect::<String>())
    }
}
