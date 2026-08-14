# Explore Scope: scope-artifact-persistence

## Visibility

Public

## Core Question

`/scope` is the default front door for tactical work of any size, but every
completed run leaves a permanent PRD and DESIGN in `docs/` regardless of what
the work turned out to be. The floor is structural, not heuristic: the
consolidation judgment can only absorb where the downstream *type's* required
sections have a home for every required section of the upstream *type*, and
against the current formats only BRIEF-to-PRD qualifies. That test is a schema
comparison with the same answer on every run, so above the first hop the
content question never gets to run. What has to change so that each hop's
verdict is decided by what the two documents in front of it actually contain --
letting a run end with all four artifacts, some, or none?

## Context

Filed as shirabe#280 after running `/scope` then `/execute` on #270 (PR #278).
That run absorbed the BRIEF into the PRD, recorded `keep` for PRD-to-DESIGN and
DESIGN-to-PLAN with the unmapped sections named, deleted the PLAN at
finalization, and left a PRD and a DESIGN behind permanently. For that change
the DESIGN arguably earned its place (it records why a koto gate fix used a
declared variable rather than a glob, and that koto discards gate stdout/stderr);
the PRD did not.

Verified against the code before scoping:

- `skills/scope/references/phases/phase-2-chain-orchestration.md` (Consolidation
  Judgment, Stage 1) gates absorption on a total required-section mapping and
  tabulates BRIEF-to-PRD as the only absorbable hop.
- `crates/shirabe-validate/src/formats.rs` confirms the section lists behind
  that table. A DESIGN has no home for Goals, User Stories, Requirements,
  Acceptance Criteria or Out of Scope; a single-pr PLAN (Status, Scope Summary,
  Decomposition Strategy, Issue Outlines, Implementation Sequence) has no home
  for any of the DESIGN's reasoning sections.
- `skills/scope/references/phases/phase-1-discovery.md` has a section named
  "The Durable-Artifact Floor" that states the floor as intended and says "Do
  not add a guard for this. Its condition cannot hold."

Author's direction, given during scoping and refined during convergence:

- `/scope` is the default front door. Folding is not mandatory on any run --
  the workflow must *allow* it at every hop. Some runs should end with every
  durable doc in place, some with a subset, some with none. Which one a run
  gets is decided by that run's content.
- The defect is that the absorbability judgment is short-circuited by a
  type-level test, so above BRIEF-to-PRD the content question never runs and
  the verdict is `keep` on every run regardless of what the documents say.
- Reduction stays a content-preserving move, never a discard. Nothing is
  dropped because it was judged not worth keeping.
- DESIGN-to-PLAN absorption must be supported. Not every activity needs a
  persistent design; when a DESIGN's value was decomposing tasks and ordering
  them, that value is spent once the PLAN encodes it.
- Code must carry comments explaining why it works the way it does, kept
  current as the code changes. That is `/execute`'s standing job, unconditional
  and independent of whether an upstream DESIGN ever existed.
- Because that property is unconditional, the keep-or-fold decision is
  encapsulated in `/scope`'s runtime. `/execute` does not need to know what the
  chain decided.

## In Scope

- The absorbability test and the per-hop mapping that currently makes the upper
  hops permanently unabsorbable.
- The artifact format contracts, to the extent a total mapping requires homes
  that do not exist today. (The consolidation BRIEF fenced this off; the fence
  is the open question this exploration has to answer rather than assume.)
- Whatever the tactical children must change to receive absorbed content.
- The knock-on effects of an upper-hop absorb: `upstream:` re-pointing,
  validator checks, lifecycle statuses, the finalization cascade, and inbound
  references from artifacts already on disk.
- Whether the run's record survives once the PLAN is deleted and the PR
  squash-merges.

## Out of Scope

- Making `/execute` aware of what the chain decided, or conditioning any
  `/execute` behaviour on it. Two `/execute` changes are nonetheless in scope
  because they are unconditional: giving it the standing job of keeping
  rationale in code current, and removing the two places where it already
  assumes a DESIGN survives (the R5 finalization guard and `run-cascade.sh`'s
  roadmap `**Downstream:**` rewrite).
- Retrofitting artifacts already on disk.
- Reintroducing any judgment that runs before the artifact it is about exists.
- The strategic chain under `/charter`. It has no consolidation mechanism, and
  the mapping test yields zero absorbable hops there.

## Research Leads

1. **What would a total section mapping at PRD-to-DESIGN and DESIGN-to-PLAN
   actually require of the format contracts?**
   The mapping cannot become total unless a DESIGN grows a home for
   requirements and acceptance criteria and a PLAN grows one for decision
   provenance. Need to know what `formats.rs` enforces (FC04 presence, FC15
   canonical order), whether any notion of optional or appendix sections
   exists, and what the smallest format change that opens both hops looks like.

2. **What breaks downstream when an upper hop absorbs?**
   An absorb re-points `upstream:` and `git rm`s the upstream. Need the blast
   radius: R6's resolve-to-a-tracked-file check, the PRD's `In Progress` and
   `Done` statuses, the finalization cascade, the one-to-many lineage handling
   that landed in #271, index or alias checks, and any artifact already on disk
   that points at a PRD or DESIGN this would delete.

3. **Does the run's record survive the PLAN's death?**
   Phase 3 writes what the chain produced and absorbed into the PR body, then
   the PR squash-merges and Phase 4 removes the state file. Combined with what
   `/execute` leaves in commits and code, does the decision provenance from the
   #270 case survive a fold-to-PLAN, or does it quietly disappear?

4. **Can the tactical children receive absorbed content today?**
   The consolidation BRIEF found `/prd` names a BRIEF as upstream but never
   reads its body. If `/design` and `/plan` have the same non-consumption
   problem, most of this change lands in the children rather than the parent.

5. **Does the strategic chain under `/charter` have the same floor?**
   VISION to STRATEGY to ROADMAP has the same shape, with ROADMAP as the
   ephemeral terminal artifact. Cheap to check and it decides whether the
   scope boundary covers one chain or both.

6. **What did #260 already settle, and was this tension seen at the time?**
   Re-read the shipped PRD and DESIGN behind the consolidation change so this
   work does not re-litigate ground that was deliberately closed, and to find
   whether upper-hop absorption was considered and rejected for a reason that
   still holds.
