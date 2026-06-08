//! jsonview-core: pure business logic, no UI dependencies.

pub mod model;
pub mod parser;
pub mod compose;
pub mod template;
pub mod path;
pub mod smells;
pub mod folding;
pub mod i18n;
pub mod config;
pub mod workspace;
pub mod git;

// Re-export key types for convenience
pub use model::{Arena, Node, Kind};
pub use parser::{parse, format, minify, remove_nulls, json_replace, ParseError};
pub use path::query;
pub use path::aggregate_child_keys;
pub use smells::{scan as scan_smells, Smell};
pub use compose::{compose, referenced_files};
pub use template::{find_variables, render_vars, list_templates};
pub use folding::{scan_fold_ranges, build_display_text, real_to_display_line, FoldRange};
pub use i18n::{Locale, t};
pub use config::{Config, load as load_config, save as save_config};
pub use workspace::{Entry, read_tree};
pub use git::{CommitInfo, is_repo, init as git_init, commit_file, log as git_log, show as git_show};
