---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-fold-record-removal.md
milestone: "Fold-record removal"
issue_count: 5
---

# PLAN: Fold-Record Removal

## Status

Active

## Scope Summary

Remove `docs/folds.md` and every mechanism serving only it, replace the two prose
claims that cite it as evidence, correct the references that name it without
spelling its path, and amend the seven shipped documents whose requirements and
decisions it discharges.

## Decomposition Strategy

**Horizontal.** The design names five groups whose boundaries are already clear
and whose runtime interaction is nil — prose, workflow configuration, a shell
script, an eval fixture, and document amendments. There is no pipeline to
exercise end-to-end and no integration risk to surface early, so a walking
skeleton would buy nothing. Each issue takes one group to completion.

**Execution mode: single-pr.** A split fails the value test rather than merely
being avoidable. No group delivers observable value alone and several are harmful
alone: deleting the record while seven documents still assert it exists;
correcting prose to describe a state the tree is not in; amending documents to say
a change landed that has not. The design states it directly — nothing here is
independently shippable. Neither multi-pr escape condition holds: one repository,
no landing order, no merge gate.

## Issue Outlines

### Issue 1: Delete the fold record and the machinery serving only it

**Goal**: Remove `docs/folds.md` and every mechanism whose sole purpose is to
serve it, so nothing in the tree maintains a record that no longer exists.

**Acceptance Criteria**:
- [ ] `docs/folds.md` does not exist in the working tree (AC1).
- [ ] `.gitattributes` contains no `merge=union` entry and no comment block
      describing fold-record concurrency (AC4).
- [ ] `.github/workflows/validate-docs.yml` contains no step named for
      fold-record verification, and no `git show`, `grep`, or `rev-parse`
      invocation against the record path (AC5).
- [ ] `check-citations.sh --record x` exits non-zero with an unknown-option
      error, and neither search tier contains a record exclusion pathspec (AC6).
- [ ] The argument validation applied to `--target` and `--survivor` is
      unchanged — the flag removal must not disturb the security-reviewed
      validation block those values pass through.
- [ ] `bash skills/scope/scripts/check-citations_test.sh` exits 0 and contains no
      case asserting that the fold record does not refuse a later hop (AC7).
- [ ] `skills/scope/references/phases/phase-4-cleanup.md` contains no carve-out
      naming the record (AC10).

**Dependencies**: None

**Type**: code
**Files**: `docs/folds.md`, `.gitattributes`, `.github/workflows/validate-docs.yml`, `skills/scope/scripts/check-citations.sh`, `skills/scope/scripts/check-citations_test.sh`, `skills/scope/references/phases/phase-4-cleanup.md`

### Issue 2: Renumber the absorb procedure to eight steps

**Goal**: Take the absorb procedure from nine steps to eight and bring every
count, table row, cross-reference and step range that describes it into
agreement.

**Acceptance Criteria**:
- [ ] The step list in `phase-2-chain-orchestration.md` is contiguously numbered
      with the append step removed (AC8).
- [ ] The sentences stating the step count — in `phase-2-chain-orchestration.md`
      and in `skills/scope/SKILL.md`'s cross-reference — both match the list
      length (AC8).
- [ ] The rollback table has one row per writing step, with step numbers matching
      the renumbered list, and no append row or un-append cells (AC8).
- [ ] The standalone paragraph justifying the un-append is gone, and the
      partial-absorb resume paragraph's step range matches the renumbered list
      (AC8).
- [ ] The final commit step's object list no longer includes the record (AC8).
- [ ] `skills/scope/SKILL.md`'s `absorb` verdict definition still states what the
      verdict ends with rather than trailing off where the record used to be (R8).
- [ ] The closed write-target set in `skills/scope/SKILL.md` and the read-back in
      `phase-3-exit-finalization.md` enumerate deletions and mutations only, do
      not contradict each other, and the sentence stating how many groups the
      absorb adds matches the number listed (AC9).
- [ ] The `verdict:`/`stage:` enum re-validation retains its control with a
      restated justification — the values still reach the survivor's `## Status`
      absorption line — rather than losing its stated reason.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `skills/scope/references/phases/phase-2-chain-orchestration.md`, `skills/scope/SKILL.md`, `skills/scope/references/phases/phase-3-exit-finalization.md`

### Issue 3: Replace the prose claims that cite the record as evidence

**Goal**: Point `/execute`'s fully-folded rule and the roadmap downstream cell at
the same surface, with the residual stated, so the corpus carries one answer
rather than two.

**Acceptance Criteria**:
- [ ] `skills/execute/SKILL.md`'s rule for distinguishing a fully-folded chain
      from an unfinalized one does not cite the record, names the roadmap
      downstream cell as the surface a reader consults, and states in the same
      passage what a reader observes when there is no roadmap feature or the
      roadmap has been deleted (AC11).
- [ ] `skills/execute/scripts/run-cascade.sh` emits
      `**Downstream:** _none (chain folded)_`, containing no pointer to the
      record while still distinguishing a chain that folded from one that never
      ran (AC12).
