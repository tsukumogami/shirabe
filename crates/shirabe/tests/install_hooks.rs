//! End-to-end tests for the pre-commit hook `shirabe install-hooks` writes.
//!
//! Each test builds a throwaway git repository, installs the hook with the
//! built binary, puts that binary first on `PATH` so the hook runs it, and
//! commits. Git's global and system configuration are switched off so a
//! developer's `core.hooksPath`, signing or identity settings can't change
//! where the hook lands or whether the commit runs it.
//!
//! The roadmap staged here is invalid on purpose (a milestone status the
//! schema rejects), like the roadmap fixtures under this crate's
//! `tests/fixtures/`. The hook must skip it under a `tests/fixtures/`
//! directory, as CI's document validation does, and still refuse the same
//! file anywhere else.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

/// A roadmap/v3 document that is invalid on purpose: Milestone 1's status is
/// a word no roadmap schema accepts, so `shirabe validate` reports it with
/// FC21. It is written inline, not read from a fixture, so a later change to
/// which statuses the schema accepts can't make it valid.
const INVALID_ROADMAP: &str = "---
schema: roadmap/v3
status: Active
theme: |
  Plugins a maintainer can find.
scope: |
  The loader and the registry.
---

# ROADMAP: plugins

## Status

Active

## Theme

Plugins a maintainer can find.

## Milestones

### Milestone 1: Loader

**Outcome:** A maintainer sees loader work end to end.

**Evidence:**
- A reviewer, from a clean install, runs it and sees loader listed.

**Left open:** None

**Dependencies:** None
**Status:** Withdrawn

### Milestone 2: Registry

**Outcome:** A maintainer sees registry work end to end.

**Evidence:**
- A reviewer, from a clean install, runs it and sees registry listed.

**Left open:** None

**Dependencies:** Milestone 1
**Status:** Not started

## Sequencing Rationale

Each milestone builds on the one it names.

## Progress

Nothing is finished.

## Implementation Issues

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

| Milestone | Issues | Dependencies | Status |
|-----------|--------|--------------|--------|

## Dependency Graph

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

```mermaid
graph TD
```
";

/// Where the invalid roadmap is staged as a test input, the same directory
/// as this repository's own roadmap fixtures.
const FIXTURE_REPO_PATH: &str = "crates/shirabe/tests/fixtures/roadmap-v3/ROADMAP-invalid-status.md";

struct Repo {
    root: PathBuf,
}

impl Repo {
    fn new() -> Self {
        static N: AtomicUsize = AtomicUsize::new(0);
        let root = std::env::temp_dir().join(format!(
            "shirabe-install-hooks-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let repo = Repo { root };
        repo.ok(&["init", "-q", "-b", "main"]);
        repo.ok(&["config", "user.name", "Test"]);
        repo.ok(&["config", "user.email", "test@example.invalid"]);
        repo.ok(&["config", "commit.gpgsign", "false"]);
        repo.write("README.md", "# test repo\n");
        repo.ok(&["add", "README.md"]);
        repo.ok(&["commit", "-q", "-m", "initial"]);
        repo
    }

    /// `PATH` with the binary under test first, then the inherited one for
    /// git and bash.
    fn path_env() -> String {
        let bin = Path::new(env!("CARGO_BIN_EXE_shirabe"));
        let dir = bin.parent().expect("binary has a directory");
        let inherited = std::env::var("PATH").unwrap_or_default();
        format!("{}:{}", dir.display(), inherited)
    }

    fn command(&self, program: &str) -> Command {
        let mut cmd = Command::new(program);
        cmd.current_dir(&self.root)
            .env("PATH", Self::path_env())
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env_remove("GIT_DIR")
            .env_remove("GIT_WORK_TREE")
            .env_remove("GIT_INDEX_FILE");
        cmd
    }

    fn git(&self, args: &[&str]) -> Output {
        self.command("git").args(args).output().expect("git runs")
    }

    fn ok(&self, args: &[&str]) {
        let out = self.git(args);
        assert!(out.status.success(), "git {:?} failed:\n{}", args, text(&out));
    }

    fn write(&self, rel: &str, contents: &str) {
        let path = self.root.join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, contents).unwrap();
    }

    fn install_hook(&self) {
        let out = self
            .command(env!("CARGO_BIN_EXE_shirabe"))
            .arg("install-hooks")
            .output()
            .expect("shirabe runs");
        assert!(out.status.success(), "install-hooks failed:\n{}", text(&out));
        assert!(
            self.root.join(".git/hooks/pre-commit").is_file(),
            "install-hooks wrote no hook into the test repository"
        );
    }
}

impl Drop for Repo {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn text(out: &Output) -> String {
    format!(
        "stdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    )
}

#[test]
fn a_staged_test_fixture_commits() {
    let repo = Repo::new();
    repo.install_hook();
    repo.write(FIXTURE_REPO_PATH, INVALID_ROADMAP);
    repo.ok(&["add", "--", FIXTURE_REPO_PATH]);

    let out = repo.git(&["commit", "-q", "-m", "add fixture"]);
    assert!(
        out.status.success(),
        "the hook refused a commit staging a test fixture:\n{}",
        text(&out)
    );
}

#[test]
fn a_merge_bringing_in_a_test_fixture_commits() {
    let repo = Repo::new();
    repo.ok(&["checkout", "-q", "-b", "feature"]);
    repo.write("notes.txt", "feature work\n");
    repo.ok(&["add", "notes.txt"]);
    repo.ok(&["commit", "-q", "-m", "feature work"]);

    // The fixture lands on main before the hook exists, as it would through
    // a merged pull request.
    repo.ok(&["checkout", "-q", "main"]);
    repo.write(FIXTURE_REPO_PATH, INVALID_ROADMAP);
    repo.ok(&["add", "--", FIXTURE_REPO_PATH]);
    repo.ok(&["commit", "-q", "-m", "fixture on main"]);

    repo.install_hook();
    repo.ok(&["checkout", "-q", "feature"]);
    repo.ok(&["merge", "-q", "--no-ff", "--no-commit", "main"]);

    // `git commit` concluding the merge is what runs the pre-commit hook.
    let out = repo.git(&["commit", "-q", "--no-edit"]);
    assert!(
        out.status.success(),
        "the hook refused a merge commit staging a test fixture:\n{}",
        text(&out)
    );
}

#[test]
fn the_same_roadmap_outside_test_fixtures_is_refused() {
    let repo = Repo::new();
    repo.install_hook();
    let rel = "docs/roadmaps/ROADMAP-invalid-status.md";
    repo.write(rel, INVALID_ROADMAP);
    repo.ok(&["add", "--", rel]);

    let out = repo.git(&["commit", "-q", "-m", "add roadmap"]);
    assert!(
        !out.status.success(),
        "the hook let an invalid roadmap outside test fixtures commit:\n{}",
        text(&out)
    );
    assert!(
        text(&out).contains("[FC21]"),
        "the refusal didn't come from the roadmap check:\n{}",
        text(&out)
    );
}

#[test]
fn a_fixture_directory_that_is_not_under_tests_is_still_validated() {
    let repo = Repo::new();
    repo.install_hook();
    let rel = "docs/fixtures/ROADMAP-invalid-status.md";
    repo.write(rel, INVALID_ROADMAP);
    repo.ok(&["add", "--", rel]);

    let out = repo.git(&["commit", "-q", "-m", "add roadmap"]);
    assert!(
        !out.status.success(),
        "the hook skipped a fixtures directory that isn't a test or eval one:\n{}",
        text(&out)
    );
}
