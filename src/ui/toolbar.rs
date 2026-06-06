//! Top toolbar: wordmark, workspace open, format/minify/remove-nulls, settings, toast.

use crate::app::JsonViewApp;
use crate::icons::Icon;
use crate::telemetry;
use eframe::egui::{self, FontFamily, RichText};

impl JsonViewApp {
    pub fn ui_toolbar(&mut self, ctx: &egui::Context) {
        let p = self.pal();
        let frame = egui::Frame::none()
            .fill(p.window)
            .inner_margin(egui::Margin::symmetric(12.0, 8.0));

        egui::TopBottomPanel::top("toolbar")
            .frame(frame)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    // wordmark
                    ui.label(
                        RichText::new("{ }")
                            .family(FontFamily::Name("mono_semibold".into()))
                            .size(15.0)
                            .color(p.accent),
                    );
                    ui.label(
                        RichText::new("Json Viewer")
                            .family(FontFamily::Name("mono_semibold".into()))
                            .size(14.0)
                            .color(p.text),
                    );
                    ui.label(
                        RichText::new(format!("v{}", telemetry::VERSION))
                            .size(10.0)
                            .color(p.dim),
                    );
                    sep(ui, p);

                    if ui.button(self.t("toolbar.open_workspace")).clicked() {
                        if let Some(dir) = rfd::FileDialog::new().pick_folder() {
                            self.open_workspace(dir);
                        }
                    }
                    sep(ui, p);

                    let has_text = !self.editor_text.trim().is_empty();
                    if ui
                        .add_enabled(has_text, egui::Button::new(self.t("toolbar.format")))
                        .clicked()
                    {
                        match crate::parser::format(&self.editor_text, self.config.indent) {
                            Ok(s) => { self.editor_text = s; self.dirty = true; self.reparse(); }
                            Err(e) => self.toast(format!("Format failed: {}", e.message)),
                        }
                    }
                    if ui
                        .add_enabled(has_text, egui::Button::new(self.t("toolbar.minify")))
                        .clicked()
                    {
                        match crate::parser::minify(&self.editor_text) {
                            Ok(s) => { self.editor_text = s; self.dirty = true; self.reparse(); }
                            Err(e) => self.toast(format!("Minify failed: {}", e.message)),
                        }
                    }
                    if ui
                        .add_enabled(has_text, egui::Button::new(self.t("toolbar.remove_nulls")))
                        .on_hover_text(self.t("toolbar.remove_nulls"))
                        .clicked()
                    {
                        match crate::parser::remove_nulls(&self.editor_text, self.config.indent) {
                            Ok(s) => { self.editor_text = s; self.dirty = true; self.reparse(); }
                            Err(e) => self.toast(format!("Failed: {}", e.message)),
                        }
                    }

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        // Settings icon button
                        if crate::icons::toolbar_button(ui, Icon::Settings, 28.0, p.dim, p.hover)
                            .on_hover_text(self.t("toolbar.settings"))
                            .clicked()
                        {
                            self.show_settings = !self.show_settings;
                        }

                        // Toast message
                        if let Some((msg, _)) = &self.toast {
                            ui.colored_label(p.accent, msg);
                        }
                    });
                });
            });
    }
}

fn sep(ui: &mut egui::Ui, p: crate::theme::Palette) {
    ui.add_space(4.0);
    let (rect, _) = ui.allocate_exact_size(egui::vec2(1.0, 16.0), egui::Sense::hover());
    ui.painter().rect_filled(rect, egui::Rounding::ZERO, p.sep);
    ui.add_space(4.0);
}
