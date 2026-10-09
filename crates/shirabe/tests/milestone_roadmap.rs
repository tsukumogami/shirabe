//! CLI integration tests for milestone roadmaps (`schema: roadmap/v2`).
//!
//! A `roadmap/v2` roadmap is checked by every roadmap check plus FC21, which
//! names each milestone missing its Outcome, Evidence, Left open or
//! Dependencies, carrying a Status outside the four values, naming a
//! dependency that is no other milestone, repeating a tag, or hidden behind a
//! heading that isn't a milestone heading. A `roadmap/v1` roadmap gets none of
//! that. These tests drive the built binary end to end.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;

use assert_cmd::Command;
use predicates::str::contains;

fn shirabe() -> Command {
    Command::cargo_bin("shirabe").expect("binary `shirabe` builds")
}

/// Write `content` as `ROADMAP-<tag>.md` in a temp dir unique to the test
/// and return its path.
fn write_roadmap(tag: &str, content: &str) -> PathBuf {
    let dir =
        std::env::temp_dir().join(format!("shirabe-milestone-{}-{}", std::process::id(), tag));
    fs::create_dir_all(&dir).expect("mkdir temp");
    let path = dir.join(format!("ROADMAP-{tag}.md"));
    fs::write(&path, content).expect("write roadmap");
    path
}

/// A roadmap whose Features section is `features`, around the other
/// sections in their canonical order, at the given schema.
fn roadmap(schema: &str, features: &str) -> String {
    format!(
        "---\nschema: {schema}\nstatus: Draft\ntheme: |\n  Plugins a maintainer can find.\n\
         scope: |\n  The loader and the registry.\n---\n\n\
         # ROADMAP: plugins\n\n\
         ## Status\n\nDraft\n\n\
         ## Theme\n\nPlugins a maintainer can find.\n\n\
         ## Features\n\n{features}\n\
         ## Sequencing Rationale\n\nThe loader comes first because the registry reads what it loads.\n\n\
         ## Progress\n\nNothing has started.\n\n\
         ## Implementation Issues\n\n\
         <!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->\n\n\
         | Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n\n\
         ## Dependency Graph\n\n\
         <!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->\n\n\
         ```mermaid\ngraph TD\n```\n"
    )
}

/// The first milestone, every field present.
const AB1: &str = "### AB1: Loader\n\n\
**Outcome:** A maintainer who installed three plugins sees each one\n\
listed by name with the version it loaded.\n\n\
**Evidence:**\n\
- A reviewer, from a clean install with three sample plugins, runs the\n  \
  list command and sees exactly those three names and versions.\n\n\
**Left open:** None\n\n\
**Needs:** `needs-design` -- the loader's manifest shape\n\
**Dependencies:** None\n\
**Status:** Not started\n\n";

/// The second milestone, with a letter-suffixed tag, a cross-repo
/// dependency, a `**Downstream:**` line and free prose.
const AB10A: &str = "### AB10a: Registry\n\n\
**Outcome:** A maintainer finds a plugin by name without reading the\n\
plugin directory.\n\n\
**Evidence:**\n\
- A reviewer runs the find command for an installed plugin and sees its\n  \
  path; for a missing one, a message naming it and a non-zero exit.\n\
- The same reviewer removes a manifest and sees the plugin skipped by name.\n\n\
**Left open:** the registry's storage format.\n\n\
**Dependencies:** AB1, acme/widgets#12\n\
**Status:** In progress\n\
**Downstream:** PLAN-registry.md\n\n\
The registry builds on the loader.\n\n";

fn valid() -> String {
    format!("{AB1}{AB10A}")
}

/// Run `shirabe validate` on `path`; returns (success, combined output).
fn validate(path: &Path, extra: &[&str]) -> (bool, String) {
    let out = shirabe()
        .arg("validate")
        .args(extra)
        .arg(path)
        .output()
        .expect("run shirabe validate");
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    (out.status.success(), text)
}

fn fc21_lines(text: &str) -> Vec<String> {
    text.lines()
        .filter(|l| l.contains("[FC21]"))
        .map(str::to_string)
        .collect()
}

