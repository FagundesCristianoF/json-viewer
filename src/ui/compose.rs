//! Compose modal — write a JSON template with {{file.json}} placeholders,
//! preview the resolved output, and load it into the editor.

use crate::app::JsonViewApp;
use eframe::egui;

impl JsonViewApp {
    pub fn ui_compose(&mut self, ctx: &egui::Context) {
        if !self.show_compose {
            return;
        }
        let p = self.pal();
        let base_dir = self
            .selected
            .as_ref()
            .and_then(|f| f.parent().map(|p| p.to_path_buf()))
            .or_else(|| self.ws_root.clone());

        let mut open = true;
        egui::Window::new("Compose")
            .open(&mut open)
            .collapsible(false)
            .resizable(true)
            .min_width(620.0)
            .min_height(440.0)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.add_space(4.0);

                // ── Base dir hint ──────────────────────────────────
                let base_label = base_dir
                    .as_ref()
                    .map(|d| d.display().to_string())
                    .unwrap_or_else(|| "(no workspace — open a folder first)".to_string());
                ui.horizontal(|ui| {
                    ui.label(egui::RichText::new("Base dir:").color(p.dim).size(11.0));
                    ui.label(
                        egui::RichText::new(&base_label)
                            .monospace()
                            .size(11.0)
                            .color(p.dim),
                    );
                });
                ui.add_space(6.0);

                // ── Template editor ────────────────────────────────
                crate::theme::section_label(ui, "Template");
                ui.label(
                    egui::RichText::new("Use {{filename.json}} to include other files.")
                        .color(p.dim)
                        .size(11.0),
                );
                ui.add_space(4.0);
                let template_resp = ui.add(
                    egui::TextEdit::multiline(&mut self.compose_template)
                        .desired_width(f32::INFINITY)
                        .desired_rows(8)
                        .font(egui::TextStyle::Monospace)
                        .hint_text(
                            "{\n  \"products\": [\n    {{productA.json}},\n    {{productB.json}}\n  ]\n}",
                        ),
                );

                if template_resp.changed() {
                    self.update_compose_preview(base_dir.as_deref());
                }

                // ── Referenced files ───────────────────────────────
                let refs = crate::compose::referenced_files(&self.compose_template);
                if !refs.is_empty() {
                    ui.add_space(4.0);
                    ui.horizontal_wrapped(|ui| {
                        ui.label(egui::RichText::new("References:").color(p.dim).size(11.0));
                        for r in &refs {
                            crate::theme::badge(ui, r, p.accent);
                        }
                    });
                }

                ui.add_space(8.0);

                // ── Preview ────────────────────────────────────────
                crate::theme::section_label(ui, "Preview");

                match &self.compose_preview {
                    None => {
                        ui.label(
                            egui::RichText::new("Enter a template above to preview.")
                                .color(p.dim)
                                .size(12.0),
                        );
                    }
                    Some(Err(e)) => {
                        let err_color = p.kind_color(crate::model::Kind::Bool);
                        ui.label(egui::RichText::new(e).color(err_color).size(12.0));
                    }
                    Some(Ok(_)) => {
                        let preview = self.compose_preview
                            .as_ref()
                            .and_then(|r| r.as_ref().ok())
                            .cloned()
                            .unwrap_or_default();
                        egui::ScrollArea::vertical()
                            .id_source("compose_preview_scroll")
                            .max_height(160.0)
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

                // ── Actions ────────────────────────────────────────
                ui.horizontal(|ui| {
                    let can_apply = matches!(&self.compose_preview, Some(Ok(_)));
                    if ui
                        .add_enabled(can_apply, egui::Button::new("Load into editor"))
                        .clicked()
                    {
                        if let Some(Ok(result)) = self.compose_preview.take() {
                            self.editor_text = result;
                            self.dirty = true;
                            self.needs_parse = true;
                            self.last_edit = Some(std::time::Instant::now());
                            self.show_compose = false;
                            self.toast("Composed");
                        }
                    }

                    if ui.button("Refresh").clicked() {
                        let bd = base_dir.clone();
                        self.update_compose_preview(bd.as_deref());
                    }

                    if ui.button("Cancel").clicked() {
                        self.show_compose = false;
                    }
                });
            });

        if !open {
            self.show_compose = false;
        }
    }

    pub fn update_compose_preview(&mut self, base_dir: Option<&std::path::Path>) {
        let tmpl = self.compose_template.trim().to_string();
        if tmpl.is_empty() {
            self.compose_preview = None;
            return;
        }
        let Some(dir) = base_dir else {
            self.compose_preview = Some(Err("No base directory — open a workspace first.".to_string()));
            return;
        };
        self.compose_preview = Some(crate::compose::compose(&tmpl, dir, self.config.indent));
    }
}
