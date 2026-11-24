//! Milestone statuses read through the shared status table, end to end.
//!
//! `skills/roadmap/references/milestone-statuses.json` decides what every
//! milestone Status means, and `shirabe validate` and `shirabe roadmap
//! populate` read it through `shirabe_validate::statuses`. These tests drive
//! the built binary on the fixtures under `tests/fixtures/roadmap-v4/` and
//! `tests/fixtures/roadmap-v3/`: a `roadmap/v4` roadmap with all five statuses,
//! a `roadmap/v3` roadmap at Shipped and Closed, and a v3/v4 pair where a
//! dependent of a Dropped milestone stays blocked and a dependent of a
//! finished one is ready. That v1 to v3 roadmaps otherwise read exactly as
//! before is `roadmap_identity.rs`'s job.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn fixture(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(rel)
}

fn shirabe(cwd: &Path) -> Command {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_shirabe"));
    cmd.current_dir(cwd)
        .env_remove("SHIRABE_PR_NUMBER")
        .env_remove("GITHUB_REF")
        .env_remove("GITHUB_REPOSITORY")
        .env_remove("GITHUB_TOKEN");
    cmd
}

fn text(out: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    )
}

/// A scratch copy of the fixture `rel`, so populate can rewrite it; `tag`
/// keeps two tests copying the same fixture out of each other's way.
fn scratch_copy(rel: &str, tag: &str) -> (PathBuf, String) {
    let name = Path::new(rel)
        .file_name()
        .unwrap()
        .to_string_lossy()
        .into_owned();
    let dir = std::env::temp_dir().join(format!(
        "shirabe-statuses-{}-{tag}-{}",
        std::process::id(),
        name.trim_end_matches(".md")
    ));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("mkdir scratch");
    fs::copy(fixture(rel), dir.join(&name)).expect("copy fixture");
    (dir, name)
}

fn validate(dir: &Path, name: &str) -> Output {
    shirabe(dir)
        .args(["validate", name])
        .output()
        .expect("run shirabe validate")
}

/// Validate the fixture (must pass), populate it, validate the result (must
/// pass) and return the populated document.
fn populate(rel: &str) -> String {
    let (dir, name) = scratch_copy(rel, "populate");
    let out = validate(&dir, &name);
    assert_eq!(
        out.status.code(),
        Some(0),
        "{rel} validates: {}",
        text(&out)
    );
    let out = shirabe(&dir)
        .args(["roadmap", "populate", "--no-issues", &name])
        .output()
        .expect("run shirabe roadmap populate");
    assert!(out.status.success(), "{rel} populates: {}", text(&out));
    let doc = fs::read_to_string(dir.join(&name)).expect("read populated roadmap");
    let out = validate(&dir, &name);
    assert_eq!(
        out.status.code(),
        Some(0),
        "{rel} validates after populate: {}\n{doc}",
        text(&out)
    );
    let _ = fs::remove_dir_all(&dir);
    doc
}

/// The populated table row for `label` and the class line for node `F<n>`.
fn row<'a>(doc: &'a str, label: &str) -> &'a str {
    let plain = format!("| {label} |");
    let struck = format!("| ~~{label}~~ |");
    doc.lines()
        .find(|l| l.starts_with(&plain) || l.starts_with(&struck))
        .unwrap_or_else(|| panic!("no row for {label}:\n{doc}"))
}

fn assert_class(doc: &str, node: usize, class: &str) {
    let line = format!("    class F{node} {class}");
    assert!(
        doc.lines().any(|l| l == line),
        "expected `{line}` in:\n{doc}"
    );
}

fn assert_struck(doc: &str, label: &str, struck: bool) {
    let r = row(doc, label);
    assert_eq!(
        r.starts_with("| ~~"),
        struck,
        "{label} struck={struck}: {r}"
    );
}

