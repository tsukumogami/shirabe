---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-multi-pr-plan-decoupling.md
milestone: none
issue_count: 8
---

# PLAN: Multi-PR Plan Decoupling

## Status

Active

## Scope Summary

Separate a PLAN's delivery shape from its work tracking, bind each to a
repository preference on the existing convention-header channel, and give every
plan whose shape is not the obvious one a durable record of why, checked before
the work merges.

## Decomposition Strategy

Horizontal, in four layers matching the design's batches. The layers have
well-defined interfaces between them — a frontmatter field, two header names, a
resolved enum — which is the condition that favours horizontal over a walking
skeleton. There is no end-to-end runtime path here whose integration risk would
justify building a thin vertical slice first; the risk in this change is
concentrated in one issue (the extraction rewrite) rather than spread across a
pipeline.

The layering is also what makes the first layer independently valuable. Issues 1
through 3 deliver the record and its check, which is the auditability the feature
exists for, using the two split branches that exist before any preference does.
Issues 4 through 6 add the two preferences. Issue 7 is the extraction change that
depends on the tracking preference being resolvable. Issue 8 is the amendment
that keeps the prior design's decision honest.

**Execution mode: single-pr.** Applying today's rule rather than the one this
design proposes. No hard constraint forces a split: nothing spans a second
repository, no workflow file must reach the default branch before something can
invoke it, and no step needs a merge gate before the next can start. The plan is
not being split for incremental value either, so the escape conditions do not
fire and the default holds.

That is worth stating rather than leaving implicit, because this plan is a
negative example of its own subject. It carries no record of why it is
single-pr, and under the design's own R15 it would still carry none once the
feature ships: shirabe states no delivery preference, `consolidated` is the
default, and single-pr is exactly what that preference produces. The plan passes
the check it is building.

## Issue Outlines

### Issue 1: Author the shared split-triggers reference

**Goal**:
Create `references/split-triggers.md` as the single source for the split rule,
with a shared core naming three branches (Hard Constraint, Incremental Value,
Stated Preference) and two profiles: plan, which takes all three as-is, and
coordinated, which adds Merge-Order Necessity. Repoint P1 in
`references/workflow-principles.md` and the Coarsest-Legal-Grouping Rule in
`references/coordination-strategy.md` to cite it rather than enumerate their own
lists. Retire "independently mergeable" and "independently rollback-able" as
free-standing coordination triggers, folding them into Hard Constraint's
coordinated examples, and retire the reviewability ceiling as a fourth trigger by
folding it into Stated Preference.

**Acceptance Criteria**:
- `references/split-triggers.md` exists with a shared-core section and two
  profile sections, following the structure `references/issues-table.md` uses for
  its shared core plus per-profile deltas.
- `references/workflow-principles.md` P1 cites the new reference and no longer
  enumerates its escape conditions inline.
- `references/coordination-strategy.md`'s Coarsest-Legal-Grouping Rule cites the
  new reference and retains only Merge-Order Necessity as profile-specific.
- Reviewability is named in exactly one place across both files: the Stated
  Preference branch.
- A reader of either file can reach the full trigger definitions in one hop.
- `shirabe validate` passes on both edited files.

**Dependencies**:
None. This is the head of the chain.

**Type**:
docs

**Files**:
`references/split-triggers.md`, `references/workflow-principles.md`,
`references/coordination-strategy.md`

### Issue 2: Document split_rationale and emit its branch

**Goal**:
Add the `split_rationale` frontmatter field to the PLAN format contract, required
when `execution_mode` is not `single-pr` or when the plan departs from the
repository's resolved delivery preference, holding free text that names one of
Issue 1's three branches plus the specific justification. Teach step 3.6 in
`skills/plan/references/phases/phase-3-decomposition.md` to select and emit the
branch name alongside the mode it recommends.

**Acceptance Criteria**:
- `skills/plan/references/plan-format.md` documents the field, its condition, and
  the requirement that the entry name its branch.
- Step 3.6's procedure names which branch produced its recommendation and writes
  it into the decomposition artifact.
- A plan authored under the revised step 3.6 with a forcing constraint carries a
  `split_rationale` naming Hard Constraint.
- A `single-pr` plan in a repository stating no preference carries no field and
  that is documented as correct, not an omission.
- The field is free text; no enumeration is added to any schema.

**Dependencies**:
Issue 1 — the branch vocabulary must exist before the field can require naming
one.

**Type**:
docs

**Files**:
`skills/plan/references/plan-format.md`,
`skills/plan/references/phases/phase-3-decomposition.md`

### Issue 3: Implement the L09 record check

