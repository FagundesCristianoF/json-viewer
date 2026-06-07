//! Editable monospace text pane for the selected file, with JSON highlighting.

use crate::app::JsonViewApp;
use eframe::egui::{self, FontFamily, FontId, Rect, pos2, vec2};
use std::time::Instant;

/// If `text_before_cursor` ends inside an unclosed `{{...`, return the byte
/// offset of `{{` in the full `editor_text` and the partial token typed so far.
fn detect_brace_token(full_text: &str, cursor_byte: usize) -> Option<(usize, String)> {
    let before = &full_text[..cursor_byte];
    let last_open = before.rfind("{{")?;
    let after_open = &before[last_open + 2..];
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
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if !self.auto_save {
                        ui.label(
                            egui::RichText::new(self.t("editor.save_hint"))
                                .color(p.dim)
                                .size(11.0),
                        );
                    }
                    let is_compose = self.editor_text.contains("{{") && self.editor_text.contains("}}");
                    if is_compose {
                        let raw_active = self.editor_raw_mode;
                        let stroke = egui::Stroke::new(1.5, p.accent);

                        // Right-to-left: Result drawn first = rightmost
                        let result_color = if !raw_active { p.text } else { p.dim };
                        let result_resp = ui.add(
                            egui::Label::new(
                                egui::RichText::new("Result").size(11.0).color(result_color).monospace(),
                            )
                            .sense(egui::Sense::click()),
                        );
                        let result_rect = result_resp.rect;
                        if result_resp.clicked() && (raw_active || self.pointer_resolved.is_none()) {
                            self.editor_raw_mode = false;
                            self.refresh_pointer_resolved();
                        }

                        ui.add_space(4.0);

                        let raw_color = if raw_active { p.text } else { p.dim };
                        let raw_resp = ui.add(
                            egui::Label::new(
                                egui::RichText::new("Raw").size(11.0).color(raw_color).monospace(),
                            )
                            .sense(egui::Sense::click()),
                        );
                        let raw_rect = raw_resp.rect;
                        if raw_resp.clicked() && !raw_active {
                            self.editor_raw_mode = true;
                            self.reparse();
                        }

                        ui.add_space(8.0);

                        let painter = ui.painter();
                        if raw_active {
                            painter.line_segment(
                                [egui::pos2(raw_rect.left(), raw_rect.bottom() + 1.0), egui::pos2(raw_rect.right(), raw_rect.bottom() + 1.0)],
                                stroke,
                            );
                        } else {
                            painter.line_segment(
                                [egui::pos2(result_rect.left(), result_rect.bottom() + 1.0), egui::pos2(result_rect.right(), result_rect.bottom() + 1.0)],
                                stroke,
                            );
                        }
                    }
                });
            });
            ui.add_space(4.0);

            // ── Search / Replace bar (Cmd+F / Cmd+H) ──────────────
            if self.show_editor_search {
                let esc = ui.input(|i| i.key_pressed(egui::Key::Escape));
                if esc {
                    self.show_editor_search = false;
                    self.show_editor_replace = false;
                    self.editor_search.clear();
                    self.editor_search_matches.clear();
                    self.editor_replace.clear();
                }

                ui.horizontal(|ui| {
                    let r = ui.add(
                        egui::TextEdit::singleline(&mut self.editor_search)
                            .desired_width(220.0)
                            .font(egui::TextStyle::Monospace)
                            .hint_text("Find…"),
                    );
                    if r.changed() {
                        self.run_editor_search();
                    }
                    if r.gained_focus() || self.show_editor_search {
                        r.request_focus();
                    }

                    let count = self.editor_search_matches.len();
                    if !self.editor_search.is_empty() {
                        let label = if count == 0 {
                            "no matches".to_string()
                        } else {
                            format!("{}/{}", self.editor_search_idx + 1, count)
                        };
                        ui.label(egui::RichText::new(label).color(p.dim).size(11.0));
                    }

                    ui.add_enabled_ui(count > 1, |ui| {
                        if ui.small_button("↑").clicked()
                            || ui.input(|i| i.modifiers.shift && i.key_pressed(egui::Key::Enter))
                        {
                            if count > 0 {
                                self.editor_search_idx =
                                    (self.editor_search_idx + count - 1) % count;
                                self.editor_search_navigate = true;
                            }
                        }
                        if ui.small_button("↓").clicked()
                            || ui.input(|i| !i.modifiers.shift && i.key_pressed(egui::Key::Enter))
                        {
                            if count > 0 {
                                self.editor_search_idx =
                                    (self.editor_search_idx + 1) % count;
                                self.editor_search_navigate = true;
                            }
                        }
                    });

                    let replace_label = if self.show_editor_replace { "▾ Replace" } else { "▸ Replace" };
                    if ui.small_button(replace_label).clicked() {
                        self.show_editor_replace = !self.show_editor_replace;
                    }

                    if crate::icons::button(ui, crate::icons::Icon::Close, 20.0, p.dim)
                        .on_hover_text("Close (Esc)")
                        .clicked()
                    {
                        self.show_editor_search = false;
                        self.show_editor_replace = false;
                        self.editor_search.clear();
                        self.editor_search_matches.clear();
                        self.editor_replace.clear();
                    }
                });

                if self.show_editor_replace {
                    ui.horizontal(|ui| {
                        ui.add(
                            egui::TextEdit::singleline(&mut self.editor_replace)
                                .desired_width(220.0)
                                .font(egui::TextStyle::Monospace)
                                .hint_text("Replace with…"),
                        );
                        let has_match = !self.editor_search_matches.is_empty()
                            && !self.editor_search.is_empty();
                        if ui.add_enabled(has_match, egui::Button::new("Replace")).clicked() {
                            self.replace_current();
                        }
                        if ui.add_enabled(has_match, egui::Button::new("Replace All")).clicked() {
                            self.replace_all();
                        }
                    });
                }
                ui.add_space(4.0);
            }

            // ── Editor ────────────────────────────────────────────
            let font = FontId::new(12.5, FontFamily::Monospace);
            let search_term = if self.show_editor_search {
                self.editor_search.clone()
            } else {
                String::new()
            };

            // Compute fold ranges (cheap linear scan)
            let fold_ranges = crate::folding::scan_fold_ranges(&self.editor_text);
            let has_foldable = !fold_ranges.is_empty();

            // Build display text if any lines are folded
            let (display_text, real_line_map) = if !self.folded_lines.is_empty() {
                crate::folding::build_display_text(&self.editor_text, &self.folded_lines, &fold_ranges)
            } else {
                (self.editor_text.clone(), (0..self.editor_text.lines().count()).collect())
            };
            let folds_active = !self.folded_lines.is_empty();

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

            // Scroll to current search match
            let scroll_to: Option<f32> = if self.editor_search_navigate
                && !self.editor_search_matches.is_empty()
            {
                self.editor_search_navigate = false;
                let byte_offset = self.editor_search_matches[self.editor_search_idx];
                let char_idx = self.editor_text[..byte_offset].chars().count();
                let mut state = egui::TextEdit::load_state(ctx, editor_id).unwrap_or_default();
                let cursor = egui::text::CCursor::new(char_idx);
                state.cursor.set_char_range(Some(egui::text::CCursorRange::one(cursor)));
                egui::TextEdit::store_state(ctx, editor_id, state);
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

            // ── Intercept autocomplete keys BEFORE TextEdit renders ──
            let ac_showing = self.editor_ac_pos.is_some() && !self.compose_ws_files.is_empty();
            let (ac_up, ac_down, ac_enter, ac_tab, ac_esc) = if ac_showing {
                let mut up = false;
                let mut down = false;
                let mut enter = false;
                let mut tab = false;
                let mut esc = false;
                ctx.input_mut(|i| {
                    let mut remove = Vec::new();
                    for (idx, e) in i.events.iter().enumerate() {
                        match e {
                            egui::Event::Key { key: egui::Key::ArrowUp, pressed: true, .. } => { up = true; remove.push(idx); }
                            egui::Event::Key { key: egui::Key::ArrowDown, pressed: true, .. } => { down = true; remove.push(idx); }
                            egui::Event::Key { key: egui::Key::Enter, pressed: true, .. } => { enter = true; remove.push(idx); }
                            egui::Event::Key { key: egui::Key::Tab, pressed: true, .. } => { tab = true; remove.push(idx); }
                            egui::Event::Key { key: egui::Key::Escape, pressed: true, .. } => { esc = true; remove.push(idx); }
                            egui::Event::Text(t) if t == "\n" || t == "\r\n" || t == "\r" => { enter = true; remove.push(idx); }
                            _ => {}
                        }
                    }
                    for idx in remove.into_iter().rev() {
                        i.events.remove(idx);
                    }
                });
                (up, down, enter, tab, esc)
            } else {
                (false, false, false, false, false)
            };

            // ── Layout: gutter strip + editor ─────────────────────
            let full_rect = ui.available_rect_before_wrap();
            let line_h: f32 = 18.0;
            let gutter_w: f32 = if has_foldable { 16.0 } else { 0.0 };

            let editor_area = Rect::from_min_max(
                pos2(full_rect.min.x + gutter_w, full_rect.min.y),
                full_rect.max,
            );

            let viewport_rect = editor_area;

            // Result view (selectable but not persisted)
            let in_result_mode = self.pointer_resolved.is_some() && !self.editor_raw_mode;

            let sa_output = ui.allocate_ui_at_rect(editor_area, |ui| {
                if in_result_mode {
                    let resolved = self.pointer_resolved.clone().unwrap_or_default();
                    let mut display = resolved;
                    scroll_area.show(ui, |ui| {
                        ui.add_sized(
                            ui.available_size(),
                            egui::TextEdit::multiline(&mut display)
                                .id(editor_id)
                                .code_editor()
                                .desired_width(f32::INFINITY)
                                // No interactive(false) → text is selectable/copyable
                                .layouter(&mut layouter),
                        )
                    })
                } else if folds_active {
                    // Read-only collapsed view — click anywhere to unfold all
                    let mut dt = display_text.clone();
                    let sa = scroll_area.show(ui, |ui| {
                        ui.add_sized(
                            ui.available_size(),
                            egui::TextEdit::multiline(&mut dt)
                                .id(editor_id)
                                .code_editor()
                                .desired_width(f32::INFINITY)
                                .interactive(false)
                                .layouter(&mut layouter),
                        )
                    });
                    sa
                } else {
                    // Normal editable mode
                    scroll_area.show(ui, |ui| {
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

                        // Update autocomplete context from cursor position
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
                                        if self.editor_ac_idx.is_none() {
                                            self.editor_ac_idx = Some(0);
                                        }
                                    }
                                    None => {
                                        self.editor_ac_pos = None;
                                        self.editor_ac_partial.clear();
                                        self.editor_ac_idx = None;
                                    }
                                }
                            }
                        }
                        resp
                    })
                }
            }).inner;

            // ── Gutter: fold chevrons ──────────────────────────────
            if has_foldable {
                let scroll_y = sa_output.state.offset.y;
                let gutter_rect = Rect::from_min_size(
                    full_rect.min,
                    vec2(gutter_w, full_rect.height()),
                );

                // Subtle gutter background
                ui.painter().rect_filled(gutter_rect, egui::Rounding::ZERO, p.sidebar);

                // Collect toggle decisions (can't mutate self inside iterator)
                let mut toggle_line: Option<usize> = None;

                for range in &fold_ranges {
                    let is_folded = self.folded_lines.contains(&range.start_line);
                    let display_line = if folds_active {
                        crate::folding::real_to_display_line(range.start_line, &real_line_map)
                    } else {
                        range.start_line
                    };

                    let cy = gutter_rect.min.y
                        + display_line as f32 * line_h
                        - scroll_y
                        + line_h * 0.5;

                    if cy < gutter_rect.min.y - line_h || cy > gutter_rect.max.y + line_h {
                        continue;
                    }

                    let cx = gutter_rect.center().x;

                    // Interaction first (ui.interact doesn't allocate layout space)
                    let hit_rect = Rect::from_center_size(pos2(cx, cy), vec2(gutter_w, line_h));
                    let chevron_id = egui::Id::new("fold_chevron").with(range.start_line);
                    let resp = ui.interact(hit_rect, chevron_id, egui::Sense::click());
                    if resp.clicked() {
                        toggle_line = Some(range.start_line);
                    }
                    if resp.hovered() {
                        ctx.set_cursor_icon(egui::CursorIcon::PointingHand);
                    }

                    // Paint chevron on top
                    let color = if resp.hovered() { p.text } else if is_folded { p.accent } else { p.dim };
                    let s = 5.0_f32;
                    if is_folded {
                        // ▶ right-pointing
                        ui.painter().add(egui::Shape::convex_polygon(
                            vec![
                                pos2(cx - s * 0.6, cy - s),
                                pos2(cx + s * 0.6, cy),
                                pos2(cx - s * 0.6, cy + s),
                            ],
                            color,
                            egui::Stroke::NONE,
                        ));
                    } else {
                        // ▼ down-pointing
                        ui.painter().add(egui::Shape::convex_polygon(
                            vec![
                                pos2(cx - s, cy - s * 0.4),
                                pos2(cx + s, cy - s * 0.4),
                                pos2(cx, cy + s * 0.6),
                            ],
                            color,
                            egui::Stroke::NONE,
                        ));
                    }
                }

                if let Some(line) = toggle_line {
                    if self.folded_lines.contains(&line) {
                        self.folded_lines.remove(&line);
                    } else {
                        self.folded_lines.insert(line);
                    }
                }
            }

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
                            && (partial.is_empty() || f.to_lowercase().contains(&partial))
                    })
                    .cloned()
                    .collect();

                if !suggestions.is_empty() {
                    let n = suggestions.len();

                    // Apply navigation state from pre-captured keys
                    if ac_esc {
                        self.editor_ac_pos = None;
                        self.editor_ac_partial.clear();
                        self.editor_ac_idx = None;
                    }
                    if ac_down {
                        self.editor_ac_idx = Some(
                            self.editor_ac_idx.map(|i| (i + 1) % n).unwrap_or(0)
                        );
                    }
                    if ac_up {
                        self.editor_ac_idx = Some(
                            self.editor_ac_idx.map(|i| (i + n - 1) % n).unwrap_or(n - 1)
                        );
                    }

                    // Key-triggered insertion (resolved before entering the Area closure)
                    let key_chosen: Option<String> = if ac_enter || ac_tab {
                        let idx = self.editor_ac_idx.unwrap_or(0);
                        suggestions.get(idx).cloned()
                    } else {
                        None
                    };

                    // Cursor screen position for popup placement
                    let ac_byte = self.editor_ac_pos.unwrap_or(0);
                    let cursor_line = self.editor_text[..ac_byte]
                        .bytes().filter(|&b| b == b'\n').count();
                    let cursor_col = self.editor_text[..ac_byte]
                        .rfind('\n')
                        .map(|nl| ac_byte - nl - 1)
                        .unwrap_or(ac_byte);
                    let scroll_offset = sa_output.state.offset;
                    let popup_x = (viewport_rect.min.x
                        + cursor_col as f32 * 7.5
                        - scroll_offset.x
                        + 8.0)
                        .clamp(viewport_rect.min.x + 4.0, viewport_rect.max.x - 320.0);
                    let raw_y = viewport_rect.min.y
                        + (cursor_line + 1) as f32 * 18.0
                        - scroll_offset.y;
                    let popup_y = if raw_y + 180.0 > viewport_rect.max.y {
                        raw_y - 18.0 - 180.0
                    } else {
                        raw_y
                    }.clamp(viewport_rect.min.y, viewport_rect.max.y - 40.0);

                    // Collect mouse-click choice from the popup
                    let mut mouse_chosen: Option<String> = None;
                    let ac_id = egui::Id::new("editor_ac_popup");
                    egui::Area::new(ac_id)
                        .fixed_pos(egui::pos2(popup_x, popup_y))
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
                                        egui::RichText::new("Insert file  ↑↓ navigate · Enter insert · Esc close")
                                            .size(10.0)
                                            .color(p.dim),
                                    );
                                    ui.add_space(2.0);
                                    for (i, f) in suggestions.iter().take(8).enumerate() {
                                        let selected = Some(i) == self.editor_ac_idx;
                                        let basename = std::path::Path::new(f)
                                            .file_name()
                                            .map(|n| n.to_string_lossy().into_owned())
                                            .unwrap_or_else(|| f.clone());
                                        let label = egui::RichText::new(&basename)
                                            .monospace()
                                            .size(12.0)
                                            .color(p.text);
                                        if ui.selectable_label(selected, label).clicked() {
                                            mouse_chosen = Some(f.clone());
                                        }
                                    }
                                });
                        });

                    // ── Perform insertion (outside all closures) ──────
                    let file_to_insert = mouse_chosen.or(key_chosen);
                    if let Some(file) = file_to_insert {
                        if let Some(pos) = self.editor_ac_pos {
                            let end = pos + 2 + self.editor_ac_partial.len();
                            let replacement = format!("{{{{{}}}}}", file);
                            self.editor_text.replace_range(pos..end, &replacement);
                            self.dirty = true;
                            self.needs_parse = true;
                            self.last_edit = Some(Instant::now());
                            self.editor_ac_pos = None;
                            self.editor_ac_partial.clear();
                            self.editor_ac_idx = None;
                            let new_cursor_byte = pos + replacement.len();
                            let char_idx = self.editor_text[..new_cursor_byte].chars().count();
                            let mut st = egui::TextEdit::load_state(ctx, editor_id).unwrap_or_default();
                            let c = egui::text::CCursor::new(char_idx);
                            st.cursor.set_char_range(Some(egui::text::CCursorRange::one(c)));
                            egui::TextEdit::store_state(ctx, editor_id, st);
                        }
                    }
                }
            }
        });
    }

    pub fn replace_current(&mut self) {
        let count = self.editor_search_matches.len();
        if count == 0 || self.editor_search.is_empty() {
            return;
        }
        let byte_offset = self.editor_search_matches[self.editor_search_idx];
        let search_len = self.editor_search.len();
        let replacement = self.editor_replace.clone();
        self.editor_text.replace_range(byte_offset..byte_offset + search_len, &replacement);
        self.dirty = true;
        self.needs_parse = true;
        self.last_edit = Some(Instant::now());
        self.run_editor_search();
        let new_count = self.editor_search_matches.len();
        if new_count > 0 {
            self.editor_search_idx = self.editor_search_idx.min(new_count - 1);
        }
        self.editor_search_navigate = true;
    }

    pub fn replace_all(&mut self) {
        if self.editor_search.is_empty() {
            return;
        }
        let search = self.editor_search.clone();
        let replacement = self.editor_replace.clone();
        let lower_text = self.editor_text.to_lowercase();
        let lower_search = search.to_lowercase();
        let mut result = String::with_capacity(self.editor_text.len());
        let mut last = 0;
        let mut start = 0;
        while let Some(pos) = lower_text[start..].find(&lower_search) {
            let abs = start + pos;
            result.push_str(&self.editor_text[last..abs]);
            result.push_str(&replacement);
            last = abs + search.len();
            start = last;
        }
        result.push_str(&self.editor_text[last..]);
        if result != self.editor_text {
            self.editor_text = result;
            self.dirty = true;
            self.needs_parse = true;
            self.last_edit = Some(Instant::now());
            self.run_editor_search();
            self.toast("Replaced all");
        }
    }
}
