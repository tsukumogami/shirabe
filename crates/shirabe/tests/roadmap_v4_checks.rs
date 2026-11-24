//! The `roadmap/v4` checks of `shirabe validate`, end to end.
//!
//! On a `roadmap/v4` roadmap FC21 refuses the roadmap's own Done while a
//! milestone doesn't close, a milestone whose block Status and Progress table
//! row disagree, and a milestone at Done; FC07 reconciles the `completed` and
//! `dropped` diagram classes and FC08 counts them in its palette. These tests
//! drive the built binary on the fixtures under `tests/fixtures/roadmap-v4/`,
//! editing a scratch copy where a case needs a variant. That none of it
//! reaches a v1 to v3 roadmap is shown here for the Progress table and the
//! roadmap's Done, and for every corpus roadmap by `roadmap_identity.rs`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn fixture(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(rel)
}

/// Validate a copy of the fixture `rel` after applying `edits` (each a
/// `(from, to)` text replacement that must match), returning the exit code
/// and the combined output. `tag` keeps tests copying the same fixture out
/// of each other's way.
fn validate_variant(rel: &str, tag: &str, edits: &[(&str, &str)]) -> (Option<i32>, String) {
    let name = Path::new(rel)
        .file_name()
        .unwrap()
        .to_string_lossy()
        .into_owned();
    let dir = std::env::temp_dir().join(format!("shirabe-v4-checks-{}-{tag}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("mkdir scratch");
    let mut doc = fs::read_to_string(fixture(rel)).expect("read fixture");
    for (from, to) in edits {
        assert!(doc.contains(from), "{rel} has no {from:?}");
        doc = doc.replace(from, to);
    }
    fs::write(dir.join(&name), doc).expect("write variant");
    let out: Output = Command::new(env!("CARGO_BIN_EXE_shirabe"))
        .current_dir(&dir)
        .env_remove("SHIRABE_PR_NUMBER")
        .env_remove("GITHUB_REF")
        .env_remove("GITHUB_REPOSITORY")
        .env_remove("GITHUB_TOKEN")
        .args(["validate", &name])
        .output()
        .expect("run shirabe validate");
    let _ = fs::remove_dir_all(&dir);
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    (out.status.code(), text)
}

/// The output lines carrying `code`.
fn lines_with<'a>(text: &'a str, code: &str) -> Vec<&'a str> {
    let tag = format!("[{code}]");
    text.lines().filter(|l| l.contains(&tag)).collect()
}

/// A Done roadmap whose milestones read Verified and Dropped. The failing
/// cases are built from it here rather than committed: every committed
/// roadmap must pass FC21 (`milestone_roadmap.rs` checks them all).
const DONE_CLOSED: &str = "roadmap-v4/ROADMAP-done-closed.md";
const PROGRESS: &str = "roadmap-v4/ROADMAP-progress-table.md";
const POPULATED: &str = "roadmap-v4/ROADMAP-populated-classes.md";

#[test]
fn a_done_v4_roadmap_fails_once_per_milestone_that_does_not_close() {
    let (code, t) = validate_variant(
        DONE_CLOSED,
        "done-open",
        &[
            ("**Status:** Verified", "**Status:** Completed"),
            ("**Status:** Dropped", "**Status:** In progress"),
        ],
    );
    assert_eq!(code, Some(2), "{t}");
    let fc21 = lines_with(&t, "FC21");
    assert_eq!(fc21.len(), 2, "{t}");
    assert!(
        fc21[0].contains("milestone 'Milestone 1: Loader' has Status 'Completed' on a roadmap whose status is Done"),
        "{t}"
    );
    assert!(
        fc21[1].contains("milestone 'Milestone 2: Registry' has Status 'In progress' on a roadmap whose status is Done"),
        "{t}"
    );
}

#[test]
fn a_done_v4_roadmap_passes_once_every_milestone_is_verified_or_dropped() {
    let cases: [(&str, &[(&str, &str)]); 2] = [
        ("verified-dropped", &[]),
        (
            "all-dropped",
            &[("**Status:** Verified", "**Status:** Dropped")],
        ),
    ];
    for (tag, edits) in cases {
        let (code, t) = validate_variant(DONE_CLOSED, tag, edits);
        assert_eq!(code, Some(0), "{tag}: {t}");
        assert!(lines_with(&t, "FC21").is_empty(), "{tag}: {t}");
    }
}

