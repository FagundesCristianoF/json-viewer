//! Local telemetry: optional event log + diagnostic snapshot for bug reports.
//!
//! Privacy-first: nothing is sent anywhere automatically. The user controls
//! whether the local log is written (`Config::telemetry_enabled`). The bug-
//! report helper builds a text snapshot the user can copy or email manually.

use crate::config;
use directories::ProjectDirs;
use std::path::PathBuf;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Write one line to the local event log. No-op when logging is disabled.
pub fn log_event(enabled: bool, event: &str) {
    if !enabled {
        return;
    }
    if let Some(path) = log_path() {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let line = format!("{} {}\n", timestamp(), event);
        use std::io::Write;
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
            let _ = f.write_all(line.as_bytes());
        }
    }
}

/// Build a diagnostic string the user can include in a bug report.
pub fn diagnostic_snapshot(cfg: &config::Config) -> String {
    let last_ws = cfg.last_workspace.as_deref().unwrap_or("(none)");
    let last_lines = last_log_lines(10);
    format!(
        "Json Viewer {VERSION}\nmacOS {macos}\n\nconfig:\n  indent={indent}  dark={dark}  auto_save={auto_save}\n  workspace={last_ws}\n\nlast events:\n{last_lines}",
        macos = macos_version(),
        indent = cfg.indent,
        dark = cfg.dark,
        auto_save = cfg.auto_save,
    )
}

fn log_path() -> Option<PathBuf> {
    ProjectDirs::from("", "", "json-viewer")
        .map(|d| d.data_local_dir().join("events.log"))
}

fn last_log_lines(n: usize) -> String {
    let path = match log_path() {
        Some(p) => p,
        None => return "(no log)".to_string(),
    };
    match std::fs::read_to_string(&path) {
        Ok(text) => {
            let lines: Vec<&str> = text.lines().collect();
            let start = lines.len().saturating_sub(n);
            lines[start..].join("\n")
        }
        Err(_) => "(no log)".to_string(),
    }
}

fn timestamp() -> String {
    // Use file mtime as a proxy for "now" without Date::now() — just read a
    // byte from /dev/urandom for sequence; real timestamps come from the OS
    // file modification time visible in the log file.
    // We use a monotonic-ish approach: seconds since Unix epoch via stat.
    #[cfg(target_os = "macos")]
    {
        use std::time::{SystemTime, UNIX_EPOCH};
        let secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        return format!("{secs}");
    }
    #[allow(unreachable_code)]
    "(ts)".to_string()
}

fn macos_version() -> String {
    std::process::Command::new("sw_vers")
        .arg("-productVersion")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_semver() {
        let parts: Vec<&str> = VERSION.split('.').collect();
        assert_eq!(parts.len(), 3);
        for p in parts {
            p.parse::<u64>().expect("version component must be numeric");
        }
    }

    #[test]
    fn diagnostic_contains_version() {
        let cfg = config::Config::default();
        let snap = diagnostic_snapshot(&cfg);
        assert!(snap.contains(VERSION));
        assert!(snap.contains("indent=2"));
    }
}