**Goal**:
Implement `L09` in `crates/shirabe-validate/src/lifecycle.rs`, following `L06`'s
shape as a single-document draft-tolerable check, and register it in
`validate::posture_class`'s `DraftTolerable` arm. The check short-circuits: when
`execution_mode` is not `single-pr` the field is required with no filesystem
read; only a `single-pr` plan triggers the delivery-preference resolution, which
is inert until Issue 4 lands.

**Acceptance Criteria**:
- `L09` fires on a `multi-pr` PLAN with no `split_rationale`, and does not fire
  when the field is present and names a branch.
- The finding is a notice under `--mode=draft` and an error under `--mode=ready`.
- `L09` does not fire on a `single-pr` PLAN with no field, in a repository
  stating no delivery preference.
- The two doc comments in `validate.rs` that enumerate the draft-tolerable set
  name `L09`, and `posture_class_classifies_lifecycle_codes` covers it.
- No `FormatSpec` in `formats.rs` is modified, and `check_fc01`'s signature is
  unchanged.
- `cargo test` passes.

**Dependencies**:
Issue 2 — the field must be specified before a check can enforce it.

**Type**:
feat

**Files**:
`crates/shirabe-validate/src/lifecycle.rs`,
`crates/shirabe-validate/src/validate.rs`

### Issue 4: Add the delivery-preference header

**Goal**:
Add `## Delivery Preference: consolidated|atomic` to the convention-header
registry, defaulting to `consolidated`, resolved flag then header then default.
Teach step 3.6 to consult it before recommending a mode, and activate `L09`'s
departure branch so a `single-pr` plan in an `atomic` repository owes a record.

**Acceptance Criteria**:
- `references/fixes/claude-md-conventions.md` carries the header with its
  accepted values, its default, and its precedence order.
- A repository declaring `atomic` produces a multi-PR shape for a change whose
  decomposition permits one; the same change in a `consolidated` repository
  produces `single-pr`. The two runs differ only in the header.
- The invocation flag overrides a conflicting header, and the header overrides
  the default, each producing a different observable `execution_mode`.
- A repository declaring nothing produces the same `execution_mode` the
  pre-change workflow produces.
- The value-confirmation guard runs against each unit under `atomic` and reports
  a failing unit as a mis-decomposition rather than accepting it.
- `L09` fires on a `single-pr` plan in an `atomic` repository with no record.
- The header is not named `Execution Mode`.

**Dependencies**:
Issue 3 — the check must exist before its departure branch can be activated.

**Type**:
feat

**Files**:
`references/fixes/claude-md-conventions.md`, `skills/plan/SKILL.md`,
`skills/plan/references/phases/phase-3-decomposition.md`,
`crates/shirabe-validate/src/lifecycle.rs`

### Issue 5: Add the tracking-level header and gate issue creation on it

**Goal**:
Add `## Tracking Level: none|issues|issues-and-milestone` to the registry,
defaulting to `issues-and-milestone` for `multi-pr` plans and `none` for
`single-pr` plans. Write the resolved value into the PLAN as a `tracking_level`
frontmatter field, so later consumers read it from the document rather than
re-resolving it from configuration that may since have changed. Change Phase 7's
issue and milestone creation to branch on the resolved level rather than on
`execution_mode`, leaving `coordinated` plans governed by the coordination
contract.

**Acceptance Criteria**:
- The registry carries the header with accepted values, default, and precedence.
- Each of the six combinations of `{single-pr, multi-pr}` and the three levels is
  produced by stating the corresponding preferences, and each is confirmed by
  what was created: no GitHub artifacts, issues with no milestone assigned, or
  issues with a milestone assigned.
- A repository stating a delivery preference but no tracking preference gets
  `issues-and-milestone` for `multi-pr` and nothing for `single-pr`.
- The flag overrides the header and the header overrides the default, each
  producing a different observable set of artifacts.
- A `coordinated` plan's tracking is unchanged under every value.
- Every authored PLAN carries `tracking_level` in frontmatter recording what was
  resolved, and changing the repository header afterwards does not change the
  value in an already-authored plan.

**Dependencies**:
Issue 1 only, for vocabulary consistency. Independent of Issues 2 through 4 —
it touches a different phase and a different header.

**Type**:
feat

**Files**:
`references/fixes/claude-md-conventions.md`,
`skills/plan/references/phases/phase-7-creation.md`

### Issue 6: Re-key the approval gate and amend its decision record

