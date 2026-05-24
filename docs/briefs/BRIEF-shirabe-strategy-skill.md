---
schema: brief/v1
status: Draft
problem: |
  shirabe ships VISION, ROADMAP, PRD, DESIGN, and PLAN as first-class
  artifact types with format specs and validation, but has no artifact
  type at medium-term defensibility altitude. The gap currently gets
  filled ad-hoc on a per-team basis; without a codified type, future
  authors at this altitude reverse-engineer the shape from prior
  examples and structural drift goes unchecked.
outcome: |
  Skill authors reach for `/strategy` the way they reach for `/vision`
  or `/prd` today: a loadable skill with phased authoring, a referenced
  format spec, a Phase 4 jury that catches structural and altitude
  defects, and `shirabe validate` CLI coverage that recognizes the
  artifact at lifecycle transitions. The medium-term defensibility
  layer becomes durable infrastructure rather than a workspace-local
  pattern.
---

# BRIEF: shirabe-strategy-skill

## Status

Draft

Authored ahead of the `/brief` skill landing as a structural
sample for that skill.

The brief intentionally stops before requirements articulation. The
follow-on PRD (`PRD-shirabe-strategy-skill.md`) owns the format-spec
details, the jury rubric, the validate-CLI checklist, and the
authoring-path-specific decisions.

## Problem Statement

shirabe today recognizes five artifact types — VISION, ROADMAP, PRD,
DESIGN, PLAN — each with a loadable skill, a referenced format spec,
and `shirabe validate` coverage. The taxonomy maps cleanly onto
long-term aspiration (VISION), sequenced features (ROADMAP),
requirements (PRD), implementation architecture (DESIGN), and
execution steps (PLAN).

The gap is medium-term defensibility. When the work in front of a team
operationalizes a piece of an upstream VISION but doesn't pivot the
long-term thesis, neither VISION nor ROADMAP fits. VISION is too
abstract — re-justifying the project's existence is overkill for
additive work. ROADMAP is too implementation-bound — sequencing
features pre-supposes the bet that motivates them is settled, and
asking authors to pivot to feature lists prematurely truncates the bet
conversation.

The shape that fits this altitude is a strategic document: it carries
forward enough upstream VISION content to stand alone, articulates a
falsifiable medium-term bet with named corrective actions, decomposes
the bet into coherent building blocks at a granularity that defers
sequencing to a downstream roadmap, and identifies the load-bearing
claims whose failure should trigger reconsideration. The document type
exists by demonstration in prior workspace work; the codification step
makes it durable infrastructure.

The remaining gap has four parts:

- **No skill entry point.** Future strategy authors have no
  `/strategy` to load. They must read prior examples and
  reverse-engineer the structure.
- **No format reference.** There is no `strategy-format.md` to point
  at, so structural drift between strategy documents is unbounded.
- **No validation discipline.** `shirabe validate` does not yet
  recognize the strategy frontmatter schema or its required section
  set. Lifecycle transitions (Draft → Accepted → Active → Sunset)
  lack tooling enforcement.
- **No jury rubric.** Phase 4 review of the prior strategic document
  was bespoke. Without a codified jury structure (bet quality,
  altitude, structural format), future strategies depend on author
  discipline alone.

The problem isn't that authors can't write strategic documents. It's
that without codification, each one reinvents the discipline, and the
cost compounds as the taxonomy fragments.

## User Outcome

A skill author opens Claude Code in a repo where a strategic
conversation needs to happen at medium-term defensibility altitude.
They invoke `/strategy`. The skill walks them through the same phased
authoring pattern they know from `/vision` and `/decision`: discovery,
drafting, jury review, finalization. The output lands in
`docs/strategies/STRATEGY-<name>.md` with `schema: strategy/v1`
frontmatter, all required sections present, and the Phase 4 jury's
PASS verdicts recorded in the Status section.

