//! Editable monospace text pane for the selected file, with JSON highlighting.

use crate::app::JsonViewApp;
use eframe::egui::{self, FontFamily, FontId};
use std::time::Instant;

/// If `text_before_cursor` ends inside an unclosed `{{...`, return the byte
/// offset of `{{` in the full `editor_text` and the partial token typed so far.
fn detect_brace_token(full_text: &str, cursor_byte: usize) -> Option<(usize, String)> {
    let before = &full_text[..cursor_byte];
    let last_open = before.rfind("{{")?;
    let after_open = &before[last_open + 2..];
    // Already closed → not in autocomplete context
    if after_open.contains("}}") {
        return None;
    }
    Some((last_open, after_open.to_string()))
}

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
                                self.editor_search_navigate = true;
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
                                self.editor_search_navigate = true;
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

            // Compute scroll offset when navigation is requested
            let scroll_to: Option<f32> = if self.editor_search_navigate
                && !self.editor_search_matches.is_empty()
            {
                self.editor_search_navigate = false;
                let byte_offset = self.editor_search_matches[self.editor_search_idx];
                // Set cursor to match position
                let char_idx = self.editor_text[..byte_offset].chars().count();
                let mut state = egui::TextEdit::load_state(ctx, editor_id)
                    .unwrap_or_default();
                let cursor = egui::text::CCursor::new(char_idx);
                state.cursor.set_char_range(Some(
                    egui::text::CCursorRange::one(cursor),
                ));
                egui::TextEdit::store_state(ctx, editor_id, state);
                // Compute line-based scroll offset
                let line = self.editor_text[..byte_offset]
                    .bytes()
                    .filter(|&b| b == b'\n')
                    .count();
                Some((line as f32 * 18.0 - 80.0).max(0.0))
            } else {
                None
            };

            let mut scroll_area = egui::ScrollArea::both().auto_shrink([false, false]);
            if let Some(y) = scroll_to {
                scroll_area = scroll_area.scroll_offset(egui::vec2(0.0, y));
            }

            // Viewport rect in screen coords — needed to position the AC popup
            let viewport_rect = ui.available_rect_before_wrap();

            let sa_output = scroll_area.show(ui, |ui| {
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
                        if self.show_editor_search && !self.editor_search.is_empty() {
                            self.run_editor_search();
                        }
                    }

                    // Detect {{ autocomplete context from cursor position
                    if let Some(state) = egui::TextEdit::load_state(ctx, editor_id) {
                        if let Some(range) = state.cursor.char_range() {
                            let char_idx = range.primary.index;
                            let byte_offset = self.editor_text
                                .char_indices()
                                .nth(char_idx)
                                .map(|(i, _)| i)
                                .unwrap_or(self.editor_text.len());
                            match detect_brace_token(&self.editor_text, byte_offset) {
                                Some((pos, partial)) => {
                                    self.editor_ac_pos = Some(pos);
                                    self.editor_ac_partial = partial;
                                }
                                None => {
                                    self.editor_ac_pos = None;
                                    self.editor_ac_partial.clear();
                                }
                            }
                        }
                    }
                });

            // ── Autocomplete popup ────────────────────────────────
            if self.editor_ac_pos.is_some() && !self.compose_ws_files.is_empty() {
                let partial = self.editor_ac_partial.to_lowercase();
                let current_name = self.selected.as_ref()
                    .and_then(|p| p.file_name())
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_default();

                let suggestions: Vec<String> = self.compose_ws_files.iter()
                    .filter(|f| {
                        let basename = std::path::Path::new(f)
                            .file_name()
                            .map(|n| n.to_string_lossy().into_owned())
                            .unwrap_or_default();
                        basename != current_name
                            && (partial.is_empty()
                                || f.to_lowercase().contains(&partial))
                    })
                    .cloned()
                    .collect();

                if !suggestions.is_empty() {
                    // Compute cursor screen position from line/col + scroll offset
                    let ac_byte = self.editor_ac_pos.unwrap_or(0);
                    let cursor_line = self.editor_text[..ac_byte]
                        .bytes().filter(|&b| b == b'\n').count();
                    let cursor_col = self.editor_text[..ac_byte]
                        .rfind('\n')
                        .map(|nl| ac_byte - nl - 1)
                        .unwrap_or(ac_byte);
                    let line_h = 18.0_f32;
                    let char_w = 7.5_f32; // IBM Plex Mono 12.5px approx
                    let scroll_offset = sa_output.state.offset;
                    let popup_x = (viewport_rect.min.x
                        + cursor_col as f32 * char_w
                        - scroll_offset.x
                        + 8.0)
                        .clamp(viewport_rect.min.x + 4.0, viewport_rect.max.x - 320.0);
                    let raw_y = viewport_rect.min.y
                        + (cursor_line + 1) as f32 * line_h
                        - scroll_offset.y;
                    // Flip above cursor if not enough space below
                    let popup_y = if raw_y + 180.0 > viewport_rect.max.y {
                        raw_y - line_h - 180.0
                    } else {
                        raw_y
                    }.clamp(viewport_rect.min.y, viewport_rect.max.y - 40.0);

                    let popup_pos = egui::pos2(popup_x, popup_y);
                    let ac_id = egui::Id::new("editor_ac_popup");
                    egui::Area::new(ac_id)
                        .fixed_pos(popup_pos)
                        .order(egui::Order::Foreground)
                        .show(ctx, |ui| {
                            let p = self.pal();
                            egui::Frame::none()
                                .fill(p.sidebar)
                                .stroke(egui::Stroke::new(1.0, p.sep))
                                .rounding(egui::Rounding::same(6.0))
                                .inner_margin(egui::Margin::same(6.0))
                                .show(ui, |ui| {
                                    ui.set_max_width(300.0);
                                    ui.label(
                                        egui::RichText::new("Insert file")
                                            .size(10.0)
                                            .color(p.dim),
                                    );
                                    ui.add_space(2.0);
                                    let mut chosen: Option<String> = None;
                                    for f in suggestions.iter().take(8) {
                                        let basename = std::path::Path::new(f)
                                            .file_name()
                                            .map(|n| n.to_string_lossy().into_owned())
                                            .unwrap_or_else(|| f.clone());
                                        let label = egui::RichText::new(&basename)
                                            .monospace()
                                            .size(12.0)
                                            .color(p.text);
                                        if ui.selectable_label(false, label).clicked() {
                                            chosen = Some(f.clone());
                                        }
                                    }
                                    if let Some(file) = chosen {
                                        if let Some(pos) = self.editor_ac_pos {
                                            let end = pos + 2 + self.editor_ac_partial.len();
                                            let replacement = format!("{{{{{}}}}}", file);
                                            self.editor_text.replace_range(pos..end, &replacement);
                                            self.dirty = true;
                                            self.needs_parse = true;
                                            self.last_edit = Some(Instant::now());
                                            self.editor_ac_pos = None;
                                            self.editor_ac_partial.clear();
                                            // place cursor after inserted token
                                            let new_cursor_byte = pos + replacement.len();
                                            let char_idx = self.editor_text[..new_cursor_byte].chars().count();
                                            let mut st = egui::TextEdit::load_state(ctx, editor_id)
                                                .unwrap_or_default();
                                            let c = egui::text::CCursor::new(char_idx);
                                            st.cursor.set_char_range(Some(
                                                egui::text::CCursorRange::one(c),
                                            ));
                                            egui::TextEdit::store_state(ctx, editor_id, st);
                                        }
                                    }
                                });
                        });
                }
            }
        });
    }
}