#[test]
fn a_v4_roadmap_renders_completed_apart_from_verified() {
    let doc = populate("roadmap-v4/ROADMAP-five-statuses.md");

    // Completed: unstruck, its own class, and its dependent is ready.
    assert_struck(&doc, "Loader", false);
    assert_class(&doc, 1, "completed");
    assert_struck(&doc, "Registry", false);
    assert_class(&doc, 2, "ready");
    // Verified: struck, done.
    assert_struck(&doc, "Search", true);
    assert_class(&doc, 3, "done");
    // Dropped: struck, dropped.
    assert_struck(&doc, "Old index", true);
    assert_class(&doc, 4, "dropped");
    // In progress: open.
    assert_struck(&doc, "Docs", false);
    assert_class(&doc, 5, "ready");

    assert!(doc.contains("    classDef completed "), "{doc}");
    assert!(doc.contains("    classDef dropped "), "{doc}");
    let legend = doc
        .lines()
        .find(|l| l.starts_with("**Legend**:"))
        .expect("a Legend line");
    assert!(
        legend.contains("= completed") && legend.contains("= dropped"),
        "{legend}"
    );
}

#[test]
fn a_v3_roadmap_at_shipped_and_closed_reads_as_done() {
    let doc = populate("roadmap-v3/ROADMAP-shipped-closed.md");
    assert_struck(&doc, "Loader", true);
    assert_class(&doc, 1, "done");
    assert_class(&doc, 2, "ready");
    assert_struck(&doc, "Search", true);
    assert_class(&doc, 3, "done");
    assert_class(&doc, 4, "ready");
    assert!(!doc.contains("classDef completed") && !doc.contains("classDef dropped"));
}

#[test]
fn a_dropped_dependency_blocks_and_a_finished_one_does_not_on_v3_and_v4() {
    for (rel, dropped_struck, finished_class) in [
        ("roadmap-v3/ROADMAP-dropped-done.md", false, "done"),
        ("roadmap-v4/ROADMAP-dropped-completed.md", true, "completed"),
    ] {
        let doc = populate(rel);
        // Milestone 1 is Dropped: struck only on v4, and on both it never
        // satisfies Milestone 2.
        assert_struck(&doc, "Old index", dropped_struck);
        assert_class(&doc, 2, "blocked");
        // Milestone 3 is Done (v3) or Completed (v4): Milestone 4 is ready.
        assert_class(&doc, 3, finished_class);
        assert_class(&doc, 4, "ready");
    }
}

#[test]
fn a_v4_milestone_at_a_v1_to_v3_word_fails_fc21_naming_the_five_words() {
    let (dir, name) = scratch_copy("roadmap-v4/ROADMAP-five-statuses.md", "fc21");
    let path = dir.join(&name);
    let doc = fs::read_to_string(&path)
        .unwrap()
        .replace("**Status:** Verified", "**Status:** Done");
    fs::write(&path, doc).unwrap();
    let out = validate(&dir, &name);
    let t = text(&out);
    assert_ne!(out.status.code(), Some(0), "{t}");
    assert!(
        t.contains(
            "has Status 'Done', not one of Not started, In progress, Completed, Verified, Dropped"
        ),
        "{t}"
    );
    let _ = fs::remove_dir_all(&dir);
}

/// `shirabe --version` names the status table it embeds, and that is the
/// `version` of the file in the roadmap skill's references. The version line
/// itself stays the one stdout line the release check compares.
#[test]
fn version_names_the_embedded_status_table() {
    let file = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../skills/roadmap/references/milestone-statuses.json");
    let v: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(file).expect("read table")).expect("parse table");
    let version = v["version"].as_u64().expect("a numeric version");

    let out = shirabe(Path::new(env!("CARGO_MANIFEST_DIR")))
        .arg("--version")
        .output()
        .expect("run shirabe --version");
    assert!(out.status.success());
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        format!("shirabe {}\n", env!("CARGO_PKG_VERSION"))
    );
    assert_eq!(
        String::from_utf8_lossy(&out.stderr),
        format!("milestone statuses table version {version}\n")
    );
}
