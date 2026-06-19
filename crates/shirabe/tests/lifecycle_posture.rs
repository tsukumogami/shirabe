//! End-to-end posture-classification tests for `shirabe validate
//! --lifecycle`, exercising the built binary so the full roll-up is
//! proven: a doc tree on disk -> the binary under `--mode=draft|ready`
//! -> the process exit code and the `shirabe-validate/v1` JSON envelope's
//! per-finding `severity`.
//!
//! These lock the Issue-2 classification (#197): the lifecycle in-flight
//! findings L02/L06/L07 are draft-tolerable (notice under draft, error
//! under ready), while L01/L03/L04/L05 are always-enforced (error under
//! both). The exit code and the JSON `severity` are read from the same
//! `effective_severity` seam, so each test asserts they agree.
//!
//! Exit-code contract: 0 clean (only notices/none), 2 violations (any
//! error-level finding). A draft-tolerable-only tree therefore exits 0
//! under draft and 2 under ready; an always-enforced finding exits 2
//! under both.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use assert_cmd::Command;
use predicates::prelude::PredicateBooleanExt;
use predicates::str::contains;

static COUNTER: AtomicUsize = AtomicUsize::new(0);

fn shirabe() -> Command {
    Command::cargo_bin("shirabe").expect("binary `shirabe` builds")
}

/// Build a uniquely-named temp dir with the standard `docs/`
/// subdirectories and write the given docs into it. Each tuple is
/// `(repo-relative-path, full-file-content)`. Returns the canonical root.
fn build_tree(docs: &[(&str, String)]) -> PathBuf {
    let n = COUNTER.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!(
        "shirabe-cli-lifecycle-posture-{}-{}",
        std::process::id(),
        n
    ));
    let _ = fs::remove_dir_all(&root);
    for sub in &[
        "docs/briefs",
        "docs/prds",
        "docs/designs",
        "docs/designs/current",
        "docs/plans",
        "docs/roadmaps",
    ] {
        fs::create_dir_all(root.join(sub)).unwrap();
    }
    for (rel, content) in docs {
        let path = root.join(rel);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(&path, content).unwrap();
    }
    fs::canonicalize(&root).unwrap()
}

fn doc(frontmatter: &str, body: &str) -> String {
    format!("---\n{}---\n\n{}\n", frontmatter, body)
}

fn brief(status: &str, upstream: &str) -> String {
    let mut fm = format!(
        "schema: brief/v1\nstatus: {}\nproblem: |\n  problem.\noutcome: |\n  outcome.\n",
        status
    );
    if !upstream.is_empty() {
        fm.push_str(&format!("upstream: {}\n", upstream));
    }
    let body = format!(
        "# BRIEF: t\n\n## Status\n\n{}\n\n## Problem Statement\n\nP.\n\n## User Outcome\n\nO.\n\n## User Journeys\n\n### Journey 1\n\nU does thing.\n\n## Scope Boundary\n\nIN: x.\nOUT: y.\n",
        status
    );
    doc(&fm, &body)
}

fn prd(status: &str, upstream: &str) -> String {
    let fm = format!(
        "schema: prd/v1\nstatus: {}\nproblem: |\n  problem.\ngoals: |\n  goals.\nupstream: {}\n",
        status, upstream
    );
    let body = format!(
        "# PRD: t\n\n## Status\n\n{}\n\n## Problem Statement\n\nP.\n\n## Goals\n\nG.\n\n## User Stories\n\nAs a user.\n\n## Requirements\n\nR1.\n\n## Acceptance Criteria\n\n- [ ] AC.\n\n## Out of Scope\n\nOOS.\n",
        status
    );
    doc(&fm, &body)
}

fn design(status: &str, upstream: &str) -> String {
    let fm = format!(
        "schema: design/v1\nstatus: {}\nproblem: |\n  problem.\ndecision: |\n  decision.\nrationale: |\n  rationale.\nupstream: {}\n",
        status, upstream
    );
    let body = format!(
        "# DESIGN: t\n\n## Status\n\n{}\n\n## Context and Problem Statement\n\nP.\n\n## Decision Drivers\n\nD.\n\n## Considered Options\n\nO.\n\n## Decision Outcome\n\nD.\n\n## Solution Architecture\n\nS.\n\n## Implementation Approach\n\nI.\n\n## Security Considerations\n\nS.\n\n## Consequences\n\nC.\n",
        status
    );
    doc(&fm, &body)
}

