//! Narrow panel between editor and tree — Raw / Result toggle for compose files.

use crate::app::JsonViewApp;
use eframe::egui;

impl JsonViewApp {
    pub fn ui_view_mode(&mut self, ctx: &egui::Context) {
        let is_compose = self.editor_text.contains("{{") && self.editor_text.contains("}}");
        if !is_compose {
            return;
        }

        let p = self.pal();
        let frame = egui::Frame::none()
            .fill(p.window)
            .inner_margin(egui::Margin::symmetric(8.0, 8.0));

        egui::SidePanel::right("view_mode_panel")
            .frame(frame)
            .resizable(false)
            .exact_width(54.0)
            .show(ctx, |ui| {
                ui.vertical_centered(|ui| {
                    ui.add_space(2.0);

                    let raw_active = self.editor_raw_mode;
                    let raw_color = if raw_active { p.text } else { p.dim };
                    let result_color = if !raw_active { p.text } else { p.dim };

                    let raw_resp = ui.add(
                        egui::Label::new(
                            egui::RichText::new("Raw")
                                .size(11.0)
                                .color(raw_color)
                                .monospace(),
                        )
                        .sense(egui::Sense::click()),
                    );
                    if raw_resp.clicked() && !raw_active {
                        self.editor_raw_mode = true;
                        self.reparse();
                    }

                    ui.add_space(6.0);

                    let result_resp = ui.add(
                        egui::Label::new(
                            egui::RichText::new("Result")
                                .size(11.0)
                                .color(result_color)
                                .monospace(),
                        )
                        .sense(egui::Sense::click()),
                    );
                    if result_resp.clicked() && (raw_active || self.pointer_resolved.is_none()) {
                        self.editor_raw_mode = false; // set BEFORE reparse inside refresh
                        self.refresh_pointer_resolved();
                    }

                    // Underline the active tab
                    let painter = ui.painter();
                    let stroke = egui::Stroke::new(1.5, p.accent);
                    if raw_active {
                        let r = raw_resp.rect;
                        painter.line_segment(
                            [egui::pos2(r.left(), r.bottom() + 1.0), egui::pos2(r.right(), r.bottom() + 1.0)],
                            stroke,
                        );
                    } else {
                        let r = result_resp.rect;
                        painter.line_segment(
                            [egui::pos2(r.left(), r.bottom() + 1.0), egui::pos2(r.right(), r.bottom() + 1.0)],
                            stroke,
                        );
                    }
                });
            });
    }
}
