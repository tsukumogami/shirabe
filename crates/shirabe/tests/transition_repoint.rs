//! End-to-end tests for the reference repoint each moving transition runs.
//!
//! These need a real repository: the pass takes its file set from
//! `git ls-files` and stages what it rewrites, so a temp directory without
//! an index would exercise neither. Each case builds a fresh repo, commits a
//! small corpus, runs `shirabe transition`, and asserts on the resulting
//! tree and on `git status`.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

/// A throwaway git repository, removed on drop.
struct Repo {
    root: PathBuf,
}

impl Repo {
    fn new(label: &str) -> Self {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "shirabe-repoint-{}-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed),
            label
        ));
        std::fs::create_dir_all(&root).expect("create repo root");
        let repo = Repo { root };
        repo.git(&["init", "--quiet"]);
        repo.git(&["config", "user.email", "test@example.com"]);
        repo.git(&["config", "user.name", "test"]);
        repo
    }

    fn git(&self, args: &[&str]) -> Output {
        let out = Command::new("git")
            .arg("-C")
            .arg(&self.root)
            .args(args)
            .output()
            .expect("run git");
        assert!(
            out.status.success(),
            "git {args:?} failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        out
    }

    fn write(&self, rel: &str, contents: &str) {
        let path = self.root.join(rel);
        std::fs::create_dir_all(path.parent().expect("parent")).expect("create dirs");
        std::fs::write(&path, contents).expect("write file");
    }

    fn read(&self, rel: &str) -> String {
        std::fs::read_to_string(self.root.join(rel)).unwrap_or_else(|e| panic!("read {rel}: {e}"))
    }

    fn commit_all(&self) {
        self.git(&["add", "-A"]);
        self.git(&["commit", "--quiet", "-m", "corpus"]);
    }

    /// Repo-relative paths git reports as staged.
    fn staged(&self) -> Vec<String> {
        let out = self.git(&["diff", "--cached", "--name-only"]);
        String::from_utf8_lossy(&out.stdout)
            .lines()
            .map(str::to_string)
            .collect()
    }

    fn transition(&self, doc: &str, status: &str, extra: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_shirabe"))
            .current_dir(&self.root)
            .arg("transition")
            .arg(doc)
            .arg(status)
            .args(extra)
            .output()
            .expect("run shirabe transition")
    }

    fn validate(&self, args: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_shirabe"))
            .current_dir(&self.root)
            .arg("validate")
            .args(args)
            .output()
            .expect("run shirabe validate")
    }
}

