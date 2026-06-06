//! Bottom panel: JSONPath bar + tabbed issues (syntax / smells).

use crate::app::{IssuesTab, JsonViewApp, Mode};
use eframe::egui;

impl JsonViewApp {
    pub fn ui_bottom(&mut self, ctx: &egui::Context) {
        let p = self.pal();
        let err_color = p.kind_color(crate::model::Kind::Bool);
        let frame = egui::Frame::none()
            .fill(p.inspector)
            .inner_margin(egui::Margin::symmetric(12.0, 8.0));

        egui::TopBottomPanel::bottom("bottom")
            .frame(frame)
            .resizable(true)
            .default_height(184.0)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    crate::theme::section_label(ui, self.t("jp.section"));
                    let r = ui.add(
                        egui::TextEdit::singleline(&mut self.jsonpath)
                            .desired_width(260.0)
                            .font(egui::TextStyle::Monospace)
                            .hint_text("$.store.book[*].title"),
                    );
                    if r.changed() {
                        self.run_jsonpath();
                    }
                    // × clear button — appears when text is present
                    if !self.jsonpath.is_empty() {
                        if crate::icons::button(ui, crate::icons::Icon::Close, 20.0, p.dim)
                            .on_hover_text("Clear")
                            .clicked()
                        {
                            self.jsonpath.clear();
                            self.run_jsonpath();
                        }
                    }
                    ui.add_space(4.0);
                    let hl_label = self.t("jp.highlight");
                    let fi_label = self.t("jp.filter");
                    if crate::theme::segment(ui, self.jp_mode == Mode::Highlight, hl_label).clicked() {
                        self.jp_mode = Mode::Highlight;
                    }
                    if crate::theme::segment(ui, self.jp_mode == Mode::Filter, fi_label).clicked() {
                        self.jp_mode = Mode::Filter;
                    }

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if let Some(e) = &self.jp_error {
                            ui.colored_label(err_color, e);
                        } else if !self.jsonpath.trim().is_empty() {
                            let hits = self.jp_order.len();
                            let label = format!("{hits} {}", self.t("jp.hits"));
                            crate::theme::badge(ui, &label, p.accent);
                        }
                    });
                });
                ui.add_space(6.0);

                let syntax_count = usize::from(self.parse_error.is_some());
                let smells_count = self.smells.len();
                let history_count = self.history.len();
                let keys_count = self.key_collect_results.iter().map(|(_, ks)| ks.len()).sum::<usize>();
                let syntax_label = self.t("issues.syntax");
                let smells_label = self.t("issues.smells");
                let history_label = self.t("history.tab");
                ui.horizontal(|ui| {
                    self.issue_tab(ui, IssuesTab::Syntax, syntax_label, syntax_count);
                    self.issue_tab(ui, IssuesTab::Smells, smells_label, smells_count);
                    self.issue_tab(ui, IssuesTab::History, history_label, history_count);
                    self.issue_tab(ui, IssuesTab::Keys, "Keys", keys_count);
                });
                ui.add_space(2.0);

                match self.issues_tab {
                    IssuesTab::History => {
                        self.ui_history_body(ui);
                    }
                    IssuesTab::Keys => {
                        self.ui_key_collector(ui);
                    }
                    _ => {
                        egui::ScrollArea::vertical()
                            .auto_shrink([false, false])
                            .show(ui, |ui| match self.issues_tab {
                                IssuesTab::Syntax => {
                                    if let Some(e) = &self.parse_error {
                                        ui.colored_label(
                                            err_color,
                                            format!("{} (line {}, col {})", e.message, e.line, e.col),
                                        );
                                    } else {
                                        ui.label(egui::RichText::new("No syntax errors.").color(p.dim));
                                    }
                                }
                                IssuesTab::Smells => {
                                    if self.smells.is_empty() {
                                        ui.label(egui::RichText::new("No smells.").color(p.dim));
                                    }
                                    for s in &self.smells {
                                        ui.horizontal(|ui| {
                                            ui.label(
                                                egui::RichText::new(&s.path).monospace().color(p.accent),
                                            );
                                            ui.label(egui::RichText::new(&s.message).color(p.text));
                                        });
                                    }
                                }
                                IssuesTab::History | IssuesTab::Keys => unreachable!(),
                            });
                    }
                }
            });
    }

    fn issue_tab(&mut self, ui: &mut egui::Ui, tab: IssuesTab, label: &'static str, count: usize) {
        let p = self.pal();
        let active = self.issues_tab == tab;
        let text = if count > 0 {
            format!("{}  {}", label, count)
        } else {
            label.to_string()
        };
        let mut rich = egui::RichText::new(text).size(12.0);
        if active {
            rich = rich.color(p.accent);
        }
        if ui.selectable_label(active, rich).clicked() {
            self.issues_tab = tab;
        }
    }
}
