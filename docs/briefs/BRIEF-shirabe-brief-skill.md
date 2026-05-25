---
schema: brief/v1
status: Done
problem: |
  shirabe's tactical chain runs roadmap to PRD to design to plan, but
  has no codified artifact between feature sequencing and requirements.
  Authors jump from "which feature" straight to "what are the
  requirements," skipping the step that frames a feature's problem,
  intended outcome, journeys, and scope. The brief shape exists by
  demonstration but has no skill, no format spec, no validation, and
  no jury.
outcome: |
  A skill author reaches for `/brief` the way they reach for `/prd`
  today: a loadable phased skill, a referenced format spec, a Phase 4
  jury that catches content and structural defects, and `shirabe
  validate` coverage at lifecycle transitions. The brief becomes a
  first-class artifact type with the same lifecycle and cross-repo
  contract as the rest of the taxonomy.
---

# BRIEF: shirabe-brief-skill

## Status

Done

The brief intentionally stops before requirements articulation.
The follow-on PRD (`PRD-shirabe-brief-skill.md`) owns the format-spec
details, the jury rubric, the validate-CLI checklist, and the
brief-specific artifact-decision prose.

This document is itself a brief, about the brief skill. The recursion
is intentional: shirabe already shipped one brief by demonstration
(`docs/briefs/BRIEF-shirabe-strategy-skill.md`), and this one follows
its shape while describing the skill that codifies it.

## Problem Statement

shirabe's tactical authoring chain runs `/roadmap` to `/prd` to
`/design` to `/plan` to `/work-on`. Each link maps onto a clear
altitude: a roadmap sequences which features get built and in what
order; a PRD captures what a single feature does and why; a design
captures how it's built; a plan decomposes that into issues; work-on
executes.

The gap sits between the roadmap and the PRD. Once a roadmap names a
feature, an author who reaches for `/prd` is asked to articulate
requirements — user stories, acceptance criteria, scope — before
anything has framed the feature's *problem*, its *intended outcome*,
the *journeys* it serves, and the *boundary* of what it touches. The
roadmap entry is a line item; the PRD is a requirements contract.
Between them lies the framing step, and shirabe doesn't codify it.

The shape that fits this altitude is a brief: a short document that
states the problem the feature solves, the outcome a user should
experience, the concrete journeys that exercise it, and the scope it
holds in and pushes out — in a form the next skill can pick up
directly. The shape already exists by demonstration. The
strategy-skill brief is the existence proof: it was authored by hand,
ahead of any `/brief` skill, precisely because the brief shape was the
right tool for the job and no skill yet produced it.

The remaining gap has four parts:

- **No skill entry point.** An author who wants to frame a feature
  before writing requirements has no `/brief` to load. They either
  skip the step or reverse-engineer the shape from the one existing
  example.
- **No format reference.** There is no `brief-format.md` to point at,
  so structural drift between briefs is unbounded — the four sections,
  their order, and the lifecycle are conventions held only in a single
  prior document.
- **No validation discipline.** `shirabe validate` doesn't recognize
  the `brief/v1` frontmatter schema or its required section set.
  Lifecycle transitions lack tooling enforcement, and the existing
  brief validates only because nothing checks it.
- **No jury rubric.** The prior brief got no Phase 4 review. Without a
  codified jury, a brief's quality — whether its problem statement is
  really a problem, whether its outcome is outcome-shaped — depends on
  author discipline alone.

The problem isn't that authors can't write briefs. It's that without
codification, each one reinvents the discipline, and the framing step
the chain needs stays optional and undefended.

## User Outcome

A skill author opens Claude Code in a repo where a roadmap has named a
feature and the requirements conversation hasn't started yet. They
invoke `/brief`. The skill walks them through the same phased
authoring pattern they know from `/prd` and `/strategy`: scoping,
drafting the four sections, a Phase 4 jury, finalization. The output
lands in `docs/briefs/BRIEF-<name>.md` with `schema: brief/v1`
frontmatter, all required sections present, and the jury's PASS
verdicts recorded in the Status section.

