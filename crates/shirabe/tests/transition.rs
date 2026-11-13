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
    // Draft -> Active is a legal edge; the non-empty-features precondition
    // (Issue 2) is satisfied by the `### Feature` headings.
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

// ---- design Draft status ----
//
// A design is written at `Draft` with only `status` and `problem`, moves to
// `Proposed` once its decision is written, and can come back to `Draft` only
// from `Proposed`. Each test gives its document a distinct basename, since
// `write_doc` names the temp dir after it.

const PROBLEM: &str = "problem: |\n  The problem.\n";
const DECISION_AND_RATIONALE: &str =
    "decision: |\n  The decision.\nrationale: |\n  The rationale.\n";

/// A design whose frontmatter is `schema`, `status: <status>` and `extra_fm`,
/// and whose body holds all nine required sections: the Status (the status
/// value without quotes or surrounding spaces), a sentence each under Context
/// and Problem Statement and Decision Drivers, and one stub line in each of
/// the other six.
fn design_doc(status: &str, extra_fm: &str) -> String {
    let body_status = status.trim().trim_matches('"');
    format!(
        "---\nschema: design/v1\nstatus: {}\n{}---\n\n# DESIGN: t\n\n## Status\n\n{}\n\n## Context and Problem Statement\n\nThe problem.\n\n## Decision Drivers\n\nA driver.\n\n## Considered Options\n\nTo be written.\n\n## Decision Outcome\n\nTo be written.\n\n## Solution Architecture\n\nTo be written.\n\n## Implementation Approach\n\nTo be written.\n\n## Security Considerations\n\nTo be written.\n\n## Consequences\n\nTo be written.\n",
        status, extra_fm, body_status
    )
}

/// Run `shirabe validate <path>` and return (exit code, stdout).
fn validate(path: &str) -> (i32, String) {
    let out = shirabe()
        .arg("validate")
        .arg(path)
        .output()
        .expect("run shirabe");
    let code = out.status.code().expect("exit code");
    let stdout = String::from_utf8(out.stdout).expect("utf8 stdout");
    (code, stdout)
}

/// Output lines carrying the given check code.
fn lines_with<'a>(text: &'a str, code: &str) -> Vec<&'a str> {
    let tag = format!("[{}]", code);
    text.lines().filter(|l| l.contains(&tag)).collect()
}

/// Assert `out` holds FC01 for `decision` and for `rationale` and no other
/// FC01.
fn assert_fc01_decision_and_rationale(out: &str) {
    let fc01 = lines_with(out, "FC01");
    assert_eq!(fc01.len(), 2, "{}", out);
    assert!(fc01.iter().any(|l| l.contains("\"decision\"")), "{}", out);
    assert!(fc01.iter().any(|l| l.contains("\"rationale\"")), "{}", out);
}

#[test]
fn design_draft_skeleton_validates_clean() {
    let path = write_doc("DESIGN-draft-skeleton.md", &design_doc("Draft", PROBLEM));
    let (code, out) = validate(&path);
    assert_eq!(code, 0, "{}", out);
    for check in ["FC01", "FC02", "FC03", "FC04"] {
        assert!(lines_with(&out, check).is_empty(), "{}: {}", check, out);
    }
}

#[test]
fn design_draft_missing_problem_gets_one_fc01() {
    let path = write_doc("DESIGN-draft-no-problem.md", &design_doc("Draft", ""));
    let (code, out) = validate(&path);
    assert_eq!(code, 2, "{}", out);
    let fc01 = lines_with(&out, "FC01");
    assert_eq!(fc01.len(), 1, "{}", out);
    assert!(fc01[0].contains("\"problem\""), "{}", out);
    assert!(!out.contains("\"decision\""), "{}", out);
    assert!(!out.contains("\"rationale\""), "{}", out);
}

#[test]
fn design_later_statuses_still_need_decision_and_rationale() {
    for status in ["Proposed", "Accepted", "Planned", "Current", "Superseded"] {
        let path = write_doc(
            &format!("DESIGN-later-{}.md", status),
            &design_doc(status, PROBLEM),
        );
        let (code, out) = validate(&path);
        assert_eq!(code, 2, "{}: {}", status, out);
        assert_fc01_decision_and_rationale(&out);
    }
}