- [ ] `bash skills/execute/scripts/run-cascade_test.sh` exits 0 (AC12).
- [ ] `README.md` describes the consolidation judgment without naming the record
      (AC13).
- [ ] `docs/guides/doc-validation.md` describes no fold-record check (AC14).

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `skills/execute/SKILL.md`, `skills/execute/scripts/run-cascade.sh`, `README.md`, `docs/guides/doc-validation.md`

### Issue 4: Correct the non-path references and the eval fixture

**Goal**: Fix the comments and the eval that name the record without spelling its
path, which no path-based sweep can reach.

**Acceptance Criteria**:
- [ ] `crates/shirabe-validate/src/formats.rs`,
      `.github/workflows/check-scope-scripts.yml`, and
      `skills/scope/scripts/check-citations.sh` each describe the absorbed-path
      shape's readers without naming a record checker or a fold signature, and
      the reader count stated in each matches the number that remains — two: the
      absorb procedure as the gate, and the crate's absorbed-declaration check as
      the backstop (AC22).
- [ ] `formats.rs`'s `contribution_heading` doc comment names no durable record
      column (AC22).
- [ ] `skills/scope/evals/evals.json` describes the eight-step procedure: no
      expected output or rubric criterion mentions appending a row, its ordering
      relative to the deletion, or a record committed alongside it (AC21).
- [ ] The eval scenario still asserts that the `git rm` precedes the
      re-validation, that the re-validation precedes the commit, and that the
      deletion, the splice and the survivor's edits land in one commit (AC21).
- [ ] `git diff <merge-base>..HEAD -- crates/` touches comment lines only, and
      `cargo test` passes (AC18, AC19).

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe-validate/src/formats.rs`, `.github/workflows/check-scope-scripts.yml`, `skills/scope/evals/evals.json`

### Issue 5: Amend the seven shipped documents

**Goal**: Record what no longer holds in each shipped document the removal
falsifies, without editing their bodies and without a lifecycle transition.

**Acceptance Criteria**:
- [ ] Each of these seven carries a `## Amendment — <date>` heading, with the
      separator being U+2014 EM DASH and the date on or after the day this change
      lands, and the text under it contains the string `folds.md` (AC15):
      `docs/briefs/BRIEF-scope-artifact-persistence.md`,
      `docs/prds/PRD-scope-artifact-persistence.md`,
      `docs/designs/current/DESIGN-scope-artifact-persistence.md`,
      `docs/prds/PRD-scope-consolidation-over-skipping.md`,
      `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`,
      `docs/prds/PRD-scope-chain-mandatory-steps.md`,
      `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md`.
- [ ] Each amendment carries the pinned formula "The original text above is left
      unedited; this section records what no longer holds," and each document's
      body above the amendment is unedited.
- [ ] Each document's `status:` is unchanged from the merge base (AC15).
- [ ] The amendment to `DESIGN-scope-consolidation-over-skipping.md` states that
      the record of *why* survives in the code as a standing `/work-on`
      instruction, and states what carries the record of *what happened* — the
      survivor's `absorbed:` declaration for every hop that leaves one, the
      roadmap cell conditionally and temporarily, and nothing for a PLAN the
      cascade deletes (AC16).
- [ ] That amendment does not reopen Option D, suggest re-examining the
      DESIGN-to-PLAN hop, or imply a durable-artifact floor.
- [ ] `git grep -n 'docs/folds\.md' HEAD` with the exclusion set in AC2 returns
      no output (AC2).
- [ ] `git grep -in 'fold record\|fold-record\|record checker\|fold signature'
      HEAD` with the same exclusions returns no output (AC3).
- [ ] `shirabe validate --visibility=public` over the changed set exits 0, and
      the full-corpus error count is no greater than five (AC20).

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:4>>

**Type**: docs
**Files**: `docs/briefs/BRIEF-scope-artifact-persistence.md`, `docs/prds/PRD-scope-artifact-persistence.md`, `docs/designs/current/DESIGN-scope-artifact-persistence.md`, `docs/prds/PRD-scope-consolidation-over-skipping.md`, `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`, `docs/prds/PRD-scope-chain-mandatory-steps.md`, `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md`

## Implementation Issues

## Dependency Graph

## Implementation Sequence

**Critical path:** Issue 1 → any of Issues 2/3/4 → Issue 5. Four steps deep, five
issues wide at its narrowest point.

Issue 1 leads because deleting the record is what makes every other issue's
correction true rather than anticipatory. Issue 5 trails because each amendment
describes a change that has already landed — writing them earlier would assert a
state the tree is not yet in, which is the defect this whole change corrects.

**Parallelization:** Issues 2, 3 and 4 are mutually independent and touch
disjoint files once Issue 1 has landed. Issue 4 shares
`skills/scope/scripts/check-citations.sh` with Issue 1, which owns it; the
comment correction in Issue 4 applies after Issue 1's flag removal.

**Verification runs once, at the end**, because the acceptance criteria describe a
post-change state: the two shell test suites, `cargo test`, the document validator
over the changed set, and the two inventory sweeps in AC2 and AC3.