Downstream, when a PRD author writes `upstream:
docs/briefs/BRIEF-<name>.md` in their frontmatter, the reference
resolves cleanly because BRIEF is a first-class artifact type with the
same lifecycle and cross-repo contract as the rest. `shirabe validate`
on a BRIEF file exercises the same Formats-map lookup path that any
other artifact type uses today: a missing required section fails
validation, an invalid status fails validation, and the same check
runs in CI on every PR through the reusable validation workflow
shirabe and its adopters already consume. Briefs land with the same
gating the rest of the taxonomy gets.

The skill also carries the framing judgment, not just the template. An
author who starts the tactical chain partway up — say, from an issue
body that already implies a problem and a desired outcome — gets a
skill that decides whether a durable brief artifact earns its keep or
whether the existing evidence should pass forward to the PRD as-is.
The author doesn't have to make that call cold; the skill's phase
prose makes it for them.

Adopters who install shirabe through the marketplace get BRIEF
alongside the rest of the taxonomy. The framing step between roadmap
and requirements becomes a tool authors can reach for the moment a
feature is named, without having to read a prior example to learn the
shape.

## User Journeys

The brief calls out four journeys that exercise the artifact and the
skill from different entry points. Each names the user, the trigger,
and the outcome shape.

### Journey 1: Standalone author, cold invocation