#[test]
fn design_statusless_skeleton_still_refused() {
    let doc = "---\nschema: design/v1\n---\n\n# DESIGN: t\n\n## Status\n\nProposed\n\n## Context and Problem Statement\n\nThe problem.\n\n## Decision Drivers\n\nA driver.\n";
    let path = write_doc("DESIGN-statusless.md", doc);
    let (code, out) = validate(&path);
    assert_eq!(code, 2, "{}", out);
    assert_eq!(lines_with(&out, "FC01").len(), 4, "{}", out);
    assert_eq!(lines_with(&out, "FC03").len(), 1, "{}", out);
    assert_eq!(lines_with(&out, "FC04").len(), 6, "{}", out);
}

#[test]
fn design_draft_spelling() {
    // Lowercase `draft` is outside the design enum and keeps the full field
    // list.
    let lower = write_doc("DESIGN-spelling-lower.md", &design_doc("draft", PROBLEM));
    let (code, out) = validate(&lower);
    assert_eq!(code, 2, "{}", out);
    assert_eq!(lines_with(&out, "FC02").len(), 1, "{}", out);
    assert_fc01_decision_and_rationale(&out);

    // A quoted value and one followed by trailing spaces parse to `Draft` and
    // give the same findings and exit code as the unquoted value.
    let plain = write_doc("DESIGN-spelling-plain.md", &design_doc("Draft", PROBLEM));
    let (plain_code, plain_out) = validate(&plain);
    assert_eq!(plain_code, 0, "{}", plain_out);
    let plain_out = plain_out.replace(&plain, "<doc>");
    for (basename, status) in [
        ("DESIGN-spelling-quoted.md", "\"Draft\""),
        ("DESIGN-spelling-spaces.md", "Draft   "),
    ] {
        let path = write_doc(basename, &design_doc(status, PROBLEM));
        let (code, out) = validate(&path);
        assert_eq!(code, plain_code, "{:?}: {}", status, out);
        assert_eq!(out.replace(&path, "<doc>"), plain_out, "{:?}", status);
    }
}

#[test]
fn design_draft_to_proposed_rewrites_both_lines() {
    let path = write_doc("DESIGN-draft-to-proposed.md", &design_doc("Draft", PROBLEM));

    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Proposed")
        .assert()
        .success()
        .stdout(contains("\"old_status\": \"Draft\""))
        .stdout(contains("\"new_status\": \"Proposed\""));

    let updated = fs::read_to_string(&path).unwrap();
    assert!(updated.contains("\nstatus: Proposed\n"), "{}", updated);
    assert!(updated.contains("\n## Status\n\nProposed\n"), "{}", updated);
    assert!(!updated.contains("Draft"), "{}", updated);

    // At Proposed the design needs its decision and rationale.
    let (code, out) = validate(&path);
    assert_eq!(code, 2, "{}", out);
    assert_fc01_decision_and_rationale(&out);
}

#[test]
fn design_proposed_to_draft_rewrites_both_lines() {
    let path = write_doc(
        "DESIGN-proposed-to-draft.md",
        &design_doc("Proposed", PROBLEM),
    );

    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Draft")
        .assert()
        .success()
        .stdout(contains("\"old_status\": \"Proposed\""))
        .stdout(contains("\"new_status\": \"Draft\""));

    let updated = fs::read_to_string(&path).unwrap();
    assert!(updated.contains("\nstatus: Draft\n"), "{}", updated);
    assert!(updated.contains("\n## Status\n\nDraft\n"), "{}", updated);
    assert!(!updated.contains("Proposed"), "{}", updated);
}

#[test]
fn design_into_draft_refused_from_later_statuses() {
    for status in ["Accepted", "Planned", "Current", "Superseded"] {
        let mut extra = format!("{}{}", PROBLEM, DECISION_AND_RATIONALE);
        if status == "Superseded" {
            extra.push_str("superseded_by: docs/designs/DESIGN-new.md\n");
        }
        let doc = design_doc(status, &extra);
        let path = write_doc(&format!("DESIGN-refuse-draft-{}.md", status), &doc);

        shirabe()
            .arg("transition")
            .arg(&path)
            .arg("Draft")
            .assert()
            .code(2)
            .stderr(contains("\"code\": 2"))
            .stderr(contains(format!(
                "Invalid transition: {} -> Draft. A design moves into Draft only from Proposed.",
                status
            )));

        assert_eq!(fs::read_to_string(&path).unwrap(), doc, "{}", status);
    }
}

#[test]
fn design_draft_to_draft_is_a_no_op() {
    let doc = design_doc("Draft", PROBLEM);
    let path = write_doc("DESIGN-draft-no-op.md", &doc);

    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Draft")
        .assert()
        .success()
        .stdout(contains("\"old_status\": \"Draft\""))
        .stdout(contains("\"new_status\": \"Draft\""));

    assert_eq!(fs::read_to_string(&path).unwrap(), doc);
}
