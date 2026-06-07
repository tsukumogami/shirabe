---
schema: prd/v1
status: Draft
problem: |
  shirabe coordinators authoring single-pr plans get no structural validation.
  The Plan profile's required-sections list and every content check is shaped
  for multi-pr; single-pr plans can omit Issue Outlines, populate the wrong
  section, mismatch issue_count, and still pass every check while well-formed
  single-pr plans get zero structural enforcement.
goals: |
  Bring single-pr plans up to parity with multi-pr plans on structural
  validation. A coordinator authoring a single-pr plan gets the same level of
  notice-level feedback at validate time -- in IDE or in CI -- that a multi-pr
  coordinator gets today, with the validator catching missing required
  sections, malformed outline blocks, unresolved outline-to-outline deps,
  issue_count mismatches, and content in the wrong execution-mode section.
upstream: docs/briefs/BRIEF-single-pr-plan-validation.md
source_issue: 154
---

# PRD: single-pr-plan-validation

## Status

Draft

## Problem Statement

shirabe coordinators today author plans in two execution modes:

- **multi-pr**: the milestone decomposes into a populated
  `## Implementation Issues` table with one row per GitHub issue plus a
  `## Dependency Graph` that mirrors the same shape. Each row carries a
  cross-issue dependency expression, a complexity classification, and (on
  closed rows) the strikethrough marker that signals terminality.
- **single-pr**: the milestone is authored as a sequence of outline blocks
  under `## Issue Outlines`, each block declaring a goal, an
  acceptance-criteria block, and an outline-to-outline dependencies
  declaration. The Implementation Issues table is absent or empty; the
  Dependency Graph is absent or empty.

`shirabe validate` does not see this distinction. The Plan profile in
`crates/shirabe-validate/src/formats.rs` declares one flat `required_sections`
list (`Status`, `Scope Summary`, `Decomposition Strategy`,
`Implementation Issues`, `Dependency Graph`, `Implementation Sequence`)
regardless of `execution_mode`. There is no `execution_mode`-aware dispatch
anywhere in the validator. Every existing content check (FC04
required-sections, FC05/FC06/FC07/FC08/FC09 over the issues table) is shaped
for multi-pr; on single-pr plans those checks are either false-errors (FC04
demanding sections single-pr plans do not carry) or no-ops (FC05 onwards
reading an empty table).

The consequence is a real quality gap. A single-pr plan can declare
`execution_mode: single-pr`, omit `## Issue Outlines` entirely, populate
`## Implementation Issues` with a multi-pr-shaped table, mismatch
`issue_count` against the actual outline count, and still pass every check. A
well-formed single-pr plan with structured outlines, outline-to-outline
dependencies, and an accurate `issue_count` gets zero structural enforcement
either way. The discipline that produces well-formed single-pr plans today is
entirely on author convention.

The format reference at `skills/plan/references/quality/plan-doc-structure.md`
already describes the single-pr / multi-pr distinction (Issue Outlines
populated in single-pr, Implementation Issues populated in multi-pr) and gives
a per-outline structural contract (goal, acceptance criteria, dependencies).
The validator does not enforce any of it. That is the gap this PRD closes.

