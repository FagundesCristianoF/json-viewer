//! Lightweight git integration via `std::process::Command`.
//!
//! All operations target a specific workspace root. Errors are soft —
//! the app keeps working if git is absent or the repo is broken.

use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

// ─── Data types ────────────────────────────────────────────────────────────

#[derive(Clone, Debug)]
pub struct CommitInfo {
    /// 7-char abbreviated hash.
    pub hash: String,
    /// First line of the commit message.
    pub message: String,
    /// Unix timestamp (seconds).
    pub timestamp: i64,
    /// Human-readable relative age: "2 min ago", "3 hrs ago", etc.
    pub relative: String,
}

// ─── Public API ────────────────────────────────────────────────────────────

/// Return true if `dir` (or any ancestor) is a git repository.
pub fn is_repo(dir: &Path) -> bool {
    git(dir, &["rev-parse", "--git-dir"]).is_ok()
}

/// Initialise a new repo at `dir`. No-op if it already is one.
pub fn init(dir: &Path) -> Result<(), String> {
    git(dir, &["init"])?;
    // Write an initial .gitignore so we never accidentally commit the OS junk.
    let gi = dir.join(".gitignore");
    if !gi.exists() {
        let _ = std::fs::write(gi, ".DS_Store\n");
    }
    Ok(())
}

/// Stage `file` and commit it. Returns the new short hash.
/// Uses a fallback identity so commits work even without global git config.
pub fn commit_file(workspace: &Path, file: &Path, message: &str) -> Result<String, String> {
    let rel = file
        .strip_prefix(workspace)
        .map_err(|_| "file outside workspace".to_string())?
        .to_string_lossy()
        .to_string();

    // Stage only this file.
    git(workspace, &["add", "--", &rel])?;

    // Commit — skip if nothing staged (file unchanged).
    let status = Command::new("git")
        .current_dir(workspace)
        .args([
            "-c", "user.name=Json Viewer",
            "-c", "user.email=json-viewer@local",
            "commit",
            "--allow-empty",  // removed — we want to skip truly empty commits
            "-m", message,
            "--",
            &rel,
        ])
        .output()
        .map_err(|e| e.to_string())?;

    if !status.status.success() {
        let err = String::from_utf8_lossy(&status.stderr).to_string();
        // "nothing to commit" is not an error for us.
        if err.contains("nothing to commit") || err.contains("nothing added") {
            return Ok(String::new());
        }
        return Err(err);
    }

    // Read back the short hash of HEAD.
    let hash = git(workspace, &["rev-parse", "--short", "HEAD"])
        .unwrap_or_default()
        .trim()
        .to_string();
    Ok(hash)
}

/// Return up to `limit` commits that touched `file`, newest first.
pub fn log(workspace: &Path, file: &Path, limit: usize) -> Result<Vec<CommitInfo>, String> {
    let rel = file
        .strip_prefix(workspace)
        .map_err(|_| "file outside workspace".to_string())?
        .to_string_lossy()
        .to_string();

    let limit_str = limit.to_string();
    let out = git(
        workspace,
        &[
            "log",
            "--follow",
            &format!("--format=%h\x1f%s\x1f%at"),
            "-n",
            &limit_str,
            "--",
            &rel,
        ],
    )?;

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let mut entries = Vec::new();
    for line in out.lines() {
        let parts: Vec<&str> = line.splitn(3, '\x1f').collect();
        if parts.len() < 3 {
            continue;
        }
        let ts: i64 = parts[2].parse().unwrap_or(0);
        entries.push(CommitInfo {
            hash: parts[0].to_string(),
            message: parts[1].to_string(),
            timestamp: ts,
            relative: relative_time(now - ts),
        });
    }
    Ok(entries)
}

/// Return the content of `file` as it existed at `hash`.
pub fn show(workspace: &Path, hash: &str, file: &Path) -> Result<String, String> {
    let rel = file
        .strip_prefix(workspace)
        .map_err(|_| "file outside workspace".to_string())?
        .to_string_lossy()
        .to_string();

    let spec = format!("{hash}:{rel}");
    git(workspace, &["show", &spec])
}

// ─── Helpers ───────────────────────────────────────────────────────────────

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    let out = Command::new("git")
        .current_dir(dir)
        .args(args)
        .output()
        .map_err(|e| format!("git not found: {e}"))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim_end().to_string())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim_end().to_string())
    }
}

fn relative_time(secs: i64) -> String {
    let secs = secs.max(0) as u64;
    if secs < 60 {
        "just now".to_string()
    } else if secs < 3600 {
        let m = secs / 60;
        format!("{m} min ago")
    } else if secs < 86400 {
        let h = secs / 3600;
        format!("{h} hr ago")
    } else if secs < 86400 * 30 {
        let d = secs / 86400;
        format!("{d} day{} ago", if d == 1 { "" } else { "s" })
    } else if secs < 86400 * 365 {
        let mo = secs / (86400 * 30);
        format!("{mo} mo ago")
    } else {
        let y = secs / (86400 * 365);
        format!("{y} yr ago")
    }
}

// ─── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn tmpdir() -> PathBuf {
        let thread_id = format!("{:?}", std::thread::current().id())
            .chars()
            .filter(|c| c.is_alphanumeric())
            .collect::<String>();
        let p = std::env::temp_dir().join(format!(
            "jsonview_git_test_{}_{}",
            std::process::id(),
            thread_id,
        ));
        // Clean slate each run.
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        p
    }

    #[test]
    fn init_creates_repo() {
        let dir = tmpdir();
        assert!(!is_repo(&dir));
        init(&dir).unwrap();
        assert!(is_repo(&dir));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn commit_and_log() {
        let dir = tmpdir();
        init(&dir).unwrap();

        let f = dir.join("test.json");
        fs::write(&f, r#"{"v":1}"#).unwrap();
        let hash = commit_file(&dir, &f, "Add test.json").unwrap();
        assert!(!hash.is_empty());

        let entries = log(&dir, &f, 10).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].message, "Add test.json");

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn show_restores_content() {
        let dir = tmpdir();
        init(&dir).unwrap();

        let f = dir.join("data.json");
        fs::write(&f, r#"{"v":1}"#).unwrap();
        commit_file(&dir, &f, "v1").unwrap();

        fs::write(&f, r#"{"v":2}"#).unwrap();
        commit_file(&dir, &f, "v2").unwrap();

        let entries = log(&dir, &f, 10).unwrap();
        assert_eq!(entries.len(), 2);

        // Show the first (oldest) commit = v1
        let content = show(&dir, &entries[1].hash, &f).unwrap();
        assert_eq!(content, r#"{"v":1}"#);

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn relative_time_units() {
        assert_eq!(relative_time(30), "just now");
        assert_eq!(relative_time(90), "1 min ago");
        assert_eq!(relative_time(7200), "2 hr ago");
        assert_eq!(relative_time(86400), "1 day ago");
        assert_eq!(relative_time(86400 * 3), "3 days ago");
    }
}
