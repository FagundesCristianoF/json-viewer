//! Editable monospace text pane for the selected file, with JSON highlighting.

use crate::app::JsonViewApp;
use eframe::egui::{self, FontFamily, FontId};
use std::time::Instant;

impl JsonViewApp {
    pub fn ui_editor(&mut self, ctx: &egui::Context) {
        let p = self.pal();
        let frame = egui::Frame::none()
            .fill(p.window)
            .inner_margin(egui::Margin::symmetric(10.0, 8.0));
        egui::CentralPanel::default().frame(frame).show(ctx, |ui| {
            ui.horizontal(|ui| {
                crate::theme::section_label(ui, self.t("editor.section"));
                // Breadcrumb: workspace_root / folder / file.json
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
                    ui.label(
                        egui::RichText::new(breadcrumb)
                            .color(p.dim)
                            .size(11.0),
                    );
                }
                if !self.auto_save {
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.label(egui::RichText::new(self.t("editor.save_hint")).color(p.dim).size(11.0));
                    });
                }
            });
            ui.add_space(4.0);

            // In filter mode with matches: show read-only projection, not raw text.
            if let Some(filtered) = self.filtered_json() {
                let font = FontId::new(12.5, FontFamily::Monospace);
                let mut text = filtered;
                let mut layouter = |ui: &egui::Ui, txt: &str, wrap_width: f32| {
                    let job = crate::highlight::layout_job(txt, &p, font.clone(), wrap_width);
                    ui.fonts(|f| f.layout_job(job))
                };
                egui::ScrollArea::both()
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        ui.add_sized(
                            ui.available_size(),
                            egui::TextEdit::multiline(&mut text)
                                .code_editor()
                                .interactive(false)
                                .desired_width(f32::INFINITY)
                                .layouter(&mut layouter),
                        );
                    });
                return;
            }

            let font = FontId::new(12.5, FontFamily::Monospace);
            let mut layouter = |ui: &egui::Ui, text: &str, wrap_width: f32| {
                let job = crate::highlight::layout_job(text, &p, font.clone(), wrap_width);
                ui.fonts(|f| f.layout_job(job))
            };

            egui::ScrollArea::both()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    let resp = ui.add_sized(
                        ui.available_size(),
                        egui::TextEdit::multiline(&mut self.editor_text)
                            .code_editor()
                            .desired_width(f32::INFINITY)
                            .layouter(&mut layouter),
                    );
                    if resp.changed() {
                        self.dirty = true;
                        self.needs_parse = true;
                        self.last_edit = Some(Instant::now());
                    }
                });
        });
    }
}
