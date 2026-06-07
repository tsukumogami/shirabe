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
that consumes both). Outline 1 (FormatSpec extension) and Outline 2 (outline
parser) are independent prerequisites of Outline 3 (`check_fc14` dispatch +
tests). Outline 3 wires them together and registers FC14 in `is_notice`.

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

### Outline 1: Extend FormatSpec with execution_mode-aware required sections

**Goal:** Extend `FormatSpec` in `crates/shirabe-validate/src/formats.rs` so the
Plan profile's required-sections shape branches on the frontmatter
`execution_mode` value (`single-pr` vs `multi-pr`). Other profiles (Roadmap,
Brief, PRD, Design, Vision, Strategy, Comp) continue to use the existing flat
`required_sections` field unchanged. FC04's call site consults the new
per-mode shape for Plan profile docs and falls back to the existing flat shape
for everything else.

**Acceptance Criteria:**
- [ ] `FormatSpec` carries a new field (exact shape an implementation choice;
      `Option<HashMap<String, Vec<String>>>` or `Option<Vec<(String, Vec<String>)>>`
      both acceptable) that the Plan profile populates with per-mode
      required-sections lists.
- [ ] The Plan profile's `single-pr` required-sections list is
      `["Status", "Scope Summary", "Decomposition Strategy", "Issue Outlines",
      "Implementation Sequence"]`.
- [ ] The Plan profile's `multi-pr` required-sections list is the existing
      `["Status", "Scope Summary", "Decomposition Strategy",
      "Implementation Issues", "Dependency Graph", "Implementation Sequence"]`.
- [ ] FC04 consults the per-mode shape for Plan profile docs and the existing
      flat `required_sections` for non-Plan profiles.
- [ ] All non-Plan profiles' existing `required_sections` field is unchanged.
- [ ] `cargo test -p shirabe-validate` passes including a new test asserting
      Plan profile branches on `execution_mode` and a regression test asserting
      every other profile's required-sections list is unchanged.

**Dependencies:** None

### Outline 2: Add outline parser for `## Issue Outlines` section

**Goal:** Add a new outline parser to `crates/shirabe-validate/src/` (file
location an implementation choice: extending `table.rs` or adding a sibling
`outlines.rs`) that locates the `## Issue Outlines` section in a `plan/v1`
doc and parses it into a `Vec<OutlineBlock>`. Each `OutlineBlock` carries
`key` (outline heading text), `goal` (`Option<String>`),
`acceptance_criteria` (`Option<Vec<String>>`), `dependencies` (`Vec<String>`
of outline keys or the literal `"None"`), and `line` (1-indexed line of the
outline heading). The parser is total over arbitrary input — never panics on
malformed headers, missing fields, or unterminated blocks; each defect
surfaces in the returned `OutlineBlock` as a missing or empty field that the
downstream check (`check_fc14` in Outline 3) reports.

**Acceptance Criteria:**
- [ ] A new function with the signature
      `parse_issue_outlines(doc: &Doc) -> Vec<OutlineBlock>` is exposed from
      the validator crate.
- [ ] `OutlineBlock` carries `key`, `goal`, `acceptance_criteria`,
      `dependencies`, and `line` fields with the shapes named in the Goal.
- [ ] Well-formed outline blocks parse correctly: each block's `key` is the
      heading text, `goal` is the `Goal:` paragraph (when present),
      `acceptance_criteria` is the bullet list inside the `Acceptance
      Criteria:` block (when present), and `dependencies` is the list of
      outline keys named in the `Dependencies:` declaration (or `["None"]`
      when the declaration is literal `None`).
- [ ] An outline block missing its goal returns `OutlineBlock` with
      `goal: None`; no panic.
- [ ] An outline block missing its acceptance-criteria block returns
      `OutlineBlock` with `acceptance_criteria: None`; no panic.
- [ ] An outline block with a malformed dependencies declaration returns
      `OutlineBlock` with `dependencies: Vec::new()` (or whatever defect-
      indicating shape the implementer chooses); no panic.
- [ ] A doc with no `## Issue Outlines` section returns `Vec::new()`; no
      panic.
- [ ] An unterminated outline block (eof inside the block) does not panic;
      the parser returns the partial OutlineBlock with whatever fields it
      successfully extracted before eof.
- [ ] `cargo test -p shirabe-validate` passes including parser unit tests
      covering each of the cases above.

**Dependencies:** None

### Outline 3: Add check_fc14 with sub-checks A-E, register in is_notice, dispatch in Plan arm