/// A single-pr PLAN. `acs` is the verbatim acceptance-criteria bullet
/// block under the `### Issue 1` outline (e.g. `"- [ ] open\n"` for an
/// unticked AC, or `"- [x] done\n"` for a ticked one).
fn single_pr_plan(status: &str, upstream: &str, acs: &str) -> String {
    let fm = format!(
        "schema: plan/v1\nstatus: {}\nexecution_mode: single-pr\nmilestone: \"m\"\nissue_count: 1\nupstream: {}\n",
        status, upstream
    );
    let body = format!(
        "# PLAN: t\n\n## Status\n\n{}\n\n## Scope Summary\n\nS.\n\n## Decomposition Strategy\n\nD.\n\n## Issue Outlines\n\n### Issue 1: first\n\n**Goal**: do it.\n\n**Acceptance Criteria**:\n{}\n**Dependencies**: None\n\n## Implementation Sequence\n\nSeq.\n",
        status, acs
    );
    doc(&fm, &body)
}

/// Run `validate --lifecycle <root> --mode <mode> --format json` and
/// return (exit_code, stdout).
fn run_lifecycle(root: &Path, mode: &str) -> (i32, String) {
    let out = shirabe()
        .arg("validate")
        .arg("--lifecycle")
        .arg(root)
        .arg("--mode")
        .arg(mode)
        .arg("--format")
        .arg("json")
        .output()
        .expect("run shirabe");
    let code = out.status.code().expect("exit code");
    let stdout = String::from_utf8(out.stdout).expect("utf8 stdout");
    (code, stdout)
}

// ---- #197 reproduction: an orphan BRIEF at Draft (L02) ----

#[test]
fn issue_197_orphan_brief_at_draft_exits_0_draft_2_ready() {
    // The head of a fresh /scope chain: a BRIEF at Draft with no
    // downstream artifact and no upstream. The orphan rule fires L02
    // (orphan BRIEF at non-terminal status). This is the issue #197
    // hard-fail on a draft PR. Under draft posture L02 is a notice so the
    // run is clean (exit 0); under ready posture it is an error (exit 2).
    let root = build_tree(&[("docs/briefs/BRIEF-foo.md", brief("Draft", ""))]);

    let (code_draft, json_draft) = run_lifecycle(&root, "draft");
    assert_eq!(
        code_draft, 0,
        "orphan BRIEF at Draft must exit 0 under draft (#197); json: {}",
        json_draft
    );
    // The L02 finding is present but rendered notice-level, and the
    // envelope outcome is clean. Severity field agrees with exit 0.
    assert!(
        json_draft.contains("\"code\": \"L02\""),
        "json: {}",
        json_draft
    );
    assert!(
        json_draft.contains("\"outcome\": \"clean\""),
        "json: {}",
        json_draft
    );
    assert!(
        json_draft.contains("\"severity\": \"notice\""),
        "L02 must render notice under draft; json: {}",
        json_draft
    );

    let (code_ready, json_ready) = run_lifecycle(&root, "ready");
    assert_eq!(
        code_ready, 2,
        "orphan BRIEF at Draft must exit 2 under ready; json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"code\": \"L02\""),
        "json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"outcome\": \"violations\""),
        "json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"severity\": \"error\""),
        "L02 must render error under ready; json: {}",
        json_ready
    );
}

// ---- L06 reproduction: single-pr PLAN with an unticked AC ----

#[test]
fn l06_unticked_ac_single_pr_plan_exits_0_draft_2_ready() {
    // An Active single-pr chain whose PLAN carries an unticked outline-AC
    // checkbox. The chain shape is otherwise healthy at the single-pr
    // mid-PR posture (BRIEF Accepted, PRD Accepted, DESIGN Planned, PLAN
    // Active), so the only lifecycle finding is L06. L06 is draft-tolerable:
    // notice under draft (exit 0), error under ready (exit 2). Under ready
    // the single-pr-mid-PR re-target also surfaces L01 errors, but the
    // outcome is already 2; the contract under test is the L06 flip.
    let root = build_tree(&[
        ("docs/briefs/BRIEF-foo.md", brief("Accepted", "")),
        (
            "docs/prds/PRD-foo.md",
            prd("Accepted", "docs/briefs/BRIEF-foo.md"),
        ),
        (
            "docs/designs/DESIGN-foo.md",
            design("Planned", "docs/prds/PRD-foo.md"),
        ),
        (
            "docs/plans/PLAN-foo.md",
            single_pr_plan("Active", "docs/designs/DESIGN-foo.md", "- [ ] open\n"),
        ),
    ]);

    let (code_draft, json_draft) = run_lifecycle(&root, "draft");
    assert_eq!(
        code_draft, 0,
        "unticked-AC single-pr PLAN must exit 0 under draft; json: {}",
        json_draft
    );
    assert!(
        json_draft.contains("\"code\": \"L06\""),
        "json: {}",
        json_draft
    );
    assert!(
        json_draft.contains("\"outcome\": \"clean\""),
        "json: {}",
        json_draft
    );
    assert!(
        json_draft.contains("\"severity\": \"notice\""),
        "L06 must render notice under draft; json: {}",
        json_draft
    );

    let (code_ready, json_ready) = run_lifecycle(&root, "ready");
    assert_eq!(
        code_ready, 2,
        "unticked-AC single-pr PLAN must exit 2 under ready; json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"code\": \"L06\""),
        "json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"outcome\": \"violations\""),
        "json: {}",
        json_ready
    );
}