A skill author has a feature in front of them — named on a roadmap, or
just surfaced in conversation — and wants to frame it before writing
requirements. They invoke `/brief` cold, with a short input describing
the feature. The skill walks them through Problem Statement (what the
feature solves), User Outcome (what a user should experience), User
Journeys (concrete paths through the feature), and Scope Boundary
(what's in and out). Phase 4 jury runs two reviewers — content-quality
and structural-format — and returns PASS verdicts. The author ratifies
and the brief lands at `docs/briefs/BRIEF-<name>.md`.

This is the primary mode at ship-time: a standalone framing artifact
produced before requirements exist.

### Journey 2: PRD author tracing upstream

A PRD author is writing requirements for a feature and needs to
declare what the PRD operationalizes. The brief that framed the
feature is the right upstream. They write the brief's path in the
PRD's `upstream:` frontmatter field, and the reference resolves
because BRIEF is a first-class artifact type. `shirabe validate` on
the PRD recognizes the BRIEF reference as a valid upstream artifact
type rather than rejecting an unknown schema.

This journey validates that BRIEF slots into the existing
upstream/downstream graph without special-casing.

### Journey 3: Artifact-decision safety valve

An author starts the tactical chain mid-altitude. The trigger is a
rich issue body that already implies the feature's problem and the
outcome it should produce — most of a brief's content exists, just not
as a brief. They invoke `/brief`, and the skill's phase prose makes a
decision: produce a durable brief artifact when the framing warrants
recording, or pass the existing evidence forward to the PRD when
authoring a separate document would be ceremony. The outcome is either
a committed brief or an explicit hand-off, not a brief written by
reflex.

This journey validates that the skill carries the framing judgment,
not just the template, so the chain stays usable when it's entered
partway up.

### Journey 4: Brief review and acceptance

A drafted brief sits at status `Draft`. Phase 4 jury runs against it.
The content-quality reviewer flags a User Outcome written as a feature
list rather than an outcome a user experiences; the structural-format
reviewer flags a missing Scope Boundary section. The author addresses
each, re-runs Phase 4, and the brief transitions to `Accepted` once
both reviewers PASS.

This journey validates that the jury catches real content and
structural defects of the kind a single ad-hoc read would miss.

## Scope Boundary

This brief, and the downstream PRD it points at, cover the standalone
`/brief` skill and the BRIEF doc template. The scope holds the
following inside:

- BRIEF artifact type definition: frontmatter schema, the four
  required content sections (Problem Statement, User Outcome, User
  Journeys, Scope Boundary), and lifecycle states (Draft, Accepted,
  Done).
- `brief-format.md` reference file at
  `skills/brief/references/brief-format.md`, following the structural
  skeleton of `strategy-format.md` and `prd-format.md`.
- `/brief` skill as a loadable plain-English SKILL.md following the
  `/strategy` and `/decision` pattern: entry modes, phased authoring,
  resume logic, critical requirements.
- Phase 4 jury structure with two reviewers — content-quality and
  structural-format — modeled on the existing phase-4-validate
  precedent but without an altitude reviewer, since briefs aren't
  altitude-sensitive the way the strategy type is.
- `shirabe validate` CLI extension: add `brief/v1` to the Formats map
  in `internal/validate/formats.go`. The CLI's `DetectFormat` already
  routes `BRIEF-` filenames by longest-prefix match, so no detection
  change is needed.
- Brief-specific artifact-decision prose in the skill's phases: the
  "produce a durable brief vs. hand off evidence-only" safety valve
  for when the chain is entered partway up.
- A status transition script for the Draft to Accepted to Done
  lifecycle, with no directory movement on any terminal state.
- A light shirabe CLAUDE.md update explaining when to reach for a
  brief versus a PRD.
- A light `/explore` routing-table touch placing the brief between the
  roadmap and the PRD in the tactical chain.

The scope explicitly excludes:

- **The `/scope` parent-skill integration.** A later feature
  integrates the brief into a parent skill that delegates to `/brief`
  as a child phase. This work ships the standalone skill only; the
  parent integration is separate downstream work and doesn't constrain
  this brief.
- **The general per-skill artifact-decision contract.** A later
  feature generalizes the produce-vs-hand-off decision across every
  tactical skill. This work ships only the brief-specific prose; it
  does not build the general mechanism.
- **Any new visibility-gated section or custom validate check.** The
  brief has no equivalent of the strategy type's competitive framing,
  so this work adds no `checkBriefPublic`-style check and no new
  validate error code.
- **Migration of existing artifact types.** This work adds the brief
  without changing the shape, naming, or validation of VISION,
  STRATEGY, ROADMAP, PRD, DESIGN, or PLAN.

## Open Questions

These surface for the downstream PRD to resolve. None block this
brief.

1. **Required frontmatter fields.** The format spec defines the exact
   `brief/v1` required-field set. The hard constraint: whatever the
   set is, the already-shipped `BRIEF-shirabe-strategy-skill.md` must
   keep validating green once `brief/v1` enters the Formats map. The
   PRD picks the field set against that constraint.

2. **Required vs optional sections.** The four content sections are
   required, and Status is required by convention across every shirabe
   type. Whether `Open Questions` and `Downstream Artifacts` are
   required or optional is undecided — both appear in the existing
   brief, but a leaner brief might omit them. The PRD picks one.

3. **Skill phase count.** The `/strategy` and `/prd` skills differ in
   how many phases they expose. The brief's authoring path is simpler
   (four sections, no altitude dimension), so it may warrant fewer
   phases. The PRD settles the phase count the SKILL.md exposes.

## Downstream Artifacts

- **`PRD-shirabe-brief-skill.md`** — requirements articulation for the
  `/brief` skill, the brief-format reference, the Phase 4 jury rubric,
  the validate-CLI extension, and the brief-specific artifact-decision
  prose. Lives in `docs/prds/`.
- **`DESIGN-shirabe-brief-skill.md`** — implementation shape, picked up
  after the PRD lands. Lives in `docs/designs/current/`.

## References

- Brief proof-by-example and structural template:
  `docs/briefs/BRIEF-shirabe-strategy-skill.md`.
- Skill structure template: `skills/strategy/SKILL.md`.
- Format-spec reference precedent:
  `skills/strategy/references/strategy-format.md`.
- Validate CLI extension point: `internal/validate/formats.go`.
- Cross-repo visibility rules: `references/cross-repo-references.md`.
