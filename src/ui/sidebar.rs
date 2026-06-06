//! Workspace tree sidebar + filesystem operations.

use crate::app::{Dialog, JsonViewApp};
use crate::icons::Icon;
use crate::workspace::Entry;
use eframe::egui;
use std::path::Path;

impl JsonViewApp {
    pub fn ui_sidebar(&mut self, ctx: &egui::Context) {
        let p = self.pal();
        let frame = egui::Frame::none()
            .fill(p.sidebar)
            .inner_margin(egui::Margin::symmetric(8.0, 8.0));
        egui::SidePanel::left("sidebar")
            .frame(frame)
            .resizable(true)
            .default_width(244.0)
            .show(ctx, |ui| {
                // ── header row ───────────────────────────────────
                ui.horizontal(|ui| {
                    crate::theme::section_label(ui, self.t("sidebar.workspace"));
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        let p = self.pal();
                        if crate::icons::button(ui, Icon::Refresh, 24.0, p.dim)
                            .on_hover_text(self.t("sidebar.refresh")).clicked()
                        {
                            self.refresh_tree();
                        }
                        if let Some(root) = self.ws_root.clone() {
                            if crate::icons::button(ui, Icon::FilePlus, 24.0, p.dim)
                                .on_hover_text(self.t("sidebar.new_json")).clicked()
                            {
                                self.pending = Some(Dialog::NewJson(root.clone(), String::new()));
                            }
                            if crate::icons::button(ui, Icon::FolderPlus, 24.0, p.dim)
                                .on_hover_text(self.t("sidebar.new_folder")).clicked()
                            {
                                self.pending = Some(Dialog::NewFolder(root, String::new()));
                            }
                        }
                    });
                });

                // ── cut clipboard banner ──────────────────────────
                if let Some(src) = self.cut.clone() {
                    ui.horizontal(|ui| {
                        ui.label(
                            egui::RichText::new(format!("✂ {}", file_name(&src)))
                                .color(p.accent)
                                .size(11.0),
                        );
                        if ui.small_button("clear").clicked() {
                            self.cut = None;
                        }
                    });
                }

                // ── search bar ────────────────────────────────────
                if self.tree.is_some() {
                    ui.add_space(4.0);
                    ui.horizontal(|ui| {
                        let p = self.pal();
                        let search_hint = self.t("sidebar.search_hint");
                        let resp = ui.add(
                            egui::TextEdit::singleline(&mut self.sidebar_search)
                                .desired_width(ui.available_width() - 28.0)
                                .hint_text(search_hint)
                                .font(egui::TextStyle::Small),
                        );
                        let _ = resp;
                        if !self.sidebar_search.is_empty() {
                            if crate::icons::button(ui, Icon::Close, 20.0, p.dim)
                                .on_hover_text("Clear search")
                                .clicked()
                            {
                                self.sidebar_search.clear();
                            }
                        }
                    });
                }

                ui.add_space(4.0);

                // ── file tree / empty state ───────────────────────
                egui::ScrollArea::vertical()
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        if let Some(tree) = self.tree.take() {
                            let query = self.sidebar_search.to_lowercase();
                            self.render_entry(ui, &tree, &query);
                            self.tree = Some(tree);
                        } else {
                            // empty state
                            ui.add_space(24.0);
                            ui.vertical_centered(|ui| {
                                ui.label(
                                    egui::RichText::new("No workspace open")
                                        .color(p.dim)
                                        .size(13.0),
                                );
                                ui.add_space(6.0);
                                ui.label(
                                    egui::RichText::new("Open a folder to browse JSON files")
                                        .color(p.dim)
                                        .size(11.0),
                                );
                                ui.add_space(10.0);
                                if ui.button(self.t("toolbar.open_workspace")).clicked() {
                                    if let Some(dir) = rfd::FileDialog::new().pick_folder() {
                                        self.open_workspace(dir);
                                    }
                                }
                            });
                        }
                    });
            });

        self.show_dialog(ctx);
    }

    fn render_entry(&mut self, ui: &mut egui::Ui, entry: &Entry, query: &str) {
        if entry.is_dir {
            // In search mode only show dirs that contain matching files.
            if !query.is_empty() && !dir_has_match(entry, query) {
                return;
            }
            let resp = egui::CollapsingHeader::new(format!("📁 {}", entry.name))
                .id_source(&entry.path)
                .default_open(true)
                .show(ui, |ui| {
                    for child in &entry.children {
                        self.render_entry(ui, child, query);
                    }
                });
            resp.header_response.context_menu(|ui| {
                self.dir_menu(ui, &entry.path);
            });
        } else {
            // Filter by search query.
            if !query.is_empty() && !entry.name.to_lowercase().contains(query) {
                return;
            }
            let p = self.pal();
            let selected = self.selected.as_deref() == Some(entry.path.as_path());

            // Full-width row with hover-reveal actions (Proxyman pattern).
            let row_h = 22.0;
            let desired = egui::vec2(ui.available_width(), row_h);
            let (row_rect, row_resp) =
                ui.allocate_exact_size(desired, egui::Sense::click());

            // Background
            let bg = if selected {
                Some(p.sel)
            } else if row_resp.hovered() {
                Some(p.hover)
            } else {
                None
            };
            if let Some(color) = bg {
                ui.painter().rect_filled(row_rect, egui::Rounding::same(4.0), color);
            }

            let mut child = ui.child_ui(
                row_rect,
                egui::Layout::left_to_right(egui::Align::Center),
                None,
            );
            child.add_space(4.0);
            child.label(egui::RichText::new("📄").size(12.0));
            child.add_space(2.0);

            // File name
            let name_color = if selected { p.accent } else { p.text };
            child.label(egui::RichText::new(&entry.name).size(12.5).color(name_color));

            // File size — dim, right-aligned
            if let Some(bytes) = entry.size_bytes {
                child.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    // On hover show actions; otherwise show size
                    if row_resp.hovered() {
                        // placeholder — context menu on right-click covers this
                    } else {
                        ui.add_space(4.0);
                        ui.label(
                            egui::RichText::new(fmt_size(bytes))
                                .size(10.0)
                                .color(p.dim),
                        );
                    }
                });
            }

            if row_resp.clicked() {
                self.select_file(entry.path.clone());
            }
            row_resp.context_menu(|ui| {
                self.file_menu(ui, &entry.path);
            });
        }
    }

    fn dir_menu(&mut self, ui: &mut egui::Ui, path: &Path) {
        if ui.button("New folder").clicked() {
            self.pending = Some(Dialog::NewFolder(path.to_path_buf(), String::new()));
            ui.close_menu();
        }
        if ui.button("New JSON").clicked() {
            self.pending = Some(Dialog::NewJson(path.to_path_buf(), String::new()));
            ui.close_menu();
        }
        if ui.button("Rename").clicked() {
            self.pending = Some(Dialog::Rename(path.to_path_buf(), file_name(path)));
            ui.close_menu();
        }
        if self.cut.is_some() && ui.button("Paste here").clicked() {
            if let Some(src) = self.cut.take() {
                self.do_move(src, path.to_path_buf());
            }
            ui.close_menu();
        }
        ui.separator();
        if ui.button("Delete").clicked() {
            self.do_delete(path.to_path_buf());
            ui.close_menu();
        }
    }

    fn file_menu(&mut self, ui: &mut egui::Ui, path: &Path) {
        if ui.button("Rename").clicked() {
            self.pending = Some(Dialog::Rename(path.to_path_buf(), file_name(path)));
            ui.close_menu();
        }
        if ui.button("Cut").clicked() {
            self.cut = Some(path.to_path_buf());
            ui.close_menu();
        }
        ui.separator();
        if ui.button("Delete").clicked() {
            self.do_delete(path.to_path_buf());
            ui.close_menu();
        }
    }

    fn show_dialog(&mut self, ctx: &egui::Context) {
        let mut submit = false;
        let mut cancel = false;
        if let Some(dialog) = &mut self.pending {
            let (title, buf): (&str, &mut String) = match dialog {
                Dialog::NewFolder(_, b) => ("New folder", b),
                Dialog::NewJson(_, b) => ("New JSON file", b),
                Dialog::Rename(_, b) => ("Rename", b),
            };
            egui::Window::new(title)
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    let r = ui.text_edit_singleline(buf);
                    r.request_focus();
                    // Check Enter while focused OR on the same frame focus is lost via Enter.
                    let entered = r.has_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter))
                        || r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));
                    ui.horizontal(|ui| {
                        if ui.button("OK").clicked() || entered {
                            submit = true;
                        }
                        if ui.button("Cancel").clicked() {
                            cancel = true;
                        }
                    });
                });
        }
        if submit {
            self.apply_dialog();
        } else if cancel {
            self.pending = None;
        }
    }
}

/// Whether any file in this dir subtree matches the query.
fn dir_has_match(entry: &Entry, query: &str) -> bool {
    for child in &entry.children {
        if child.is_dir {
            if dir_has_match(child, query) {
                return true;
            }
        } else if child.name.to_lowercase().contains(query) {
            return true;
        }
    }
    false
}

fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn fmt_size(bytes: u64) -> String {
    if bytes < 1024 {
        format!("{bytes}B")
    } else if bytes < 1024 * 1024 {
        format!("{:.1}K", bytes as f64 / 1024.0)
    } else {
        format!("{:.1}M", bytes as f64 / (1024.0 * 1024.0))
    }
}