The recent landing of FC09 (PR #167, doc-vs-github-state reconciliation) and
the chain-aware passing-state lifecycle work (PR #173, PR #176) elevated
single-pr plans to first-class lifecycle citizens -- they now pass through
the unified Draft -> Active -> Done -> DELETED state graph, and the
work-on cascade fires their terminal transition deterministically.
Structural validation parity is the last open asymmetry between the two
execution modes.

## Goals

1. **Validator parity.** A single-pr plan gets the same level of structural
   notice-level feedback a multi-pr plan gets today, surfaced at the same
   places (`shirabe validate` in the IDE, the CI Validate Docs job).
2. **No vacuous-pass.** A single-pr plan that violates its own structural
   contract (missing Issue Outlines, malformed outline block, unresolved
   outline-to-outline dep, `issue_count` mismatch, wrong-section content)
   produces a notice naming the specific defect.
3. **No regression on multi-pr.** Multi-pr plans see no behavioural change;
   the same notices fire on the same defects with the same wording.
4. **One-line promotion seam.** The new check ships at notice severity and
   carries a one-line path to error severity, matching FC07/FC08/FC09's
   staged-rollout pattern.

## User Stories

- **As a coordinator authoring a single-pr PLAN**, I want `shirabe validate`
  to flag missing outline blocks, malformed outlines, unresolved
  outline-to-outline deps, and `issue_count` mismatches, so that I find and
  fix structural defects at draft time, before the PR opens for review.

- **As a reviewer scanning an open single-pr PLAN PR in CI**, I want
  `[FC14]` notices to surface in the Validate Docs job annotations alongside
  the existing FC07-FC13 notice family, formatted identically, naming the
  specific defect verbatim, so that I can comment on the structural break
  with a one-line pointer.

- **As a coordinator running `/work-on` on a single-pr PLAN**, I want
  upstream FC14 enforcement to mean the cascade does not encounter
  malformed outlines at runtime, so that my outline-by-outline traversal is
  deterministic and any structural failure traces back to the PR gate that
  should have caught it.

- **As a coordinator who mixed execution-mode content** (declared
  `execution_mode: single-pr` but populated `## Implementation Issues`
  instead of `## Issue Outlines`), I want FC14 to fire a notice on the
  populated-wrong-section condition naming both halves of the
  inconsistency, so that I can pick a side (switch the frontmatter mode or
  move the content) and re-run with confidence.

- **As a maintainer of the validator's check family**, I want FC14 to be
  registered in `is_notice` membership and to expose a one-line promotion
  path to error severity, so that after the corpus stabilizes I can promote
  FC14 the same way I promote FC07/FC08/FC09.

## Requirements

### Functional

- **R1: Execution-mode-aware required sections.** The validator's Plan
  profile MUST branch its required-sections check on the frontmatter
  `execution_mode` value:
  - When `execution_mode: single-pr`, the required sections are `Status`,
    `Scope Summary`, `Decomposition Strategy`, `Issue Outlines`,
    `Implementation Sequence`. `Implementation Issues` and
    `Dependency Graph` are optional; if present, they MUST be empty (no
    table rows for Implementation Issues, no diagram nodes for Dependency
    Graph).
  - When `execution_mode: multi-pr`, the required sections are the existing
    set (`Status`, `Scope Summary`, `Decomposition Strategy`,
    `Implementation Issues`, `Dependency Graph`, `Implementation Sequence`).
    `Issue Outlines` is optional; if present, it MUST be empty.
  - Other profiles (Roadmap, Brief, PRD, Design, Vision, Strategy, Comp)
    MUST see no behavioural change in their required-sections check.

- **R2: Issue Outlines structural check.** When `execution_mode: single-pr`,
  the validator MUST parse the `## Issue Outlines` section into a sequence
  of outline blocks and emit a notice for each defect:
  - Outline block missing a goal declaration.
  - Outline block missing an acceptance-criteria block.
  - Outline block with a malformed dependencies declaration (per the format
    reference at `skills/plan/references/quality/plan-doc-structure.md`).

- **R3: Outline-to-outline dependency resolution.** For each outline's
  dependencies list, every dependency token MUST either name another
  outline in the same `## Issue Outlines` section (by its outline key, as
  defined by the format reference) OR be the literal `None`. The validator
  MUST emit a notice when an outline names a dependency that resolves to
  no known sibling outline.

- **R4: issue_count consistency.** The frontmatter `issue_count` value
  MUST match the count of structural work units in the body:
  - For `execution_mode: single-pr`: the count of outline blocks in the
    `## Issue Outlines` section.
  - For `execution_mode: multi-pr`: the count of entity rows in the
    `## Implementation Issues` table.
  The validator MUST emit a notice on mismatch, naming the declared count
  and the observed count.

- **R5: Mutual exclusion of populated execution-mode-specific sections.**
  The validator MUST emit a notice when:
  - `execution_mode: single-pr` and `## Implementation Issues` contains a
    populated table (any non-comment, non-empty entity rows after the
    header/separator).
  - `execution_mode: multi-pr` and `## Issue Outlines` contains a populated
    outline block.
  The notice MUST name both halves of the inconsistency (the declared
  execution mode and the populated wrong section) so the author can pick
  which side to change.

- **R6: New check code.** The new check MUST be registered under code
  `FC14` (not `FC10` -- `FC10` is already taken by the writing-style
  banned-word check; FC10-FC13 are all claimed). The issue title's "fc10"
  working name is left as-is; the implementation code is `FC14`.

- **R7: Notice-severity ship.** All notices emitted by `check_fc14` MUST be
  classified as notices (not errors) via membership in the `is_notice` set
  in `crates/shirabe-validate/src/validate.rs`. The validator MUST exit
  with code 0 on a doc that produces only FC14 notices.

- **R8: One-line promotion seam.** Promotion from notice to error MUST be
  achievable by removing FC14 from the `is_notice` match arm, mirroring
  FC07/FC08/FC09's promotion pattern. No other change MUST be required to
  promote.

- **R9: Reconciliation messages name the specific defect.** Each FC14
  notice's message MUST include enough information to make the fix
  mechanical:
  - The outline key (the heading text of the offending outline block) for
    outline-block defects.
  - The missing field name (`goal`, `acceptance criteria`, `dependencies`)
    for missing-field defects.
  - The unresolved dependency token verbatim for unresolved-dep defects.
  - The declared count and observed count for `issue_count` mismatches.
  - The declared execution mode and the populated wrong-section name for
    Sub-check E.

- **R10: Roadmap arm unchanged.** The Roadmap arm of `validate_file` MUST
  see no change. Roadmaps have no single-pr / multi-pr distinction at the
  plan-format level; FC14 applies only to the Plan arm.

- **R11: Format-spec refactor extends the FormatSpec contract for
  Plan profile only.** The `FormatSpec` struct in
  `crates/shirabe-validate/src/formats.rs` MUST be extended with an
  `execution_mode`-aware required-sections shape that the Plan profile
  populates. Other profiles MUST use the existing flat `required_sections`
  field as the fallback. The exact field shape (a map, a vec of tuples, an
  optional sibling struct) is a downstream implementation choice; the
  contract is "Plan profile branches by execution_mode; other profiles
  unchanged."

- **R12: Outline parser is total over arbitrary input.** The new outline
  parser MUST be total -- it MUST NOT panic on malformed headers, missing
  fields, or unterminated blocks. Each defect surfaces as a per-defect
  notice rather than as a parser failure.

### Non-Functional

- **R13: Test coverage.** The implementation MUST include table-driven
  tests covering, separately for single-pr and multi-pr:
  - Well-formed plan (no FC14 notice).
  - Missing required section (FC14 fires for the correct mode).
  - Populated wrong section per Sub-check E (FC14 fires).
  - Outline block missing goal (FC14 fires).
  - Outline block missing acceptance-criteria block (FC14 fires).
  - Outline block with unresolved dep (FC14 fires).
  - `issue_count` mismatch (FC14 fires).
  - Malformed outline block (parser does not panic; per-defect notices fire
    if applicable).

- **R14: Build and test gates.** The PR adding FC14 MUST pass
  `cargo build -p shirabe -p shirabe-validate --release` and
  `cargo test -p shirabe-validate` on the project's CI matrix.

- **R15: No corpus migration in this PR.** This PRD does NOT mandate
  migrating existing malformed single-pr plans. Notice severity ensures CI
  stays green on the existing corpus; corpus migration is a separate
  follow-up.

## Acceptance Criteria

### Sub-check A: execution-mode-aware required sections

- [ ] A single-pr plan missing `## Issue Outlines` produces an FC14 notice
      naming the section.
- [ ] A multi-pr plan missing `## Implementation Issues` produces the
      existing FC04 behaviour unchanged (FC14 does not duplicate the
      notice).
- [ ] A single-pr plan with a populated `## Implementation Issues` table
      (rather than the empty placeholder) produces an FC14 notice per
      Sub-check E.
- [ ] A multi-pr plan with a populated `## Issue Outlines` section
      produces an FC14 notice per Sub-check E.
- [ ] Roadmap, Brief, PRD, Design, Vision, Strategy, Comp profiles see no
      behavioural change in their required-sections check.

### Sub-check B: Issue Outlines structural check

- [ ] An outline block declared in `## Issue Outlines` without a `Goal:`
      declaration produces an FC14 notice naming the outline key and the
      missing field.
- [ ] An outline block without an `Acceptance Criteria:` block produces an
      FC14 notice naming the outline key and the missing field.
- [ ] An outline block with a malformed `Dependencies:` declaration
      produces an FC14 notice naming the outline key and the malformed
      shape.
- [ ] A well-formed outline block (goal + AC block + valid dependencies)
      produces no FC14 notice.

### Sub-check C: outline-to-outline dependency resolution

- [ ] An outline whose `Dependencies:` line names a sibling outline that
      exists in the same `## Issue Outlines` section produces no FC14
      notice for that dep.
- [ ] An outline whose `Dependencies:` line is the literal `None` produces
      no FC14 notice.
- [ ] An outline whose `Dependencies:` line names an unresolved sibling
      (no outline with that key exists in the section) produces an FC14
      notice naming the unresolved token verbatim and the offending outline
      key.

### Sub-check D: issue_count consistency

- [ ] A single-pr plan whose frontmatter `issue_count` matches the count
      of outline blocks in `## Issue Outlines` produces no FC14 notice for
      the count check.
- [ ] A single-pr plan whose frontmatter `issue_count` does not match the
      outline count produces an FC14 notice naming declared vs observed.
- [ ] A multi-pr plan whose frontmatter `issue_count` matches the count
      of entity rows in `## Implementation Issues` produces no FC14 notice.
- [ ] A multi-pr plan whose frontmatter `issue_count` does not match the
      entity-row count produces an FC14 notice naming declared vs observed.

### Sub-check E: mutual exclusion of populated sections

- [ ] A single-pr plan with `## Implementation Issues` populated (non-empty
      table after header + separator) produces an FC14 notice naming the
      declared mode and the populated wrong section.
- [ ] A multi-pr plan with `## Issue Outlines` populated (non-empty
      outline block) produces an FC14 notice naming the declared mode and
      the populated wrong section.

### Implementation-level acceptance

- [ ] `check_fc14` lives in `crates/shirabe-validate/src/checks.rs` and is
      dispatched in the Plan arm of `validate_file` alongside FC05-FC13.
- [ ] `FC14` is registered in the `is_notice` set in
      `crates/shirabe-validate/src/validate.rs`.
- [ ] The outline parser is total over the arbitrary-input cases tested in
      R13 (malformed headers, missing fields, unterminated blocks) -- the
      parser returns a per-defect notice or an empty result rather than
      panicking on any of those inputs.
- [ ] Table-driven tests cover every per-sub-check scenario in the
      acceptance-criteria list above.
- [ ] `cargo build -p shirabe -p shirabe-validate --release` and
      `cargo test -p shirabe-validate` both pass.
- [ ] The Roadmap arm of `validate_file` is unchanged by inspection.
- [ ] A multi-pr plan missing a multi-pr-required section produces the
      pre-existing FC04 notice, NOT an additional FC14 notice (FC04 and
      FC14 do not double-report the same multi-pr defect).
- [ ] `shirabe validate` exits with code 0 on a doc that produces only
      FC14 notices and no errors (notice-severity exit-code contract).
- [ ] A single-pr plan with a populated `## Dependency Graph` (non-empty
      mermaid diagram) produces an FC14 notice per Sub-check E, mirroring
      the populated-`## Implementation Issues` case.
- [ ] A plan whose frontmatter `execution_mode` is absent or carries any
      value other than `single-pr` or `multi-pr` is rejected at the
      pre-existing FC02 / FC01 frontmatter-validation stage; FC14 itself
      does not need to defend against this case.

## Out of Scope

- **Promotion of FC14 to error severity.** This PRD ships FC14 at notice
  severity. Promotion to error is a one-line change (remove FC14 from
  `is_notice`) shipped separately after the corpus stabilizes.
- **Roadmap arm changes.** Roadmaps have no single-pr / multi-pr
  distinction at the plan-format level. FC14 applies only to the Plan arm.
- **Corpus migration to fix existing malformed single-pr plans.** Notice
  severity preserves CI on the existing corpus; any necessary corpus edits
  land in their own follow-up PRs.
- **`/plan` skill changes.** The skill's existing authoring flow is
  unchanged. FC14 adds validator behaviour, not skill behaviour.
- **CI workflow changes.** FC14 runs inside the existing Validate Docs job
  via the existing `shirabe validate` invocation. No new workflow file, no
  new job entry.
- **Single-pr PLAN format-spec authoring.** The format spec already lives
  at `skills/plan/references/quality/plan-doc-structure.md`; FC14 enforces
  that spec, it does not author or revise it.
- **Renaming or reorganizing existing FC checks.** FC10's writing-style
  binding is not changed by this work, even though "fc10" appears in the
  upstream issue title as a working name. FC14 is the implementation code.

## Decisions and Trade-offs

### Decision D1: New check code is FC14, not FC10

The upstream issue (#154) and the parent PLAN row both refer to this work
as "fc10" in their titles. Phase 2 research revealed that `FC10` is already
taken by the writing-style banned-word check in
`crates/shirabe-validate/src/checks.rs` (lines 2090-2155), and FC10, FC11,
FC12, FC13 are all claimed. The next free code is FC14.

**Decision:** the implementation uses code `FC14`. The issue title's
"fc10" label is left as-is (it is a working name only; renaming a public
GitHub issue would break inbound links).

**Alternative considered:** rename writing-style FC10 to a different code
to free FC10 for this check. **Rejected** because it would force a
churning rename of every reference to writing-style FC10 across the docs,
codebase, and CI annotations -- much larger blast radius than naming the
new check FC14.

### Decision D2: One check fanning out into five sub-checks, not five separate checks

The five sub-checks (A-E) above all share the same execution-mode-aware
machinery: each consumes the frontmatter `execution_mode` value and the
parsed outline-block sequence. Shipping them as five separate FCnn codes
would force five `is_notice` registrations and five separate
dispatch points in `validate_file`.

**Decision:** ship all five sub-checks as one check (`check_fc14`) that
emits sub-check-specific notice codes via the same code (`[FC14]`) with
distinguishing prefix text (e.g., `[FC14] missing required section ...`,
`[FC14] outline outline-3 missing goal`, `[FC14] unresolved dependency ...`).

**Alternative considered:** split into FC14-FC18, one per sub-check.
**Rejected** because the five sub-checks share enough machinery that the
split would multiply the wiring without improving the notice ergonomics --
a reviewer scanning CI annotations sees a single `[FC14]` family with
specific defect text, mirroring how FC07's three sub-checks land under one
`check_fc07`.

### Decision D3: Outline parser file location left to implementation

The outline parser could extend the existing `crates/shirabe-validate/src/table.rs`
or live in a sibling `outlines.rs`.

**Decision:** the PRD does not pick. R11 specifies the contract
(execution_mode-aware Plan profile, others unchanged) and R12 specifies the
parser's total-over-arbitrary-input requirement. File location is a
downstream implementation decision.

### Decision D4: BRIEF amended in place rather than re-written

The BRIEF was Accepted before Phase 2 research surfaced the FC10 code
collision. Per the BRIEF format spec, Accepted briefs can be edited in
place if the framing shifts before the downstream PRD lands. The
framing did not shift -- only the specific check code changed.

**Decision:** the BRIEF was amended in place to reference FC14 throughout
(17 occurrences), and a Status-paragraph note records the correction date,
the trigger (PRD Phase 2 research), and the scope of the change (code
only; framing unchanged).

**Alternative considered:** loop back to /brief and re-run the chain from
the top. **Rejected** because the framing is solid; only the code label
changed.

## Known Limitations

- **Single-issue surface area.** FC14 closes one validator gap (single-pr
  plan structural enforcement) and ships at notice severity. Adopters who
  expect strict-mode enforcement out of the box must wait for the
  promotion follow-up. This is intentional and matches FC07/FC08/FC09's
  staged rollout.
- **No outline-key uniqueness check in this PRD.** If two outline blocks
  share the same key (e.g., two `### Outline 1:` headings), FC14's
  Sub-check C may resolve a dep to whichever appears first. The acceptance
  criteria deliberately do not specify behaviour for duplicate-key
  outlines; either fail-on-duplicate or first-wins is acceptable to the
  PRD. A future increment may add a duplicate-key sub-check; this PRD does
  not require it.
- **Grammar precision delegated to the format reference.** Several ACs
  refer to "malformed dependencies declaration" and "well-formed outline
  block" without inline grammar; the authoritative grammar lives in
  `skills/plan/references/quality/plan-doc-structure.md`. The
  implementation MUST follow that reference. If two implementers disagree
  on what counts as malformed, the format reference is the tiebreaker;
  if it is ambiguous on a specific shape, that ambiguity surfaces a
  format-reference bug, not an FC14 bug.