**Goal**:
Change every statement that the Draft-to-Active gate is human-approved for
`multi-pr` into one keyed on whether the activation will create GitHub issues,
across the five prose sites that carry it. Amend
`DECISION-multi-pr-posture-detection-2026-06-06.md` to record that its predicate
changed while its decision stands.

**Acceptance Criteria**:
- No remaining statement gates activation on `execution_mode`.
- The transition tables in `plan-format.md` and `plan-doc-structure.md` cover
  `multi-pr` with `none` as automatic and `single-pr` with `issues` as
  human-approved.
- The decision record carries an amendment naming the new predicate and stating
  that the asymmetry itself is unchanged; it is not superseded.
- A grep for the old framing returns nothing outside the amendment's own
  quotation of it.

**Dependencies**:
Issue 5 — the tracking level must be resolvable before a gate can key on it.

**Type**:
docs

**Files**:
`skills/plan/SKILL.md`, `skills/plan/references/plan-format.md`,
`skills/plan/references/quality/plan-doc-structure.md`,
`skills/plan/references/phases/phase-7-creation.md`,
`docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`

### Issue 7: Emit issueless multi-pr work items from the plan's outlines

**Goal**:
Add a third source-var scheme to task extraction so a `multi-pr` plan whose
resolved tracking level is `none` produces a schedulable graph. Branch
`process_multi_pr` on the tracking level; the `none` path reuses the
`## Issue Outlines` parse and the local-id machinery the single-pr path already
runs, emitting `ISSUE_SOURCE=plan_item` with `m-<slug>` ids. Document the scheme
in the contract.

**Acceptance Criteria**:
- A `multi-pr` plan with tracking `none` yields a task graph in which every
  dependency edge resolves to a declared work item, with no unresolved keys.
- The emitted vars are `ISSUE_SOURCE=plan_item`, `ARTIFACT_PREFIX=m-<slug>`, and
  `ISSUE_TYPE` when the outline carries one.
- Ids collide-suffix and truncate identically to the single-pr `o-<slug>` path,
  exercised by a test with two outlines whose titles slugify the same.
- A `multi-pr` plan with tracking `issues` still emits `ISSUE_SOURCE=github` with
  `#N`, unchanged.
- `plan-to-tasks-contract.md` documents the third scheme alongside the existing
  two.
- `plan-to-tasks_test.sh` covers the new path and passes.

**Dependencies**:
Issue 5 — extraction reads the `tracking_level` field, which Issue 5 writes.

**Type**:
feat

**Files**:
`skills/plan/scripts/plan-to-tasks.sh`,
`skills/plan/references/plan-to-tasks-contract.md`,
`skills/plan/scripts/plan-to-tasks_test.sh`

### Issue 8: Amend Decision 6 of the roadmap-plan-standardization design

**Goal**:
Record in `DESIGN-roadmap-plan-standardization.md` that Decision 6's single-pr
default is now conditional on the repository's delivery preference. Its
de-conflation of decomposition strategy from execution mode, and its
re-anchoring of the roadmap case on value rather than mechanism, are unchanged.

**Acceptance Criteria**:
- Decision 6 carries an amendment naming what changed and what did not.
- The amendment cites this design rather than restating its reasoning.
- Nothing in the original decision text is deleted.

**Dependencies**:
Issue 4 — the preference must exist before a decision can be amended to depend
on it.

**Type**:
docs

**Files**:
`docs/designs/current/DESIGN-roadmap-plan-standardization.md`

## Dependency Graph

## Implementation Sequence

**Critical path:** Issue 1 → 2 → 3 → 4 → 8. Five issues deep, and it is the
record-and-preference spine. Issue 4 is the widest single issue on it, touching
the registry, the skill surface, a phase file, and the check's departure branch.

**Parallel opportunity:** Issue 5 depends only on Issue 1, so the tracking half
can run alongside the whole of 2 → 3 → 4. Issues 6 and 7 both hang off 5 and are
independent of each other, so once 5 lands they can proceed in parallel with the
tail of the delivery-preference chain. Under one pull request this parallelism is
about ordering work within a session rather than about concurrent branches, but
it does mean a blocked spine never idles the tracking work.

**Riskiest issue:** Issue 7. It is the only one that rewrites working shell logic
rather than adding prose or an additive check, it is the one the exploration
named as the most underpriced, and its acceptance depends on a test surface that
has to be extended rather than merely run. Sequencing it late is deliberate:
everything above it is verifiable without it, so a stall there does not strand
the rest.

**Natural stopping point:** after Issue 3. A reviewer who wants to land the
auditability half and defer the preferences has a coherent artifact at that
point — plans record why they are shaped as they are, using the two branches that
exist before any preference does.
