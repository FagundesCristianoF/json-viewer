//! Editable monospace text pane for the selected file, with JSON highlighting.

use crate::app::JsonViewApp;
use eframe::egui::{self, FontFamily, FontId};
use std::time::Instant;

const EDITOR_ID: &str = "main_editor";

impl JsonViewApp {
    pub fn ui_editor(&mut self, ctx: &egui::Context) {
        let p = self.pal();
        let frame = egui::Frame::none()
            .fill(p.window)
            .inner_margin(egui::Margin::symmetric(10.0, 8.0));

        egui::CentralPanel::default().frame(frame).show(ctx, |ui| {
            // ── Header row ────────────────────────────────────────
            ui.horizontal(|ui| {
                crate::theme::section_label(ui, self.t("editor.section"));
                if let Some(path) = &self.selected {
                    let breadcrumb = if let Some(root) = &self.ws_root {
                        path.strip_prefix(root)
                            .ok()
                            .map(|rel| {
                                rel.components()
                                    .map(|c| c.as_os_str().to_string_lossy())
                                    .collect::<Vec<_>>()
                                    .join(" / ")
                            })
                            .unwrap_or_else(|| {
                                path.file_name()
                                    .map(|n| n.to_string_lossy().to_string())
                                    .unwrap_or_default()
                            })
                    } else {
                        path.file_name()
                            .map(|n| n.to_string_lossy().to_string())
                            .unwrap_or_default()
                    };
                    ui.label(egui::RichText::new(breadcrumb).color(p.dim).size(11.0));
                }
                if !self.auto_save {
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.label(
                            egui::RichText::new(self.t("editor.save_hint"))
                                .color(p.dim)
                                .size(11.0),
                        );
                    });
                }
            });
            ui.add_space(4.0);

            // ── Search bar (Cmd+F) ─────────────────────────────────
            if self.show_editor_search {
                let esc = ui.input(|i| i.key_pressed(egui::Key::Escape));
                if esc {
                    self.show_editor_search = false;
                    self.editor_search.clear();
                    self.editor_search_matches.clear();
                }

                ui.horizontal(|ui| {
                    let r = ui.add(
                        egui::TextEdit::singleline(&mut self.editor_search)
                            .desired_width(220.0)
                            .font(egui::TextStyle::Monospace)
                            .hint_text("Search…"),
                    );

                    if r.changed() {
                        self.run_editor_search();
                    }

                    // Focus search bar when it first appears
                    if r.gained_focus() || self.show_editor_search {
                        r.request_focus();
                    }

                    let count = self.editor_search_matches.len();
                    if !self.editor_search.is_empty() {
                        let label = if count == 0 {
                            "no matches".to_string()
                        } else {
                            format!(
                                "{}/{}",
                                self.editor_search_idx + 1,
                                count
                            )
                        };
                        ui.label(egui::RichText::new(label).color(p.dim).size(11.0));
                    }

                    // Prev / Next
                    ui.add_enabled_ui(count > 1, |ui| {
                        if ui.small_button("↑").clicked()
                            || ui.input(|i| {
                                i.modifiers.shift && i.key_pressed(egui::Key::Enter)
                            })
                        {
                            if count > 0 {
                                self.editor_search_idx =
                                    (self.editor_search_idx + count - 1) % count;
                            }
                        }
                        if ui.small_button("↓").clicked()
                            || ui.input(|i| {
                                !i.modifiers.shift && i.key_pressed(egui::Key::Enter)
                            })
                        {
                            if count > 0 {
                                self.editor_search_idx =
                                    (self.editor_search_idx + 1) % count;
                            }
                        }
                    });

                    if crate::icons::button(
                        ui,
                        crate::icons::Icon::Close,
                        20.0,
                        p.dim,
                    )
                    .on_hover_text("Close (Esc)")
                    .clicked()
                    {
                        self.show_editor_search = false;
                        self.editor_search.clear();
                        self.editor_search_matches.clear();
                    }
                });
                ui.add_space(4.0);
            }

            // ── Editor ────────────────────────────────────────────
            let font = FontId::new(12.5, FontFamily::Monospace);
            let search_term = if self.show_editor_search {
                self.editor_search.clone()
            } else {
                String::new()
            };

            let mut layouter = {
                let p_clone = p;
                let font_clone = font.clone();
                let term = search_term.clone();
                move |ui: &egui::Ui, text: &str, wrap_width: f32| {
                    let job = crate::highlight::layout_job_search(
                        text,
                        &p_clone,
                        font_clone.clone(),
                        wrap_width,
                        &term,
                    );
                    ui.fonts(|f| f.layout_job(job))
                }
            };

            let editor_id = egui::Id::new(EDITOR_ID);

            // Scroll to current search match by placing cursor there
            if self.show_editor_search
                && !self.editor_search_matches.is_empty()
                && !self.editor_search.is_empty()
            {
                let byte_offset = self.editor_search_matches[self.editor_search_idx];
                let char_idx = self.editor_text[..byte_offset].chars().count();
                let mut state = egui::TextEdit::load_state(ctx, editor_id)
                    .unwrap_or_else(egui::text_edit::TextEditState::default);
                let cursor = egui::text::CCursor::new(char_idx);
                state
                    .cursor
                    .set_char_range(Some(egui::text::CCursorRange::one(cursor)));
                egui::TextEdit::store_state(ctx, editor_id, state);
            }

            egui::ScrollArea::both()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    let resp = ui.add_sized(
                        ui.available_size(),
                        egui::TextEdit::multiline(&mut self.editor_text)
                            .id(editor_id)
                            .code_editor()
                            .desired_width(f32::INFINITY)
                            .layouter(&mut layouter),
                    );
                    if resp.changed() {
                        self.dirty = true;
                        self.needs_parse = true;
                        self.last_edit = Some(Instant::now());
                        // keep search matches in sync while editing
                        if self.show_editor_search && !self.editor_search.is_empty() {
                            self.run_editor_search();
                        }
                    }
                });
        });
    }
}
