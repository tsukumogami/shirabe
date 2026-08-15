# Decision Context: What surface carries R20's durable fold record?

## Question

What surface carries the durable fold record R20 requires — a record on the
default branch naming what folded into what, on what verdict, with the
per-contribution carry result and a content hash of the pre-fold original —
across all three deletion sites?

## Complexity

critical (Tier 4, full path: phases 0-6 with persistent validators)

## Constraints

**Settled upstream, not re-litigable:**
- The record is of the *operation*, never of the distillate. Any destination
  preserving absorbed content must assert every time it fires that the verdict
  was partly wrong. Closes the whole class including an archive directory and a
  per-run decision record.
- Produced mechanically (`git hash-object` plus a formatted append), not
  authored by an agent.
- No gate on the verdict itself.

**Verified in the repository (this decider, directly):**
- `/scope`'s closed write-target set is prose at
  `skills/scope/references/phases/phase-3-exit-finalization.md:277-308` and
  `skills/scope/SKILL.md:714-726`. It is one of six enumerated pattern-level
  security surfaces. Any surface costs an explicit amendment.
- Phase 2's consolidation contributes exactly **one deletion target**
  (`docs/briefs/BRIEF-<topic>.md`) and **no creation target**
  (`phase-3-exit-finalization.md:294-297`). VERIFIED.
- `docs/decisions/` is constrained to
  `DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`
  (`phase-3-exit-finalization.md:285`), bound to four templates. A new shape
  costs an amendment to that closed set. VERIFIED.
- The PR-body route is specified at `phase-3-exit-finalization.md:64-76`
  ("Durable record of what the chain produced") and never implemented.
- `/execute`'s `pr_finalization` does a full `--body-file` replacement
  (`skills/execute/koto-templates/execute.md:415-428`) and is barred from
  reading child PR bodies or diffs (R14/R15, metadata-only). It cannot merge
  into a body it did not author.
- `/execute`'s cascade `git rm -f "$PLAN_DOC"` at
  `skills/execute/scripts/run-cascade.sh:860`, on every run, fold or no fold.
- Squash-merge with branch deletion: the absorbed document never existed on
  `main`. Hence a content hash rather than a path.
- `/scope` Phase 4 deletes `wip/` state, so nothing staged there survives merge.

## Three deletion sites

1. **BRIEF-to-PRD (any hop with a durable survivor)** — a survivor exists and
   can carry the record in its own frontmatter.
2. **The terminal fold into the PLAN** — no survivor; the PLAN itself is
   deleted later by `/execute`.
3. **`/execute`'s cascade deletion of the PLAN** — a different skill entirely,
   fires on every run, fold or no fold.

## Known Options

- A single shared append-only index (one `docs/deletions.md`, created on first
  append, one row per deletion).
- The surviving document's frontmatter.
- The PR body's durable half (Part 1, which becomes the squash commit body).
- Better surfaces if they exist.

## Inherited criteria

Three PRD acceptance criteria inherit this answer, plus the surface for the
R14 carry-check failure finding and the R15 refused-deletion finding.

## Background

R20 (PRD-scope-artifact-persistence): "A fold SHALL NOT land unless a record
was written to the default branch naming what folded into what, on what
verdict, with the per-contribution carry result and a content hash of the
pre-fold original. The record SHALL be produced mechanically and SHALL NOT
carry the absorbed document's contributions."

A per-run artifact risks reading as the floor this whole feature removes. A
shared index does not. R27 forbids a second reduction mechanism; R30 requires
failure toward `keep` at every added decision point, including record
production.