impl Drop for Repo {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn design(status: &str) -> String {
    format!("---\nschema: design/v1\nstatus: {status}\n---\n\n## Status\n\n{status}\n")
}

fn assert_success(out: &Output) {
    assert_eq!(
        out.status.code(),
        Some(0),
        "transition failed:\n--- stdout ---\n{}\n--- stderr ---\n{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn a_design_moved_to_current_leaves_its_referrers_naming_the_new_path() {
    let repo = Repo::new("design-current");
    repo.write("docs/designs/DESIGN-a.md", &design("Proposed"));
    repo.write(
        "docs/prds/PRD-a.md",
        "---\nschema: prd/v1\nstatus: Done\n---\n\n## Related\n\nSee `docs/designs/DESIGN-a.md`.\n",
    );
    repo.write(
        "docs/briefs/BRIEF-a.md",
        "Framed by [the design](docs/designs/DESIGN-a.md).\n",
    );
    repo.write(
        "skills/plan/references/contract.md",
        "Read `docs/designs/DESIGN-a.md` first.\n",
    );
    repo.commit_all();

    let out = repo.transition("docs/designs/DESIGN-a.md", "Current", &[]);
    assert_success(&out);

    for rel in [
        "docs/prds/PRD-a.md",
        "docs/briefs/BRIEF-a.md",
        "skills/plan/references/contract.md",
    ] {
        let text = repo.read(rel);
        assert!(
            text.contains("docs/designs/current/DESIGN-a.md"),
            "{rel} was not repointed: {text}"
        );
        assert!(
            !text.contains("`docs/designs/DESIGN-a.md`")
                && !text.contains("(docs/designs/DESIGN-a.md)"),
            "{rel} still names the old path: {text}"
        );
    }

    // Every rewritten file is staged alongside the moved one.
    let staged = repo.staged();
    for rel in [
        "docs/designs/current/DESIGN-a.md",
        "docs/prds/PRD-a.md",
        "docs/briefs/BRIEF-a.md",
        "skills/plan/references/contract.md",
    ] {
        assert!(
            staged.iter().any(|s| s == rel),
            "{rel} not staged: {staged:?}"
        );
    }

    // The report names each file and its occurrence count.
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("docs/prds/PRD-a.md (1)"),
        "stderr: {stderr}"
    );
    assert!(stderr.contains("3 file(s)"), "stderr: {stderr}");

    // And the check agrees there is nothing left to find.
    let check = repo.validate(&[
        "--check",
        "FC18",
        "docs/prds/PRD-a.md",
        "docs/briefs/BRIEF-a.md",
        "skills/plan/references/contract.md",
    ]);
    let findings = String::from_utf8_lossy(&check.stdout);
    assert!(
        !findings.contains("FC18"),
        "FC18 still reports after the repoint: {findings}"
    );
}

#[test]
fn a_superseded_design_repoints_the_same_way() {
    let repo = Repo::new("design-superseded");
    repo.write("docs/designs/current/DESIGN-a.md", &design("Current"));
    repo.write("docs/designs/current/DESIGN-b.md", &design("Current"));
    repo.write(
        "docs/prds/PRD-a.md",
        "Superseded design: `docs/designs/current/DESIGN-a.md`.\n",
    );
    repo.commit_all();

    let out = repo.transition(
        "docs/designs/current/DESIGN-a.md",
        "Superseded",
        &["--superseded-by", "docs/designs/current/DESIGN-b.md"],
    );
    assert_success(&out);
    assert!(repo
        .read("docs/prds/PRD-a.md")
        .contains("docs/designs/archive/DESIGN-a.md"));
}

#[test]
fn a_sunset_vision_and_strategy_repoint_the_same_way() {
    let repo = Repo::new("sunset");
    repo.write(
        "docs/visions/VISION-a.md",
        "---\nschema: vision/v1\nstatus: Active\n---\n\n## Status\n\nActive\n",
    );
    repo.write(
        "docs/strategies/STRATEGY-a.md",
        "---\nschema: strategy/v1\nstatus: Active\n---\n\n## Status\n\nActive\n",
    );
    repo.write(
        "docs/prds/PRD-a.md",
        "Under `docs/visions/VISION-a.md` and `docs/strategies/STRATEGY-a.md`.\n",
    );
    repo.commit_all();

    assert_success(&repo.transition("docs/visions/VISION-a.md", "Sunset", &[]));
    assert_success(&repo.transition(
        "docs/strategies/STRATEGY-a.md",
        "Sunset",
        &["--reason", "replaced"],
    ));

    let text = repo.read("docs/prds/PRD-a.md");
    assert!(text.contains("docs/visions/sunset/VISION-a.md"), "{text}");
    assert!(
        text.contains("docs/strategies/sunset/STRATEGY-a.md"),
        "{text}"
    );
}

#[test]
fn a_repointed_diff_contains_only_the_substituted_path() {
    let repo = Repo::new("diff-shape");
    repo.write("docs/designs/DESIGN-a.md", &design("Proposed"));
    // Trailing whitespace on one line, CRLF endings on the other file: both
    // are what a re-render would quietly normalize.
    repo.write(
        "docs/prds/PRD-ws.md",
        "Line with trailing space:   \nSee `docs/designs/DESIGN-a.md`.\t\n",
    );
    repo.write(
        "docs/prds/PRD-crlf.md",
        "---\r\nschema: prd/v1\r\n---\r\n\r\nSee `docs/designs/DESIGN-a.md`.\r\n",
    );
    repo.commit_all();

    assert_success(&repo.transition("docs/designs/DESIGN-a.md", "Current", &[]));

    // The whole diff, minus the header lines, is one removed line and one
    // added line per file, differing only in the path.
    let diff = repo.git(&["diff", "--cached", "-U0", "--", "docs/prds"]);
    let text = String::from_utf8_lossy(&diff.stdout);
    let removed: Vec<&str> = text
        .lines()
        .filter(|l| l.starts_with('-') && !l.starts_with("---"))
        .collect();
    let added: Vec<&str> = text
        .lines()
        .filter(|l| l.starts_with('+') && !l.starts_with("+++"))
        .collect();
    assert_eq!(removed.len(), 2, "{text}");
    assert_eq!(added.len(), 2, "{text}");
    for (before, after) in removed.iter().zip(added.iter()) {
        assert_eq!(
            before[1..].replace(
                "docs/designs/DESIGN-a.md",
                "docs/designs/current/DESIGN-a.md"
            ),
            after[1..],
            "only the path substring may differ"
        );
    }

    assert!(
        repo.read("docs/prds/PRD-crlf.md").contains("\r\n"),
        "CRLF endings survive the rewrite"
    );
    assert!(
        repo.read("docs/prds/PRD-ws.md").contains("space:   \n"),
        "trailing whitespace survives the rewrite"
    );
}

#[test]
fn a_pre_move_path_inside_a_code_block_is_not_rewritten() {
    let repo = Repo::new("code-block");
    repo.write("docs/designs/DESIGN-a.md", &design("Proposed"));
    let example = concat!(
        "A worked example:\n",
        "\n",
        "```yaml\n",
        "upstream: docs/designs/DESIGN-a.md\n",
        "```\n",
        "\n",
        "    docs/designs/DESIGN-a.md\n",
        "\n",
        "End.\n",
    );
    repo.write("docs/prds/PRD-a.md", example);
    repo.commit_all();

    assert_success(&repo.transition("docs/designs/DESIGN-a.md", "Current", &[]));
    assert_eq!(
        repo.read("docs/prds/PRD-a.md"),
        example,
        "an example naming the pre-move path stops being that example if a tool updates it"
    );
}

#[test]
fn an_inbound_frontmatter_upstream_is_repointed_and_r6_stays_quiet() {
    let repo = Repo::new("frontmatter");
    repo.write("docs/designs/DESIGN-a.md", &design("Proposed"));
    repo.write(
        "docs/plans/PLAN-a.md",
        "---\nschema: plan/v1\nstatus: Active\nexecution_mode: single-pr\nupstream: docs/designs/DESIGN-a.md\n---\n\n## Status\n\nActive\n",
    );
    repo.commit_all();

    assert_success(&repo.transition("docs/designs/DESIGN-a.md", "Current", &[]));
    assert!(repo
        .read("docs/plans/PLAN-a.md")
        .contains("upstream: docs/designs/current/DESIGN-a.md"));

    let out = repo.validate(&["--check", "R6", "docs/plans/PLAN-a.md"]);
    let findings = String::from_utf8_lossy(&out.stdout);
    assert!(
        !findings.contains("R6"),
        "R6 must not report a dangle after the repoint: {findings}"
    );
}

#[test]
fn a_relative_referrer_is_repointed_and_stays_relative() {
    let repo = Repo::new("relative");
    repo.write("docs/designs/DESIGN-a.md", &design("Proposed"));
    repo.write(
        "docs/prds/PRD-a.md",
        "See [the design](../designs/DESIGN-a.md).\n",
    );
    repo.commit_all();

    assert_success(&repo.transition("docs/designs/DESIGN-a.md", "Current", &[]));
    assert_eq!(
        repo.read("docs/prds/PRD-a.md"),
        "See [the design](../designs/current/DESIGN-a.md).\n"
    );
}

#[test]
fn a_second_run_reports_nothing_rather_than_failing() {
    let repo = Repo::new("idempotent");
    repo.write("docs/designs/DESIGN-a.md", &design("Proposed"));
    repo.write("docs/prds/PRD-a.md", "See `docs/designs/DESIGN-a.md`.\n");
    repo.commit_all();

    assert_success(&repo.transition("docs/designs/DESIGN-a.md", "Current", &[]));
    let after_first = repo.read("docs/prds/PRD-a.md");

    let second = repo.transition("docs/designs/current/DESIGN-a.md", "Current", &[]);
    assert_success(&second);
    assert_eq!(repo.read("docs/prds/PRD-a.md"), after_first);
    let stderr = String::from_utf8_lossy(&second.stderr);
    assert!(
        !stderr.contains("repointed"),
        "a settled tree reports no rewrites: {stderr}"
    );
}

#[test]
fn the_repoint_does_not_apply_the_prose_finding_cap() {
    // Truncating a rewrite leaves a file half-repointed. The cap is a
    // reporting policy, and this is not reporting.
    let repo = Repo::new("no-cap");
    repo.write("docs/designs/DESIGN-a.md", &design("Proposed"));
    let body = "See `docs/designs/DESIGN-a.md`.\n".repeat(120);
    repo.write("docs/prds/PRD-a.md", &body);
    repo.commit_all();

    let out = repo.transition("docs/designs/DESIGN-a.md", "Current", &[]);
    assert_success(&out);
    let text = repo.read("docs/prds/PRD-a.md");
    assert_eq!(
        text.matches("docs/designs/current/DESIGN-a.md").count(),
        120
    );
    assert!(!text.contains("`docs/designs/DESIGN-a.md`"));
    assert!(String::from_utf8_lossy(&out.stderr).contains("docs/prds/PRD-a.md (120)"));
}

#[test]
fn a_write_failure_refuses_the_transition_and_names_what_changed() {
    // A read-only referrer makes the write phase fail. The transition must
    // exit non-zero rather than report a move whose inbound references were
    // only partly repaired.
    let repo = Repo::new("write-failure");
    repo.write("docs/designs/DESIGN-a.md", &design("Proposed"));
    // `a` sorts before `z`, so the first file is rewritten and the second
    // fails: the message has to name both roles.
    repo.write("docs/prds/PRD-a.md", "See `docs/designs/DESIGN-a.md`.\n");
    repo.write("docs/prds/PRD-z.md", "See `docs/designs/DESIGN-a.md`.\n");
    repo.commit_all();

    let locked = repo.root.join("docs/prds/PRD-z.md");
    set_readonly(&locked, true);
    let out = repo.transition("docs/designs/DESIGN-a.md", "Current", &[]);
    set_readonly(&locked, false);

    assert_eq!(out.status.code(), Some(3), "a repoint failure is exit 3");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("\"success\": false"), "stderr: {stderr}");
    assert!(stderr.contains("docs/prds/PRD-z.md"), "stderr: {stderr}");
    assert!(
        stderr.contains("already rewritten: docs/prds/PRD-a.md"),
        "stderr: {stderr}"
    );
    assert!(
        String::from_utf8_lossy(&out.stdout).is_empty(),
        "no success result is printed"
    );
}

fn set_readonly(path: &Path, readonly: bool) {
    let mut perms = std::fs::metadata(path).expect("metadata").permissions();
    perms.set_readonly(readonly);
    std::fs::set_permissions(path, perms).expect("set permissions");
}
