---
schema: brief/v1
status: Draft
problem: |
  shirabe authors have no parent skill that walks them through a
  strategic conversation as a sequenced chain (vision-update → comp
  → strategy → roadmap). Each of the four children exists or is in
  flight, but invoking them sequentially is a manual discipline with
  no codification, no resume contract, and no terminal-artifact
  guarantees. Without a parent skill the three-rule terminal-artifact
  contract and the three exit paths are unenforceable, and the
  discipline-vs-artifact decoupling the strategic chain depends on
  fails empirically.
outcome: |
  Skill authors reach for `/charter` the way they reach for
  `/strategy` or `/vision` today: a loadable parent skill with a
  phased orchestration ladder, conditional invocation of vision,
  comp, strategy, and roadmap children, a resume contract that picks
  up mid-chain across child boundaries, and three first-class exit
  paths — full-run, re-evaluation Decision Record, and
  abandonment-forced materialization. The strategic chain becomes
  durable infrastructure rather than a manual sequencing discipline.
---

# BRIEF: shirabe-charter-skill

## Status

Draft. Authored as the brief input to the downstream PRD and the
shared design (`DESIGN-shirabe-progression-authoring.md`, co-authored
across `/charter`, `/scope`, and the `/work-on` migration).

This brief intentionally stops before requirements articulation. The
follow-on PRD owns the per-phase prose, the resume ladder, the
artifact-decision heuristics, and the exact delegation contracts at
each `/charter` → child interface.

## Problem Statement

shirabe ships VISION, STRATEGY, and ROADMAP at the strategic chain's
altitude — each as a loadable child skill (`/vision`, `/strategy`,
`/roadmap`) that authors invoke directly. COMP exists as an artifact
category by example and via workspace tooling; the `/comp` child
skill in shirabe core is parallel work. What's missing is the parent
layer: a skill that walks an author through the strategic
conversation as a *sequence*, deciding which children to invoke,
carrying scope between them, and enforcing the contract that the
conversation always lands at a durable artifact.

In the absence of a parent skill, authors today reach for the chain
as three separate invocations (with a fourth — `/comp` — in parallel
flight). This costs them in three ways. They
re-derive the sequencing decisions on every run (when does a vision
update fire? when is a roadmap warranted?). They carry context
between children manually, with no resume contract if the session
breaks. And they have no enforcement that the conversation produces a
durable terminal artifact — paused or abandoned chains leave evidence
files in `wip/` with no review surface.

The deeper problem is that the strategic chain has invariants that
cannot be enforced in the absence of `/charter`. `/charter`'s design
commits to a three-rule terminal-artifact contract: every chain ends
at a durable artifact for human review; re-evaluation of a healthy
upstream is a first-class lightweight exit; paused or abandoned
chains force-materialize the most-recent intermediate. None of these
invariants survive a manual chain. The discipline-vs-artifact
decoupling — the load-bearing principle that strategic work can be
*disciplined* without being forced to *produce* — depends on a
parent skill that enforces the three exits. Without it, every
strategic conversation is tempted into a STRATEGY revision
regardless of whether one is warranted, and the discipline collapses
into ad-hoc artifact creation.

The remaining gap has five parts:

- **No parent skill entry point.** Future strategic-chain authors
  have no `/charter` to load. They re-discover the sequencing logic
  per run.
- **No codified delegation graph.** The four `/charter` → child
  interfaces (`/vision`, `/comp`, `/strategy`, `/roadmap`) each have
  different inputs, outputs, conditionality, and visibility rules,
  but no document encodes them as a single contract.
