//! egui app state + update loop. Wires the pure modules to the UI.

use crate::{config, git, i18n, model, parser, path, smells, telemetry, template, theme, workspace};
use eframe::egui;
use std::collections::HashSet;
use std::path::PathBuf;
use std::time::Instant;

#[derive(PartialEq, Eq, Clone, Copy)]
pub enum Mode {
    Highlight,
    Filter,
}

#[derive(PartialEq, Eq, Clone, Copy)]
pub enum IssuesTab {
    Syntax,
    Smells,
    History,
    Keys,
}

/// A pending sidebar text-input dialog.
pub enum Dialog {
    NewFolder(PathBuf, String),
    NewJson(PathBuf, String),
    Rename(PathBuf, String),
}

const REPARSE_DEBOUNCE: f64 = 0.25; // seconds

pub struct JsonViewApp {
    pub config: config::Config,
    pub ws_root: Option<PathBuf>,
    pub tree: Option<workspace::Entry>,

    pub selected: Option<PathBuf>,
    pub editor_text: String,
    pub dirty: bool,

    pub arena: Option<model::Arena>,
    pub parse_error: Option<parser::ParseError>,
    pub smells: Vec<smells::Smell>,
    pub expanded: HashSet<usize>,

    pub jsonpath: String,
    pub jp_mode: Mode,
    pub jp_matches: HashSet<usize>,
    pub jp_order: Vec<usize>,
    pub jp_error: Option<String>,

    pub issues_tab: IssuesTab,

    pub pending: Option<Dialog>,
    pub cut: Option<PathBuf>,
    pub sidebar_search: String,

    pub toast: Option<(String, Option<f64>)>,
    pub needs_parse: bool,
    pub last_edit: Option<Instant>,

    pub dark: bool,
    pub theme_dirty: bool,
    pub auto_save: bool,

    pub locale: i18n::Locale,
    pub show_settings: bool,

    // compose
    pub show_compose: bool,
    pub compose_template: String,
    pub compose_preview: Option<Result<String, String>>,

    // key collector
    pub key_collect_query: String,
    pub key_collect_results: Vec<(String, Vec<String>)>, // (parent_path, child_keys)

    // compose file picker
    pub compose_ws_files: Vec<String>, // all workspace json filenames (relative to ws_root)

    // template modal
    pub show_template: bool,
    pub template_files: Vec<std::path::PathBuf>, // .template.json files in workspace
    pub template_selected: Option<std::path::PathBuf>,
    pub template_content: String,
    pub template_vars: Vec<(String, String)>, // (var_name, current_value)
    pub template_preview: Option<Result<String, String>>,

    // replace tool
    pub show_replace: bool,
    pub replace_path: String,
    pub replace_content: String,
    pub replace_preview: Option<Result<String, String>>,

    // git history
    pub history: Vec<git::CommitInfo>,
    pub history_preview: Option<String>, // content shown in preview pane
    pub history_selected: Option<String>, // hash of selected commit
}

