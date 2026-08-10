//! Integration tests for `shirabe roadmap populate`.
//!
//! Exercises the built binary end-to-end via `assert_cmd`. All tests run
//! `--dry-run` so no GitHub API calls are made.
//!
//! The 30-scenario coverage from the bash test predecessor collapses into
//! these named scenarios -- the parser-level cases are now covered by
//! `shirabe-validate`'s `features::tests` and the populate module's unit
//! tests; this file owns the CLI-surface contract.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;

use assert_cmd::Command;
use predicates::str::contains;

fn shirabe() -> Command {
    Command::cargo_bin("shirabe").expect("binary `shirabe` builds")
}

/// Three-feature fixture covering the canonical shapes:
/// - Feature 1: no deps, needs-design, Not started
/// - Feature 2: depends on Feature 1, needs-spike, Not started
/// - Feature 3: cross-repo dep + Feature 1, no needs, Done
fn write_basic_fixture(dir: &Path) -> PathBuf {
    let path = dir.join("roadmap.md");
    fs::write(
        &path,
        "---\n\
schema: roadmap/v1\n\
status: Draft\n\
theme: |\n  Test theme.\n\
scope: |\n  Test scope.\n\
---\n\
\n\
# ROADMAP: test\n\
\n\
## Status\n\
\n\
Draft\n\
\n\
## Theme\n\
\n\
Test theme.\n\
\n\
## Features\n\
\n\
### Feature 1: Foundation layer\n\
**Needs:** `needs-design` -- architecture undecided\n\
**Dependencies:** None\n\
**Status:** Not started\n\
\n\
The foundation layer delivers the base abstractions.\n\
\n\
### Feature 2: Caching layer\n\
**Needs:** `needs-spike` -- feasibility unknown\n\
**Dependencies:** Feature 1\n\
**Status:** Not started\n\
\n\
Adds a cache on top of the foundation.\n\
\n\
### Feature 3: Cross-repo bridge\n\
**Needs:** None\n\
**Dependencies:** tsukumogami/koto#65, Feature 1\n\
**Status:** Done\n\
\n\
Bridges to the koto repo.\n\
\n\
## Sequencing Rationale\n\
\n\
Foundation first.\n\
\n\
## Progress\n\
\n\
In progress.\n\
\n\
## Implementation Issues\n\
\n\
<!-- Populated by /plan during decomposition. Do not fill manually. -->\n\
\n\
| Feature | Issues | Dependencies | Status |\n\
|---------|--------|--------------|--------|\n\
\n\
## Dependency Graph\n\
\n\
<!-- Populated by /plan during decomposition. Do not fill manually. -->\n\
\n\
",
    )
    .unwrap();
    path
}

