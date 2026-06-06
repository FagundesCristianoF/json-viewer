//! Persisted app config: last-opened workspace + indent width.

use crate::i18n::Locale;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

fn default_indent() -> usize {
    2
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Config {
    #[serde(default)]
    pub last_workspace: Option<String>,
    #[serde(default = "default_indent")]
    pub indent: usize,
    #[serde(default)]
    pub dark: bool,
    #[serde(default)]
    pub auto_save: bool,
    #[serde(default)]
    pub locale: Locale,
    #[serde(default)]
    pub telemetry_enabled: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            last_workspace: None,
            indent: default_indent(),
            dark: false,
            auto_save: false,
            locale: Locale::En,
            telemetry_enabled: false,
        }
    }
}

/// `~/Library/Application Support/json-viewer/config.json` on macOS.
pub fn config_path() -> Option<PathBuf> {
    directories::ProjectDirs::from("", "", "json-viewer")
        .map(|d| d.config_dir().join("config.json"))
}

pub fn load() -> Config {
    let Some(path) = config_path() else {
        return Config::default();
    };
    match std::fs::read_to_string(&path) {
        Ok(text) => serde_json::from_str(&text).unwrap_or_default(),
        Err(_) => Config::default(),
    }
}

pub fn save(cfg: &Config) -> std::io::Result<()> {
    let Some(path) = config_path() else {
        return Ok(());
    };
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let text = serde_json::to_string_pretty(cfg).unwrap_or_else(|_| "{}".to_string());
    std::fs::write(path, text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults() {
        let c = Config::default();
        assert_eq!(c.indent, 2);
        assert!(c.last_workspace.is_none());
    }

    #[test]
    fn roundtrip_serde() {
        let c = Config {
            last_workspace: Some("/tmp/ws".to_string()),
            indent: 4,
            dark: true,
            auto_save: false,
            locale: crate::i18n::Locale::En,
            telemetry_enabled: false,
        };
        let s = serde_json::to_string(&c).unwrap();
        let back: Config = serde_json::from_str(&s).unwrap();
        assert_eq!(back.indent, 4);
        assert_eq!(back.last_workspace.as_deref(), Some("/tmp/ws"));
    }

    #[test]
    fn tolerates_partial_json() {
        let back: Config = serde_json::from_str("{}").unwrap();
        assert_eq!(back.indent, 2);
    }
}
