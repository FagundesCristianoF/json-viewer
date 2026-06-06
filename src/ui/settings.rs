//! Settings modal: theme, locale, telemetry.

use crate::app::JsonViewApp;
use crate::i18n::Locale;
use eframe::egui;

impl JsonViewApp {
    pub fn ui_settings(&mut self, ctx: &egui::Context) {
        if !self.show_settings {
            return;
        }
        let p = self.pal();

        egui::Window::new(self.t("settings.title"))
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .min_width(320.0)
            .show(ctx, |ui| {
                ui.add_space(4.0);

                // ── Appearance ────────────────────────────────────
                crate::theme::section_label(ui, self.t("settings.appearance"));
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    ui.label(self.t("settings.theme"));
                    ui.add_space(8.0);
                    let dark_label = self.t("toolbar.theme_dark");
                    let light_label = self.t("toolbar.theme_light");
                    if crate::theme::segment(ui, self.dark, dark_label).clicked() && !self.dark {
                        self.toggle_theme();
                    }
                    if crate::theme::segment(ui, !self.dark, light_label).clicked() && self.dark {
                        self.toggle_theme();
                    }
                });

                ui.add_space(8.0);

                // ── Language ──────────────────────────────────────
                crate::theme::section_label(ui, self.t("settings.language"));
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    ui.label(self.t("settings.language_label"));
                    ui.add_space(8.0);
                    egui::ComboBox::from_id_source("settings_locale")
                        .selected_text(self.locale.label())
                        .width(160.0)
                        .show_ui(ui, |ui| {
                            for loc in [Locale::En, Locale::PtBr] {
                                if ui.selectable_label(self.locale == loc, loc.label()).clicked() {
                                    self.locale = loc;
                                    self.config.locale = loc;
                                    let _ = crate::config::save(&self.config);
                                }
                            }
                        });
                });

                ui.add_space(8.0);

                // ── Editor ────────────────────────────────────────
                crate::theme::section_label(ui, self.t("settings.editor"));
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    ui.label(self.t("toolbar.indent"));
                    ui.add(egui::DragValue::new(&mut self.config.indent).range(0..=8));
                });

                ui.add_space(4.0);

                let auto_save_label = self.t("editor.auto_save");
                if ui.checkbox(&mut self.auto_save, auto_save_label).changed() {
                    self.config.auto_save = self.auto_save;
                    let _ = crate::config::save(&self.config);
                }

                ui.add_space(8.0);

                // ── Privacy ───────────────────────────────────────
                crate::theme::section_label(ui, self.t("settings.privacy"));
                ui.add_space(4.0);

                let mut tel = self.config.telemetry_enabled;
                if ui
                    .checkbox(&mut tel, self.t("settings.telemetry"))
                    .on_hover_text(self.t("settings.telemetry_hint"))
                    .changed()
                {
                    self.config.telemetry_enabled = tel;
                    let _ = crate::config::save(&self.config);
                }

                ui.add_space(8.0);

                // ── Diagnostics ───────────────────────────────────
                crate::theme::section_label(ui, "Diagnostics");
                ui.add_space(4.0);

                let snap = crate::telemetry::diagnostic_snapshot(&self.config);
                let mut snap_copy = snap.clone();
                ui.add(
                    egui::TextEdit::multiline(&mut snap_copy)
                        .code_editor()
                        .desired_rows(5)
                        .interactive(false)
                        .desired_width(f32::INFINITY),
                );
                if ui.button("Copy diagnostics").clicked() {
                    ctx.copy_text(snap);
                    self.toast("Diagnostics copied");
                }

                ui.add_space(12.0);

                ui.horizontal(|ui| {
                    ui.label(
                        egui::RichText::new(format!("Json Viewer  v{}", crate::telemetry::VERSION))
                            .color(p.dim)
                            .size(10.0),
                    );
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui.button(self.t("settings.close")).clicked() {
                            self.show_settings = false;
                        }
                    });
                });
            });
    }
}