Downstream, when a ROADMAP author writes `upstream:
docs/strategies/STRATEGY-<name>.md` in their frontmatter, the
reference resolves cleanly because STRATEGY is a first-class artifact
type with the same lifecycle and cross-repo visibility contract as the
rest. `shirabe validate` on a STRATEGY file exercises the same
Formats-map lookup path that any other artifact type uses today; a
missing required section fails validation; an invalid status fails
validation. The same check runs in CI on every PR through the
reusable `validate-docs.yml` workflow shirabe and its adopters
already consume today, so STRATEGY documents land with the same
gating other artifact types get — not just locally, but in the
review surface where the format spec actually defends content
quality.

Adopters who install shirabe through the marketplace get STRATEGY
alongside the rest of the taxonomy. The medium-term defensibility
altitude becomes a tool authors can reach for the moment their work
warrants it, without having to read a prior example to learn the
shape.

## User Journeys

The brief calls out four journeys that exercise the artifact and the
skill from different entry points. Each names the user, the trigger,
and the outcome shape.

### Journey 1: Strategy author, standalone invocation

A skill author working in a repo identifies a strategic conversation
that doesn't fit VISION (no long-term identity shift) or ROADMAP (the
sequencing question isn't ripe). They invoke `/strategy` cold, with a
short input describing the bet they want to articulate. The skill
walks them through Strategic Context drafting (carrying forward
upstream VISION content), Defensibility Thesis (the medium-term bet),
Building Blocks (concrete units of work at sequencing-deferred
granularity), Coordination Dependencies, and Falsifiability. Phase 4
jury runs three reviewers (bet quality, altitude, structural format)
and returns PASS verdicts. Author ratifies and commits the artifact at
`docs/strategies/STRATEGY-<name>.md`.

This is the primary mode at ship-time. Chained invocation from a
strategic parent skill is downstream future work.

### Journey 2: ROADMAP author tracing upstream

A roadmap author is writing a feature decomposition and needs to
declare what bet the roadmap operationalizes. The existing pattern
points at VISION, but the conversation is more local than
VISION-altitude. They reach for STRATEGY as the right upstream, either
citing an existing STRATEGY document or invoking `/strategy` to draft
the missing upstream first. The ROADMAP's frontmatter `upstream:`
field accepts the STRATEGY path. `shirabe validate` on the ROADMAP
recognizes the STRATEGY reference as a valid upstream artifact type.

This journey validates that STRATEGY slots into the existing
upstream/downstream graph without special-casing.

### Journey 3: Adopter, public-repo strategy

A team using shirabe through the marketplace hits a strategic question
in a public repo. They invoke `/strategy`. The skill produces a
STRATEGY document at the right altitude, with sections that carry
competitive framing omitted in public-repo mode (mirroring VISION's
visibility-gated-section pattern). The author doesn't have to know the
rule; the skill enforces it.

This journey validates that STRATEGY honors shirabe's existing
visibility discipline rather than re-inventing it.

### Journey 4: Strategy review and acceptance

A drafted STRATEGY document sits at status `Draft`. Phase 4 jury runs
against it. The bet-quality reviewer challenges a claim that isn't
falsifiable; the altitude reviewer flags a Building Block that slipped
into ROADMAP-level sequencing; the structural reviewer catches a
missing Downstream Artifacts entry. The author addresses each, re-runs
Phase 4, and the document transitions to `Accepted` once all three
reviewers PASS.

This journey validates that the jury catches real defects of the kind
caught in bespoke reviews of prior strategic documents.

## Scope Boundary

This brief, and the downstream PRD it points at, cover the standalone
`/strategy` skill and the STRATEGY doc template. The scope holds the
following inside:

- STRATEGY artifact type definition (frontmatter schema, required and
  optional sections, lifecycle states).
- `strategy-format.md` reference file at
  `skills/strategy/references/strategy-format.md`, following the
  structural skeleton of `vision-format.md`, `roadmap-format.md`, and
  `prd-format.md`.
- `/strategy` skill as a loadable plain-English SKILL.md following
  the `/vision` and `/decision` pattern (entry modes, phased
  authoring, resume logic, critical requirements).
- Phase 4 jury structure with three reviewers (bet quality, altitude,
  structural format), modeled on
  `skills/vision/references/phases/phase-4-validate.md`.
