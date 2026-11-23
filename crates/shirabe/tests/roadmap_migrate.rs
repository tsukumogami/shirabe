//! `shirabe roadmap migrate`, end to end.
//!
//! Each test copies a fixture from `tests/fixtures/roadmap-migrate/` into a
//! scratch directory that stands for a repository (it holds a `.git`
//! directory, which is all the command looks for), runs the built binary
//! there, and compares the output lines, the exit code and the file's
//! checksum. Cases whose roadmap would fail `shirabe validate` as committed
//! (a schema-less file, an unparseable block) are built from a passing
//! fixture in the test, because every committed roadmap must pass FC21.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

use sha2::{Digest, Sha256};

fn fixture(name: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/roadmap-migrate")
        .join(name);
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

/// A fresh scratch directory; with `repo` it holds a `.git` directory.
fn scratch(tag: &str, repo: bool) -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!(
        "shirabe-migrate-{}-{}-{tag}",
        std::process::id(),
        n
    ));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("mkdir scratch");
    if repo {
        fs::create_dir(dir.join(".git")).expect("mkdir .git");
    }
    dir
}

fn checksum(path: &Path) -> String {
    let bytes = fs::read(path).expect("read for checksum");
    Sha256::digest(&bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn shirabe(dir: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_shirabe"))
        .current_dir(dir)
        .env_remove("SHIRABE_PR_NUMBER")
        .env_remove("GITHUB_REF")
        .env_remove("GITHUB_REPOSITORY")
        .env_remove("GITHUB_TOKEN")
        .args(args)
        .output()
        .expect("run shirabe")
}

fn stdout_lines(out: &Output) -> Vec<String> {
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(str::to_string)
        .collect()
}

fn stderr(out: &Output) -> String {
    String::from_utf8_lossy(&out.stderr).into_owned()
}

/// Write `text` as `name` in a fresh repository scratch directory.
fn place(tag: &str, name: &str, text: &str) -> (PathBuf, PathBuf) {
    let dir = scratch(tag, true);
    let path = dir.join(name);
    fs::write(&path, text).expect("write roadmap");
    (dir, path)
}

/// The block Status of the milestone headed `heading`.
fn block_status(doc: &str, heading: &str) -> String {
    let at = doc
        .find(heading)
        .unwrap_or_else(|| panic!("no {heading:?} in the roadmap"));
    let rest = &doc[at..];
    let s = rest.find("**Status:** ").expect("a Status line") + "**Status:** ".len();
    rest[s..].lines().next().unwrap().to_string()
}

const V3: &str = "ROADMAP-v3-verdicts.md";

const L1: &str =
    "- 2026-10-02: Milestone 1 -- verified, checked by plugin-lead (entry 2, 2b3c4d5e)";
const L2: &str =
    "- 2026-10-04: Feature 2 -- verified with follow-ups, checked by plugin-lead (entry 4, 4d5e6f7a)";
const L4: &str =
    "- 2026-10-08: Milestone 4 -- changes needed, checked by plugin-lead (entry 5, 5e6f7a8b)";

fn v3_expected_lines() -> Vec<String> {
    vec![
        format!("Milestone 1: Done -> Verified ({L1})"),
        format!("Milestone 2: Done -> Verified ({L2})"),
        "Milestone 3: Done -> Completed (no verdict line)".to_string(),
        format!("Milestone 4: Shipped -> Completed ({L4})"),
        "Milestone 5: In progress -> In progress (no verdict line)".to_string(),
        "Milestone 6: Dropped -> Dropped (no verdict line)".to_string(),
        "Milestone 7: Not started -> Not started (no verdict line)".to_string(),
    ]
}

#[test]
fn migrate_dry_run_prints_each_move_and_writes_nothing() {
    let (dir, path) = place("dry", V3, &fixture(V3));
    let before = checksum(&path);
    let out = shirabe(&dir, &["roadmap", "migrate", V3, "--dry-run"]);
    assert_eq!(out.status.code(), Some(0), "{}", stderr(&out));
    assert_eq!(stdout_lines(&out), v3_expected_lines());
    assert_eq!(checksum(&path), before);
    let names: Vec<_> = fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().file_name())
        .collect();
    assert_eq!(names.len(), 2, "dry run left a file behind: {names:?}");
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn migrate_moves_v3_to_v4_and_a_second_run_changes_nothing() {
    let original = fixture(V3);
    let (dir, path) = place("write", V3, &original);
    let out = shirabe(&dir, &["roadmap", "migrate", V3]);
    assert_eq!(out.status.code(), Some(0), "{}", stderr(&out));
    assert_eq!(stdout_lines(&out), v3_expected_lines());

    let migrated = fs::read_to_string(&path).unwrap();
    assert!(migrated.contains("\nschema: roadmap/v4\n"));
    for (heading, status) in [
        ("### Milestone 1: A", "Verified"),
        ("### Milestone 2: B", "Verified"),
        ("### Milestone 3: C", "Completed"),
        ("### Milestone 4: D", "Completed"),
        ("### Milestone 5: E", "In progress"),
        ("### Milestone 6: F", "Dropped"),
        ("### Milestone 7: G", "Not started"),
    ] {
        assert_eq!(block_status(&migrated, heading), status, "{heading}");
    }
    for row in [
        "| Milestone 1: A | Verified | verified (2026-10-02) |",
        "| Milestone 2: B | Verified | verified with follow-ups (2026-10-04) |",
        "| Milestone 3: C | Completed | -- |",
        "| Milestone 4: D | Completed | changes needed (2026-10-08) |",
        "| Milestone 5: E | In progress | -- |",
        "| Milestone 6: F | Dropped | -- |",
        "| Milestone 7: G | Not started | -- |",
    ] {
        assert!(
            migrated.contains(&format!("\n{row}\n")),
            "missing row {row}"
        );
    }

    // Nothing but the schema line, the four Done-family Status lines and
    // their four Progress rows changed.
    let changed: Vec<(&str, &str)> = original
        .lines()
        .zip(migrated.lines())
        .filter(|(a, b)| a != b)
        .collect();
    assert_eq!(original.lines().count(), migrated.lines().count());
    assert_eq!(changed.len(), 9, "{changed:#?}");

    let val = shirabe(&dir, &["validate", V3]);
    assert_eq!(
        val.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&val.stdout)
    );

    let after = checksum(&path);
    let again = shirabe(&dir, &["roadmap", "migrate", V3]);
    assert_eq!(again.status.code(), Some(0));
    assert_eq!(stdout_lines(&again), vec!["already roadmap/v4".to_string()]);
    assert_eq!(checksum(&path), after);
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn migrate_changes_needed_after_an_earlier_verified_line_reads_completed() {
    // Milestone 4's verified line is followed by a changes-needed one.
    let (dir, path) = place("latest", V3, &fixture(V3));
    let out = shirabe(&dir, &["roadmap", "migrate", V3]);
    assert_eq!(out.status.code(), Some(0), "{}", stderr(&out));
    assert!(stdout_lines(&out).contains(&format!("Milestone 4: Shipped -> Completed ({L4})")));
    let migrated = fs::read_to_string(&path).unwrap();
    assert_eq!(block_status(&migrated, "### Milestone 4: D"), "Completed");
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn migrate_moves_v2_features_to_v4_milestones() {
    let name = "ROADMAP-v2-features.md";
    let (dir, path) = place("v2", name, &fixture(name));
    let out = shirabe(&dir, &["roadmap", "migrate", name]);
    assert_eq!(out.status.code(), Some(0), "{}", stderr(&out));
    assert_eq!(
        stdout_lines(&out),
        vec![
            "Milestone 1: Shipped -> Completed (- 2026-09-01: Milestone 1 -- changes needed, checked by plugin-lead (entry 1, 1a2b3c4d))".to_string(),
            "Milestone 2: Done -> Verified (- 2026-09-03: Feature 2 -- verified, checked by plugin-lead (entry 2, 2b3c4d5e))".to_string(),
            "Milestone 3: Not started -> Not started (no verdict line)".to_string(),
        ]
    );
    let migrated = fs::read_to_string(&path).unwrap();
    assert!(migrated.contains("\nschema: roadmap/v4\n"));
    assert!(migrated.contains("\n## Milestones\n"));
    assert!(!migrated.contains("\n## Features\n"));
    assert!(!migrated.contains("### Feature "));
    assert_eq!(
        block_status(&migrated, "### Milestone 1: Loader"),
        "Completed"
    );
    assert_eq!(
        block_status(&migrated, "### Milestone 2: Registry"),
        "Verified"
    );
    assert_eq!(
        block_status(&migrated, "### Milestone 3: Search"),
        "Not started"
    );
    assert!(migrated.contains("**Dependencies:** Milestone 1, Milestone 2\n"));
    assert!(migrated.contains("\n| Milestone | Issues | Dependencies | Status |\n"));
    let val = shirabe(&dir, &["validate", name]);
    assert_eq!(
        val.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&val.stdout)
    );
    let _ = fs::remove_dir_all(&dir);
}

/// Run migrate on `text` and expect a refusal naming `reason`, with the
/// file unchanged.
fn assert_refused(tag: &str, text: &str, reason: &str) {
    let name = "ROADMAP-refused.md";
    let (dir, path) = place(tag, name, text);
    let before = checksum(&path);
    for args in [
        vec!["roadmap", "migrate", name],
        vec!["roadmap", "migrate", name, "--dry-run"],
    ] {
        let out = shirabe(&dir, &args);
        assert_ne!(out.status.code(), Some(0), "{tag}: {args:?} exited 0");
        assert!(
            stderr(&out).contains(reason),
            "{tag}: stderr lacks {reason:?}: {}",
            stderr(&out)
        );
        assert!(
            out.stdout.is_empty(),
            "{tag}: printed {:?}",
            stdout_lines(&out)
        );
        assert_eq!(checksum(&path), before, "{tag}: file changed");
    }
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn migrate_refuses_v1_schemaless_done_and_unparseable_roadmaps() {
    assert_refused(
        "v1",
        &fixture("ROADMAP-v1.md"),
        "is roadmap/v1; only a roadmap/v2 or roadmap/v3 roadmap is migrated",
    );
    let schemaless = fixture(V3).replace("schema: roadmap/v3\n", "");
    assert_refused(
        "noschema",
        &schemaless,
        "has no schema; only a roadmap/v2 or roadmap/v3 roadmap is migrated",
    );
    assert_refused(
        "done",
        &fixture("ROADMAP-v3-done.md"),
        "has status Done; a finished roadmap isn't migrated",
    );
    let no_status = fixture(V3).replacen("**Status:** In progress\n", "", 1);
    assert_refused(
        "nostatus",
        &no_status,
        "can't parse the milestone block 'Milestone 5': it has no **Status:** line",
    );
    let bad_heading = fixture(V3).replacen("### Milestone 3: C", "### Milestone three: C", 1);
    assert_refused(
        "heading",
        &bad_heading,
        "'### Milestone three: C' isn't a milestone heading",
    );
    let bad_status = fixture(V3).replacen("**Status:** Not started", "**Status:** Blocked", 1);
    assert_refused(
        "status",
        &bad_status,
        "its Status 'Blocked' isn't a roadmap/v3 status",
    );
}

#[test]
fn migrate_refuses_a_path_outside_the_repository() {
    let repo = scratch("repo", true);
    let elsewhere = scratch("elsewhere", false);
    let path = elsewhere.join(V3);
    fs::write(&path, fixture(V3)).unwrap();
    let before = checksum(&path);
    let target = path.to_string_lossy().into_owned();
    for args in [
        vec!["roadmap", "migrate", target.as_str()],
        vec!["roadmap", "migrate", target.as_str(), "--dry-run"],
    ] {
        let out = shirabe(&repo, &args);
        assert_ne!(out.status.code(), Some(0));
        assert!(
            stderr(&out).contains("is outside the repository this runs in"),
            "{}",
            stderr(&out)
        );
        assert_eq!(checksum(&path), before);
    }

    // A symlink inside the repository pointing out of it is refused too.
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(&path, repo.join(V3)).unwrap();
        let out = shirabe(&repo, &["roadmap", "migrate", V3]);
        assert_ne!(out.status.code(), Some(0));
        assert!(stderr(&out).contains("is outside the repository this runs in"));
        assert_eq!(checksum(&path), before);
    }
    let _ = fs::remove_dir_all(&repo);
    let _ = fs::remove_dir_all(&elsewhere);
}

#[cfg(unix)]
#[test]
fn migrate_a_read_only_directory_leaves_the_original_and_a_planted_file_untouched() {
    use std::os::unix::fs::PermissionsExt;

    let (dir, path) = place("readonly", V3, &fixture(V3));
    let planted = [
        dir.join(format!("{V3}.tmp")),
        dir.join(format!(".{V3}.migrate.tmp")),
        dir.join(format!(".{V3}.tmp")),
    ];
    for p in &planted {
        fs::write(p, "planted\n").unwrap();
    }
    let before = checksum(&path);
    let planted_before: Vec<String> = planted.iter().map(|p| checksum(p)).collect();

    fs::set_permissions(&dir, fs::Permissions::from_mode(0o555)).unwrap();
    // A process that can write a read-only directory anyway (root) can't
    // show the refusal; the rest of the test still holds for it.
    let probe = dir.join("probe");
    let writable = fs::write(&probe, "x").is_ok();
    let _ = fs::remove_file(&probe);

    let out = shirabe(&dir, &["roadmap", "migrate", V3]);
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o755)).unwrap();

    if !writable {
        assert_ne!(out.status.code(), Some(0));
        assert!(
            stderr(&out).contains("the roadmap is unchanged"),
            "{}",
            stderr(&out)
        );
        assert_eq!(checksum(&path), before);
    }
    let after: Vec<String> = planted.iter().map(|p| checksum(p)).collect();
    assert_eq!(after, planted_before);

    // Once writable, the migration succeeds without touching a planted file
    // and leaves no temporary file behind.
    let out = shirabe(&dir, &["roadmap", "migrate", V3]);
    assert_eq!(out.status.code(), Some(0), "{}", stderr(&out));
    let after: Vec<String> = planted.iter().map(|p| checksum(p)).collect();
    assert_eq!(after, planted_before);
    let leftovers: Vec<String> = fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|n| n.contains(".migrate-"))
        .collect();
    assert!(leftovers.is_empty(), "{leftovers:?}");
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn migrate_control_characters_in_a_verdict_line_are_not_printed() {
    let text = fixture(V3).replace(
        "- 2026-10-02: Milestone 1 -- verified, checked by plugin-lead (entry 2, 2b3c4d5e)",
        "- 2026-10-02: Milestone 1 -- verified, checked by \u{1b}[31mplugin-lead\u{7}\r (entry 2)",
    );
    let (dir, _path) = place("controls", V3, &text);
    let out = shirabe(&dir, &["roadmap", "migrate", V3, "--dry-run"]);
    assert_eq!(out.status.code(), Some(0), "{}", stderr(&out));
    let lines = stdout_lines(&out);
    assert_eq!(
        lines[0],
        "Milestone 1: Done -> Verified (- 2026-10-02: Milestone 1 -- verified, checked by [31mplugin-lead (entry 2))"
    );
    assert!(!out.stdout.iter().any(|b| *b < 0x20 && *b != b'\n'));
    let _ = fs::remove_dir_all(&dir);
}
