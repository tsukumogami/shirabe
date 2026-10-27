//! A ready scoping PR for an outline-shaped `multi-pr` PLAN, judged the same
//! whether the PLAN is an issueless `plan/v1` or a `plan/v2` step plan.
//!
//! Each case is a small repository root: a PRD at `In Progress`, a DESIGN at
//! `Planned`, and a PLAN in `multi-pr` mode at `tracking_level: none` whose
//! criteria are not yet ticked. Its work lands one pull request at a time
//! after the scoping PR merges, so the whole-tree run (the pull-request gate)
//! holds it to the multi-pr postures. The chain-targeted run the completion
//! cascade uses keeps the single-pr shape, so a present PLAN still fails
//! there at ready.

use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use shirabe_validate::{
    run_lifecycle_chain_check, run_lifecycle_check, Config, ReviewPosture, ValidationError,
};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

#[derive(Debug, Clone, Copy)]
enum Schema {
    /// An issueless `plan/v1` PLAN carrying `## Issue Outlines`.
    V1,
    /// A `plan/v2` step plan.
    V2,
}

const SCHEMAS: [Schema; 2] = [Schema::V1, Schema::V2];

const PLAN: &str = "docs/plans/PLAN-foo.md";

fn plan_frontmatter(schema: Schema, status: &str) -> String {
    let (schema_line, count_line) = match schema {
        Schema::V1 => ("plan/v1", "issue_count: 2"),
        Schema::V2 => ("plan/v2", "step_count: 2"),
    };
    format!(
        "schema: {schema_line}\nstatus: {status}\nexecution_mode: multi-pr\ntracking_level: none\nmilestone: \"m\"\n{count_line}\nsplit_rationale: Hard Constraint. The work lands in two repositories.\nupstream: docs/designs/DESIGN-foo.md\n"
    )
}

fn plan_body(schema: Schema, status: &str) -> String {
    match schema {
        Schema::V1 => format!(
            "# PLAN: t\n\n## Status\n\n{status}\n\n## Scope Summary\n\nS.\n\n## Decomposition Strategy\n\nD.\n\n## Issue Outlines\n\n### Issue 1: first\n\n**Goal**: g.\n\n**Acceptance Criteria**:\n\n- [ ] a.\n\n**Dependencies**: None\n\n### Issue 2: second\n\n**Goal**: g.\n\n**Acceptance Criteria**:\n\n- [ ] b.\n\n**Dependencies**: Issue 1\n\n## Implementation Sequence\n\nSeq.\n"
        ),
        Schema::V2 => format!(
            "# PLAN: t\n\n## Status\n\n{status}\n\n## Scope Summary\n\nS.\n\n## Decomposition Strategy\n\nD.\n\n## Steps\n\n### Step 1: first\n\n**Goal**: g.\n\n**Acceptance Criteria**:\n\n- [ ] a.\n\n**Check**: run it.\n\n**Dependencies**: None\n\n### Step 2: second\n\n**Goal**: g.\n\n**Acceptance Criteria**:\n\n- [ ] b.\n\n**Check**: run it.\n\n**Dependencies**: Step 1\n"
        ),
    }
}

/// Write the scoping PR's tree into a fresh temp directory and return its
/// canonical root.
fn scoping_tree(schema: Schema, plan_status: &str) -> PathBuf {
    let n = COUNTER.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!(
        "shirabe-lifecycle-outline-multi-pr-{}-{}",
        std::process::id(),
        n
    ));
    let _ = fs::remove_dir_all(&root);
    for sub in [
        "docs/briefs",
        "docs/prds",
        "docs/designs",
        "docs/designs/current",
        "docs/plans",
        "docs/roadmaps",
    ] {
        fs::create_dir_all(root.join(sub)).unwrap();
    }
    let docs = [
        (
            "docs/prds/PRD-foo.md",
            "schema: prd/v1\nstatus: In Progress\nproblem: |\n  problem.\ngoals: |\n  goals.\n"
                .to_string(),
            "# PRD: t\n\n## Status\n\nIn Progress\n\n## Problem Statement\n\nP.\n\n## Goals\n\nG.\n\n## User Stories\n\nAs a user.\n\n## Requirements\n\nR1.\n\n## Acceptance Criteria\n\n- [ ] AC.\n\n## Out of Scope\n\nOOS.\n"
                .to_string(),
        ),
        (
            "docs/designs/DESIGN-foo.md",
            "schema: design/v1\nstatus: Planned\nproblem: |\n  problem.\ndecision: |\n  decision.\nrationale: |\n  rationale.\nupstream: docs/prds/PRD-foo.md\n"
                .to_string(),
            "# DESIGN: t\n\n## Status\n\nPlanned\n\n## Context and Problem Statement\n\nP.\n\n## Decision Drivers\n\nD.\n\n## Considered Options\n\nO.\n\n## Decision Outcome\n\nD.\n\n## Solution Architecture\n\nS.\n\n## Implementation Approach\n\nI.\n\n## Security Considerations\n\nS.\n\n## Consequences\n\nC.\n"
                .to_string(),
        ),
        (
            PLAN,
            plan_frontmatter(schema, plan_status),
            plan_body(schema, plan_status),
        ),
    ];
    for (rel, frontmatter, body) in docs {
        fs::write(root.join(rel), format!("---\n{frontmatter}---\n\n{body}\n")).unwrap();
    }
    fs::canonicalize(&root).unwrap()
}

fn l01_mentioning<'a>(errors: &'a [ValidationError], posture: &str) -> Vec<&'a ValidationError> {
    errors
        .iter()
        .filter(|e| e.code == "L01" && e.message.contains(posture))
        .collect()
}

/// The whole-tree run passes a ready scoping PR whose outline-shaped
/// `multi-pr` PLAN is at `Active`, for `plan/v1` as for `plan/v2`: DESIGN at
/// `Planned`, PLAN at `Active` and outline criteria unticked are the in-flight
/// states, not findings.
#[test]
fn an_outline_shaped_multi_pr_plan_is_in_flight_at_ready() {
    for schema in SCHEMAS {
        let root = scoping_tree(schema, "Active");
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Ready);
        assert!(
            errors.is_empty(),
            "{schema:?}: a ready scoping PR for an outline-shaped multi-pr PLAN must pass the whole-tree run; got {errors:?}"
        );
    }
}

/// The chain-targeted run keeps the single-pr shape for the same tree, so the
/// completion cascade, which runs that mode at ready, still sees a present
/// PLAN fail and knows it has work to do.
#[test]
fn the_chain_targeted_run_still_fails_a_present_plan_at_ready() {
    for schema in SCHEMAS {
        let root = scoping_tree(schema, "Active");
        let errors =
            run_lifecycle_chain_check(&root.join(PLAN), &Config::default(), ReviewPosture::Ready);
        assert!(
            !l01_mentioning(&errors, "single-pr at-merge").is_empty(),
            "{schema:?}: the chain-targeted run must still fail a present PLAN at ready; got {errors:?}"
        );
    }
}

/// A PLAN at `Done` left in the tree is the multi-pr work-completing state,
/// which still fails L01 in the whole-tree run: the PLAN is owed deletion.
#[test]
fn a_done_outline_shaped_multi_pr_plan_fails_l01_as_work_completing() {
    for schema in SCHEMAS {
        let root = scoping_tree(schema, "Done");
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Ready);
        assert!(
            l01_mentioning(&errors, "multi-pr work-completing")
                .iter()
                .any(|e| e.message.contains("PLAN at status 'Done'")),
            "{schema:?}: a Done PLAN must fail L01 at the multi-pr work-completing posture; got {errors:?}"
        );
    }
}
