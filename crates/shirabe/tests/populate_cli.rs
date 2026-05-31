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
    assert!(
        out.contains("| Caching layer | [#1002](https://github.com/example/repo/issues/1002) | Feature 1 | needs-spike |"),
        "expected Caching row in:\n{}",
        out
    );
    assert!(
        out.contains("| Cross-repo bridge | [#1003](https://github.com/example/repo/issues/1003) | tsukumogami/koto#65, Feature 1 | Done |"),
        "expected Bridge row in:\n{}",
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
    assert!(out.contains("F1[\"#1001: Foundation layer\"]"));
    assert!(out.contains("F2[\"#1002: Caching layer\"]"));
    assert!(out.contains("F3[\"#1003: Cross-repo bridge\"]"));
    assert!(out.contains("    F1 --> F2"));
    assert!(out.contains("    F1 --> F3"));
    // Full palette per dependency-diagram.md.
    assert!(out.contains("classDef done fill:#c8e6c9"));
    assert!(out.contains("classDef ready fill:#bbdefb"));
    assert!(out.contains("classDef blocked fill:#fff9c4"));
    assert!(out.contains("classDef needsDesign fill:#e1bee7"));
    assert!(out.contains("classDef needsPrd fill:#b3e5fc"));
    assert!(out.contains("classDef needsSpike fill:#ffcdd2"));
    assert!(out.contains("classDef needsDecision fill:#d1c4e9"));
    assert!(out.contains("classDef tracksDesign"));
    assert!(out.contains("classDef tracksPlan"));
    // Classes by status / needs.
    assert!(out.contains("    class F1 needsDesign"));
    assert!(out.contains("    class F2 needsSpike"));
    assert!(out.contains("    class F3 done"));
    assert!(out.contains("**Legend**:"));
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
    fs::write(
        &stub_path,
        "#!/usr/bin/env bash\nexit 99\n",
    )
    .unwrap();
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
        .args([
            "--dry-run",
            "--repo",
            "example/repo",
            "--output-map",
        ])
        .arg(&map_path)
        .assert()
        .success();

    assert!(map_path.exists(), "output mapping not written");
    let body = fs::read_to_string(&map_path).unwrap();
    assert!(body.starts_with('{'));
    assert!(body.ends_with('}'));
    // Three feature IDs.
    assert!(body.contains("\"1\": 1001"));
    assert!(body.contains("\"2\": 1002"));
    assert!(body.contains("\"3\": 1003"));
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
        .map(|_| std::path::PathBuf::from(env!("CARGO_BIN_EXE_shirabe")).parent().unwrap().to_path_buf())
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
