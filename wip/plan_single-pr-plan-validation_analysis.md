# /plan Phase 1 Analysis: single-pr-plan-validation

## Input

- **input_type:** topic (per /scope chain Dispatch Contract; only the topic slug is passed)
- **Effective upstream:** `docs/prds/PRD-single-pr-plan-validation.md` (Accepted at commit `1cb3da4`)
- **BRIEF context:** `docs/briefs/BRIEF-single-pr-plan-validation.md` (Accepted, amended in place for FC10→FC14 at commit `b0995f1`)
- **Scope:** Tactical (shirabe default; no `--strategic` flag)
- **Visibility:** Public

## Source Document Status Validation

Upstream PRD frontmatter `status: Accepted` ✓ (verified at commit `1cb3da4`).
Upstream BRIEF frontmatter `status: Accepted` ✓ (verified at commit `b0995f1`).
Validator pass-through ✓ for both.

## Scope Summary

Add `check_fc14` (a new validator check) and the supporting machinery (an
`execution_mode`-aware `FormatSpec` extension for the Plan profile, plus a
new outline parser helper) to close the structural-validation parity gap
between single-pr and multi-pr plans. Ships at notice severity matching the
FC07-FC13 staged-rollout pattern.

## Components

Five components map to the PRD's R1-R15:

1. **`FormatSpec` extension** (R1, R11). Extend the Plan profile's
   required-sections shape to branch on `execution_mode`. Other profiles
   unchanged. Lives in `crates/shirabe-validate/src/formats.rs`.

2. **Outline parser helper** (R2, R12). New `parse_issue_outlines(doc: &Doc)
   -> Vec<OutlineBlock>` function extracting outline blocks with per-block
   `key`, `goal`, `acceptance_criteria`, `dependencies` fields. Total over
   arbitrary input (no panics). File location is a downstream implementation
   choice (extending `table.rs` or new `outlines.rs`).

3. **`check_fc14` dispatch** (R2-R5, R9). The new check function in
   `crates/shirabe-validate/src/checks.rs`, dispatched in the Plan arm of
   `validate_file` alongside FC05-FC13. Walks the 5 sub-checks (A through E)
   and emits per-defect notices.

4. **`is_notice` registration + promotion seam** (R6, R7, R8). Add `FC14` to
   the `is_notice` match arm in `crates/shirabe-validate/src/validate.rs`.
   This keeps FC14 notices from reddening CI; removing the arm promotes to
   error.

5. **Tests** (R13, R14). Table-driven test coverage in `checks.rs::tests`
   covering every per-sub-check AC scenario from the PRD's Sub-check A-E
   acceptance criteria plus the implementation-level ACs (exit-0
   contract; FC04 non-duplication; multi-pr unchanged; Dependency Graph
   under single-pr; parser-totality cases).

## Implementation Phases

The PRD's Decisions and Trade-offs D2 ("one check fanning out into five
sub-checks") and D3 ("outline parser file location left to implementation")
collapse the work to a single integrated implementation:

1. Extend `FormatSpec` (component 1).
2. Add outline parser (component 2).
3. Add `check_fc14` calling the parser and walking sub-checks A-E (component 3).
4. Register `FC14` in `is_notice` (component 4).
5. Author tests (component 5).

All five fit into one bounded session — the wiring is well-understood (FC07/FC08/FC09 precedents), the parser is a straightforward extension of `parse_issues_table`, and `is_notice` is a one-line change.

## Success Metrics (from PRD Goals)

1. Validator parity: a single-pr plan gets the same level of notice-level feedback as a multi-pr plan.
2. No vacuous-pass: each of the 5 sub-check defect cases produces a notice.
3. No regression on multi-pr: existing FC04/FC05/FC06/FC07/FC08/FC09 behavior unchanged.
4. One-line promotion seam: removing FC14 from `is_notice` promotes to error.

## Dependencies

- Upstream PRD: Accepted (commit `1cb3da4`).
- Upstream BRIEF: Accepted (commit `b0995f1`).
- Issue #119 (FC07 mermaid extractor + table-diagram reconciliation): closed; provides the `Doc` IR, `Profile` enum, `parse_issues_table` precedent, and the `is_notice` match-arm pattern.

No external dependencies; the work is entirely inside `crates/shirabe-validate/src/`.

## Decomposition Recommendation

**Single bounded outline.** The work is one logically cohesive implementation:
add a check, the parser it consumes, the FormatSpec extension that drives the
required-sections branching, and the tests that verify the behavior. The 5
sub-checks share enough machinery (frontmatter `execution_mode` consumption,
outline-block traversal) that they ship as one `check_fc14` with sub-check-
specific notice messages.

**Execution mode recommendation: single-pr.** Per `/plan`'s default ("Reach
for one PR") anchored on usable-value principle P1, and per the FC09
precedent (PR #167, also one PR). The work delivers observable value as a
single increment: a coordinator authoring a single-pr plan gets immediate
notice-level feedback after one PR merges. No multi-pr escape conditions
apply: no cross-repo landing order, no workflow-must-reach-main gate, no
merge gate between steps, no genuine independent value from splitting.
