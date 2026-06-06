//! Template modal — select a .template.json, fill variables, preview, load into editor.

use crate::app::JsonViewApp;
use eframe::egui;

impl JsonViewApp {
    pub fn ui_template(&mut self, ctx: &egui::Context) {
        if !self.show_template {
            return;
        }
        let p = self.pal();
        let mut open = true;

        egui::Window::new("Template")
            .open(&mut open)
            .collapsible(false)
            .resizable(true)
            .min_width(580.0)
            .min_height(420.0)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.add_space(4.0);

                // ── Template file list ─────────────────────────────
                crate::theme::section_label(ui, "Template file");
                if self.template_files.is_empty() {
                    ui.label(
                        egui::RichText::new(
                            "No *.template.json files found in workspace. Create one to get started.",
                        )
                        .color(p.dim)
                        .size(11.0),
                    );
                } else {
                    egui::ScrollArea::vertical()
                        .id_source("tpl_file_list")
                        .max_height(96.0)
                        .auto_shrink([false, true])
                        .show(ui, |ui| {
                            let files = self.template_files.clone();
                            for path in &files {
                                let name = path
                                    .file_name()
                                    .map(|n| n.to_string_lossy().into_owned())
                                    .unwrap_or_default();
                                let selected = self.template_selected.as_deref() == Some(path.as_path());
                                let label = egui::RichText::new(&name)
                                    .monospace()
                                    .size(12.0)
                                    .color(if selected { p.accent } else { p.text });
                                if ui.selectable_label(selected, label).clicked() {
                                    let p_clone = path.clone();
                                    self.select_template(p_clone);
                                }
                            }
                        });
                }

                if self.template_selected.is_none() {
                    ui.add_space(10.0);
                    ui.horizontal(|ui| {
                        if ui.button("Cancel").clicked() {
                            self.show_template = false;
                        }
                    });
                    return;
                }

                ui.add_space(8.0);

                // ── Variables ──────────────────────────────────────
                crate::theme::section_label(ui, "Variables");

                if self.template_vars.is_empty() {
                    ui.label(
                        egui::RichText::new("No variables found — template has no {{varName}} placeholders.")
                            .color(p.dim)
                            .size(11.0),
                    );
                } else {
                    let mut changed = false;
                    let var_count = self.template_vars.len();
                    egui::Grid::new("tpl_vars_grid")
                        .num_columns(2)
                        .spacing([8.0, 4.0])
                        .show(ui, |ui| {
                            for i in 0..var_count {
                                let name = self.template_vars[i].0.clone();
                                let hint = format!("value for {name}");
                                ui.label(
                                    egui::RichText::new(&name)
                                        .monospace()
                                        .size(12.0)
                                        .color(p.accent),
                                );
                                let resp = ui.add(
                                    egui::TextEdit::singleline(&mut self.template_vars[i].1)
                                        .desired_width(320.0)
                                        .hint_text(hint),
                                );
                                if resp.changed() {
                                    changed = true;
                                }
                                ui.end_row();
                            }
                        });
                    if changed {
                        self.update_template_preview();
                    }
                }

                ui.add_space(8.0);

                // ── Preview button ─────────────────────────────────
                if ui.button("Preview").clicked() {
                    self.update_template_preview();
                }

                ui.add_space(6.0);

                // ── Preview ────────────────────────────────────────
                crate::theme::section_label(ui, "Preview");
                match &self.template_preview {
                    None => {
                        ui.label(
                            egui::RichText::new("Fill variables above and click Preview.")
                                .color(p.dim)
                                .size(12.0),
                        );
                    }
                    Some(Err(e)) => {
                        let err_color = p.kind_color(crate::model::Kind::Bool);
                        ui.label(egui::RichText::new(e).color(err_color).size(12.0));
                    }
                    Some(Ok(_)) => {
                        let preview = self
                            .template_preview
                            .as_ref()
                            .and_then(|r| r.as_ref().ok())
                            .cloned()
                            .unwrap_or_default();
                        egui::ScrollArea::vertical()
                            .id_source("tpl_preview_scroll")
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

                // ── Actions ────────────────────────────────────────
                ui.horizontal(|ui| {
                    let can_apply = matches!(&self.template_preview, Some(Ok(_)));
                    if ui
                        .add_enabled(can_apply, egui::Button::new("Load into editor"))
                        .clicked()
                    {
                        if let Some(Ok(result)) = self.template_preview.take() {
                            self.editor_text = result;
                            self.dirty = true;
                            self.needs_parse = true;
                            self.last_edit = Some(std::time::Instant::now());
                            self.show_template = false;
                            self.toast("Template applied");
                        }
                    }
                    if ui.button("Cancel").clicked() {
                        self.show_template = false;
                    }
                });
            });

        if !open {
            self.show_template = false;
        }
    }
}
