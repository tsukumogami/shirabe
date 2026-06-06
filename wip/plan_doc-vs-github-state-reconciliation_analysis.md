---
input_type: design
source_doc: docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md
visibility: public
effective_scope: tactical
execution_mode_directive: single-pr  # pre-committed by /scope chain
---

# Plan Analysis: doc-vs-github-state-reconciliation

## Source Document

Path: `docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md`
Status: Current
Upstream PRD: `docs/prds/PRD-doc-vs-github-state-reconciliation.md` (17
requirements, 28 acceptance criteria).
Parent PLAN row: `PLAN-roadmap-plan-standardization.md` #153.

## Scope (one-paragraph)

FC09 is the third reconciliation axis in `shirabe-validate` -- it
reconciles the plan/roadmap doc's claims about issue state (table
strikethrough, diagram class assignments) against GitHub's actual
issue state plus the current PR's `Closes #N` body lines. The check
lands as one new function `check_fc09` in `checks.rs`, consuming a
new `gh.rs` module that declares an `IssueStateClient` trait, a
`GhSubprocessClient` production impl, a `MockIssueStateClient` for
tests, and a `detect_pr_context` env-var reader. It ships notice-level
via the existing `is_notice` membership; the promotion seam is the
one-line removal of the `FC09` arm.

## Components / Implementation Steps

The DESIGN's `## Implementation Approach` section names six
implementation steps. They are the decomposition input for Phase 3.

1. **Step 1 (gh.rs scaffold).** Create the new module
   `crates/shirabe-validate/src/gh.rs`. Declare `IssueStateClient`,
   `IssueState`, `ClientError`, `PrContext`, the empty
   `GhSubprocessClient` struct (constructor only, no method impls
   yet), and `detect_pr_context()`. Unit-test `detect_pr_context`
   against the env-var matrix from Decision 7. Add `pub mod gh;` to
   `lib.rs`.

2. **Step 2 (GhSubprocessClient impl + MockIssueStateClient).**
   Implement the two `IssueStateClient` methods on
   `GhSubprocessClient`: spawn `gh api`, poll with timeout, parse
   stdout JSON (depth-aware top-level field extraction), classify
   stderr patterns. Implement `#[cfg(test)] MockIssueStateClient` per
   Decision 3. Unit-test the success path, each `ClientError`
   variant, the 5s timeout, the auth probe, and the mock's behavior
   across the six pinned cases.

3. **Step 3 (check_fc09 + validate_file wiring).** Implement the
   three sub-check passes inside `check_fc09`: Sub A (doc claims
   done vs GH open), Sub B (doc claims open vs GH closed), Sub C
   (PR `Closes #N` reconciliation in both directions). Wire FC09
   into the `Plan` and `Roadmap` arms of `validate_file`. Construct
   `GhSubprocessClient` once per `validate_file` call.
   Integration-test with at least one plan and one roadmap fixture
   per sub-check defect using `MockIssueStateClient`.

4. **Step 4 (is_notice extension).** Extend the existing `is_notice`
   match in `crates/shirabe-validate/src/validate.rs` to include
   `"FC09"` (Decision 6). Rename the test
   `is_notice_only_schema_and_fc07` to
   `is_notice_only_schema_fc07_fc09` and update its body. Update the
   doc comment to the FC09-aware wording.

5. **Step 5 (public-cleanliness scan).** Walk the committed
   `docs/plans/*.md` and `docs/roadmaps/*.md` corpus with FC09
   enabled. Inspect every emitted notice body for token bytes,
   private repo names, pre-announcement features, paths to private
   files, or external issue numbers from private repos. Verify
   `ClientError::Malformed(String)` payload never reaches a notice
   body, log message, or any user-visible surface. R17 acceptance
   criterion's surface.

6. **Step 6 (notice volume corpus survey).** Run the validator with
   FC09 enabled against the full committed corpus locally. Capture
   the notice count. The number goes into the PR body's verification
   section as evidence FC09 ships at a tractable notice volume (the
   parent DESIGN's "no-day-one-breakage" invariant; PRD Known
   Limitation #1).

## Sequencing Constraints (from DESIGN's "Dependency between steps")

- Step 2 depends on the trait declared in Step 1.
- Step 3 calls into the impl Step 2 lands.
- Step 4 is the membership wiring that turns the check into a notice.
- Steps 5 and 6 run after Step 4 and can be combined (both are
  corpus-scoped scans).
- The DESIGN explicitly states a single bundled PR carrying all six
  steps is the default shape; the FC07 sub-DESIGN's Decision 6 also
  defaults to a single bundled PR.

## Coupling Posture (decomposition-strategy input)

The six steps are **horizontally coupled by a clear prerequisite
chain**: Step 1 declares the trait surface, Step 2 implements it,
Step 3 consumes the impl, Step 4 wires the notice membership, and
Steps 5/6 verify the rollout against the committed corpus. There is
no end-to-end runtime path to thicken; each step builds one
capability fully before the next can build on top. This is a
horizontal decomposition, not a walking skeleton (the parent
DESIGN's Decision 3 and the FC07 sub-DESIGN's Decision 6 took the
same posture).

## Notes for Phase 3

- The DESIGN's Implementation Approach gives one outline per step;
  the natural decomposition is 1:1 (six outlines).
- Steps 5 and 6 are both corpus-scope verification scans and could
  fold into a single outline, but they answer two distinct
  questions (R17 cleanliness vs R20 no-day-one-breakage) and
  produce two PR-body bullets. They stay as two outlines.
- Step 1 is split-acceptable per the DESIGN's last sentence in the
  "Dependency between steps" subsection ("splitting at the
  trait/impl boundary (Step 1 alone) is acceptable if the
  maintainer prefers a smaller diff"). In single-pr mode this
  doesn't change the outline shape; it just means the implementer
  can land Step 1 first if useful, then the rest, all within the
  same PR.
