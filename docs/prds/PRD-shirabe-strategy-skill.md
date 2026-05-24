---
schema: prd/v1
status: Accepted
problem: |
  shirabe ships VISION, ROADMAP, PRD, DESIGN, and PLAN as first-class
  artifact types with format specs, validation, and dedicated skills,
  but has no artifact type at medium-term defensibility altitude.
  Strategic documents at this altitude get authored ad-hoc; without a
  codified type, the next author reverse-engineers the shape from
  prior examples, and structural drift goes unchecked. The upstream
  brief identified the gap and committed to a standalone `/strategy`
  skill plus a STRATEGY doc template; this PRD locks the requirements
  for both.
goals: |
  STRATEGY becomes a first-class shirabe artifact type alongside
  VISION, ROADMAP, PRD, DESIGN, and PLAN, with the same shape of
  infrastructure each of the others has today: a loadable skill, a
  format reference, a Phase 4 jury, `shirabe validate` CLI coverage,
  and CI validation via the existing reusable workflow. Authors reach
  for `/strategy` when their work operationalizes a piece of an
  upstream VISION at medium-term defensibility altitude; the skill
  walks them through phased authoring, the jury catches structural
  and altitude defects, and validation runs at both the CLI and PR
  layers using the patterns the other artifact types already
  established.
upstream: docs/briefs/BRIEF-shirabe-strategy-skill.md
---

# PRD: shirabe-strategy-skill

## Status

Accepted

This PRD picks up the requirements work scoped by
`docs/briefs/BRIEF-shirabe-strategy-skill.md`. It owns the
artifact-format details, the jury rubric, the `shirabe validate`
extension, the CI activation, and the `/strategy` skill structure.
Implementation (the actual skill body, format-reference content,
Go-side Formats map entry, and CI release-notes obligations) lands
in a downstream DESIGN doc plus implementation issues.

The PRD closes the three open questions the brief raised:
acceptance trigger, Sunset semantics, and Building-Blocks granularity
rubric. Positions are recorded in the Decisions and Trade-offs
section with rationale grounded in existing artifact-type precedents.

## Problem Statement

shirabe recognizes five artifact types today, each with a dedicated
loadable skill (`/vision`, `/roadmap`, `/prd`, `/design`, `/plan`),
a format reference file at `skills/<name>/references/<name>-format.md`,
a Phase 4 jury where applicable, and `shirabe validate` Formats-map
coverage. The taxonomy spans long-term aspiration (VISION),
sequenced features (ROADMAP), requirements (PRD), implementation
architecture (DESIGN), and execution steps (PLAN).

