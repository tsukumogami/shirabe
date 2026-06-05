//! CLI integration tests for the `shirabe transition` subcommand.
//!
//! These exercise the built binary end to end with `assert_cmd`, locking the
//! user-facing contract Issue 1 establishes: a legal change rewrites the doc
//! and emits the per-type JSON result on stdout (exit 0); an unknown status
//! emits an error with `code: 2` on stderr (exit 2); an unrecognized filename
//! exits 1.

use std::fs;

use assert_cmd::Command;
use predicates::str::contains;

fn shirabe() -> Command {
    Command::cargo_bin("shirabe").expect("binary `shirabe` builds")
}

/// Write `content` to a uniquely-named temp dir under the given basename and
/// return the path string.
fn write_doc(basename: &str, content: &str) -> String {
    let dir = std::env::temp_dir().join(format!(
        "shirabe-cli-transition-{}-{}",
        std::process::id(),
        basename
    ));
    fs::create_dir_all(&dir).expect("mkdir temp");
    let path = dir.join(basename);
    fs::write(&path, content).expect("write doc");
    path.to_string_lossy().into_owned()
}

#[test]
fn prd_legal_change_writes_doc_and_emits_base_result() {
    let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
    let path = write_doc("PRD-cli.md", doc);

    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("In Progress")
        .assert()
        .success()
        .stdout(contains("\"success\": true"))
        .stdout(contains("\"old_status\": \"Draft\""))
        .stdout(contains("\"new_status\": \"In Progress\""));

    let updated = fs::read_to_string(&path).unwrap();
    assert!(updated.contains("status: In Progress"));
    assert!(updated.contains("\n## Status\n\nIn Progress\n"));
}

#[test]
fn roadmap_legal_change_emits_new_path_and_moved_false() {
    // Draft -> Active is a legal edge; the >=2-features precondition (Issue 2)
    // is satisfied by the two `### Feature` headings.
    let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n\n### Feature A\n### Feature B\n";
    let path = write_doc("ROADMAP-cli.md", doc);

    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Active")
        .assert()
        .success()
        .stdout(contains("\"new_path\""))
        .stdout(contains("\"moved\": false"));
}

#[test]
fn unknown_status_exits_2_with_code_field() {
    let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
    let path = write_doc("BRIEF-cli.md", doc);

    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Bogus")
        .assert()
        .code(2)
        .stderr(contains("\"code\": 2"))
        .stderr(contains("Invalid status"));
}

#[test]
fn unrecognized_filename_exits_1() {
    let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
    let path = write_doc("README.md", doc);

    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Done")
        .assert()
        .code(1)
        .stderr(contains("\"code\": 1"))
        .stderr(contains("cannot determine artifact type"));
}
