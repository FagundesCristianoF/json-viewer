//! Minimal compile-time-safe i18n. Add new variants to `Locale` and new
//! arms to `t()` to support additional languages. All UI strings live here.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum Locale {
    #[default]
    En,
    PtBr,
}

impl Locale {
    pub fn label(self) -> &'static str {
        match self {
            Locale::En => "English",
            Locale::PtBr => "Português (BR)",
        }
    }
}

pub fn t(locale: Locale, key: &'static str) -> &'static str {
    match (locale, key) {
        // ── toolbar ──────────────────────────────────────────────
        (_, "toolbar.open_workspace") => match locale {
            Locale::En => "Open workspace",
            Locale::PtBr => "Abrir workspace",
        },
        (_, "toolbar.format") => match locale {
            Locale::En => "Format",
            Locale::PtBr => "Formatar",
        },
        (_, "toolbar.minify") => match locale {
            Locale::En => "Minify",
            Locale::PtBr => "Minificar",
        },
        (_, "toolbar.indent") => match locale {
            Locale::En => "indent",
            Locale::PtBr => "recuo",
        },
        (_, "toolbar.theme_dark") => match locale {
            Locale::En => "Dark",
            Locale::PtBr => "Escuro",
        },
        (_, "toolbar.theme_light") => match locale {
            Locale::En => "Light",
            Locale::PtBr => "Claro",
        },
        // ── sidebar ──────────────────────────────────────────────
        (_, "sidebar.workspace") => match locale {
            Locale::En => "Workspace",
            Locale::PtBr => "Workspace",
        },
        (_, "sidebar.no_workspace") => match locale {
            Locale::En => "No workspace open",
            Locale::PtBr => "Nenhum workspace aberto",
        },
        (_, "sidebar.search_hint") => match locale {
            Locale::En => "Filter files…",
            Locale::PtBr => "Filtrar arquivos…",
        },
        (_, "sidebar.refresh") => match locale {
            Locale::En => "Refresh from disk",
            Locale::PtBr => "Recarregar do disco",
        },
        (_, "sidebar.new_json") => match locale {
            Locale::En => "New JSON",
            Locale::PtBr => "Novo JSON",
        },
        (_, "sidebar.new_folder") => match locale {
            Locale::En => "New folder",
            Locale::PtBr => "Nova pasta",
        },
        // ── editor ───────────────────────────────────────────────
        (_, "editor.section") => match locale {
            Locale::En => "Editor",
            Locale::PtBr => "Editor",
        },
        (_, "editor.auto_save") => match locale {
            Locale::En => "auto-save",
            Locale::PtBr => "salvar auto",
        },
        (_, "editor.save_hint") => match locale {
            Locale::En => "Cmd+S save",
            Locale::PtBr => "Cmd+S salvar",
        },
        // ── tree ─────────────────────────────────────────────────
        (_, "tree.section") => match locale {
            Locale::En => "Tree",
            Locale::PtBr => "Árvore",
        },
        (_, "tree.expand") => match locale {
            Locale::En => "expand",
            Locale::PtBr => "expandir",
        },
        (_, "tree.collapse") => match locale {
            Locale::En => "collapse",
            Locale::PtBr => "recolher",
        },
        (_, "tree.invalid_json") => match locale {
            Locale::En => "Invalid JSON — see Issues",
            Locale::PtBr => "JSON inválido — veja Problemas",
        },
        // ── jsonpath ─────────────────────────────────────────────
        (_, "jp.section") => match locale {
            Locale::En => "JSONPath",
            Locale::PtBr => "JSONPath",
        },
        (_, "jp.highlight") => match locale {
            Locale::En => "highlight",
            Locale::PtBr => "destacar",
        },
        (_, "jp.filter") => match locale {
            Locale::En => "filter",
            Locale::PtBr => "filtrar",
        },
        (_, "jp.hits") => match locale {
            Locale::En => "hits",
            Locale::PtBr => "resultados",
        },
        // ── issues ───────────────────────────────────────────────
        (_, "issues.syntax") => match locale {
            Locale::En => "Syntax",
            Locale::PtBr => "Sintaxe",
        },
        (_, "issues.smells") => match locale {
            Locale::En => "Smells",
            Locale::PtBr => "Odores",
        },
        (_, "issues.no_errors") => match locale {
            Locale::En => "No syntax errors.",
            Locale::PtBr => "Sem erros de sintaxe.",
        },
        (_, "issues.no_smells") => match locale {
            Locale::En => "No smells.",
            Locale::PtBr => "Sem odores.",
        },
        // ── status ───────────────────────────────────────────────
        (_, "status.no_file") => match locale {
            Locale::En => "no file",
            Locale::PtBr => "sem arquivo",
        },
        (_, "status.unsaved") => match locale {
            Locale::En => "● unsaved",
            Locale::PtBr => "● não salvo",
        },
        (_, "status.invalid_json") => match locale {
            Locale::En => "invalid JSON",
            Locale::PtBr => "JSON inválido",
        },
        (_, "status.nodes") => match locale {
            Locale::En => "nodes",
            Locale::PtBr => "nós",
        },
        (_, "status.smells") => match locale {
            Locale::En => "smells",
            Locale::PtBr => "odores",
        },
        // ── toasts ───────────────────────────────────────────────
        (_, "toast.saved") => match locale {
            Locale::En => "Saved",
            Locale::PtBr => "Salvo",
        },
        (_, "toast.moved") => match locale {
            Locale::En => "Moved",
            Locale::PtBr => "Movido",
        },
        (_, "toast.deleted") => match locale {
            Locale::En => "Deleted",
            Locale::PtBr => "Deletado",
        },
        (_, "toast.copied") => match locale {
            Locale::En => "Copied",
            Locale::PtBr => "Copiado",
        },
        // ── toolbar actions ───────────────────────────────────────
        (_, "toolbar.remove_nulls") => match locale {
            Locale::En => "Remove nulls",
            Locale::PtBr => "Remover nulos",
        },
        (_, "toolbar.settings") => match locale {
            Locale::En => "Settings",
            Locale::PtBr => "Configurações",
        },
        // ── settings modal ────────────────────────────────────────
        (_, "settings.title") => match locale {
            Locale::En => "Settings",
            Locale::PtBr => "Configurações",
        },
        (_, "settings.appearance") => match locale {
            Locale::En => "Appearance",
            Locale::PtBr => "Aparência",
        },
        (_, "settings.theme") => match locale {
            Locale::En => "Theme",
            Locale::PtBr => "Tema",
        },
        (_, "settings.language") => match locale {
            Locale::En => "Language",
            Locale::PtBr => "Idioma",
        },
        (_, "settings.language_label") => match locale {
            Locale::En => "Language",
            Locale::PtBr => "Idioma",
        },
        (_, "settings.editor") => match locale {
            Locale::En => "Editor",
            Locale::PtBr => "Editor",
        },
        (_, "settings.privacy") => match locale {
            Locale::En => "Privacy",
            Locale::PtBr => "Privacidade",
        },
        (_, "settings.telemetry") => match locale {
            Locale::En => "Enable local event log (opt-in, never sent)",
            Locale::PtBr => "Ativar log local de eventos (opt-in, nunca enviado)",
        },
        (_, "settings.telemetry_hint") => match locale {
            Locale::En => "Events are written to ~/Library/Application Support/json-viewer/events.log only.",
            Locale::PtBr => "Eventos gravados apenas em ~/Library/Application Support/json-viewer/events.log.",
        },
        (_, "settings.close") => match locale {
            Locale::En => "Close",
            Locale::PtBr => "Fechar",
        },
        // ── history ───────────────────────────────────────────────
        (_, "history.tab") => match locale {
            Locale::En => "History",
            Locale::PtBr => "Histórico",
        },
        (_, "history.no_commits") => match locale {
            Locale::En => "No commits yet.",
            Locale::PtBr => "Nenhum commit ainda.",
        },
        (_, "history.restore") => match locale {
            Locale::En => "Restore this version",
            Locale::PtBr => "Restaurar esta versão",
        },
        (_, "toast.restored") => match locale {
            Locale::En => "Restored",
            Locale::PtBr => "Restaurado",
        },
        // fallback
        _ => key,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn en_keys_present() {
        let keys = [
            "toolbar.open_workspace",
            "toolbar.format",
            "editor.auto_save",
            "tree.section",
            "jp.highlight",
            "issues.syntax",
            "status.no_file",
        ];
        for k in keys {
            let v = t(Locale::En, k);
            assert_ne!(v, k, "missing translation for key: {k}");
        }
    }

    #[test]
    fn ptbr_keys_present() {
        let keys = ["toolbar.open_workspace", "tree.collapse", "status.nodes"];
        for k in keys {
            let en = t(Locale::En, k);
            let ptbr = t(Locale::PtBr, k);
            assert!(!en.is_empty());
            assert!(!ptbr.is_empty());
        }
    }

    #[test]
    fn unknown_key_returns_key() {
        assert_eq!(t(Locale::En, "no.such.key"), "no.such.key");
    }
}
