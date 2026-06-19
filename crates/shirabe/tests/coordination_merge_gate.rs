//! CLI integration tests for `shirabe validate --merge-gate`, the
//! posture-aware coordination merge-last gate mode that replaced the
//! `shirabe coordination gate`/`verify` verbs.
//!
//! These exercise the built binary end to end for the behaviors that are
//! deterministic offline (no live `gh` reachable in CI):
//!
//! - argument validation (`--pr`/`--upstream` require `--merge-gate`, the
//!   lifecycle/positional-file mutual exclusions);
//! - the hard input-error path (a malformed `--pr` reference, exit 1);
//! - the Coordination-PR Visibility Rule front door: a public coordination PR
//!   (the default `--visibility` unset) gating over a repo whose visibility
//!   cannot be resolved offline fails closed to private and REFUSES (exit 2),
//!   with the diagnostic F1-redacted to the opaque node id.
//!
//! The pass/block posture matrix (which needs a live `gh` merge-state read) is
//! covered by the pure `run_merge_gate` / `merge_gate_outcome` unit tests in
//! `shirabe_validate::merge_gate` and `shirabe`'s `main.rs`; those mock the
//! issue client and inject a stub visibility resolver, so the
//! draft-notice-vs-ready-block contract is locked without touching `gh`.

use assert_cmd::Command;
use predicates::prelude::PredicateBooleanExt;
use predicates::str::contains;

fn shirabe() -> Command {
    Command::cargo_bin("shirabe").expect("binary `shirabe` builds")
}

#[test]
fn merge_gate_rejects_pr_without_merge_gate_flag() {
    // `--pr` is only meaningful in merge-gate mode.
    shirabe()
        .args(["validate", "--pr", "o/r:docs/a.md#1"])
        .assert()
        .code(1)
        .stderr(contains("--pr and --upstream require --merge-gate"));
}

#[test]
fn merge_gate_conflicts_with_lifecycle_at_cli() {
    // clap rejects --merge-gate alongside --lifecycle (a validate run is one
    // mode). clap usage errors exit 2.
    shirabe()
        .args(["validate", "--merge-gate", "--lifecycle", "."])
        .assert()
        .failure();
}

#[test]
fn merge_gate_rejects_positional_files() {
    shirabe()
        .args(["validate", "--merge-gate", "docs/foo.md"])
        .assert()
        .code(1)
        .stderr(contains(
            "--merge-gate is mutually exclusive with positional file arguments",
        ));
}

#[test]
fn merge_gate_malformed_pr_is_input_error() {
    // A `--pr` missing its `#number` suffix is a hard input error (exit 1),
    // posture-independent.
    shirabe()
        .args([
            "validate",
            "--merge-gate",
            "--mode=ready",
            "--pr",
            "tsukumogami/shirabe:docs/plans/PLAN-x.md",
        ])
        .assert()
        .code(1)
        .stderr(contains("merge-gate:"));
}

#[test]
fn merge_gate_public_pr_over_unresolvable_repo_refuses_redacted() {
    // A public coordination PR (default `--visibility` unset) gating over a
    // repo whose visibility cannot be resolved offline fails closed to private
    // and REFUSES (exit 2). The refusal is F1-redacted: the opaque `pr-<n>`
    // node id appears, the raw private-shaped owner/repo/path does NOT.
    shirabe()
        .args([
            "validate",
            "--merge-gate",
            "--mode=ready",
            "--pr",
            "acme/secret-repo:docs/plans/PLAN-classified.md#7",
        ])
        .assert()
        .code(2)
        .stderr(
            contains("REFUSED")
                .and(contains("pr-7"))
                .and(contains("secret-repo").not())
                .and(contains("PLAN-classified.md").not()),
        );
}