- **No resume ladder across child boundaries.** Resume within a
  single skill (e.g., `/explore`'s Phase ladder) is precedent;
  resume across `/charter`'s children, including detection of
  partial child runs, is new.
- **No terminal-artifact enforcement.** The three exits — full-run,
  re-evaluation Decision Record, abandonment-forced materialization
  — exist as architectural intent but have no skill that implements
  them.
- **No parent-skill pattern.** `/charter` is the first of three
  parent skills shirabe needs. Without `/charter` as the validation
  point, downstream parent skills (`/scope`, the `/work-on`
  migration) have no precedent to inherit from.

The problem is not that authors can't sequence the strategic chain
by hand. It's that without `/charter`, the strategic chain's
invariants are unenforceable and the parent-skill pattern can't be
proven out for the parent skills that follow.

## User Outcome

A skill author opens Claude Code in a repo where a strategic
conversation needs to happen. They invoke `/charter`. The skill
opens with a discovery phase: it gathers context, detects whether
the conversation calls for a vision update, decides whether
competitive framing is in scope (private repos only), and converges
on a clear strategic question. From there it walks through the
chain — optional `/vision` if the long-term thesis is shifting,
optional `/comp` if competitive analysis is warranted, required
`/strategy` always, optional `/roadmap` if the strategy decomposes
into coordinated multi-block work. The author never has to remember
the order; the skill enforces it.

The conversation ends at one of three durable exits, each suited to
the shape the strategic work took:

- **Full-run exit.** A new or revised STRATEGY (Draft) is written,
  plus a ROADMAP if the strategy's blocks have cross-block
  dependencies. The chain halts at the durable artifact for human
  review.
- **Re-evaluation exit.** When the upstream STRATEGY is healthy and
  the chain confirms the existing bet still holds, a Decision Record
  is written referencing the existing STRATEGY. This is the
  lightweight exit that satisfies the terminal-artifact contract
  without forcing a redundant STRATEGY revision.
- **Abandonment-forced exit.** When the user breaks the chain
  mid-flight, the most-recently-run skill is forced to materialize
  its artifact even if its decision rule said evidence-only. The
  chain leaves a review surface regardless of how it terminated.

A `/charter` run that closes without one of these three has violated
the terminal-artifact contract; the skill enforces all three
explicitly. The Re-evaluation exit is the novel contribution — it's
what prevents every `/charter` run from being tempted into a
STRATEGY revision when nothing changed, and it's what proves the
discipline-vs-artifact decoupling thesis empirically.

The author can resume `/charter` mid-chain if the session breaks. The
resume contract detects partial child runs (artifacts in `wip/` or
durable docs/) and offers continue-from-here. Manual re-invocation
of any child directly outside `/charter` remains a first-class path;
`/charter` warns but does not act on the staleness of downstream
artifacts. `/charter`'s design treats manual fallback as steady-state
capability rather than a temporary shim — the author can always step
outside the chain without losing the discipline the parent skill
provides.

In public repos, the chain skips the `/comp` sub-phase silently — the
skill never asks about competitive analysis in a repo where the
content would be inappropriate. In private repos, `/comp` is offered
as an optional discovery feeder. Visibility is layered defense:
`/charter` doesn't invoke `/comp` publicly, the downstream
`/strategy` jury catches any competitive-content leakage into a
public STRATEGY, and `shirabe validate` blocks PRs that violate the
rule at CI time.

Downstream, `/charter`'s shipping validates the parent-skill pattern
for the two siblings that follow: `/scope` will inherit the same
parent/child shape, and the future `/work-on` migration will pivot
from its current substrate into the same pattern. `/charter` is not
just a new skill — it's the first instance of the parent-skill
infrastructure shirabe is committing to.

## User Journeys

[To be drafted by journey-author in Phase 3.]

## Scope Boundary

This brief, and the downstream PRD it points at, cover the
`/charter` parent skill as a loadable plain-English SKILL.md, plus
the scope-of-`/charter` portions of the shared design doc. The scope
holds the following inside:

- The `/charter` SKILL.md following the existing parent-skill
  template (input modes, execution-mode flag parsing, topic-slug
  constraint, workflow phases diagram, resume logic ladder, phase
  execution list, reference files table).
- The four delegation contracts at the `/charter` → child interfaces
  (`/vision`, `/comp`, `/strategy`, `/roadmap`), including inputs,
  outputs, conditionality rules, and review-halt behavior.
- The three exit paths (full-run, re-evaluation Decision Record,
  abandonment-forced materialization) as first-class skill behavior.
- The resume ladder across child boundaries, including dual-surface
  detection (`wip/` evidence and durable `docs/` artifacts) and
  status-aware re-entry for terminal STRATEGY.
- The visibility model that gates the `/comp` sub-phase to private
  repos and inherits shirabe's CLAUDE.md visibility regex pattern.
- The `/charter`-scoped portions of
  `DESIGN-shirabe-progression-authoring.md`, the shared design doc
  authored across the parent-skill pattern's three features.
- The discover/converge engine extraction from `/explore` as it
  applies to `/charter`'s Phase 1 discovery (the shared reference is
  consumed by `/charter`).
