//! Key Collector panel — find all child keys of every node whose own key matches a name.
//! Useful for SDUI trees where "options", "actions", etc. appear at arbitrary depths.

use crate::app::JsonViewApp;
use eframe::egui;

impl JsonViewApp {
    pub fn ui_key_collector(&mut self, ui: &mut egui::Ui) {
        let p = self.pal();

        // ── Search bar ─────────────────────────────────────────────
        ui.horizontal(|ui| {
            crate::theme::section_label(ui, "Parent key");
            let r = ui.add(
                egui::TextEdit::singleline(&mut self.key_collect_query)
                    .desired_width(200.0)
                    .font(egui::TextStyle::Monospace)
                    .hint_text("options"),
            );
            if r.changed() {
                self.run_key_collect();
            }
            if !self.key_collect_query.is_empty() {
                if crate::icons::button(ui, crate::icons::Icon::Close, 20.0, p.dim)
                    .on_hover_text("Clear")
                    .clicked()
                {
                    self.key_collect_query.clear();
                    self.key_collect_results.clear();
                }
            }

            if !self.key_collect_results.is_empty() {
                // Unique keys across all occurrences
                let unique: std::collections::BTreeSet<String> = self
                    .key_collect_results
                    .iter()
                    .flat_map(|(_, ks)| ks.iter().cloned())
                    .collect();
                ui.add_space(8.0);
                crate::theme::badge(
                    ui,
                    &format!("{} unique", unique.len()),
                    p.accent,
                );
                ui.add_space(4.0);
                crate::theme::badge(
                    ui,
                    &format!("{} occurrences", self.key_collect_results.len()),
                    p.dim,
                );

                // Copy unique keys as JSON array
                if ui.small_button("Copy keys").clicked() {
                    let arr: Vec<serde_json::Value> =
                        unique.iter().map(|k| serde_json::Value::String(k.clone())).collect();
                    ui.ctx().copy_text(serde_json::to_string_pretty(&arr).unwrap_or_default());
                    // toast is not accessible here, but clipboard feedback is instant
                }
            }
        });

        if self.key_collect_query.trim().is_empty() {
            ui.add_space(8.0);
            ui.label(
                egui::RichText::new("Type a key name to find all its child keys across the document.")
                    .color(p.dim)
                    .size(12.0),
            );
            return;
        }

        if self.key_collect_results.is_empty() {
            ui.add_space(8.0);
            ui.label(
                egui::RichText::new(format!(
                    "No object nodes with key \"{}\" found.",
                    self.key_collect_query
                ))
                .color(p.dim)
                .size(12.0),
            );
            return;
        }

        ui.add_space(4.0);

        // ── Results ────────────────────────────────────────────────
        // Two columns: path on left, keys on right as badges.
        egui::ScrollArea::vertical()
            .id_source("key_collector_scroll")
            .auto_shrink([false, false])
            .show(ui, |ui| {
                let results = self.key_collect_results.clone();
                for (path, keys) in &results {
                    ui.horizontal_wrapped(|ui| {
                        ui.label(
                            egui::RichText::new(path)
                                .monospace()
                                .size(11.0)
                                .color(p.accent),
                        );
                        ui.add_space(4.0);
                        for key in keys {
                            crate::theme::badge(ui, key, p.dim);
                        }
                    });
                }

                // Aggregate: all unique keys with count.
                ui.add_space(8.0);
                ui.separator();
                ui.add_space(4.0);
                crate::theme::section_label(ui, "All unique keys");
                ui.add_space(4.0);

                let mut counts: std::collections::BTreeMap<String, usize> =
                    std::collections::BTreeMap::new();
                for (_, keys) in &results {
                    for k in keys {
                        *counts.entry(k.clone()).or_insert(0) += 1;
                    }
                }

                ui.horizontal_wrapped(|ui| {
                    for (key, count) in &counts {
                        let label = if *count > 1 {
                            format!("{key} ×{count}")
                        } else {
                            key.clone()
                        };
                        crate::theme::badge(ui, &label, p.accent);
                    }
                });
            });
    }
}
