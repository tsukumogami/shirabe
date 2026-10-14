//! CLI integration tests for milestone roadmaps (`schema: roadmap/v2` and
//! `roadmap/v3`).
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
    roadmap_with(schema, "Features", "Feature", features)
}

/// A `roadmap/v3` roadmap: the items under `## Milestones` and the
/// `Milestone` key column.
fn roadmap_v3(features: &str) -> String {
    roadmap_with("roadmap/v3", "Milestones", "Milestone", features)
}

/// [`roadmap`] with the items section named `section` and the table's key
/// column `key`.
fn roadmap_with(schema: &str, section: &str, key: &str, features: &str) -> String {
    let rule = "-".repeat(key.len() + 2);
    format!(
        "---\nschema: {schema}\nstatus: Draft\ntheme: |\n  Plugins a maintainer can find.\n\
         scope: |\n  The loader and the registry.\n---\n\n\
         # ROADMAP: plugins\n\n\
         ## Status\n\nDraft\n\n\
         ## Theme\n\nPlugins a maintainer can find.\n\n\
         ## {section}\n\n{features}\n\
         ## Sequencing Rationale\n\nThe loader comes first because the registry reads what it loads.\n\n\
         ## Progress\n\nNothing has started.\n\n\
         ## Implementation Issues\n\n\
         <!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->\n\n\
         | {key} | Issues | Dependencies | Status |\n|{rule}|--------|--------------|--------|\n\n\
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

/// Run `shirabe validate` on `path`; returns (exit code, combined output).
fn validate_code(path: &Path, extra: &[&str]) -> (i32, String) {
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
    (out.status.code().unwrap_or(-1), text)
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

    let v4 = write_roadmap("classic-v4", &roadmap("roadmap/v4", CLASSIC));
    let (code, text) = validate_code(&v4, &[]);
    assert_eq!(code, 4, "an unknown schema is skipped, exit 4:\n{text}");
    assert!(
        text.contains("schema \"roadmap/v4\" not in supported range"),
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
        // The byte-identity corpus carries a v2 roadmap with a
        // `### Milestone 2:` heading on purpose; its FC21 finding is part of
        // what roadmap_identity.rs pins.
        if file.contains("/roadmap-identity/") {
            continue;
        }
        let path = root.join(file);
        let (_, out) = validate(&path, &["--check", "FC21"]);
        assert!(
            fc21_lines(&out).is_empty(),
            "{file} gained an FC21 finding:\n{out}"
        );
    }
}

// ---- roadmap/v3: the same milestone shape in the milestone words ----

/// Three classic v3 milestones and one prefix-tagged one, every field
/// present. `Milestone 3` depends on `Milestone 2`, a prefix tag and a
/// cross-repo issue.
fn v3_valid() -> String {
    let item = |tag: &str, title: &str, deps: &str| {
        format!(
            "### {tag}: {title}\n\n\
             **Outcome:** A maintainer sees {title} work end to end.\n\n\
             **Evidence:**\n\
             - A reviewer, from a clean install, runs it and sees {title} listed.\n\n\
             **Left open:** None\n\n\
             **Dependencies:** {deps}\n\
             **Status:** Not started\n\n"
        )
    };
    [
        item("AB1", "Loader", "None"),
        item("Milestone 2", "Registry", "AB1"),
        item("Milestone 3", "Search", "Milestone 2, AB1, owner/repo#7"),
    ]
    .concat()
}

#[test]
fn a_v3_roadmap_validates_like_the_same_roadmap_as_v2() {
    let path = write_roadmap("v3-valid", &roadmap_v3(&v3_valid()));
    let (code, text) = validate_code(&path, &[]);
    assert_eq!(code, 0, "{text}");

    let as_v2 = v3_valid().replace("Milestone ", "Feature ");
    let path = write_roadmap("v3-as-v2", &roadmap("roadmap/v2", &as_v2));
    let (code, text) = validate_code(&path, &[]);
    assert_eq!(code, 0, "{text}");
}

/// Validate a v3 roadmap, expect exit 2, and return its FC21 lines.
fn v3_failing(name: &str, doc: &str) -> (Vec<String>, String) {
    let path = write_roadmap(name, doc);
    let (code, text) = validate_code(&path, &[]);
    assert_eq!(code, 2, "{name}: expected exit 2:\n{text}");
    // Every FC21 message on v3 that names an item calls it a milestone.
    for line in fc21_lines(&text) {
        assert!(
            !line.contains(" feature ") && !line.contains("'Feature N"),
            "{name}: {line}"
        );
    }
    (fc21_lines(&text), text)
}

#[test]
fn a_v3_milestone_with_no_evidence_is_named_by_its_milestone_tag() {
    let features = v3_valid().replace(
        "**Evidence:**\n- A reviewer, from a clean install, runs it and sees Registry listed.\n\n",
        "",
    );
    let (lines, text) = v3_failing("v3-no-evidence", &roadmap_v3(&features));
    assert_eq!(lines.len(), 1, "{text}");
    assert!(
        lines[0].contains("[FC21] milestone 'Milestone 2: Registry' has no Evidence"),
        "{text}"
    );
}

#[test]
fn a_v3_roadmap_with_a_features_section_names_the_milestones_section() {
    let doc = roadmap_with("roadmap/v3", "Features", "Milestone", &v3_valid());
    let (lines, text) = v3_failing("v3-features-section", &doc);
    assert!(
        text.contains("[FC04] missing required section '## Milestones'"),
        "{text}"
    );
    assert_eq!(lines.len(), 1, "{text}");
    assert!(
        lines[0].contains("section '## Features' is the roadmap/v2 items section")
            && lines[0].contains("'## Milestones'"),
        "{text}"
    );
}

#[test]
fn a_v3_heading_in_the_v2_word_names_the_heading_to_write() {
    let features = v3_valid().replace("### Milestone 2: Registry", "### Feature 2: Registry");
    let (lines, text) = v3_failing("v3-feature-heading", &roadmap_v3(&features));
    let heading: Vec<&String> = lines.iter().filter(|l| l.contains("] heading ")).collect();
    assert_eq!(heading.len(), 1, "{text}");
    assert!(
        heading[0].contains("'### Feature 2:' is written '### Milestone 2:'"),
        "{text}"
    );
}

#[test]
fn a_v3_dependency_in_the_v2_word_names_the_milestone_tag() {
    let features = v3_valid().replace(
        "**Dependencies:** Milestone 2, AB1, owner/repo#7",
        "**Dependencies:** Feature 2, Feature 9, AB1, owner/repo#7",
    );
    let (lines, text) = v3_failing("v3-feature-dependency", &roadmap_v3(&features));
    assert_eq!(lines.len(), 2, "{text}");
    assert!(
        lines[0].contains(
            "milestone 'Milestone 3: Search' names 'Feature 2' in Dependencies; on a roadmap/v3 roadmap an entry names the milestone's tag, 'Milestone 2'"
        ),
        "{text}"
    );
    assert!(
        lines[1].contains(
            "milestone 'Milestone 3: Search' names 'Feature 9' in Dependencies, which is no other milestone"
        ),
        "{text}"
    );
}

#[test]
fn v3_headings_that_are_not_milestone_headings() {
    for (name, heading) in [
        ("v3-suffix", "### Milestone 3a: Suffix"),
        ("v3-lowercase", "### milestone 3: Lowercase"),
        ("v3-no-number", "### Milestone: No number"),
    ] {
        let features = format!("{}{heading}\n\n", v3_valid());
        let (lines, text) = v3_failing(name, &roadmap_v3(&features));
        assert_eq!(lines.len(), 1, "{name}:\n{text}");
        assert!(
            lines[0].contains(&format!("heading '{heading}' is not a milestone heading"))
                && lines[0].contains("'Milestone 3' or 'AB1'"),
            "{name}:\n{text}"
        );
    }
}

#[test]
fn a_repeated_v3_milestone_tag_is_reported() {
    let features = format!(
        "{}{}",
        v3_valid(),
        v3_valid()
            .split("### Milestone 3: Search")
            .nth(1)
            .map(|rest| format!("### Milestone 3: Again{rest}"))
            .unwrap()
    );
    let (lines, text) = v3_failing("v3-duplicate", &roadmap_v3(&features));
    assert_eq!(lines.len(), 1, "{text}");
    assert!(
        lines[0]
            .contains("milestone 'Milestone 3: Again' repeats the tag of the milestone at line"),
        "{text}"
    );
}

#[test]
fn a_v3_roadmap_activates_with_one_milestone() {
    let path = write_roadmap("v3-lifecycle", &roadmap_v3(&v3_valid()));
    shirabe()
        .arg("transition")
        .arg(&path)
        .arg("Active")
        .assert()
        .success()
        .stdout(contains("\"new_status\": \"Active\""));
    let (code, text) = validate_code(&path, &[]);
    assert_eq!(code, 0, "{text}");
}

// ---- the /roadmap draft template on v3 ----

/// The v3 roadmap `/roadmap` drafts (Phase 3's template) and the same
/// roadmap with one Evidence clause sharpened (`sharpen.md`).
fn v3_fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/roadmap-v3")
        .join(name)
}

#[test]
fn the_v3_draft_and_its_sharpened_twin_validate() {
    let draft = v3_fixture("ROADMAP-plugin-system.md");
    let sharpened = v3_fixture("ROADMAP-plugin-system-sharpened.md");
    for path in [&draft, &sharpened] {
        let (code, text) = validate_code(path, &["--visibility=public"]);
        assert_eq!(code, 0, "{}:\n{text}", path.display());
    }

    // Sharpening touched only one milestone's Evidence.
    let a = fs::read_to_string(&draft).unwrap();
    let b = fs::read_to_string(&sharpened).unwrap();
    let start = a
        .lines()
        .zip(b.lines())
        .position(|(x, y)| x != y)
        .expect("the twins differ");
    let in_evidence = a
        .lines()
        .take(start)
        .collect::<Vec<_>>()
        .iter()
        .rev()
        .find(|l| l.starts_with("**") || l.starts_with("### "))
        .copied();
    assert_eq!(
        in_evidence,
        Some("**Evidence:**"),
        "first change at line {}",
        start + 1
    );
    let a_tail: Vec<&str> = a.lines().rev().collect();
    let b_tail: Vec<&str> = b.lines().rev().collect();
    let common_tail = a_tail
        .iter()
        .zip(&b_tail)
        .take_while(|(x, y)| x == y)
        .count();
    assert!(
        b.lines().count() - common_tail - start <= 3,
        "the sharpened clause is the only change"
    );

    // The draft populates and still validates, as Phase 4 runs it.
    let dir = std::env::temp_dir().join(format!("shirabe-v3-draft-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let copy = dir.join("ROADMAP-plugin-system.md");
    fs::copy(&draft, &copy).unwrap();
    shirabe()
        .args(["roadmap", "populate", "--no-issues"])
        .arg(&copy)
        .assert()
        .success();
    let populated = fs::read_to_string(&copy).unwrap();
    assert!(
        populated.contains("| Milestone | Issues | Dependencies | Status |\n"),
        "{populated}"
    );
    let (code, text) = validate_code(&copy, &["--visibility=public"]);
    assert_eq!(code, 0, "{text}");
    let _ = fs::remove_dir_all(&dir);
}
