//! Filesystem tree model + CRUD. All operations mutate the real filesystem.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug)]
pub struct Entry {
    pub name: String,
    pub path: PathBuf,
    pub is_dir: bool,
    pub children: Vec<Entry>,
    /// File size in bytes; None for directories or on stat failure.
    pub size_bytes: Option<u64>,
}

/// Read the workspace directory into a tree (folders + `.json` files only).
pub fn read_tree(root: &Path) -> io::Result<Entry> {
    let name = root
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| root.display().to_string());
    Ok(Entry {
        name,
        path: root.to_path_buf(),
        is_dir: true,
        children: read_children(root)?,
        size_bytes: None,
    })
}

fn read_children(dir: &Path) -> io::Result<Vec<Entry>> {
    let mut dirs = Vec::new();
    let mut files = Vec::new();
    for ent in fs::read_dir(dir)? {
        let ent = ent?;
        let path = ent.path();
        let name = ent.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let ft = ent.file_type()?;
        if ft.is_dir() {
            dirs.push(Entry {
                name,
                children: read_children(&path)?,
                path,
                is_dir: true,
                size_bytes: None,
            });
        } else if path.extension().and_then(|e| e.to_str()) == Some("json") {
            let size_bytes = fs::metadata(&path).ok().map(|m| m.len());
            files.push(Entry {
                name,
                path,
                is_dir: false,
                children: Vec::new(),
                size_bytes,
            });
        }
    }
    dirs.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    files.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    dirs.extend(files);
    Ok(dirs)
}

pub fn new_folder(parent: &Path, name: &str) -> io::Result<PathBuf> {
    let path = parent.join(name);
    fs::create_dir(&path)?;
    Ok(path)
}

pub fn new_json(parent: &Path, name: &str) -> io::Result<PathBuf> {
    let fname = if name.ends_with(".json") {
        name.to_string()
    } else {
        format!("{}.json", name)
    };
    let path = parent.join(fname);
    fs::write(&path, "{}\n")?;
    Ok(path)
}

pub fn rename(path: &Path, new_name: &str) -> io::Result<PathBuf> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let mut name = new_name.to_string();
    // preserve .json extension for files if the user dropped it
    if path.is_file()
        && path.extension().and_then(|e| e.to_str()) == Some("json")
        && !name.ends_with(".json")
    {
        name.push_str(".json");
    }
    let dest = parent.join(name);
    fs::rename(path, &dest)?;
    Ok(dest)
}

pub fn delete(path: &Path) -> io::Result<()> {
    if path.is_dir() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    }
}

/// Move `src` into directory `dest_dir`, keeping its file name.
pub fn move_entry(src: &Path, dest_dir: &Path) -> io::Result<PathBuf> {
    let name = src
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "source has no name"))?;
    let dest = dest_dir.join(name);
    if dest == src {
        return Ok(dest);
    }
    // refuse to move a directory into itself or a descendant
    if src.is_dir() && dest_dir.starts_with(src) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "cannot move a folder into itself",
        ));
    }
    fs::rename(src, &dest)?;
    Ok(dest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static COUNTER: AtomicUsize = AtomicUsize::new(0);

    fn temp_dir() -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("jsonview_test_{}_{}", std::process::id(), n));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn crud_roundtrip() {
        let root = temp_dir();
        let sub = new_folder(&root, "sub").unwrap();
        let f = new_json(&sub, "doc").unwrap();
        assert!(f.exists());
        assert_eq!(f.file_name().unwrap().to_str().unwrap(), "doc.json");

        let tree = read_tree(&root).unwrap();
        assert_eq!(tree.children.len(), 1);
        assert!(tree.children[0].is_dir);
        assert_eq!(tree.children[0].children.len(), 1);

        let renamed = rename(&f, "renamed").unwrap();
        assert!(renamed.exists());
        assert!(!f.exists());
        assert_eq!(renamed.file_name().unwrap().to_str().unwrap(), "renamed.json");

        let dest = new_folder(&root, "dest").unwrap();
        let moved = move_entry(&renamed, &dest).unwrap();
        assert!(moved.exists());
        assert_eq!(moved.parent().unwrap(), dest);

        delete(&sub).unwrap();
        assert!(!sub.exists());

        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn non_json_files_hidden() {
        let root = temp_dir();
        fs::write(root.join("notes.txt"), "hi").unwrap();
        new_json(&root, "data").unwrap();
        let tree = read_tree(&root).unwrap();
        assert_eq!(tree.children.len(), 1);
        assert_eq!(tree.children[0].name, "data.json");
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn refuse_move_into_self() {
        let root = temp_dir();
        let a = new_folder(&root, "a").unwrap();
        let b = new_folder(&a, "b").unwrap();
        assert!(move_entry(&a, &b).is_err());
        fs::remove_dir_all(&root).ok();
    }
}
