//! FC07 / FC09 corpus-surfacing self-check (Outline 5 AC-4).
//!
//! Exercises `shirabe validate --visibility=public` against the committed
//! plans and roadmaps and asserts:
//!
//! 1. The validator exits 0 (FC07 and FC09 ship notice-level; notices
//!    do not contribute to the exit code).
//! 2. Only notice-level codes (SCHEMA, FC07, FC09) appear on the
//!    committed docs that carry pre-existing drift (the staged-rollout's
//!    intended outcome).
//!
//! The test does NOT pin the exact notice text or count -- the
//! committed corpus may drift between this PR and the cleanup PR. The
//! pinned per-defect assertions live in the unit-level tests in
//! `shirabe-validate/src/checks.rs`.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Absolute path to the worktree root (parent of `crates/`).
fn worktree_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf()
}

#[test]
fn fc07_corpus_self_check_committed_plans_and_roadmaps() {
    let root = worktree_root();
    let docs = root.join("docs");
    if !docs.exists() {
        // Not running from a worktree with committed docs (e.g. a
        // distribution build that does not vendor docs/).
        eprintln!(
            "skipping fc07_corpus_self_check: {} does not exist",
            docs.display()
        );
        return;
    }

    let plan_glob = docs.join("plans");
    let roadmap_glob = docs.join("roadmaps");
    // Pass repo-relative paths so the validator's R6 upstream check (which
    // resolves `upstream:` paths against the process CWD) matches the
    // checked-in `upstream: docs/...` form.
    let mut targets: Vec<PathBuf> = Vec::new();
    for d in [plan_glob, roadmap_glob] {
        if let Ok(entries) = std::fs::read_dir(&d) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.extension().and_then(|e| e.to_str()) == Some("md") {
                    let rel = p.strip_prefix(&root).unwrap_or(&p).to_path_buf();
                    targets.push(rel);
                }
            }
        }
    }
    assert!(
        !targets.is_empty(),
        "expected at least one plan or roadmap under {}/{{plans,roadmaps}}",
        docs.display()
    );

    let bin = env!("CARGO_BIN_EXE_shirabe");
    let mut cmd = Command::new(bin);
    cmd.current_dir(&root);
    cmd.arg("validate").arg("--visibility=public");
    for t in &targets {
        cmd.arg(t);
    }
    let output = cmd.output().expect("failed to run shirabe");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let exit = output.status.code().unwrap_or(-1);

    // AC-4.1: exit 0. FC07 and FC09 are notice-level for v1; promotion
    // to error is a one-line is_notice change in a later cleanup PR.
    assert_eq!(
        exit, 0,
        "notice-level checks must not contribute to the exit code; got {} on the committed corpus.\nstdout: {}\nstderr: {}",
        exit,
        stdout,
        String::from_utf8_lossy(&output.stderr)
    );

    // AC-4.2: when the corpus carries drift, notice-level codes surface.
    // We do not pin the count (the committed corpus may drift PR-by-PR)
    // -- only that, if any notice line appears, it is from the
    // notice-level membership (SCHEMA, FC07-FC13, FC-CONVENTIONS).
    for line in stdout.lines() {
        if line.starts_with("::notice ") {
            assert!(
                line.contains("[FC07]")
                    || line.contains("[FC08]")
                    || line.contains("[FC09]")
                    || line.contains("[FC10]")
                    || line.contains("[FC11]")
                    || line.contains("[FC12]")
                    || line.contains("[FC13]")
                    || line.contains("[FC14]")
                    || line.contains("[FC-CONVENTIONS]")
                    || line.contains("[SCHEMA]"),
                "notice from non-notice-level code on the committed corpus: {}",
                line
            );
        }
    }
}