impl JsonViewApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let config = config::load();
        theme::install_fonts(&cc.egui_ctx);
        theme::apply(&cc.egui_ctx, config.dark);
        let dark = config.dark;
        let auto_save = config.auto_save;
        let locale = config.locale;
        let mut app = JsonViewApp {
            config,
            ws_root: None,
            tree: None,
            selected: None,
            editor_text: String::new(),
            dirty: false,
            arena: None,
            parse_error: None,
            smells: Vec::new(),
            expanded: HashSet::new(),
            jsonpath: String::new(),
            jp_mode: Mode::Highlight,
            jp_matches: HashSet::new(),
            jp_order: Vec::new(),
            jp_error: None,
            issues_tab: IssuesTab::Syntax,
            pending: None,
            cut: None,
            sidebar_search: String::new(),
            toast: None,
            needs_parse: false,
            last_edit: None,
            dark,
            theme_dirty: false,
            auto_save,
            locale,
            show_settings: false,
            show_compose: false,
            compose_template: String::new(),
            compose_preview: None,
            compose_ws_files: Vec::new(),
            show_template: false,
            template_files: Vec::new(),
            template_selected: None,
            template_content: String::new(),
            template_vars: Vec::new(),
            template_preview: None,
            key_collect_query: String::new(),
            key_collect_results: Vec::new(),
            show_replace: false,
            replace_path: String::new(),
            replace_content: String::new(),
            replace_preview: None,
            history: Vec::new(),
            history_preview: None,
            history_selected: None,
        };
        if let Some(ws) = app.config.last_workspace.clone() {
            let p = PathBuf::from(ws);
            if p.is_dir() {
                app.open_workspace(p);
            }
        }
        app
    }

    pub fn toast(&mut self, msg: impl Into<String>) {
        self.toast = Some((msg.into(), None));
    }

    /// Translate a UI string key for the current locale.
    pub fn t(&self, key: &'static str) -> &'static str {
        i18n::t(self.locale, key)
    }

    pub fn pal(&self) -> theme::Palette {
        theme::palette(self.dark)
    }

    pub fn toggle_theme(&mut self) {
        self.dark = !self.dark;
        self.config.dark = self.dark;
        self.theme_dirty = true;
        let _ = config::save(&self.config);
    }

    pub fn open_workspace(&mut self, root: PathBuf) {
        // Ensure git is available for history.
        if !git::is_repo(&root) {
            let _ = git::init(&root);
        }
        self.ws_root = Some(root.clone());
        self.config.last_workspace = Some(root.display().to_string());
        let _ = config::save(&self.config);
        self.refresh_tree();
    }

    pub fn refresh_tree(&mut self) {
        if let Some(root) = self.ws_root.clone() {
            match workspace::read_tree(&root) {
                Ok(t) => {
                    // open content immediately on first load
                    if self.selected.is_none() {
                        if let Some(first) = first_file(&t) {
                            self.select_file(first);
                        }
                    }
                    // collect all json filenames for compose picker
                    self.compose_ws_files = collect_json_names(&t, &root);
                    // collect template files
                    self.template_files = template::list_templates(&root);
                    self.tree = Some(t);
                }
                Err(e) => {
                    self.tree = None;
                    self.toast(format!("Read failed: {}", e));
                }
            }
        }
    }

    pub fn select_file(&mut self, path: PathBuf) {
        match std::fs::read_to_string(&path) {
            Ok(text) => {
                self.editor_text = text;
                self.selected = Some(path);
                self.dirty = false;
                self.expanded.clear();
                self.history.clear();
                self.history_preview = None;
                self.history_selected = None;
                self.reparse();
                if let Some(a) = &self.arena {
                    self.expanded.insert(a.root);
                }
                self.reload_history();
            }
            Err(e) => self.toast(format!("Open failed: {}", e)),
        }
    }

    pub fn reparse(&mut self) {
        match parser::parse(&self.editor_text) {
            Ok(a) => {
                self.smells = smells::scan(&a, &self.editor_text);
                self.parse_error = None;
                self.arena = Some(a);
            }
            Err(e) => {
                self.parse_error = Some(e);
                self.arena = None;
                self.smells = Vec::new();
            }
        }
        self.run_jsonpath();
        self.needs_parse = false;
    }

    pub fn run_jsonpath(&mut self) {
        self.jp_matches.clear();
        self.jp_order.clear();
        self.jp_error = None;
        if self.jsonpath.trim().is_empty() {
            return;
        }
        if let Some(a) = &self.arena {
            match path::query(a, &self.jsonpath) {
                Ok(v) => {
                    self.jp_matches = v.iter().copied().collect();
                    self.jp_order = v;
                    self.expand_to_matches();
                }
                Err(e) => self.jp_error = Some(e),
            }
        }
    }

    /// Expand every match and its ancestors so highlighted nodes are visible.
    fn expand_to_matches(&mut self) {
        let (root, parents, order) = match &self.arena {
            Some(a) => (a.root, a.parents(), self.jp_order.clone()),
            None => return,
        };
        for m in order {
            let mut p = m;
            self.expanded.insert(p);
            while p != root {
                p = parents[p];
                self.expanded.insert(p);
            }
        }
    }

    /// When in filter mode with matches, the editor shows this read-only
    /// JSON projection of the matched subtrees instead of the raw file.
    pub fn filtered_json(&self) -> Option<String> {
        if self.jp_mode != Mode::Filter
            || self.jp_error.is_some()
            || self.jsonpath.trim().is_empty()
        {
            return None;
        }
        let a = self.arena.as_ref()?;
        if self.jp_order.is_empty() {
            return Some("// no matches".to_string());
        }
        let vals: Vec<serde_json::Value> = self
            .jp_order
            .iter()
            .map(|&i| model::node_to_value(a, i))
            .collect();
        let value = if vals.len() == 1 {
            vals.into_iter().next().unwrap()
        } else {
            serde_json::Value::Array(vals)
        };
        parser::format(&value.to_string(), self.config.indent).ok()
    }

    pub fn save(&mut self) {
        if let Some(path) = self.selected.clone() {
            match std::fs::write(&path, &self.editor_text) {
                Ok(_) => {
                    self.dirty = false;
                    telemetry::log_event(self.config.telemetry_enabled, "save");
                    // Commit to git history (best-effort, silently ignore errors).
                    if let Some(ws) = &self.ws_root.clone() {
                        let msg = path
                            .file_name()
                            .map(|n| format!("Save {}", n.to_string_lossy()))
                            .unwrap_or_else(|| "Save".to_string());
                        let _ = git::commit_file(ws, &path, &msg);
                        self.reload_history();
                    }
                    self.toast(self.t("toast.saved"));
                }
                Err(e) => self.toast(format!("Save failed: {}", e)),
            }
        }
    }

    /// Collect all child keys of every node whose own key equals `query`.
    pub fn run_key_collect(&mut self) {
        self.key_collect_results.clear();
        let query = self.key_collect_query.trim().to_string();
        if query.is_empty() {
            return;
        }
        let Some(arena) = &self.arena else { return };

        // Find every node whose own key matches `query` (case-sensitive).
        for (idx, node) in arena.nodes.iter().enumerate() {
            if node.key.as_deref() == Some(&query) && node.kind == model::Kind::Object {
                // Collect immediate child keys.
                let child_keys: Vec<String> = node
                    .children
                    .clone()
                    .filter_map(|c| arena.nodes[c].key.clone())
                    .collect();
                if !child_keys.is_empty() {
                    self.key_collect_results.push((node.path.clone(), child_keys));
                }
            }
        }
    }

    /// Select a template file: read content, detect variables, reset values.
    pub fn select_template(&mut self, path: std::path::PathBuf) {
        match std::fs::read_to_string(&path) {
            Ok(content) => {
                let vars = template::find_variables(&content);
                self.template_vars = vars.into_iter().map(|v| (v, String::new())).collect();
                self.template_content = content;
                self.template_selected = Some(path);
                self.template_preview = None;
            }
            Err(e) => self.toast(format!("Read failed: {e}")),
        }
    }

    /// Re-render template preview from current var values.
    pub fn update_template_preview(&mut self) {
        let content = self.template_content.clone();
        if content.trim().is_empty() {
            self.template_preview = None;
            return;
        }
        let vars: std::collections::HashMap<String, String> =
            self.template_vars.iter().cloned().collect();
        let base_dir = self
            .template_selected
            .as_ref()
            .and_then(|p| p.parent().map(|d| d.to_path_buf()))
            .or_else(|| self.ws_root.clone());

        let expanded = match template::render_vars(&content, &vars) {
            Ok(s) => s,
            Err(e) => {
                self.template_preview = Some(Err(e));
                return;
            }
        };

        self.template_preview = Some(match base_dir {
            Some(dir) => crate::compose::compose(&expanded, &dir, self.config.indent),
            None => crate::parser::format(&expanded, self.config.indent)
                .map_err(|e| e.message.clone()),
        });
    }

    pub fn reload_history(&mut self) {
        if let (Some(ws), Some(file)) = (self.ws_root.clone(), self.selected.clone()) {
            self.history = git::log(&ws, &file, 50).unwrap_or_default();
        }
    }

    pub fn apply_dialog(&mut self) {
        let Some(d) = self.pending.take() else { return };
        let res = match d {
            Dialog::NewFolder(parent, name) if !name.trim().is_empty() => {
                workspace::new_folder(&parent, name.trim()).map(|_| ())
            }
            Dialog::NewJson(parent, name) if !name.trim().is_empty() => {
                workspace::new_json(&parent, name.trim()).map(|_| ())
            }
            Dialog::Rename(path_buf, name) if !name.trim().is_empty() => {
                workspace::rename(&path_buf, name.trim()).map(|new| {
                    if self.selected.as_deref() == Some(path_buf.as_path()) {
                        self.selected = Some(new);
                    }
                })
            }
            _ => Ok(()),
        };
        if let Err(e) = res {
            self.toast(format!("Failed: {}", e));
        }
        self.refresh_tree();
    }

    pub fn do_move(&mut self, src: PathBuf, dest_dir: PathBuf) {
        match workspace::move_entry(&src, &dest_dir) {
            Ok(new) => {
                if self.selected.as_deref() == Some(src.as_path()) {
                    self.selected = Some(new);
                }
                self.toast("Moved");
            }
            Err(e) => self.toast(format!("Move failed: {}", e)),
        }
        self.refresh_tree();
    }

    pub fn do_delete(&mut self, path_buf: PathBuf) {
        match workspace::delete(&path_buf) {
            Ok(_) => {
                if self.selected.as_deref() == Some(path_buf.as_path()) {
                    self.selected = None;
                    self.editor_text.clear();
                    self.arena = None;
                }
                telemetry::log_event(self.config.telemetry_enabled, "delete");
                self.toast(self.t("toast.deleted"));
            }
            Err(e) => self.toast(format!("Delete failed: {}", e)),
        }
        self.refresh_tree();
    }

    /// Flatten currently-visible (expanded) nodes into a row list. In filter
    /// mode only matches, their ancestors and descendants are kept.
    pub fn visible_rows(&self) -> Vec<usize> {
        let Some(a) = &self.arena else {
            return Vec::new();
        };
        let filter = self.jp_mode == Mode::Filter
            && self.jp_error.is_none()
            && !self.jsonpath.trim().is_empty();
        let allowed = if filter {
            Some(self.filter_allowed(a))
        } else {
            None
        };
        let mut rows = Vec::new();
        self.walk(a, a.root, &allowed, &mut rows);
        rows
    }

    fn walk(
        &self,
        a: &model::Arena,
        idx: usize,
        allowed: &Option<HashSet<usize>>,
        rows: &mut Vec<usize>,
    ) {
        if let Some(set) = allowed {
            if !set.contains(&idx) {
                return;
            }
        }
        rows.push(idx);
        let expand = allowed.is_some() || self.expanded.contains(&idx);
        if expand {
            for c in a.nodes[idx].children.clone() {
                self.walk(a, c, allowed, rows);
            }
        }
    }

    fn filter_allowed(&self, a: &model::Arena) -> HashSet<usize> {
        let parents = a.parents();
        let mut set = HashSet::new();
        for &m in &self.jp_order {
            // descendants
            let mut sub = Vec::new();
            model::collect_subtree(a, m, &mut sub);
            set.extend(sub);
            // ancestors
            let mut p = m;
            while p != a.root {
                p = parents[p];
                set.insert(p);
            }
            set.insert(a.root);
        }
        set
    }
}