#[test]
fn a_valid_milestone_roadmap_has_no_findings() {
    let path = write_roadmap("valid", &roadmap("roadmap/v2", &valid()));
    let (ok, text) = validate(&path, &[]);
    assert!(ok, "expected a clean run, got:\n{text}");
    assert!(fc21_lines(&text).is_empty(), "{text}");
}

#[test]
fn a_milestone_missing_evidence_fails_by_name() {
    let features = valid().replace(
        "**Evidence:**\n- A reviewer, from a clean install with three sample plugins, runs the\n  list command and sees exactly those three names and versions.\n\n",
        "",
    );
    let path = write_roadmap("no-evidence", &roadmap("roadmap/v2", &features));
    let (ok, text) = validate(&path, &[]);
    assert!(!ok, "a milestone missing Evidence must fail:\n{text}");
    let lines = fc21_lines(&text);
    assert_eq!(lines.len(), 1, "{text}");
    assert!(
        lines[0].contains("[FC21] milestone 'AB1: Loader' has no Evidence"),
        "{text}"
    );
}

/// Each case: (name, edit applied to the valid features, expected message).
fn cases() -> Vec<(&'static str, String, &'static str)> {
    let v = valid();
    vec![
        (
            "no-outcome",
            v.replace(
                "**Outcome:** A maintainer who installed three plugins sees each one\nlisted by name with the version it loaded.\n\n",
                "",
            ),
            "milestone 'AB1: Loader' has no Outcome",
        ),
        (
            "empty-outcome",
            v.replace(
                "**Outcome:** A maintainer who installed three plugins sees each one\nlisted by name with the version it loaded.\n",
                "**Outcome:**\n",
            ),
            "milestone 'AB1: Loader' has an empty Outcome",
        ),
        (
            "no-clause",
            v.replace(
                "**Evidence:**\n- A reviewer, from a clean install",
                "**Evidence:**\n\nA reviewer, from a clean install",
            ),
            "milestone 'AB1: Loader' has no Evidence clause",
        ),
        (
            "no-left-open",
            v.replace("**Left open:** None\n\n", ""),
            "milestone 'AB1: Loader' has no Left open",
        ),
        (
            "empty-dependencies",
            v.replace("**Dependencies:** None\n", "**Dependencies:**\n"),
            "milestone 'AB1: Loader' has no Dependencies",
        ),
        (
            "continued-dependencies",
            v.replace(
                "**Dependencies:** AB1, acme/widgets#12\n",
                "**Dependencies:** AB1,\nacme/widgets#12\n",
            ),
            "milestone 'AB10a: Registry' has a Dependencies line that continues onto the next line",
        ),
        (
            "unknown-dependency",
            v.replace("**Dependencies:** AB1, acme/widgets#12", "**Dependencies:** ZZ9"),
            "milestone 'AB10a: Registry' names 'ZZ9' in Dependencies, which is no other milestone",
        ),
        (
            "none-with-a-tag",
            v.replace("**Dependencies:** AB1, acme/widgets#12", "**Dependencies:** None, AB1"),
            "milestone 'AB10a: Registry' names 'None' in Dependencies, which is no other milestone",
        ),
        (
            "annotated-status",
            v.replace("**Status:** In progress", "**Status:** Done -- shipped"),
            "milestone 'AB10a: Registry' has Status 'Done -- shipped', not one of Not started, In progress, Done, Dropped",
        ),
        (
            "no-status",
            v.replace("**Status:** Not started\n", ""),
            "milestone 'AB1: Loader' has no Status",
        ),
        (
            "duplicate-tag",
            v.replace("### AB10a: Registry", "### AB1: Registry")
                .replace("**Dependencies:** AB1, acme/widgets#12", "**Dependencies:** None"),
            "milestone 'AB1: Registry' repeats the tag of the milestone at line",
        ),
        (
            "empty-title",
            format!("{v}### AB2:\n\n"),
            "heading '### AB2:' is not a milestone heading",
        ),
        (
            // Every field is there, but the coordinator's reader needs the
            // space after the colon and would drop the item; the heading is
            // the one finding.
            "no-space-after-colon",
            v.replace("### AB10a: Registry", "### AB10a:Registry"),
            "heading '### AB10a:Registry' is not a milestone heading",
        ),
    ]
}

