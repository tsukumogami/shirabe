//! FC18 corpus count over this repository's own tracked markdown.
//!
//! Pull-request CI validates only the files a diff touches. That blind spot
//! is how twenty-odd stale references accumulated in documents that every
//! run reported clean, and it is not fixed by adding a check -- a reference
//! in a file no PR touches is still never re-checked. This test is the
//! compensating control: it runs the check over the whole tracked corpus on
//! every `cargo test`, so the number moving is a test failure rather than a
//! discovery somebody makes later.
//!
//! The count is pinned, not bounded. A finding that disappears matters as
//! much as one that appears: the first means the check stopped seeing a
//! defect it used to see, and only an equality assertion catches that.

use std::path::{Path, PathBuf};
use std::process::Command;

/// The exact number of FC18 findings this repository's tracked markdown
/// carries.
///
/// Update it in the same commit as whatever moved it, and say in the commit
/// message which references changed. A bare number edit with no
/// corresponding reference change is the failure this test exists to make
/// visible.
const EXPECTED_FINDINGS: usize = 23;

/// Absolute path to the worktree root (parent of `crates/`).
fn worktree_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf()
}

/// Every tracked markdown file, from git rather than a directory walk: it
/// honors the ignore rules and excludes untracked scratch, which is the same
/// file set the repoint writes over.
fn tracked_markdown(root: &Path) -> Option<Vec<String>> {
    let output = Command::new("git")
        .arg("-C")
        .arg(root)
        .arg("ls-files")
        .arg("--")
        .arg("*.md")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let files: Vec<String> = text.lines().map(str::to_string).collect();
    if files.is_empty() {
        return None;
    }
    Some(files)
}

#[test]
fn fc18_corpus_count_is_pinned() {
    let root = worktree_root();
    let Some(files) = tracked_markdown(&root) else {
        // A distribution build that does not vendor the corpus. The unit
        // tests still pin the check's behavior.
        eprintln!("skipping fc18_corpus_count_is_pinned: no tracked markdown under {root:?}");
        return;
    };

    let bin = env!("CARGO_BIN_EXE_shirabe");
    let mut cmd = Command::new(bin);
    cmd.current_dir(&root)
        .arg("validate")
        .arg("--format")
        .arg("json")
        .arg("--check")
        .arg("FC18");
    for f in &files {
        cmd.arg(f);
    }
    let output = cmd.output().expect("run shirabe validate --check FC18");
    let stdout = String::from_utf8_lossy(&output.stdout);

    // Count `"code": "FC18"` rather than parsing JSON: the harness has no
    // JSON dependency, and the envelope's shape is pinned by its own tests.
    let found = stdout.matches("\"code\": \"FC18\"").count();

    assert_eq!(
        found, EXPECTED_FINDINGS,
        "FC18 finding count over {} tracked markdown files moved from {EXPECTED_FINDINGS} to {found}.\n\
         Re-run: git ls-files '*.md' | xargs shirabe validate --format json --check FC18\n\
         --- output ---\n{stdout}",
        files.len()
    );
}