**Goal:** Author `check_fc14` in `crates/shirabe-validate/src/checks.rs` that
consumes the frontmatter `execution_mode` value, the `FormatSpec` per-mode
required-sections shape from Outline 1, and the `OutlineBlock` sequence from
Outline 2 to emit per-defect notices across five sub-checks (A:
execution-mode-aware required sections; B: Issue Outlines structural check;
C: outline-to-outline dependency resolution; D: `issue_count` consistency;
E: mutual exclusion of populated execution-mode-specific sections). Dispatch
`check_fc14` in the Plan arm of `validate_file` alongside FC05-FC13. Register
`FC14` in the `is_notice` match arm in `crates/shirabe-validate/src/validate.rs`.
The Roadmap arm of `validate_file` is unchanged. Add table-driven tests in
`checks.rs::tests` covering every Sub-check A-E AC scenario from the PRD plus
the implementation-level ACs (exit-0 contract; FC04 non-duplication on multi-pr;
populated Dependency Graph under single-pr; absent `execution_mode` handled
by pre-existing FC02/FC01).

**Acceptance Criteria:**
- [ ] `check_fc14(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError>`
      exists in `checks.rs`.
- [ ] `check_fc14` is dispatched in the Plan arm of `validate_file`, after
      FC09 and before any post-FC09 plan checks. The Roadmap arm of
      `validate_file` is unchanged by inspection.
- [ ] `FC14` appears in the `is_notice` match arm in
      `crates/shirabe-validate/src/validate.rs`.
- [ ] Sub-check A: a single-pr plan missing `## Issue Outlines` produces an
      FC14 notice naming the section; a multi-pr plan missing
      `## Implementation Issues` produces the pre-existing FC04 notice, NOT
      a duplicate FC14 notice.
- [ ] Sub-check B: an outline block missing its `Goal:` declaration
      produces an FC14 notice naming the outline key and the missing field;
      similarly for missing `Acceptance Criteria:` and malformed
      `Dependencies:`.
- [ ] Sub-check C: an outline whose `Dependencies:` line names a sibling
      outline in the same section produces no FC14 notice; an outline whose
      `Dependencies:` line is `None` produces no FC14 notice; an outline
      whose `Dependencies:` line names an unresolved sibling produces an
      FC14 notice naming the unresolved token verbatim and the offending
      outline key.
- [ ] Sub-check D: a single-pr plan whose `issue_count` matches the outline
      count produces no FC14 notice; a mismatch produces an FC14 notice
      naming declared vs observed; the same holds for multi-pr against the
      Implementation Issues entity-row count.
- [ ] Sub-check E: a single-pr plan with populated `## Implementation
      Issues` (or populated `## Dependency Graph`) produces an FC14 notice
      naming both halves of the inconsistency; a multi-pr plan with
      populated `## Issue Outlines` produces an FC14 notice symmetrically.
- [ ] FC14 reconciliation messages name the specific defect verbatim
      (outline key for outline defects, missing field name for missing-field
      defects, unresolved token for unresolved-dep defects, declared/observed
      counts for issue_count, declared mode + wrong-section for Sub-check E).
- [ ] `shirabe validate` exits 0 on a doc that produces only FC14 notices
      and no errors.
- [ ] Multi-pr plans existing in the repo corpus (`docs/plans/PLAN-*.md`
      with `execution_mode: multi-pr`) see no behavioural change: the same
      checks fire on the same defects with the same wording.
- [ ] Table-driven tests in `checks.rs::tests` cover every AC scenario
      above plus the parser-totality cases from Outline 2.
- [ ] `cargo build -p shirabe -p shirabe-validate --release` and
      `cargo test -p shirabe-validate` both pass.

**Dependencies:** Outline 1, Outline 2

## Implementation Issues

_Empty under `execution_mode: single-pr`; the authoritative content lives in
`## Issue Outlines` above. This stub satisfies the current validator's FC04
required-sections check; once FC14 (this PLAN's own work) lands, single-pr
plans no longer need to carry this section at all._

## Dependency Graph

_Empty under `execution_mode: single-pr`; the outline-to-outline dependency
expression is declared inline in each outline's `Dependencies:` line above
(`Outline 1`, `Outline 2`, `Outline 3` -- see Outline 3's deps for the
`Outline 1, Outline 2` declaration). This stub satisfies the current
validator's FC04 required-sections check; once FC14 lands, single-pr plans
no longer need to carry this section at all._

## Implementation Sequence

**Critical path:** Outline 1 || Outline 2 -> Outline 3. Outlines 1 and 2 are
independent prerequisites of Outline 3 and can be implemented in parallel or
in either order; Outline 3 wires them together and adds the check itself plus
the tests covering the full Sub-check A-E AC set.

**Implementation order under `/work-on`'s outline-by-outline traversal:**
1. Outline 1 (FormatSpec extension; mechanical refactor with regression
   coverage).
2. Outline 2 (outline parser; new file or extended `table.rs`; total over
   arbitrary input).
3. Outline 3 (check_fc14 + is_notice registration + tests; consumes both).

The implementation sits inside one PR; `/work-on` drives the outline-by-
outline progression, the cascade fires the terminal Active → Done → DELETED
transition on the work-completing commit, and the PLAN doc is deleted
atomically in the same commit per the unified PLAN lifecycle.
