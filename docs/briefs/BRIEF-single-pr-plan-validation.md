---
schema: brief/v1
status: Accepted
upstream: docs/plans/PLAN-roadmap-plan-standardization.md
problem: |
  shirabe's validator treats single-pr and multi-pr plans identically. The Plan
  profile's required-sections list and every content check is shaped around the
  multi-pr Implementation Issues table; a single-pr plan's authoritative content
  lives under Issue Outlines, so a single-pr plan can declare execution_mode
  single-pr, omit Issue Outlines entirely, populate the wrong section, mismatch
  its issue_count, and still pass every check.
outcome: |
  A coordinator authoring a single-pr plan gets the same level of structural
  validation a multi-pr coordinator gets today. Missing outlines, malformed
  outline blocks, unresolved outline-to-outline dependencies, issue_count
  mismatches, and content in the wrong execution-mode section all surface as
  notices at validate time, in the IDE or in CI, not at review or work-on time.
---

# BRIEF: single-pr-plan-validation

## Status

Accepted

Phase 4 jury returned all-PASS; Phase 5 approval recorded under the parent
`/scope --auto` chain. The downstream PRD picks up the framing captured here
and translates the acceptance-criteria set from the upstream issue into formal
requirements.

## Problem Statement

shirabe today has two plan execution modes. A multi-pr plan decomposes a milestone
into a populated Implementation Issues table with one row per GitHub issue and a
Dependency Graph that reflects the same shape. A single-pr plan declares the
same `schema: plan/v1` but carries its authoritative content under Issue
Outlines instead -- one outline block per discrete work item, each block naming
a goal, an acceptance-criteria block, and an outline-to-outline dependencies
declaration. The Implementation Issues table is absent or empty on single-pr
plans; the Dependency Graph is absent or empty too.

`shirabe validate` does not see this distinction. The Plan profile declares one
required-sections list regardless of `execution_mode`, and there is no
`execution_mode`-aware dispatch anywhere in the validator. The consequence is a
real quality gap: a single-pr plan can declare `execution_mode: single-pr`, omit
Issue Outlines entirely, populate Implementation Issues with a multi-pr-shaped
table, mismatch `issue_count` against the actual outline count, and still pass
every check. A well-formed single-pr plan with structured outlines,
outline-to-outline dependencies, and an accurate `issue_count` gets zero
structural enforcement either way. The discipline that produces well-formed
single-pr plans today is entirely on author convention.

The format reference at `skills/plan/references/quality/plan-doc-structure.md`
already describes the single-pr / multi-pr distinction (Issue Outlines populated
in single-pr, Implementation Issues populated in multi-pr) and gives a
per-outline structural contract. The validator does not enforce any of it. That
is the gap.

## User Outcome

A coordinator authoring a single-pr plan reaches for `shirabe validate` and gets
back the same level of structural feedback a multi-pr coordinator already gets.
The validator catches a missing `## Issue Outlines` section when single-pr
requires it, an outline block missing its goal or its acceptance-criteria block,
an outline depending on a sibling that does not exist in the same section, an
`issue_count` that does not match the count of outline blocks, and content that
landed in the wrong section for the declared execution mode (a populated
Implementation Issues table under `execution_mode: single-pr`, or a populated
Issue Outlines section under `execution_mode: multi-pr`).

The coordinator finds these defects at `shirabe validate` time -- in their
editor while drafting, or in CI's Validate Docs job on the open PR -- not at
review time when a peer has to spot the structural break in prose, and not at
`/work-on` time when the cascade tries to consume a malformed outline and
falls over.

The new check, named FC10 to extend the FC07-FC09 notice family already in
place on multi-pr plans, delivers feedback in that same shape: notices, not
errors, in this first release, so an unmigrated corpus does not redden CI;
promotion to error is a one-line change after the corpus stabilizes. A
reviewer scanning a CI rollup sees `[FC10]` annotations alongside the existing
notice family, each annotation naming the specific defect (the outline key,
the missing field, the unresolved dependency name) so the fix is mechanical.

## User Journeys

### Journey 1: Coordinator authoring a single-pr PLAN

A coordinator running `/plan` for a small, bounded feature picks `single-pr` at
the value-confirmation guard, drafts the Issue Outlines section, and triggers
`shirabe validate` from their editor or from a pre-push hook. FC10 fires on any
structural defect -- a missing required section that single-pr expects, an
outline block missing its goal or acceptance-criteria block, an outline naming a
dependency that does not resolve to a sibling outline, an `issue_count` that
does not match the outline count -- naming the offending outline key and the
specific defect. The coordinator fixes the defect inline and re-runs `shirabe
validate` until the notice clears, before opening the PR for review.

### Journey 2: Reviewer scanning a single-pr PLAN PR in CI

A reviewer opens the PR page for an open single-pr PLAN PR and reads the
Validate Docs job's annotations. Any FC10 notice surfaces alongside the existing
FC07 / FC08 / FC09 notices in the same CI rollup, formatted identically, naming
the specific defect verbatim (the outline key, the missing field, the
unresolved dependency name). The reviewer marks the PR Changes Requested with a
one-line note pointing at the FC10 notice; the author's fix is mechanical.

