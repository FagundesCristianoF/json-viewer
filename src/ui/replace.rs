//! "Replace by JSONPath" modal.
//!
//! Two inputs: a JSONPath selector (used as the ID/key) and replacement JSON.
//! Live preview shows the result; Apply writes it to the editor.

use crate::app::JsonViewApp;
use eframe::egui;

impl JsonViewApp {
    pub fn ui_replace(&mut self, ctx: &egui::Context) {
        if !self.show_replace {
            return;
        }
        let p = self.pal();

        let mut open = true;
        egui::Window::new("Replace by JSONPath")
            .open(&mut open)
            .collapsible(false)
            .resizable(true)
            .min_width(560.0)
            .min_height(400.0)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.add_space(4.0);

                // ── Inputs ────────────────────────────────────────────
                crate::theme::section_label(ui, "JSONPath selector");
                let path_resp = ui.add(
                    egui::TextEdit::singleline(&mut self.replace_path)
                        .desired_width(f32::INFINITY)
                        .font(egui::TextStyle::Monospace)
                        .hint_text("$.a[?(@.id == \"x\")]"),
                );

                ui.add_space(8.0);
                crate::theme::section_label(ui, "Replacement JSON");
                let repl_resp = ui.add(
                    egui::TextEdit::multiline(&mut self.replace_content)
                        .desired_width(f32::INFINITY)
                        .desired_rows(5)
                        .font(egui::TextStyle::Monospace)
                        .hint_text("{ \"id\": \"x\", \"type\": \"new\" }"),
                );

                // Recompute preview whenever either input changes.
                if path_resp.changed() || repl_resp.changed() {
                    self.update_replace_preview();
                }

                ui.add_space(8.0);

                // ── Preview ───────────────────────────────────────────
                crate::theme::section_label(ui, "Preview");

                match &self.replace_preview {
                    None => {
                        ui.label(
                            egui::RichText::new("Enter a path and replacement above.")
                                .color(p.dim)
                                .size(12.0),
                        );
                    }
                    Some(Err(e)) => {
                        let err_color = p.kind_color(crate::model::Kind::Bool);
                        ui.label(egui::RichText::new(e).color(err_color).size(12.0));
                    }
                    Some(Ok(_)) => {
                        let preview = self.replace_preview.as_ref()
                            .and_then(|r| r.as_ref().ok())
                            .cloned()
                            .unwrap_or_default();
                        egui::ScrollArea::vertical()
                            .id_source("replace_preview_scroll")
                            .max_height(180.0)
                            .auto_shrink([false, false])
                            .show(ui, |ui| {
                                let mut text = preview;
                                ui.add(
                                    egui::TextEdit::multiline(&mut text)
                                        .font(egui::TextStyle::Monospace)
                                        .desired_width(f32::INFINITY)
                                        .interactive(false),
                                );
                            });
                    }
                }

                ui.add_space(10.0);

                // ── Actions ───────────────────────────────────────────
                ui.horizontal(|ui| {
                    let can_apply = matches!(&self.replace_preview, Some(Ok(_)));
                    if ui
                        .add_enabled(can_apply, egui::Button::new("Apply"))
                        .clicked()
                    {
                        if let Some(Ok(result)) = self.replace_preview.take() {
                            self.editor_text = result;
                            self.dirty = true;
                            self.needs_parse = true;
                            self.last_edit = Some(std::time::Instant::now());
                            self.show_replace = false;
                            self.replace_path.clear();
                            self.replace_content.clear();
                            self.toast("Replaced");
                        }
                    }
                    if ui.button("Cancel").clicked() {
                        self.show_replace = false;
                    }
                });
            });

        if !open {
            self.show_replace = false;
        }
    }

    /// Recompute the replace preview from current path + content inputs.
    pub fn update_replace_preview(&mut self) {
        let path = self.replace_path.trim().to_string();
        let content = self.replace_content.trim().to_string();

        if path.is_empty() || content.is_empty() {
            self.replace_preview = None;
            return;
        }

        let result = crate::parser::json_replace(
            &self.editor_text,
            &path,
            &content,
            self.config.indent,
        )
        .map_err(|e| e);

        self.replace_preview = Some(result);
    }
}
