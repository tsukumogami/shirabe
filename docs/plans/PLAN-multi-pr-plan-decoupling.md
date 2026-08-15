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
- `references/split-triggers.md` exists with a shared-core section that names and
  defines all three branches (Hard Constraint, Incremental Value, Stated
  Preference) at the same specificity `references/issues-table.md`'s shared core
  uses, plus a plan-profile section stating it takes all three as-is and a
  coordinated-profile section stating it adds Merge-Order Necessity as a fourth.
  Matching section headings is not sufficient.
- `references/workflow-principles.md` P1 cites the new reference and no longer
  enumerates its escape conditions inline.
- `references/coordination-strategy.md`'s Coarsest-Legal-Grouping Rule cites the
  new reference and retains only Merge-Order Necessity as profile-specific.
- Reviewability is named in exactly one place across both files: the Stated
  Preference branch.
- A reader of either file can reach the full trigger definitions in one hop.
- After the edit, "independently mergeable" and "independently rollback-able"
  appear only inside Hard Constraint's coordinated examples in the new reference,
  not as free-standing bullets in `coordination-strategy.md`, and the
  reviewability ceiling appears as a trigger nowhere outside Stated Preference.
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
- `skills/plan/references/plan-format.md` documents `split_rationale` as required
  exactly when `execution_mode` is not `single-pr`, OR when `execution_mode` is
  `single-pr` and the repository's resolved delivery preference is `atomic` —
  both disjuncts stated explicitly — and documents that the entry must name one
  of the three `split-triggers.md` branches by name.
- The format contract states that a `split_rationale` present but naming none of
  the three branches fails `L09`, so the contract and the check agree on what
  naming a branch requires.
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
- `L09` does not fire on a `single-pr` PLAN with no field in a repository stating
  no delivery preference, AND `L09` does fire on a `single-pr` PLAN with no field
  in a repository whose CLAUDE.md states `## Delivery Preference: atomic`. Both
  directions are exercised in this issue's own fixtures — `resolve_claude_md_header`
  matches literal header text, so the positive case is constructible before Issue
  4 documents the header. Without it, an implementation that stubs the departure
  branch to always report `consolidated` passes.
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
- Using two CLAUDE.md files identical except for the `Delivery Preference` value
  (`atomic` versus `consolidated`) and the same decomposition input, step 3.6
  resolves a different preference in each case and the `execution_mode`
  recommendation differs solely as a function of that resolved value — verified by
  inspecting the preference step 3.6 recorded as having consulted, not only by
  comparing the two plans' final shapes. Comparing shapes alone cannot distinguish
  a real header parse from a branch on something incidentally correlated with the
  two fixtures.
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
- A repository whose CLAUDE.md states `## Tracking Level:` with a value outside
  `none|issues|issues-and-milestone` falls back to the default rather than using
  the value or erroring, matching the design's stated mitigation for untrusted
  configuration.

**Dependencies**:
None. Issue 5 touches a different header, a different phase, and a different
frontmatter field from the record spine, and nothing in its acceptance criteria
references Issue 1's branch vocabulary. It can start immediately, in parallel
with Issue 1.

**Type**:
feat

**Files**:
`references/fixes/claude-md-conventions.md`,
`skills/plan/references/phases/phase-7-creation.md`

### Issue 6: Re-key the approval gate and amend its decision record

**Goal**:
Change every statement that the Draft-to-Active gate is human-approved for
`multi-pr` into one keyed on whether the activation will create GitHub issues,
at the six live sites the design's Decision E table marks `re-key`: four in skill
and format prose, plus the Rust doc comments in `lifecycle.rs` (lines 52, 61,
764) and `transition.rs` (lines 263, 469, 1960, 2011). The Rust edits are
comment-only. Leave the four sites the table marks `leave` untouched — three
`Current` DESIGN docs and a golden fixture record what was decided when they were
written, and editing them falsifies the audit trail rather than correcting it.
Phrasing varies across sites ("human approval", "human-approval",
"human-approved", and at `phase-7-creation.md:263` "multi-pr-style approval gate"
with no "human" in it), so any verification pattern must cover all four forms.
Amend
`DECISION-multi-pr-posture-detection-2026-06-06.md` to record that its predicate
changed while its decision stands.

**Acceptance Criteria**:
- No remaining statement gates activation on `execution_mode`.
- The transition tables in `plan-format.md` and `plan-doc-structure.md` cover
  `multi-pr` with `none` as automatic and `single-pr` with `issues` as
  human-approved.
- The decision record carries an amendment naming the new predicate and stating
  that the asymmetry itself is unchanged; it is not superseded.
- `grep -rniE "multi-pr" skills/ crates/ docs/ | grep -iE "(human[ -]approv|approval gate)"`
  returns hits only at the four sites the design marks `leave` and at the
  amendment's own quotation. Every site marked `re-key` is absent from the output.
  The two-stage pattern is load-bearing: an approval-term grep alone returns 157
  corpus-wide hits from unrelated approval prose, and a narrower pattern misses
  `lifecycle.rs:764` ("human-approved") and `phase-7-creation.md:263` ("approval
  gate" with no "human"). Both failure modes were checked against the current tree.
- The four `leave` sites are byte-identical to their pre-change state, confirmed
  by `git diff`. Re-keying a historical record is a defect, not thoroughness.
- A reviewer reads each of the six `re-key` sites and confirms none conveys the
  old rule in different words still keyed on `execution_mode`. The grep is
  evadable by paraphrase, so the reading is not optional.
- A Draft-to-Active transition whose resolved tracking level is not `none` is
  blocked without recorded approval, and a `multi-pr` plus `none` transition
  proceeds without it — verified against Phase 7's actual issue-creation gate,
  which is code, rather than against the transition-table prose alone.

**Dependencies**:
Issue 5 — the tracking level must be resolvable before a gate can key on it.

**Type**:
docs

**Files**:
`skills/plan/SKILL.md`, `skills/plan/references/plan-format.md`,
`skills/plan/references/quality/plan-doc-structure.md`,
`skills/plan/references/phases/phase-7-creation.md`,
`crates/shirabe-validate/src/lifecycle.rs`,
`crates/shirabe-validate/src/transition.rs`,
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
- A `multi-pr` plan with tracking `none`, containing at least one outline whose
  `Dependencies` references another outline, yields a task graph in which every
  dependency edge resolves to a declared work item with no unresolved keys. The
  fixture must carry a real edge: over an empty edge set the claim is vacuously
  true, and an implementation that emits no edges at all would pass.
- An outline whose `Dependencies` references a title not present in the outline
  list produces an unresolved-key error rather than a silently dropped edge.
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
- Decision 6 carries an amendment stating, in its own text, both that the
  single-pr default is now conditional on the resolved delivery preference and
  that the decomposition-strategy/execution-mode de-conflation and the
  value-based re-anchoring of the roadmap case are unchanged. A pointer to
  another document in place of either statement does not satisfy this.
- The amendment cites `DESIGN-multi-pr-plan-decoupling.md` for the reasoning and
  runs to no more than two or three sentences: it does not re-argue why the
  header exists or reproduce the alternatives analysis.
- Nothing in the original decision text is deleted, and the amendment is appended
  as a clearly separated section rather than interleaved into the original
  paragraphs, and is not phrased as superseding the decision.

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

**Parallel opportunity:** Issue 5 has no dependencies at all, so the tracking
half can start immediately, alongside Issue 1 rather than behind it. Issues 6 and
7 both hang off 5 and are independent of each other, so once 5 lands they can
proceed in parallel with the whole delivery-preference chain. Under one pull request this parallelism is
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