### Journey 3: Coordinator running `/work-on` on the resulting single-pr PLAN

A coordinator runs `/work-on` on a single-pr PLAN that already passed CI. The
cascade reads `## Issue Outlines` to drive its outline-by-outline implementation
loop and consumes the outline-to-outline dependency graph to schedule work. A
coordinator running `/work-on` against a FC10-clean PLAN gets a deterministic
outline-by-outline traversal because the upstream PR gate caught the structural
defects -- they never reach the coordinator's `/work-on` session. The cascade
doesn't have to defend against malformed outlines at runtime, and the
coordinator doesn't have to interpret a runtime failure that traces back to a
structural break the validator should have caught two steps earlier.

### Journey 4: Coordinator who mixes execution-mode content

A coordinator declares `execution_mode: single-pr` in their PLAN frontmatter but
authors the body as if it were multi-pr -- populating `## Implementation Issues`
with a table and leaving `## Issue Outlines` absent. FC10 Sub-check E fires a
notice on the populated-wrong-section condition, recommending either changing
the frontmatter to `execution_mode: multi-pr` or moving the content into
`## Issue Outlines`. The notice surfaces both halves of the inconsistency in
one place; the coordinator picks a side and re-runs.

## Scope Boundary

**In-scope:**

- A new check, FC10, added to the validator's Plan arm alongside FC05-FC09.
  The Roadmap arm is unchanged.
- Five behavioural sub-checks: (A) `execution_mode`-aware required-sections
  dispatch so single-pr and multi-pr each validate against their own section
  set; (B) Issue Outlines structural check (each outline block has a goal, an
  acceptance-criteria block, and a dependencies declaration); (C)
  outline-to-outline dependency resolution (each dependency token names a
  sibling outline in the same section, or the literal `None`); (D)
  `issue_count` consistency between frontmatter and whichever section holds
  the work (Issue Outlines on single-pr, Implementation Issues on multi-pr);
  (E) mutual exclusion of populated execution-mode-specific sections.
- A `FormatSpec` refactor making the Plan profile's required-sections shape
  `execution_mode`-aware so the required-sections check branches by mode while
  other profiles keep the existing flat shape.
- An outline parser helper extracting outline blocks as a sequence with
  per-block `key`, `goal`, `acceptance_criteria`, `dependencies` fields. The
  parser is total over arbitrary input -- no panics on malformed headers,
  missing fields, or unterminated blocks. Exact file location (extending the
  existing table parser vs adding a sibling outline parser) is a downstream
  implementation choice.
- All five sub-checks ship at notice severity in this first release,
  matching the FC07 / FC08 / FC09 staged-rollout pattern.
- Table-driven tests covering, separately for single-pr and multi-pr:
  well-formed plan (no notice), missing required section (notice fires for the
  correct mode), populated wrong section (notice fires), outline with missing
  goal (notice fires), outline with unresolved dep (notice fires),
  `issue_count` mismatch (notice fires), and malformed outline block (no panic).
- Reconciliation messages naming the specific defect verbatim (outline key,
  missing field, unresolved dep name).

**Out-of-scope:**

- **Promotion of FC10 to error severity.** That ships separately as a one-line
  `is_notice` membership change after the corpus has stabilized, mirroring how
  FC07 / FC08 / FC09 carry their own promotion path. This work delivers the
  check at notice severity.
- **Roadmap arm changes.** Roadmaps do not carry a single-pr / multi-pr
  distinction at the plan-format level; the Roadmap arm of `validate_file` is
  unchanged.
- **Corpus migration to fix existing malformed single-pr plans.** This work
  adds enforcement; corpus migration is implicit in the notice-severity ship
  pattern and any necessary corpus edits land in their own follow-ups.
- **Single-pr PLAN format authoring guidance.** The format spec already lives
  at `skills/plan/references/quality/plan-doc-structure.md`; FC10 enforces
  that spec, it does not author or revise it.
- **Changes to the `/plan` skill itself.** The skill's existing authoring flow
  is unchanged; FC10 adds validator behavior, not skill behavior.
- **CI workflow changes.** FC10 runs inside the existing Validate Docs job;
  no new workflow file, no new job entry.

## References

- `skills/plan/references/quality/plan-doc-structure.md` -- the format spec
  FC10 enforces; defines the per-outline structural contract (goal, acceptance
  criteria, dependencies) and the single-pr vs multi-pr section distinction.
- `docs/designs/current/DESIGN-table-diagram-reconciliation.md` -- the sibling
  DESIGN that introduced the row-terminality and profile-dispatch precedent
  FC10 extends to execution-mode awareness.
- `docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md` -- the FC09 BRIEF
  that this brief mirrors in shape: single-check follow-up, ships at notice
  severity, one-line promotion path to error.
- Parent PLAN (the row that schedules this increment alongside the FC07-FC09
  notice family): `docs/plans/PLAN-roadmap-plan-standardization.md`.
