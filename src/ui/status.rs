//! Thin bottom status strip: file, node count, hits, smells.
//! Background turns red-tinted when the document has a syntax error.

use crate::app::JsonViewApp;
use eframe::egui::{self, Color32, RichText};

impl JsonViewApp {
    pub fn ui_status(&mut self, ctx: &egui::Context) {
        let p = self.pal();
        let has_error = self.parse_error.is_some();

        // Error state: red-tinted background (Proxyman-style status indicator).
        let bg = if has_error {
            if p.dark {
                Color32::from_rgb(0x3a, 0x18, 0x1a)
            } else {
                Color32::from_rgb(0xff, 0xee, 0xee)
            }
        } else {
            p.sidebar
        };

        let frame = egui::Frame::none()
            .fill(bg)
            .inner_margin(egui::Margin::symmetric(12.0, 4.0));

        egui::TopBottomPanel::bottom("status")
            .frame(frame)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    // File name + unsaved dot
                    let name = self
                        .selected
                        .as_ref()
                        .and_then(|p| p.file_name())
                        .map(|n| n.to_string_lossy().into_owned())
                        .unwrap_or_else(|| self.t("status.no_file").to_string());

                    let name_color = if has_error {
                        if p.dark { Color32::from_rgb(0xff, 0x88, 0x88) } else { Color32::from_rgb(0xcc, 0x22, 0x22) }
                    } else {
                        p.dim
                    };
                    ui.label(RichText::new(&name).color(name_color).size(11.0));

                    if self.dirty {
                        ui.label(RichText::new(self.t("status.unsaved")).color(p.accent).size(11.0));
                    }

                    if has_error {
                        // Alert icon — allocated inline so it centres on the text baseline
                        let (icon_rect, _) = ui.allocate_exact_size(
                            egui::vec2(12.0, 12.0),
                            egui::Sense::hover(),
                        );
                        crate::icons::draw(
                            &ui.painter(),
                            crate::icons::Icon::AlertCircle,
                            icon_rect,
                            name_color,
                        );
                        if let Some(e) = &self.parse_error {
                            ui.label(
                                RichText::new(format!("line {}, col {}", e.line, e.col))
                                    .color(name_color)
                                    .size(11.0),
                            );
                        }
                    }

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        let parts: Vec<String> = [
                            self.parse_error
                                .as_ref()
                                .map(|_| self.t("status.invalid_json").to_string()),
                            self.arena
                                .as_ref()
                                .map(|a| format!("{} {}", a.nodes.len(), self.t("status.nodes"))),
                            (!self.jsonpath.trim().is_empty())
                                .then(|| format!("{} {}", self.jp_order.len(), self.t("jp.hits"))),
                            (!self.smells.is_empty())
                                .then(|| format!("{} {}", self.smells.len(), self.t("status.smells"))),
                        ]
                        .into_iter()
                        .flatten()
                        .collect();

                        let line = parts.join("   ·   ");
                        let line_color = if has_error { name_color } else { p.dim };
                        ui.label(RichText::new(line).color(line_color).size(11.0).monospace());
                    });
                });
            });
    }
}