- `shirabe validate` CLI extension: add `strategy/v1` to the Formats
  map in `internal/validate/formats.go`. The CLI's `DetectFormat`
  already handles longest-prefix-match routing on `STRATEGY-`
  filenames.
- CI validation enablement. Shirabe's self-caller
  (`validate-shirabe-docs.yml`) path-filters on `docs/**` and so picks
  up `docs/strategies/STRATEGY-*.md` automatically once the Formats
  entry lands. Adopter repos that pin the reusable
  `validate-docs.yml` workflow inherit STRATEGY validation when they
  bump to a shirabe release including the entry. Adopter workflows
  that path-filter narrowly (e.g., `docs/visions/**`) need to widen
  the filter to include `docs/strategies/**` — call this out in the
  release notes for the version that ships the Formats entry.
- Visibility-gated optional section for competitive framing,
  following VISION's precedent (omitted in public repos).
- Light updates to shirabe CLAUDE.md (and downstream-adopter
  guidance) explaining when to reach for STRATEGY vs VISION,
  ROADMAP, or PRD.

The scope explicitly excludes:

- **Any chained-authoring path through a strategic parent skill.**
  The roadmap entry leaves the choice between standalone `/strategy`
  and in-parent authoring open at the SE3 level; this brief scopes to
  the standalone skill only. A later integration where a strategic
  parent skill delegates to `/strategy` as a child phase is downstream
  design territory and doesn't constrain SE3.
- **`/brief` skill.** The four-section brief format named in the
  strategic upstream is exercised by the present document but not
  codified by SE3. This brief is structural inspiration, not the
  format-of-record.
- **Review-time redirect mechanism.** STRATEGY documents reference
  redirect in their Coordination Dependencies sections, but the
  mechanism itself is downstream feature work. SE3 does not need to
  wait for it.
- **Per-product VISIONs and existing artifact types.** SE3 adds
  altitude without changing VISION, ROADMAP, PRD, DESIGN, or PLAN
  shape, naming, or validation. No migration of existing artifacts.
- **External-pattern adoption beyond the reference fleet.** Whether
  external shirabe adopters reach for STRATEGY is a downstream
  signal, not a requirement of SE3.

## Open Questions

These surface for the downstream PRD to resolve. None block this
brief.

1. **Acceptance trigger.** Prior strategic documents transitioned
   Draft → Accepted via Phase 4 jury PASS plus human ratification.
   Does the format spec require both, or does jury PASS alone trigger
   Accepted (with human ratification as a separate operational step)?
   Maps onto an explicit choice in the lifecycle definition.

2. **Sunset semantics.** When does a STRATEGY document leave Active
   and enter Sunset? Likely candidates: upstream VISION pivots and
   the bet's framing no longer applies; all Downstream Artifacts
   reach Done state and the strategy has discharged its purpose; an
   explicit Sunset decision is recorded. The format spec picks one or
   names them as a non-exclusive set.

3. **Building Blocks granularity rubric.** The jury reviewer for
   altitude needs an objective handle on "Building Block is the right
   size." Candidates: block-count ranges (e.g., 3-8 typical),
   block-to-downstream-artifact ratio (each block maps to N design
   docs, with N bounded), block scope (single-product vs
   cross-product). The PRD picks a rubric that the jury can apply
   repeatably.

## Downstream Artifacts

- **`PRD-shirabe-strategy-skill.md`** — requirements articulation for
  the `/strategy` skill, the strategy-format reference, the Phase 4
  jury rubric, and the validate-CLI extension. Lives in
  `docs/prds/`.
- **(Likely) `DESIGN-shirabe-strategy-skill.md`** — implementation
  shape, picked up after PRD lands. Lives in `docs/designs/current/`.
  Authored at PRD-time judgment.

## References

- Format-spec template precedents:
  `skills/vision/references/vision-format.md`,
  `skills/prd/references/prd-format.md`,
  `skills/roadmap/references/roadmap-format.md`.
- Phase 4 jury precedent:
  `skills/vision/references/phases/phase-4-validate.md`.
- Skill structure template: `skills/vision/SKILL.md`.
- Validate CLI extension point: `internal/validate/formats.go`.
- Cross-repo visibility rules: `references/cross-repo-references.md`.