Medium-term defensibility — work that operationalizes a piece of an
upstream VISION without re-articulating the long-term thesis — has
no home in this taxonomy. Authors at this altitude either stretch
VISION beyond its intent (re-justifying the project's existence to
write what's effectively an additive bet), or compress into ROADMAP
prematurely (forcing feature decomposition before the bet that
motivates the features is settled). Neither fits, and the gap gets
filled with ad-hoc strategic documents that each invent their own
shape.

The proof-of-concept exists already (in the form of strategic
documents that have been authored at this altitude in practice),
and the structural pattern is stable. What's missing is durability:

- **No skill entry point.** Authors at medium-term defensibility
  altitude have no `/strategy` to load. They read prior examples and
  reverse-engineer the shape.
- **No format reference.** There is no `strategy-format.md`, so the
  next author has no canonical source for required sections,
  frontmatter schema, lifecycle, or visibility rules.
- **No jury rubric.** Phase 4 review of prior strategic documents
  was bespoke. Without a codified 3-reviewer pattern (bet quality,
  altitude, structural format), each strategy depends on author
  discipline alone.
- **No validation discipline.** `shirabe validate` doesn't recognize
  STRATEGY frontmatter or required sections; CI doesn't gate on
  structural correctness; lifecycle transitions go unenforced.

Each of these is small in isolation. Together they're the gap
between "strategic documents have been written" and "strategic
documents are first-class shirabe infrastructure."

## Goals

1. **Codify STRATEGY as a first-class artifact type.** Define the
   frontmatter schema (`schema: strategy/v1`), required and optional
   sections, lifecycle states, and visibility rules — all in a
   format reference that follows the existing
   `vision-format.md` / `roadmap-format.md` / `prd-format.md`
   skeleton.

2. **Author `/strategy` as a loadable phased skill.** Follow the
   `/vision` and `/decision` precedent: plain-English SKILL.md, phase
   files under `references/phases/`, progressive disclosure,
   wip/-based intermediates, and a Phase 4 jury that aggregates three
   parallel reviews before the artifact transitions to Accepted.

3. **Enable validation at both layers.** Add `strategy/v1` to the
   `shirabe validate` Formats map so the CLI validates locally; the
   existing reusable `validate-docs.yml` workflow then activates the
   same checks in CI for both shirabe and downstream adopters.

4. **Close the three open questions from the brief.** Take positions
   on acceptance trigger, Sunset semantics, and Building-Blocks
   granularity, grounded in existing artifact-type precedents and
   recorded in this PRD's Decisions and Trade-offs section.

## User Stories

**As a strategy author at medium-term defensibility altitude**, I
want to invoke `/strategy` cold against a fresh repo so that I can
draft a strategic document without having to read prior examples
and reverse-engineer the format.

**As a strategy author working through the phased skill**, I want
Phase 4's jury to catch structural and altitude defects before the
document transitions to Accepted, so that strategic documents land
with the same quality gating other artifact types get.

**As a ROADMAP author**, I want to declare `upstream:
docs/strategies/STRATEGY-<name>.md` in my roadmap's frontmatter and
have the reference resolve cleanly through the same upstream/downstream
graph the other artifact types use, so that medium-term defensibility
work integrates with existing tactical chains without special-casing.

**As a shirabe adopter who pins the reusable doc-validation
workflow**, I want STRATEGY validation to activate automatically
when I bump the pinned shirabe release, so that my consumer repo
catches STRATEGY format defects on PR without my needing to author
custom validation logic.

**As a reviewer of a STRATEGY PR**, I want CI to fail when the
document is missing a required section, has an invalid status, or
includes a visibility-gated section in a public repo, so that I
don't have to verify structural correctness by hand on every
strategic document.

## Requirements

### Functional Requirements

**R1: STRATEGY artifact type definition.** The format reference
file at `skills/strategy/references/strategy-format.md` defines
`schema: strategy/v1` with the following frontmatter:

- Required fields:
  - `status` — lifecycle state; string matching one of the valid
    statuses named in R4.
  - `bet` — paragraph-length YAML literal block scalar (`|`)
    articulating the falsifiable hypothesis the strategy commits
    to. Same value the Defensibility Thesis section elaborates in
    prose.
  - `scope` — string enum, one of `project` or `org`, identifying
    whether the bet operationalizes a project-level VISION or an
    org-level VISION.
- Optional fields: `upstream` (path to an upstream VISION, possibly
  cross-repo using the `owner/repo:path` convention defined in
  `references/cross-repo-references.md`).

**R2: Required sections.** STRATEGY documents include the following
top-level sections, in order:

1. Status
2. Strategic Context
3. Defensibility Thesis
4. Building Blocks
5. Coordination Dependencies
6. Bet-Specific Falsifiability
7. Non-Goals
8. Downstream Artifacts

**R3: Optional sections.** STRATEGY documents may additionally
include:

- **Open Questions** (Draft status only; must be empty or removed
  before Draft → Accepted transition)
- **Competitive Considerations** (private repos only; see R7)
- **Decisions and Trade-offs** (records strategic decisions with
  alternatives and reasoning, mirroring the PRD convention)

**R4: Lifecycle states and transitions.** STRATEGY uses the
VISION-style four-state lifecycle:

| State | Meaning | Transition Trigger |
|-------|---------|--------------------|
| Draft | Under development; may have open questions | Created by `/strategy` |
| Accepted | Bet locked; structural and altitude jury PASS recorded | Phase 4 jury all-PASS + explicit human approval |
| Active | Downstream work has started; strategy is being operationalized | Manual transition via `skills/strategy/scripts/transition-status.sh`, invoked when the first downstream artifact (ROADMAP or DESIGN) referencing this STRATEGY transitions to Active |
| Sunset | Bet invalidated, pivoted, or abandoned | Manual transition via `skills/strategy/scripts/transition-status.sh` with reason recorded; not automatic on downstream completion |

The transition script follows the per-skill convention established
by `skills/vision/scripts/transition-status.sh` and equivalents in
`/prd`, `/roadmap`, and `/design`. STRATEGY does not introduce
cross-repo graph-watching infrastructure — transitions are operator-
invoked, consistent with the strategy's core-layer "ships using
current shirabe patterns" constraint.

**R5: `/strategy` skill structure.** The skill is a plain-English
SKILL.md at `skills/strategy/SKILL.md` with phase files at
`skills/strategy/references/phases/phase-<N>-<name>.md`. Phase
structure mirrors `/vision` and `/decision`:

- Phase 0: Setup (entry mode, upstream detection, wip/ initialization)
- Phase 1-3: Discovery, drafting, structural fill
- Phase 4: Jury validate (three parallel reviewers; see R6)
- Phase 5: Finalize (status transition, cleanup, PR)

The skill performs the Draft → Accepted status change in code after
the user explicitly approves via the standard AskUserQuestion
finalization dialogue (mirroring `/vision` Phase 4.6 and `/prd`
finalization). Jury PASS is a necessary precondition for the
approval prompt; jury PASS alone does not transition status.

**R6: Phase 4 jury structure.** Phase 4 spawns three parallel
review agents (using the Agent tool with `run_in_background: true`,
matching `/vision` Phase 4.1), each writing a verdict to
`wip/research/strategy_<topic>_phase4_<role>.md`:

- **Bet quality reviewer.** Verifies the Defensibility Thesis names
  a genuine falsifiable hypothesis with explicit invalidation
  conditions. Verifies the Bet-Specific Falsifiability section names
  load-bearing claims and corrective actions per direction.
- **Altitude reviewer.** Verifies the document operates at
  medium-term defensibility (carries forward upstream VISION
  content without re-justifying the long-term thesis; defers
  sequenced feature decomposition to a downstream ROADMAP). Applies
  the Building Blocks granularity rubric (see R6.1).
- **Structural format reviewer.** Verifies all required sections
  are present and in order; frontmatter fields and status value are
  valid; Competitive Considerations honors the visibility rule;
  Downstream Artifacts entries are durable paths (not `wip/...`,
  not private-from-public references).

Verdict aggregation matches `/vision` Phase 4.3: all three PASS to
proceed; 1-2 FAIL with minor issues fixed in place by the authoring
agent with a brief user-facing summary; any FAIL with significant
issues surfaces to user via AskUserQuestion, with the option to loop
back to drafting (Phase 3) for substantial rework.

**R6.1: Building Blocks granularity rubric.** The altitude reviewer
applies the following objective criteria:

- **Block count.** 5-8 Building Blocks is typical. Documents with
  fewer than 3 blocks risk being under-decomposed (likely a single
  block masquerading as a strategy); documents with more than 10
  blocks risk being a roadmap in disguise.
- **Downstream-artifact ratio.** Each Building Block should map to
  1-2 downstream design docs minimum. Blocks with no plausible
  downstream design are framing statements rather than coherent
  units of work; blocks that decompose into 5+ design docs are
  likely conflating multiple blocks.
- **Scope coherence.** Single-product blocks are the norm.
  Cross-product blocks (spanning 2 repos) are permitted but should
  be exceptional (under 20% of total). Blocks that span 3 or more
  repos are signals that the strategy is two strategies sharing a
  document and warrant decomposition.

The specific count range (5-8), downstream-fanout ratio (1-2 per
block minimum), and cross-product threshold (under 20%) are the
default rubric, extrapolated from limited proof-by-example
evidence available at PRD-authoring time. The rubric is itself
revisable as jury verdict patterns accumulate; the format reference
file MAY override these defaults once empirical evidence supports
tighter or looser bounds. Revisions belong in the format reference
file (not the PRD), so the rubric tracks the artifact's evolution
without requiring a PRD amendment.

**R7: Visibility-gated Competitive Considerations section.**
STRATEGY documents may include a `Competitive Considerations`
section, but only in private repos. The same enforcement pattern
VISION uses for its `Competitive Positioning` and `Resource
Implications` sections applies: a custom check in
`internal/validate/checks.go` rejects the section in public-visibility
contexts unless `cfg.Visibility == "private"`. The shirabe `validate`
CLI accepts a `--visibility` flag (already implemented for VISION)
that this check reads.

**R8: `shirabe validate` Formats-map entry.** Add `strategy/v1` to
the `Formats` map in `internal/validate/formats.go`:

```go
"strategy/v1": {
    Name:          "Strategy",
    Prefix:        "STRATEGY-",
    SchemaVersion: "strategy/v1",
    RequiredFields: []string{"status", "bet", "scope"},
    ValidStatuses:  []string{"Draft", "Accepted", "Active", "Sunset"},
    RequiredSections: []string{
        "Status",
        "Strategic Context",
        "Defensibility Thesis",
        "Building Blocks",
        "Coordination Dependencies",
        "Bet-Specific Falsifiability",
        "Non-Goals",
        "Downstream Artifacts",
    },
},
```

The existing `DetectFormat` longest-prefix-match routing picks up
`STRATEGY-*.md` files automatically. Checks FC01 (required fields),
FC02 (valid statuses), FC03 (frontmatter status matches body
Status section), and FC04 (required sections present) activate with
no additional Go code beyond the map entry. The custom R7 check
(Competitive Considerations visibility gating) requires a small
addition to the format-dispatch switch in `ValidateFile`.

**R9: CI validation enablement.** The reusable `validate-docs.yml`
workflow in `.github/workflows/` shells out to `shirabe validate`
on PR-changed files matching its `paths:` filter. No workflow code
changes are required for STRATEGY validation to activate; the
Formats-map entry (R8) is the load-bearing change. Two operational
obligations follow:

- **Shirabe self-caller** (`validate-shirabe-docs.yml`) already
  path-filters on `docs/**`, so it picks up
  `docs/strategies/STRATEGY-*.md` automatically.
- **Release-notes obligation.** The shirabe release that ships the
  Formats-map entry must call out that adopter workflows
  path-filtering narrowly (e.g., `docs/visions/**`,
  `docs/roadmaps/**`) need to widen the filter to include
  `docs/strategies/**` to pick up STRATEGY documents on PR.

**R10: Shirabe CLAUDE.md guidance.** Add a short paragraph to
`public/shirabe/CLAUDE.md` (the planning-context section) explaining
when to reach for STRATEGY versus VISION, ROADMAP, or PRD. The
guidance covers the altitude framing (medium-term defensibility
between VISION and ROADMAP) and the trigger heuristic (work that
operationalizes a piece of an upstream VISION without pivoting the
long-term thesis).

This PRD scopes the guidance to shirabe's own CLAUDE.md only.
Downstream adopters consuming the shirabe plugin inherit this
guidance through the loaded skill content; workspace-level
CLAUDE.md authoring for organizations running shirabe across
multiple repos is downstream design territory, not a requirement
of this PRD.

### Non-Functional Requirements

**R11: Skill structure consistency.** The `/strategy` skill follows
the existing shirabe skill conventions: SKILL.md is plain English,
phase files use progressive disclosure, intermediates live in
`wip/`, and the cleanup phase deletes `wip/` artifacts before the
PR can merge per the workspace-wide wip-hygiene rule documented at
`references/wip-hygiene.md`.

**R12: No new validation infrastructure.** All validation reuses
the existing `internal/validate/` package and the existing reusable
`validate-docs.yml` workflow. No new CLI binary, no parallel
validation pipeline, no new GitHub Actions reusable workflow.

**R13: Evals coverage.** The `/strategy` skill ships with evals at
`skills/strategy/evals/evals.json` covering the structural happy
path, a missing-required-section rejection path, an
invalid-status rejection path, and a public-repo
Competitive-Considerations rejection path. Evals follow the format
documented in shirabe's CLAUDE.md.

## Acceptance Criteria

- [ ] `skills/strategy/references/strategy-format.md` exists and
  defines the frontmatter schema, required/optional sections,
  lifecycle states, visibility rules, validation rules, and per-section
  quality guidance, following the skeleton of `vision-format.md` and
  `roadmap-format.md`.
- [ ] `skills/strategy/SKILL.md` exists and runs end-to-end against
  a fresh repo (manual smoke test plus evals scenarios passing).
- [ ] `skills/strategy/references/phases/` contains phase files for
  Phase 0 through Phase 5, with Phase 4 specifying the three-reviewer
  jury structure named in R6.
- [ ] `internal/validate/formats.go` includes the `strategy/v1`
  entry exactly as specified in R8.
- [ ] Running `shirabe validate` against a fresh
  `STRATEGY-<name>.md` with all required sections passes with exit
  code 0.
- [ ] Running `shirabe validate` against a `STRATEGY-<name>.md`
  with a missing required section fails with an FC04 error.
- [ ] Running `shirabe validate` against a `STRATEGY-<name>.md`
  with an invalid status value fails with an FC02 error.
- [ ] Running `shirabe validate --visibility public` against a
  `STRATEGY-<name>.md` containing a `Competitive Considerations`
  section fails with an R7-equivalent error.
- [ ] The shirabe self-caller workflow `validate-shirabe-docs.yml`
  runs `shirabe validate` against changed `docs/strategies/**`
  files on PR (no workflow file changes needed; the path filter
  already covers `docs/**`).
- [ ] `public/shirabe/CLAUDE.md` includes a paragraph in the
  planning-context section explaining when to use STRATEGY versus
  VISION, ROADMAP, or PRD.
- [ ] `skills/strategy/evals/evals.json` exists with at least four
  scenarios covering the cases named in R13, and `scripts/run-evals.sh
  strategy` reports all assertions passing.

## Out of Scope

This PRD scopes the `/strategy` skill, the STRATEGY artifact type,
and the validation infrastructure needed to make both first-class.
The scope explicitly excludes:

- **Chained-authoring path through a strategic parent skill.** Any
  parent skill that delegates to `/strategy` as a child phase
  (alongside vision-update, competitive analysis, and roadmap
  drafting) is downstream design territory. The standalone
  `/strategy` invocation is the primary mode at ship-time; chained
  invocation lands later as separate feature work.
- **`/brief` skill and the brief artifact type.** A `/brief` skill
  is named in the upstream brief as forthcoming work. This PRD does
  not codify the brief format; the present document just consumes
  the existing brief as upstream.
- **Review-time redirect mechanism.** STRATEGY documents will
  reference review-time redirect in their Coordination Dependencies
  sections, but the mechanism itself is downstream feature work
  that doesn't gate STRATEGY's introduction.
- **Auto-Sunset on downstream artifact completion.** Sunset is
  triggered by explicit human decision only (see Decisions and
  Trade-offs); the PRD deliberately rejects auto-Sunset wiring.
- **Migration of existing artifacts.** SE3 adds altitude without
  changing VISION, ROADMAP, PRD, DESIGN, or PLAN shape, naming,
  validation, or lifecycle. No retrofit of any existing artifact.
- **Adoption tracking outside the reference fleet.** Whether
  external shirabe adopters reach for STRATEGY is a downstream
  signal worth measuring but isn't a requirement that this PRD
  must satisfy.
- **Cross-repo STRATEGY upstream validation.** The `Plan` format's
  R6 check (verifies the `upstream:` path exists and is
  git-tracked) is not extended to STRATEGY in this PRD. STRATEGY's
  upstream may be cross-repo (a private VISION feeding a public
  STRATEGY, for example), which the existing R6 check would
  incorrectly reject. Cross-repo upstream validation is a separate
  initiative.

## Decisions and Trade-offs

### Decision 1: Acceptance trigger requires both jury PASS and human approval

**Decision.** Phase 4 jury PASS is a necessary precondition for
the Draft → Accepted transition, but human ratification via the
skill's standard finalization AskUserQuestion is also required.
The skill performs the status change in code after the user
explicitly approves; jury PASS alone does not transition status.

**Alternatives considered.**

- *Jury PASS alone triggers Accepted (no human approval step).*
  Faster, less ceremony. Rejected: removes the human review surface
  that protects against premature downstream consumption of an
  artifact the jury caught issues in, and inconsistent with the
  precedent every other artifact type sets.
- *Human approval alone (no jury required).* Removes the jury
  scaffolding. Rejected: defeats the purpose of having a jury, and
  inconsistent with the value the jury delivers for VISION today.

**Rationale.** VISION and PRD both follow this pattern: jury
review validates structural and quality defects in Phase 4, then
the skill surfaces findings and asks the user for explicit
approval before status changes. The user's approval is the
irreversible point where the artifact becomes locked for downstream
reference. Jury PASS de-risks the approval step but doesn't
eliminate human judgment — the user may request changes despite
jury verdicts, or add caveats to acceptance.

### Decision 2: Sunset triggered by explicit human decision only

**Decision.** STRATEGY uses Sunset (mirroring VISION) as its
terminal state, triggered by explicit human decision with reason
recorded (abandoned, pivoted, or invalidated). Sunset is not
triggered automatically by downstream artifact completion, upstream
VISION pivot, or any other state change.

**Alternatives considered.**

- *Auto-Sunset when all Downstream Artifacts reach Done.* Simpler
  for tooling; the strategy "completes" when its operationalization
  finishes. Rejected: conflates completion of implementation with
  invalidation of the strategic thesis. The bet can remain valid
  long after the building blocks ship; another strategy can build
  on a still-active prior one.
- *Use Done as the terminal state (mirroring ROADMAP).* Rejected:
  ROADMAP's Done semantic is "all features shipped," which is
  appropriate for sequenced feature work but wrong for a falsifiable
  bet that can be invalidated by external events. STRATEGY's
  terminal-state semantic matches VISION's, not ROADMAP's.

**Rationale.** STRATEGY sits at medium-term defensibility altitude,
between VISION (long-term, years) and ROADMAP (sequenced features).
Both VISION and STRATEGY make falsifiable bets; when the bet fails
or the upstream framing changes, the document itself becomes
invalid — which is why Sunset (not Done) is semantically correct.
ROADMAP's Done is appropriate for sequenced feature work where
completion is completion; STRATEGY's lifecycle terminates on
invalidation, not implementation completion.

### Decision 3: Building Blocks granularity uses count + downstream-fanout + scope criteria

**Decision.** The altitude reviewer applies a three-part rubric to
Building Blocks: (1) count range 5-8 typical; (2) downstream-artifact
ratio of 1-2 design docs per block minimum (no fanout = framing
statement, not block; fanout of 5+ = block decomposition needed);
(3) scope coherence (single-product is the norm; cross-product
permitted but under 20% of total; 3+ repos signals two strategies
in one document).

**Alternatives considered.**

- *No rubric (reviewer applies subjective judgment).* Rejected:
  jury verdicts must be repeatable across reviewers and over time.
  "Feels right-sized" doesn't survive author appeals.
- *Count range only.* Simpler. Rejected: a strategy with the right
  count but with blocks that are all framing statements with no
  decomposition would pass the count check while failing the
  intent.
- *Downstream-fanout only.* Rejected: requires the strategy author
  to have already planned downstream design docs at strategy-time,
  which inverts the natural causal order (strategy precedes design).
  The 1-2 minimum is a *plausibility* check ("does this block have
  plausible decomposition?"), not a precondition that designs
  exist yet.

**Rationale.** The rubric makes the altitude reviewer's check
testable: a block with no plausible design follow-up is a framing
statement, not a building block; a block that decomposes into many
designs is multiple blocks conflated. Scope coherence catches the
"two strategies sharing a document" failure mode that would
otherwise hide behind the count check. The specific numeric defaults
(5-8 count, 1-2 designs per block, under-20% cross-product) are
extrapolated from limited proof-by-example evidence and are
revisable via the format reference file (see R6.1) as jury verdict
patterns accumulate — the PRD does not lock them as permanent.

### Decision 4: Standalone /strategy skill, not in-charter authoring

**Decision.** SE3 ships a standalone `/strategy` skill rather than
an in-`/charter` authoring integration. The upstream brief
(`docs/briefs/BRIEF-shirabe-strategy-skill.md`) narrowed the
authoring-path choice to the standalone skill; this PRD records
the rationale so the choice is auditable downstream.

**Alternatives considered.**

- *In-`/charter` authoring integration.* A `/charter` parent skill
  delegates to a `/strategy` phase. Defers the standalone-skill
  cost; rides charter's plumbing. Rejected for this PRD: `/charter`
  is downstream feature work, and making STRATEGY authoring
  contingent on `/charter` shipping first introduces an ordering
  dependency the core layer is designed to avoid.
- *Both — ship standalone first, extend `/charter` later.*
  Compatible with the strategic chain's eventual shape (`/charter`
  delegates to `/strategy` as a child phase). Not adopted in this
  PRD because the `/charter` integration is downstream design work;
  this PRD scopes only the standalone-skill phase. Nothing in the
  standalone design precludes a later `/charter` integration.

**Rationale.** SE3 is a core-layer feature. Core-layer features ship
using current shirabe patterns (loadable plain-English SKILL.md
following `/vision` and `/decision` precedent) without depending on
later-shipping infrastructure. The standalone `/strategy` skill
satisfies that constraint; the in-`/charter` path would create an
ordering dependency that contradicts the layering.

## Downstream Artifacts

Forthcoming work flowing from this PRD:

- **`DESIGN-shirabe-strategy-skill.md`** (in `docs/designs/current/`).
  Implementation specifics — file layouts under
  `skills/strategy/`, phase file contents, the Go-side `FormatSpec`
  literal and any associated test fixtures, the R7-equivalent
  custom-check addition, and the CLAUDE.md guidance text. Picks up
  the Decisions and Trade-offs positions and operationalizes them.
- **`skills/strategy/scripts/transition-status.sh`** — per-skill
  lifecycle transition script following the precedent of
  `skills/vision/scripts/transition-status.sh` and equivalents in
  `/prd`, `/roadmap`, and `/design`. Handles Draft → Accepted,
  Accepted → Active, Active → Sunset, and any downgrade transitions
  the format reference file authorizes.
- **Release notes** for the shirabe version that ships the
  Formats-map entry, calling out the path-filter widening adopters
  may need to apply (per R9). Authored as part of the shirabe
  release that lands these changes, not as a PR-time check.
- **Implementation issues** — created from the design via `/plan`,
  covering skill authoring, format-reference authoring,
  validate-CLI changes, transition-script authoring, CLAUDE.md
  update, evals authoring, and the release-notes entry.

## Related

- **Upstream brief:** `docs/briefs/BRIEF-shirabe-strategy-skill.md`
  (currently in review on the branch this PRD is stacked on).
- **Precedents the artifact type mirrors:** VISION
  (`skills/vision/`), `/vision` Phase 4 jury pattern at
  `skills/vision/references/phases/phase-4-validate.md`.
- **Validation precedents:**
  `internal/validate/formats.go` (Formats-map pattern),
  `internal/validate/checks.go` (visibility-gating custom check
  precedent for the R7-equivalent in R7).
- **Cross-repo reference rules:** `references/cross-repo-references.md`
  (governs how STRATEGY's `upstream:` value resolves when the
  upstream lives in a different repo).
- **wip hygiene:** `references/wip-hygiene.md` (governs the
  `/strategy` skill's intermediate-artifact cleanup obligation).
