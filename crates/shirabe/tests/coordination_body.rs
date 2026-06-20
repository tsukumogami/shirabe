//! CLI integration tests for `shirabe validate --coordination-body <FILE>`,
//! the static authoring-feedback check over an authored coordination PR body.
//!
//! These exercise the built binary end to end, entirely offline (no `gh`): the
//! mode reads a body file and checks the declaration marker, every cross-repo
//! ref token's F2 validity, and the merge-order block's acyclicity. The pure
//! check logic is unit-tested in `shirabe_validate::coordination`; these tests
//! lock the CLI shell (file read, exit code, mutual exclusions, `--format`).

use std::io::Write;

use assert_cmd::Command;
use predicates::str::contains;

fn shirabe() -> Command {
    Command::cargo_bin("shirabe").expect("binary `shirabe` builds")
}

const MARKER: &str = "This is a **coordination PR**";

fn good_body() -> String {
    format!(
        "# Coordination PR: capstone-orchestration\n\n\
         > {MARKER} for a coordinated multi-repo effort. It merges last. \
         See references/coordination-strategy.md.\n\n\
         ## Artifact Chain\n\n\
         - docs/plans/PLAN-capstone-orchestration.md\n\n\
         ## PR Index\n\n\
         - pr-1 | tsukumogami/shirabe:docs/plans/PLAN-x.md#196 | open\n\
         - pr-2 | tsukumogami/koto:docs/plans/PLAN-y.md#5 | merged\n\n\
         ## Merge Order\n\n\
         ```merge-order\n\
         # Two-node merge-order DAG.\n\
         pr-1 | open\n\
         pr-2 | merged\n\
         ```\n"
    )
}

fn write_temp(name: &str, contents: &str) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
        "shirabe-coordbody-{}-{}-{}.md",
        std::process::id(),
        name,
        line!()
    ));
    let mut f = std::fs::File::create(&path).expect("create temp body file");
    f.write_all(contents.as_bytes())
        .expect("write temp body file");
    path
}

#[test]
fn coordination_body_clean_body_passes() {
    let path = write_temp("clean", &good_body());
    shirabe()
        .args(["validate", "--coordination-body"])
        .arg(&path)
        .assert()
        .code(0);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn coordination_body_missing_marker_fails() {
    let body = good_body().replace(MARKER, "This is an ordinary PR");
    let path = write_temp("nomarker", &body);
    shirabe()
        .args(["validate", "--coordination-body"])
        .arg(&path)
        .assert()
        .code(2)
        .stdout(contains("declaration marker"));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn coordination_body_malformed_ref_fails() {
    let body = good_body().replace(
        "tsukumogami/shirabe:docs/plans/PLAN-x.md#196",
        "tsukumogami/shirabe:../escape.md#196",
    );
    let path = write_temp("badref", &body);
    shirabe()
        .args(["validate", "--format", "annotation", "--coordination-body"])
        .arg(&path)
        .assert()
        .code(2)
        .stdout(contains("F2"));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn coordination_body_unreadable_file_is_tool_error() {
    shirabe()
        .args([
            "validate",
            "--coordination-body",
            "/nonexistent/path/coordination-body.md",
        ])
        .assert()
        .code(1)
        .stderr(contains("could not read"));
}

#[test]
fn coordination_body_conflicts_with_merge_gate() {
    // Both are validate modes; clap rejects combining them (usage error, exit 2).
    shirabe()
        .args(["validate", "--coordination-body", "x.md", "--merge-gate"])
        .assert()
        .failure();
}

#[test]
fn coordination_body_rejects_positional_files() {
    shirabe()
        .args(["validate", "--coordination-body", "body.md", "docs/foo.md"])
        .assert()
        .code(1)
        .stderr(contains(
            "--coordination-body is mutually exclusive with positional file arguments",
        ));
}