#[test]
fn a_v4_block_status_that_disagrees_with_its_progress_row_fails_naming_both() {
    let (code, t) = validate_variant(PROGRESS, "progress-matching", &[]);
    assert_eq!(code, Some(0), "matching rows pass: {t}");

    let (code, t) = validate_variant(
        PROGRESS,
        "progress-disagrees",
        &[(
            "| Milestone 1: Loader | Completed | -- |",
            "| Milestone 1: Loader | In progress | -- |",
        )],
    );
    assert_eq!(code, Some(2), "{t}");
    let fc21 = lines_with(&t, "FC21");
    assert_eq!(fc21.len(), 1, "only Milestone 1, never Milestone 12: {t}");
    assert!(
        fc21[0].contains(
            "milestone 'Milestone 1: Loader' has Status 'Completed' in its block but 'In progress' in its Progress table row"
        ),
        "{t}"
    );
    assert!(fc21[0].contains("line=69"), "finding is on the row: {t}");
}

#[test]
fn a_v4_roadmap_with_no_progress_table_passes_the_row_check() {
    let (code, t) = validate_variant("roadmap-v4/ROADMAP-five-statuses.md", "no-table", &[]);
    assert_eq!(code, Some(0), "{t}");
}

#[test]
fn a_v4_milestone_at_done_fails_naming_it_and_the_five_statuses() {
    let (code, t) = validate_variant(
        "roadmap-v4/ROADMAP-five-statuses.md",
        "milestone-done",
        &[("**Status:** Verified", "**Status:** Done")],
    );
    assert_eq!(code, Some(2), "{t}");
    let fc21 = lines_with(&t, "FC21");
    assert_eq!(fc21.len(), 1, "{t}");
    assert!(
        fc21[0].contains(
            "milestone 'Milestone 3: Search' has Status 'Done', not one of Not started, In progress, Completed, Verified, Dropped"
        ),
        "{t}"
    );
}

#[test]
fn a_populated_v4_diagram_with_completed_and_dropped_passes_fc07_and_fc08() {
    let (code, t) = validate_variant(POPULATED, "populated", &[]);
    assert_eq!(code, Some(0), "{t}");
    assert!(lines_with(&t, "FC07").is_empty(), "{t}");
    assert!(lines_with(&t, "FC08").is_empty(), "{t}");
}

#[test]
fn fc07_on_v4_expects_the_class_the_status_table_gives() {
    let cases = [
        (
            "completed-as-ready",
            "class I11 completed",
            "class I11 ready",
            "I11",
            "completed",
        ),
        (
            "dropped-as-done",
            "class I14 dropped",
            "class I14 done",
            "I14",
            "dropped",
        ),
        (
            "verified-as-completed",
            "class I13 done",
            "class I13 completed",
            "I13",
            "done",
        ),
    ];
    for (tag, from, to, node, want) in cases {
        let (_, t) = validate_variant(POPULATED, tag, &[(from, to)]);
        let fc07 = lines_with(&t, "FC07");
        assert_eq!(fc07.len(), 1, "{tag}: {t}");
        assert!(
            fc07[0].contains(&format!("node \"{node}\""))
                && fc07[0].contains(&format!("expected class \"{want}\"")),
            "{tag}: {t}"
        );
    }
}

#[test]
fn a_v3_diagram_using_completed_still_gets_fc08_as_before() {
    let (_, t) = validate_variant(
        POPULATED,
        "v3-completed",
        &[
            ("schema: roadmap/v4", "schema: roadmap/v3"),
            ("Completed", "Done"),
            ("Verified", "Done"),
        ],
    );
    let fc08 = lines_with(&t, "FC08");
    assert_eq!(fc08.len(), 2, "{t}");
    assert!(
        fc08[0].contains("`classDef completed` outside the canonical Status palette"),
        "{t}"
    );
    assert!(
        fc08[1].contains("`classDef dropped` outside the canonical Status palette"),
        "{t}"
    );
    assert!(lines_with(&t, "FC07").is_empty(), "{t}");
}

#[test]
fn the_v4_checks_never_fire_on_a_v3_roadmap() {
    // A v3 roadmap at Done with an open milestone, and a Progress row that
    // disagrees with its block: both are v4 rules, so v3 reports neither.
    let (code, t) = validate_variant(
        PROGRESS,
        "v3-progress",
        &[
            ("schema: roadmap/v4", "schema: roadmap/v3"),
            ("status: Active", "status: Done"),
            ("## Status\n\nActive", "## Status\n\nDone"),
            ("**Status:** Completed", "**Status:** Done"),
            ("**Status:** Verified", "**Status:** Done"),
            (
                "| Milestone 1: Loader | Completed | -- |",
                "| Milestone 1: Loader | Not started | -- |",
            ),
        ],
    );
    assert!(lines_with(&t, "FC21").is_empty(), "{t}");
    assert_eq!(code, Some(0), "{t}");
}
