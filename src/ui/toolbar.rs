//! Top toolbar: wordmark, workspace open, format/minify/remove-nulls, settings, toast.

use crate::app::JsonViewApp;
use crate::icons::Icon;
use crate::telemetry;
use eframe::egui::{self, FontFamily, RichText};

impl JsonViewApp {
    pub fn ui_toolbar(&mut self, ctx: &egui::Context) {
        let p = self.pal();
        let frame = egui::Frame::none()
            .fill(p.elevated)
            .inner_margin(egui::Margin::symmetric(12.0, 6.0));

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

                    // Disable transforms when viewing compose result (raw template has {{}} tokens)
                    let in_result_view = self.pointer_resolved.is_some() && !self.editor_raw_mode;
                    let has_text = !self.editor_text.trim().is_empty() && !in_result_view;
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
                    if ui
                        .add_enabled(has_text, egui::Button::new("Replace…"))
                        .on_hover_text("Replace nodes matched by JSONPath")
                        .clicked()
                    {
                        self.show_replace = true;
                        self.replace_preview = None;
                    }
                    if ui
                        .button("Compose…")
                        .on_hover_text("Build JSON from {{file.json}} templates")
                        .clicked()
                    {
                        self.show_compose = true;
                        self.compose_preview = None;
                    }
                    if ui
                        .button("Template…")
                        .on_hover_text("Fill variables in a .template.json file")
                        .clicked()
                    {
                        self.show_template = true;
                        self.template_preview = None;
                        if let Some(root) = self.ws_root.clone() {
                            self.template_files = crate::template::list_templates(&root);
                        }
                    }

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        // Settings icon — always rightmost
                        if crate::icons::toolbar_button(ui, Icon::Settings, 28.0, p.dim, p.hover)
                            .on_hover_text(self.t("toolbar.settings"))
                            .clicked()
                        {
                            self.show_settings = !self.show_settings;
                        }

                        // Toast — fixed max width so it never overlaps buttons
                        if let Some((msg, _)) = &self.toast {
                            ui.set_max_width(260.0);
                            let display = if msg.chars().count() > 40 {
                                format!("{}…", msg.chars().take(40).collect::<String>())
                            } else {
                                msg.clone()
                            };
                            ui.colored_label(p.accent, display)
                                .on_hover_text(msg.as_str());
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