// ---- always-enforced finding: exits 2 under BOTH postures ----

#[test]
fn always_enforced_l04_missing_upstream_exits_2_in_both_postures() {
    // A single-pr PLAN whose `upstream:` points at a DESIGN that does not
    // exist in the tree fires L04 (chain member missing). L04 is
    // always-enforced: error under both postures, so the run exits 2
    // regardless of --mode. This proves a non-draft-tolerable lifecycle
    // finding is not softened by draft posture.
    let root = build_tree(&[(
        "docs/plans/PLAN-foo.md",
        single_pr_plan("Active", "docs/designs/DESIGN-missing.md", "- [x] done\n"),
    )]);

    let (code_draft, json_draft) = run_lifecycle(&root, "draft");
    assert_eq!(
        code_draft, 2,
        "missing-upstream L04 must exit 2 under draft; json: {}",
        json_draft
    );
    assert!(
        json_draft.contains("\"code\": \"L04\""),
        "json: {}",
        json_draft
    );
    assert!(
        json_draft.contains("\"severity\": \"error\""),
        "L04 must render error under draft; json: {}",
        json_draft
    );

    let (code_ready, json_ready) = run_lifecycle(&root, "ready");
    assert_eq!(
        code_ready, 2,
        "missing-upstream L04 must exit 2 under ready; json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"code\": \"L04\""),
        "json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"severity\": \"error\""),
        "L04 must render error under ready; json: {}",
        json_ready
    );
}

// ---- L01 posture sensitivity preserved (Issue 1 behavior) ----

#[test]
fn l01_single_pr_mid_pr_chain_exits_0_draft_2_ready() {
    // A single-pr chain whose PLAN is still present at Active with all ACs
    // ticked. Under draft the single-pr-mid-PR posture passes (PLAN at
    // Active is the healthy mid-PR state), so exit 0. Under ready the
    // re-target to single-pr-at-merge fires L01 (PLAN must be DELETED,
    // BRIEF/PRD must be Done, DESIGN Current), so exit 2. This preserves
    // the L01 posture sensitivity Issue 1 established. L01 is
    // always-enforced; here the flip comes from the posture re-target, not
    // a severity reclassification.
    let root = build_tree(&[
        ("docs/briefs/BRIEF-foo.md", brief("Accepted", "")),
        (
            "docs/prds/PRD-foo.md",
            prd("Accepted", "docs/briefs/BRIEF-foo.md"),
        ),
        (
            "docs/designs/DESIGN-foo.md",
            design("Planned", "docs/prds/PRD-foo.md"),
        ),
        (
            "docs/plans/PLAN-foo.md",
            single_pr_plan("Active", "docs/designs/DESIGN-foo.md", "- [x] done\n"),
        ),
    ]);

    let (code_draft, json_draft) = run_lifecycle(&root, "draft");
    assert_eq!(
        code_draft, 0,
        "healthy single-pr mid-PR chain must exit 0 under draft; json: {}",
        json_draft
    );
    assert!(
        json_draft.contains("\"outcome\": \"clean\""),
        "json: {}",
        json_draft
    );

    let (code_ready, json_ready) = run_lifecycle(&root, "ready");
    assert_eq!(
        code_ready, 2,
        "single-pr mid-PR chain must exit 2 under ready (L01 re-target); json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"code\": \"L01\""),
        "json: {}",
        json_ready
    );
    assert!(
        json_ready.contains("\"severity\": \"error\""),
        "L01 must render error under ready; json: {}",
        json_ready
    );
}

// ---- annotation-mode sanity: draft-tolerable L02 emits a notice line ----

#[test]
fn l02_draft_emits_notice_annotation_not_error() {
    // The default annotation format renders a draft-tolerable finding as a
    // ::notice workflow command under draft (clean exit), and as ::error
    // under ready (violations exit). This locks the human/CI-facing line
    // shape against the severity classification.
    let root = build_tree(&[("docs/briefs/BRIEF-foo.md", brief("Draft", ""))]);

    shirabe()
        .arg("validate")
        .arg("--lifecycle")
        .arg(&root)
        .arg("--mode")
        .arg("draft")
        .assert()
        .success()
        .stdout(contains("::notice").and(contains("[L02]")));

    shirabe()
        .arg("validate")
        .arg("--lifecycle")
        .arg(&root)
        .arg("--mode")
        .arg("ready")
        .assert()
        .failure()
        .stdout(contains("::error").and(contains("[L02]")));
}