- Workspace and shirabe CLAUDE.md updates documenting `/charter`'s
  entry triggers and discovery surface.
- The per-skill artifact-decision contract as instantiated in
  `/charter`'s phase prose (`/explore` Phase 5's no-artifact path is
  the precedent).
- Manual-redirect workflow as a first-class steady-state surface,
  authored as explicitly as the parent-driven workflow.

The scope explicitly excludes:

- **The `/scope` tactical progression skill.** Separate feature with
  its own brief; shares the design doc but does not bind `/charter`'s
  scope.
- **The `/work-on` migration into the parent-skill pattern.**
  Separate feature; depends on amplifier-layer workflow-composition
  substrate that `/charter` does not require for its own ship.
- **The `/comp` skill body itself.** `/charter`'s contract for
  consuming `/comp` is in scope; authoring the `/comp` SKILL.md is
  the responsibility of the `/comp` feature.
- **Revisions to the `/strategy` SKILL.md.** `/charter` consumes
  `/strategy` as it ships today; if integration surfaces a need for
  `/strategy` revisions, that's a separate PR.
- **The amplifier-layer workflow substrate.** The migration into
  workflow-composition infrastructure is downstream; `/charter`
  ships against current shirabe patterns (wip/-based intermediates,
  plain-English phase prose).
- **The review-time redirect mechanism.** Manual fallback is
  first-class by design; the automatic-redirect substrate is
  amplifier-layer work and is not a prerequisite for `/charter`.
- **The niwa workspace context surface.** `/charter` uses current
  CLAUDE.md visibility detection; substrate cleanup is unrelated.
- **Migration of existing strategic-progression artifacts.**
  `/charter` adds a parent layer without renaming or restructuring
  the children's artifacts. Existing STRATEGY, ROADMAP, VISION docs
  continue to validate under their existing schemas.
- **The tone rubric, the writing-style discipline, and other shirabe
  substrate work.** `/charter` follows the same conventions shirabe
  uses today.

## Open Questions

These surface for the downstream PRD or design to resolve. None
block this brief.

[To be finalized in Phase 3 after journey-author returns. Working
list per Phase 1 scoping:

1. `/strategy` SKILL.md verification — the actual implementation
   must be read before `/charter`'s `--upstream` flag and handoff
   scope-file shape can be finalized against it.

2. `/comp` skill ordering — does `/charter` ship with the `/comp`
   invocation as documented-but-disabled (skipped until the `/comp`
   skill lands), or does `/comp` ship first so `/charter` ships
   against a functional `/comp`?

3. Engine extraction location — does the discover/converge engine
   extract into a top-level `references/` directory (the existing
   shirabe precedent for shared content), or stay inside
   `skills/explore/references/` with `/charter` referencing those
   paths cross-skill?

4. Dual-implementation contract — the shared design must commit to a
   logical contract that satisfies both `/charter`'s wip/-based
   core-layer implementation AND the eventual amplifier-layer
   implementation that the `/work-on` migration needs. The contract
   is the freeze line; the implementations evolve. Picking the
   contract is the most novel design challenge.]

## Downstream Artifacts

[To be finalized in Phase 3.]

## References

[To be finalized in Phase 3.]