#[test]
fn each_broken_milestone_shape_fails_naming_the_milestone_and_field() {
    for (name, features, expected) in cases() {
        let path = write_roadmap(name, &roadmap("roadmap/v2", &features));
        let (ok, text) = validate(&path, &[]);
        assert!(!ok, "{name}: expected a failing run:\n{text}");
        let lines = fc21_lines(&text);
        assert_eq!(
            lines.len(),
            1,
            "{name}: expected exactly one FC21 finding:\n{text}"
        );
        assert!(
            lines[0].contains(&format!("[FC21] {expected}")),
            "{name}: expected '{expected}' in:\n{text}"
        );
    }
}

/// `### Feature N:` items with no milestone fields: a v1 roadmap's shape.
const CLASSIC: &str = "### Feature 1: Loader\n\
**Needs:** `needs-design` -- the manifest shape\n\
**Dependencies:** None\n\
**Status:** Not started\n\n\
The loader.\n\n\
### Feature 2: Registry\n\
**Dependencies:** Feature 1\n\
**Status:** Not started\n\n\
The registry.\n\n";

#[test]
fn the_schema_line_decides_whether_milestone_checks_run() {
    let v2 = write_roadmap("classic-v2", &roadmap("roadmap/v2", CLASSIC));
    let (ok, text) = validate(&v2, &[]);
    assert!(!ok, "v2 with classic items must fail:\n{text}");
    assert_eq!(
        fc21_lines(&text).len(),
        6,
        "three missing fields per item:\n{text}"
    );

    let v1 = write_roadmap("classic-v1", &roadmap("roadmap/v1", CLASSIC));
    let (ok, text) = validate(&v1, &[]);
    assert!(ok, "v1 with classic items validates:\n{text}");
    assert!(fc21_lines(&text).is_empty(), "{text}");

    let v3 = write_roadmap("classic-v3", &roadmap("roadmap/v3", CLASSIC));
    let (_, text) = validate(&v3, &[]);
    assert!(
        text.contains("schema \"roadmap/v3\" not in supported range"),
        "an unknown schema gets the SCHEMA notice:\n{text}"
    );
    assert!(fc21_lines(&text).is_empty(), "{text}");
}

#[test]
fn check_fc21_selects_the_milestone_check() {
    let features = valid().replace("**Left open:** None\n\n", "");
    let path = write_roadmap("select", &roadmap("roadmap/v2", &features));
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("FC21")
        .arg(&path)
        .assert()
        .failure()
        .stdout(contains("[FC21] milestone 'AB1: Loader' has no Left open"));
}

#[test]
fn a_milestone_roadmap_moves_through_the_lifecycle_like_any_roadmap() {
    let path = write_roadmap("lifecycle", &roadmap("roadmap/v2", &valid()));
    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Active")
        .assert()
        .success()
        .stdout(contains("\"new_status\": \"Active\""));
    let (ok, text) = validate(&path, &[]);
    assert!(ok, "the Active roadmap still validates:\n{text}");
    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Draft")
        .assert()
        .failure();
    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Done")
        .assert()
        .success()
        .stdout(contains("\"new_status\": \"Done\""));
}

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
fn no_roadmap_in_the_repository_gains_a_milestone_finding() {
    let root = worktree_root();
    let output = StdCommand::new("git")
        .arg("-C")
        .arg(&root)
        .arg("ls-files")
        .arg("--")
        .arg("*ROADMAP-*.md")
        .output();
    let Ok(output) = output else {
        eprintln!("skip: git unavailable");
        return;
    };
    let text = String::from_utf8_lossy(&output.stdout);
    let files: Vec<&str> = text.lines().collect();
    assert!(!files.is_empty(), "the repository carries roadmap fixtures");
    for file in files {
        let path = root.join(file);
        let (_, out) = validate(&path, &["--check", "FC21"]);
        assert!(
            fc21_lines(&out).is_empty(),
            "{file} gained an FC21 finding:\n{out}"
        );
    }
}