/// Collect all JSON filenames relative to `root` (depth-first).
fn collect_json_names(entry: &workspace::Entry, root: &PathBuf) -> Vec<String> {
    let mut names = Vec::new();
    collect_json_names_inner(entry, root, &mut names);
    names
}

fn collect_json_names_inner(entry: &workspace::Entry, root: &PathBuf, out: &mut Vec<String>) {
    for child in &entry.children {
        if child.is_dir {
            collect_json_names_inner(child, root, out);
        } else if let Ok(rel) = child.path.strip_prefix(root) {
            out.push(rel.to_string_lossy().into_owned());
        }
    }
}

/// Depth-first search for the first `.json` file in the tree.
fn first_file(entry: &workspace::Entry) -> Option<PathBuf> {
    for child in &entry.children {
        if child.is_dir {
            if let Some(f) = first_file(child) {
                return Some(f);
            }
        } else {
            return Some(child.path.clone());
        }
    }
    None
}

impl eframe::App for JsonViewApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if self.theme_dirty {
            theme::apply(ctx, self.dark);
            self.theme_dirty = false;
        }

        // global Cmd+S
        if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::S)) {
            self.save();
        }

        // debounced reparse after typing
        if self.needs_parse {
            if let Some(t) = self.last_edit {
                if t.elapsed().as_secs_f64() >= REPARSE_DEBOUNCE {
                    self.reparse();
                    if self.auto_save && self.parse_error.is_none() {
                        self.save();
                    }
                } else {
                    ctx.request_repaint_after(std::time::Duration::from_millis(120));
                }
            }
        }

        // toast lifetime
        let now = ctx.input(|i| i.time);
        if let Some((_, exp)) = &mut self.toast {
            if exp.is_none() {
                *exp = Some(now + 2.5);
            }
        }
        if let Some((_, Some(e))) = &self.toast {
            if now > *e {
                self.toast = None;
            } else {
                ctx.request_repaint_after(std::time::Duration::from_millis(250));
            }
        }

        self.ui_toolbar(ctx);
        self.ui_status(ctx);
        self.ui_sidebar(ctx);
        self.ui_bottom(ctx);
        self.ui_tree(ctx);
        self.ui_editor(ctx);
        self.ui_settings(ctx);
        self.ui_replace(ctx);
        self.ui_compose(ctx);
        self.ui_template(ctx);
    }
}