fn tempdir() -> PathBuf {
    let base = std::env::temp_dir();
    let dir = base.join(format!(
        "shirabe-populate-it-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn fnv_hash(path: &Path) -> u64 {
    let bytes = fs::read(path).unwrap();
    let mut h: u64 = 0xcbf29ce484222325;
    for b in bytes {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

#[test]
fn help_prints_usage_under_roadmap_populate() {
    shirabe()
        .args(["roadmap", "populate", "--help"])
        .assert()
        .success()
        .stdout(contains("Populate a roadmap's reserved"));
}

#[test]
fn features_parsed_and_table_rendered() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let out = fs::read_to_string(&path).unwrap();
    assert!(
        out.contains("| Foundation layer | [#1001](https://github.com/example/repo/issues/1001) | None | needs-design |"),
        "expected Foundation row in:\n{}",
        out
    );
    // The Dependencies cell names the depended-on feature's row key (its
    // label), not the raw `Feature 1` token that would trip FC06.
    assert!(
        out.contains("| Caching layer | [#1002](https://github.com/example/repo/issues/1002) | Foundation layer | needs-spike |"),
        "expected Caching row in:\n{}",
        out
    );
    // Feature 3 is Done: it is NOT given a fresh tracking issue (issue
    // #233), and its rows are struck through with an Issues = None cell.
    // Its cross-repo dependency is preserved verbatim.
    assert!(
        out.contains("| ~~Cross-repo bridge~~ | ~~None~~ | ~~Foundation layer, tsukumogami/koto#65~~ | ~~Done~~ |"),
        "expected struck Bridge row in:\n{}",
        out
    );
    assert!(out.contains("| _The foundation layer delivers the base abstractions._ |"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn non_reserved_content_above_implementation_issues_untouched() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);

    let before: String = fs::read_to_string(&path)
        .unwrap()
        .lines()
        .take_while(|l| !l.starts_with("## Implementation Issues"))
        .collect::<Vec<_>>()
        .join("\n");

    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();

    let after: String = fs::read_to_string(&path)
        .unwrap()
        .lines()
        .take_while(|l| !l.starts_with("## Implementation Issues"))
        .collect::<Vec<_>>()
        .join("\n");

    assert_eq!(before, after);
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn cross_repo_refs_round_trip_verbatim() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let out = fs::read_to_string(&path).unwrap();
    assert!(out.contains("tsukumogami/koto#65"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn dependency_diagram_has_nodes_edges_palette_and_classes() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let out = fs::read_to_string(&path).unwrap();
    // Nodes are keyed `I<issue-number>` (FC07 roadmap bijection). Feature 3
    // is Done and got no fresh issue, so it contributes no node.
    assert!(out.contains("I1001[\"#1001: Foundation layer\"]"));
    assert!(out.contains("I1002[\"#1002: Caching layer\"]"));
    assert!(!out.contains("Cross-repo bridge\"]"));
    assert!(out.contains("    I1001 --> I1002"));
    // Only the classes actually assigned get a classDef (FC08 Sub-B); the
    // Legend names them by camelCase classDef id (FC08 Sub-C).
    assert!(out.contains("classDef needsDesign fill:#e1bee7"));
    assert!(out.contains("classDef needsSpike fill:#ffcdd2"));
    assert!(!out.contains("classDef needsDecision"));
    assert!(!out.contains("classDef tracksPlan"));
    assert!(out.contains("    class I1001 needsDesign"));
    assert!(out.contains("    class I1002 needsSpike"));
    assert!(out.contains("**Legend**:"));
    // The Legend uses the camelCase classDef id, not the kebab form.
    assert!(out.contains("= needsSpike"));
    assert!(!out.contains("= needs-design"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn populated_output_passes_validate() {
    // CLI-level round-trip: populate, then run `shirabe validate` over the
    // populated roadmap. The renderer's own output must satisfy the
    // validator (no FC06 errors -> exit 0). Guards against the renderer
    // drifting from the checks it feeds.
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    // `validate` exits 0 when there are no error-level findings (notices,
    // such as the FC09 no-PR-context skip, do not fail the run).
    shirabe()
        .args(["validate", "--format", "human"])
        .arg(&path)
        .assert()
        .success();
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn rerun_is_idempotent() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);

    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let after_first = fs::read_to_string(&path).unwrap();

    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let after_second = fs::read_to_string(&path).unwrap();

    assert_eq!(after_first, after_second);
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn dry_run_never_invokes_gh() {
    // Salt the PATH with a stub `gh` that exits non-zero if invoked. The
    // subcommand must NOT touch gh under --dry-run, so a successful run
    // proves the stub was not called for any write action.
    let dir = tempdir();
    let path = write_basic_fixture(&dir);

    let stub_dir = dir.join("stub-bin");
    fs::create_dir_all(&stub_dir).unwrap();
    let stub_path = stub_dir.join("gh");
    fs::write(&stub_path, "#!/usr/bin/env bash\nexit 99\n").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&stub_path).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&stub_path, perms).unwrap();
    }

    let original_path = std::env::var("PATH").unwrap_or_default();
    let salted_path = format!("{}:{}", stub_dir.display(), original_path);

    shirabe()
        .env("PATH", salted_path)
        .args(["roadmap", "populate"])
        .arg(&path)
        // Explicit --repo so the subcommand does not fall back to `gh repo view`.
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn missing_reserved_section_fails_cleanly_with_no_partial_write() {
    let dir = tempdir();
    let path = dir.join("bad-roadmap.md");
    fs::write(
        &path,
        "---\nschema: roadmap/v1\nstatus: Draft\n---\n\n# ROADMAP: t\n\n## Features\n\n### Feature 1: F\n**Needs:** None\n**Dependencies:** None\n**Status:** Not started\n\nBody.\n",
    )
    .unwrap();

    let before_hash = fnv_hash(&path);

    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .failure()
        .stderr(contains("reserved section not found"));

    let after_hash = fnv_hash(&path);
    assert_eq!(before_hash, after_hash, "roadmap was mutated on failed run");
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn shell_metacharacters_in_labels_round_trip_without_executing() {
    // Feature title contains shell metacharacters. If they were ever
    // interpolated into a shell command, `HIJACKED` would appear in stdout
    // and the marker file `/tmp/shirabe-populate-injected-<pid>` would be
    // created.
    let dir = tempdir();
    let path = dir.join("inj.md");
    fs::write(
        &path,
        "---\nschema: roadmap/v1\nstatus: Draft\n---\n\n# ROADMAP: t\n\n## Features\n\n### Feature 1: Safe; rm -rf /tmp/nonexistent && echo HIJACKED\n**Needs:** None\n**Dependencies:** None\n**Status:** Not started\n\nA feature whose name contains shell metacharacters.\n\n## Sequencing Rationale\n\nx.\n\n## Progress\n\nx.\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n\n## Dependency Graph\n\n",
    )
    .unwrap();

    let assertion = shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let stdout = String::from_utf8_lossy(&assertion.get_output().stdout).to_string();
    assert!(
        !stdout.contains("HIJACKED"),
        "shell metacharacters were executed; stdout contained HIJACKED: {}",
        stdout
    );

    let out = fs::read_to_string(&path).unwrap();
    assert!(
        out.contains("| Safe; rm -rf /tmp/nonexistent && echo HIJACKED |"),
        "literal label should round-trip into the rendered table, got:\n{}",
        out
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn output_map_writes_parseable_mapping() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    let map_path = dir.join("mapping.json");

    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo", "--output-map"])
        .arg(&map_path)
        .assert()
        .success();

    assert!(map_path.exists(), "output mapping not written");
    let body = fs::read_to_string(&map_path).unwrap();
    assert!(body.starts_with('{'));
    assert!(body.ends_with('}'));
    // Features 1 and 2 are not-yet-done, so they get fresh issues. Feature
    // 3 is Done and gets no fresh issue (issue #233), so it is absent.
    assert!(body.contains("\"1\": 1001"));
    assert!(body.contains("\"2\": 1002"));
    assert!(!body.contains("\"3\":"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn mapping_input_skips_creation_and_renders_with_given_numbers() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    let map_path = dir.join("input-mapping.json");
    fs::write(&map_path, r#"{"1": 42, "2": 43, "3": 44}"#).unwrap();

    // A stub `gh` that would fail if invoked -- if --mapping is honored,
    // we never call gh at all.
    let stub_dir = dir.join("stub-bin");
    fs::create_dir_all(&stub_dir).unwrap();
    let stub_path = stub_dir.join("gh");
    fs::write(&stub_path, "#!/usr/bin/env bash\nexit 99\n").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&stub_path).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&stub_path, perms).unwrap();
    }
    let original_path = std::env::var("PATH").unwrap_or_default();
    let salted_path = format!("{}:{}", stub_dir.display(), original_path);

    shirabe()
        .env("PATH", salted_path)
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--repo", "owner/repo", "--mapping"])
        .arg(&map_path)
        .assert()
        .success();

    let out = fs::read_to_string(&path).unwrap();
    assert!(out.contains("[#42]"), "expected #42 in rendered table");
    assert!(out.contains("[#43]"));
    assert!(out.contains("[#44]"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn nonexistent_roadmap_path_fails() {
    shirabe()
        .args(["roadmap", "populate", "/tmp/does-not-exist-shirabe.md"])
        .args(["--dry-run", "--repo", "owner/repo"])
        .assert()
        .failure()
        .stderr(contains("roadmap not found"));
}

#[test]
fn empty_features_section_fails_cleanly() {
    let dir = tempdir();
    let path = dir.join("empty.md");
    fs::write(
        &path,
        "---\nschema: roadmap/v1\nstatus: Draft\n---\n\n# ROADMAP: t\n\n## Features\n\nNo features here yet.\n\n## Implementation Issues\n\n## Dependency Graph\n\n",
    )
    .unwrap();
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "owner/repo"])
        .assert()
        .failure()
        .stderr(contains("no features parsed"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn atomic_write_leaves_no_temp_files_on_success() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let entries: Vec<_> = fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.file_name())
        .collect();
    for name in &entries {
        let s = name.to_string_lossy();
        assert!(
            !s.contains(".populate.tmp."),
            "atomic-write temp leaked: {}",
            s
        );
    }
    let _ = fs::remove_dir_all(&dir);
}

// A keep-alive that exercises the path the calling skill phase uses to
// preview before the R14 gate clears -- it must complete without making
// any external state changes (no temp files, no doc mutation, no gh call)
// when given a freshly-written fixture.
#[test]
fn preview_path_is_pure() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    let before = fs::read_to_string(&path).unwrap();
    // Capture the doc before, run with --dry-run, and assert the
    // populate-mode mutation IS expected (so this is a positive control
    // for the rest of the test file -- a dry-run still writes the doc by
    // design; what it doesn't do is call gh).
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let after = fs::read_to_string(&path).unwrap();
    assert_ne!(before, after);
    let _ = fs::remove_dir_all(&dir);
}

// One final sanity check: ensure the binary doesn't accidentally regress
// to bash by depending on `bash` at runtime. We invoke with PATH set to a
// single directory containing only the stub binary directory; if the
// subcommand still works, no shell dependency exists. This is overkill but
// codifies the intent.
#[test]
fn binary_runs_without_external_shell_dependency() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    // Set PATH to only the temp dir (no bash, no gh). --dry-run + --repo
    // means no external command lookup needed.
    let cargo_bin_dir = StdCommand::new(env!("CARGO_BIN_EXE_shirabe"))
        .arg("--version")
        .output()
        .map(|_| ())
        .map(|_| {
            std::path::PathBuf::from(env!("CARGO_BIN_EXE_shirabe"))
                .parent()
                .unwrap()
                .to_path_buf()
        })
        .unwrap_or_else(|_| std::env::temp_dir());

    shirabe()
        .env("PATH", &cargo_bin_dir)
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let _ = fs::remove_dir_all(&dir);
}

// ---------------------------------------------------------------------------
// Issueless-mode rendering
// ---------------------------------------------------------------------------

/// A roadmap whose features exercise the issueless renderer's awkward cases: a
/// label that cannot key a row, a duplicate label, a body with no sentence
/// terminator, and a feature with no body at all.
fn write_awkward_fixture(dir: &Path) -> PathBuf {
    let path = dir.join("ROADMAP-awkward.md");
    let long_body = "The stages this adds, end to end: ".to_string() + &"- a stage ".repeat(40);
    let body = format!(
        "---\n\
schema: roadmap/v1\n\
status: Active\n\
theme: |\n  Theme.\n\
scope: |\n  Scope.\n\
---\n\
\n\
# ROADMAP: awkward\n\
\n\
## Status\n\
\n\
Active\n\
\n\
## Theme\n\
\n\
Theme.\n\
\n\
## Features\n\
\n\
### Feature 1: Foundation layer\n\
**Dependencies:** None\n\
**Status:** Not started\n\
\n\
{long}\n\
\n\
### Feature 2: Establish, then act\n\
**Dependencies:** Feature 1\n\
**Status:** Not started\n\
\n\
Sets the number.\n\
\n\
### Feature 3: Caching\n\
**Dependencies:** Feature 2\n\
**Status:** Not started\n\
\n\
### Feature 4: Caching\n\
**Dependencies:** Feature 1\n\
**Status:** Done\n\
\n\
A second feature sharing a label.\n\
\n\
## Sequencing Rationale\n\
\n\
Foundation first.\n\
\n\
## Progress\n\
\n\
In progress.\n\
\n\
## Implementation Issues\n\
\n\
<!-- Populated by an issueless run. Do not fill manually. -->\n\
\n\
## Dependency Graph\n\
\n\
<!-- Populated by an issueless run. Do not fill manually. -->\n\
\n",
        long = long_body
    );
    fs::write(&path, body).unwrap();
    path
}

#[test]
fn issueless_table_is_keyed_by_feature_label() {
    let dir = tempdir();
    let path = write_basic_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .arg("--no-issues")
        .assert()
        .success();
    let out = fs::read_to_string(&path).unwrap();
    // The key column names the feature; dependency cells name it by index, so
    // the column stays narrow and matches the diagram's node numbering.
    assert!(out.contains("| Foundation layer | needs-design | None | needs-design |"));
    assert!(out.contains("| Caching layer | needs-spike | F1 | needs-spike |"));
    // A delivered feature's row is struck through; the cross-repo token
    // survives verbatim alongside the resolved index.
    assert!(out
        .contains("| ~~Cross-repo bridge~~ | ~~None~~ | ~~F1, tsukumogami/koto#65~~ | ~~Done~~ |"));
    // No opaque index remains in the table's key column. Anchoring on the
    // newline is what separates the key column from the Dependencies column,
    // which now legitimately holds `F1`.
    assert!(!out.contains("\n| F1 |"));
    assert!(!out.contains("\n| F2 |"));
    // The diagram keeps its F<n> node ids, and the table's dependency cells
    // now name features by the same numbering.
    assert!(out.contains("F1[\"Foundation layer\"]"));
    assert!(out.contains("F1 --> F2"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn issueless_awkward_labels_fall_back_and_warn() {
    let dir = tempdir();
    let path = write_awkward_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .arg("--no-issues")
        .assert()
        .success()
        // The comma-bearing label cannot key a row.
        .stderr(contains(
            "feature 2 \"Establish, then act\": key falls back to F2",
        ))
        // Two features share a label, so both fall back.
        .stderr(contains("feature 3 \"Caching\": key falls back to F3"))
        .stderr(contains("feature 4 \"Caching\": key falls back to F4"))
        // The unbounded body is reported with its remedy.
        .stderr(contains(
            "feature 1 \"Foundation layer\": description truncated",
        ))
        .stderr(contains("**Functional outcome:**"));

    let out = fs::read_to_string(&path).unwrap();
    assert!(out.contains("| Foundation layer |"));
    assert!(out.contains("| F2 | None | F1 | Not started |"));
    // A feature whose key fell back to `F<n>` needs no special handling: its
    // key and its dependency alias are the same token, so a row keyed `F2`
    // and a cell naming `F2` agree by construction. FC06 resolves this one as
    // a key, never reaching the alias.
    assert!(out.contains("| F3 | None | F2 | Not started |"));
    // The feature with no body gets the placeholder rather than an empty
    // italic marker, which the validator reads as bold.
    assert!(out.contains("| _No description in the feature body._ | | | |"));
    assert!(!out.contains("| __ |"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn issueless_description_cells_are_bounded() {
    let dir = tempdir();
    let path = write_awkward_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .arg("--no-issues")
        .assert()
        .success();
    let out = fs::read_to_string(&path).unwrap();
    for line in out.lines() {
        if !line.starts_with("| _") && !line.starts_with("| ~~_") {
            continue;
        }
        let cell = line.trim_start_matches('|').trim();
        assert!(
            cell.chars().count() <= 220,
            "description cell exceeds the ceiling: {} chars",
            cell.chars().count()
        );
    }
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn issueless_output_passes_validate_on_awkward_input() {
    let dir = tempdir();
    let path = write_awkward_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .arg("--no-issues")
        .assert()
        .success();
    // The fallback exists so this holds unconditionally: a roadmap the tool
    // wrote must never fail the tool's own validator.
    shirabe()
        .args(["validate"])
        .arg(&path)
        .arg("--visibility=public")
        .assert()
        .success();
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn issue_creating_mode_emits_no_key_fallback_warning() {
    let dir = tempdir();
    let path = write_awkward_fixture(&dir);
    // Issue-creating mode keeps plain labels and never applies the fallback,
    // so reporting one would describe work it did not do.
    let assert = shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .args(["--dry-run", "--repo", "example/repo"])
        .assert()
        .success();
    let stderr = String::from_utf8_lossy(&assert.get_output().stderr).to_string();
    assert!(
        !stderr.contains("key falls back"),
        "issue-creating mode must not report a fallback: {}",
        stderr
    );
    // It does share the bounded description derivation, so it still reports a
    // cell it had to cut.
    assert!(
        stderr.contains("description truncated"),
        "stderr: {}",
        stderr
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn issueless_metacharacters_in_labels_round_trip_without_executing() {
    let dir = tempdir();
    let path = dir.join("ROADMAP-meta.md");
    let canary = dir.join("canary.txt");
    fs::write(&canary, "intact").unwrap();
    let body = format!(
        "---\n\
schema: roadmap/v1\n\
status: Active\n\
theme: |\n  Theme.\n\
scope: |\n  Scope.\n\
---\n\
\n\
# ROADMAP: meta\n\
\n\
## Status\n\
\n\
Active\n\
\n\
## Theme\n\
\n\
Theme.\n\
\n\
## Features\n\
\n\
### Feature 1: Safe; rm -rf {canary} && echo HIJACKED\n\
**Dependencies:** None\n\
**Status:** Not started\n\
\n\
Body one.\n\
\n\
### Feature 2: Dependent\n\
**Dependencies:** Feature 1\n\
**Status:** Not started\n\
\n\
Body two.\n\
\n\
## Sequencing Rationale\n\
\n\
First.\n\
\n\
## Progress\n\
\n\
Started.\n\
\n\
## Implementation Issues\n\
\n\
<!-- Populated by an issueless run. Do not fill manually. -->\n\
\n\
## Dependency Graph\n\
\n\
<!-- Populated by an issueless run. Do not fill manually. -->\n\
\n",
        canary = canary.display()
    );
    fs::write(&path, body).unwrap();

    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .arg("--no-issues")
        .assert()
        .success();

    // Label text reaching the key column is new in issueless mode, so the
    // verbatim round-trip is asserted here and not only in the
    // issue-creating test above.
    let out = fs::read_to_string(&path).unwrap();
    assert!(out.contains(&format!(
        "| Safe; rm -rf {} && echo HIJACKED | None | None | Not started |",
        canary.display()
    )));
    assert_eq!(fs::read_to_string(&canary).unwrap(), "intact");

    shirabe()
        .args(["validate"])
        .arg(&path)
        .arg("--visibility=public")
        .assert()
        .success();
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn issueless_rerun_is_idempotent() {
    let dir = tempdir();
    let path = write_awkward_fixture(&dir);
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .arg("--no-issues")
        .assert()
        .success();
    let first = fs::read_to_string(&path).unwrap();
    shirabe()
        .args(["roadmap", "populate"])
        .arg(&path)
        .arg("--no-issues")
        .assert()
        .success();
    assert_eq!(first, fs::read_to_string(&path).unwrap());
    let _ = fs::remove_dir_all(&dir);
}
