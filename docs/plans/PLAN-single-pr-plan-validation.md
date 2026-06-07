---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/prds/PRD-single-pr-plan-validation.md
milestone: "single-pr-plan-validation"
issue_count: 3
---

# PLAN: single-pr-plan-validation

## Status

Active

## Scope Summary

Add `check_fc14` to the shirabe validator alongside an `execution_mode`-aware
`FormatSpec` extension and a new outline parser, closing the structural-validation
parity gap between single-pr and multi-pr plans. Ships at notice severity matching
the FC07-FC13 staged-rollout pattern. Single PR; three outline blocks driving the
implementation sequence.

## Decomposition Strategy

**Horizontal, single-pr.** The work decomposes into three layers with clear
interfaces between them (FormatSpec contract -> outline parser -> check_fc14
that consumes both). Issue 1 (FormatSpec extension) and Issue 2 (outline
parser) are independent prerequisites of Issue 3 (`check_fc14` dispatch +
tests). Issue 3 wires them together and registers FC14 in `is_notice`.

Single-pr execution mode anchored on /plan's default ("Reach for one PR")
under the usable-value principle: the work delivers observable value as a
single increment, no multi-pr escape conditions apply (no cross-repo landing
order, no workflow-must-reach-main gate, no genuine independent value from
splitting). Matches the FC09 precedent (PR #167) for a single-check + light-
refactor validator follow-up.

The three outlines collapse to one PR; /work-on's outline-by-outline traversal
sequences the implementation deterministically, FC14 lands at notice severity
in one merge.

## Issue Outlines

### Issue 1: feat(validate): extend FormatSpec with execution_mode-aware required sections

**Goal**: Extend `FormatSpec` in `crates/shirabe-validate/src/formats.rs` so the Plan profile's required-sections shape branches on the frontmatter `execution_mode` value while every other profile keeps the existing flat `required_sections` field unchanged.

**Acceptance Criteria**:
- [ ] `FormatSpec` carries a new field that the Plan profile populates with per-mode required-sections lists (`Option<HashMap<String, Vec<String>>>` or `Option<Vec<(String, Vec<String>)>>` both acceptable).
- [ ] Plan profile single-pr required sections are `["Status", "Scope Summary", "Decomposition Strategy", "Issue Outlines", "Implementation Sequence"]`.
- [ ] Plan profile multi-pr required sections are the existing list (`Status`, `Scope Summary`, `Decomposition Strategy`, `Implementation Issues`, `Dependency Graph`, `Implementation Sequence`).
- [ ] FC04 consults the per-mode shape for Plan profile docs and the existing flat `required_sections` for non-Plan profiles.
- [ ] Non-Plan profiles' existing `required_sections` field is unchanged.
- [ ] `cargo test -p shirabe-validate` passes including a new test asserting Plan profile branches on `execution_mode` and regression coverage that every other profile's required-sections list is unchanged.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe-validate/src/formats.rs`

### Issue 2: feat(validate): add parse_issue_outlines helper

**Goal**: Add a new outline parser exposing `parse_issue_outlines(doc: &Doc) -> Vec<OutlineBlock>` that locates the `## Issue Outlines` section in a `plan/v1` doc and parses it into outline blocks total over arbitrary input (no panics on malformed headers, missing fields, or unterminated blocks).

**Acceptance Criteria**:
- [ ] `parse_issue_outlines(doc: &Doc) -> Vec<OutlineBlock>` is exposed from the validator crate.
- [ ] `OutlineBlock` carries `key`, `goal` (`Option<String>`), `acceptance_criteria` (`Option<Vec<String>>`), `dependencies` (`Vec<String>`), and `line` (1-indexed) fields.
- [ ] Well-formed outline blocks parse correctly: `key` is the heading text, `goal` is the `**Goal**:` paragraph when present, `acceptance_criteria` is the bullet list inside the `**Acceptance Criteria**:` block when present, and `dependencies` is the outline keys named in `**Dependencies**:` (or `["None"]` when literal `None`).
- [ ] An outline block missing its goal returns `OutlineBlock` with `goal: None`; no panic.
- [ ] An outline block missing its acceptance-criteria block returns `OutlineBlock` with `acceptance_criteria: None`; no panic.
- [ ] An outline block with a malformed dependencies declaration returns `OutlineBlock` with a defect-indicating shape (empty `Vec`); no panic.
- [ ] A doc with no `## Issue Outlines` section returns `Vec::new()`; no panic.
- [ ] An unterminated outline block (eof mid-block) does not panic; the parser returns the partial OutlineBlock with whatever fields it successfully extracted.
- [ ] `cargo test -p shirabe-validate` passes including parser unit tests covering each totality case above.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe-validate/src/table.rs`

### Issue 3: feat(validate): add check_fc14 with sub-checks A-E, register in is_notice

**Goal**: Author `check_fc14` consuming the FormatSpec extension from <<ISSUE:1>> and the outline parser from <<ISSUE:2>>; dispatch in the Plan arm of `validate_file`; register `FC14` in the `is_notice` match arm. The Roadmap arm is unchanged. Add table-driven tests covering every Sub-check A-E AC plus implementation-level ACs.

**Acceptance Criteria**:
- [ ] `check_fc14(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError>` exists in `checks.rs` and is dispatched in the Plan arm of `validate_file` after FC09.
- [ ] The Roadmap arm of `validate_file` is unchanged by inspection.
- [ ] `FC14` appears in the `is_notice` match arm in `crates/shirabe-validate/src/validate.rs`.
- [ ] Sub-check A: a single-pr plan missing `## Issue Outlines` produces an FC14 notice naming the section; a multi-pr plan missing `## Implementation Issues` produces the pre-existing FC04 notice (not a duplicate FC14 notice).
- [ ] Sub-check B: outline blocks missing `**Goal**`, `**Acceptance Criteria**`, or with malformed `**Dependencies**` produce per-defect FC14 notices naming the outline key and the missing/malformed field.
- [ ] Sub-check C: outlines whose dependencies resolve to a sibling outline (or literal `None`) produce no FC14 notice; outlines whose dependencies name an unresolved sibling produce an FC14 notice naming the unresolved token verbatim and the offending outline key.
- [ ] Sub-check D: `issue_count` matching the outline-count (single-pr) or entity-row count (multi-pr) produces no FC14 notice; mismatch produces an FC14 notice naming declared vs observed.
- [ ] Sub-check E: a single-pr plan with populated Implementation Issues or Dependency Graph produces an FC14 notice naming both halves of the inconsistency; symmetric for multi-pr with populated Issue Outlines.
- [ ] FC14 notice messages name the specific defect verbatim (outline key, missing field, unresolved token, declared/observed counts, declared mode + wrong section).
- [ ] `shirabe validate` exits 0 on a doc producing only FC14 notices.
- [ ] Existing multi-pr plans in the repo see no behavioural change.
- [ ] Table-driven tests cover every AC scenario above.
- [ ] `cargo build -p shirabe -p shirabe-validate --release` and `cargo test -p shirabe-validate` both pass.

**Dependencies**: Blocked by <<ISSUE:1>>, Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/validate.rs`

## Implementation Sequence

**Critical path:** Issue 1 || Issue 2 -> Issue 3. Outlines 1 and 2 are
independent prerequisites of Issue 3 and can be implemented in parallel or
in either order; Issue 3 wires them together and adds the check itself plus
the tests covering the full Sub-check A-E AC set.

**Implementation order under `/work-on`'s outline-by-outline traversal:**
1. Issue 1 (FormatSpec extension; mechanical refactor with regression
   coverage).
2. Issue 2 (outline parser; new file or extended `table.rs`; total over
   arbitrary input).
3. Issue 3 (check_fc14 + is_notice registration + tests; consumes both).

The implementation sits inside one PR; `/work-on` drives the outline-by-
outline progression, the cascade fires the terminal Active → Done → DELETED
transition on the work-completing commit, and the PLAN doc is deleted
atomically in the same commit per the unified PLAN lifecycle.
