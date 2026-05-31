---
schema: prd/v1
status: Done
problem: |
  shirabe ships seven first-class artifact types — VISION, STRATEGY,
  ROADMAP, BRIEF, PRD, DESIGN, PLAN — each with a loadable skill,
  format reference, Phase 4 jury, and `shirabe validate` CLI coverage.
  Competitive analysis (COMP) is recognized only by example: prior
  COMP documents have been authored, and a workspace-level skill
  outside shirabe carries the format reference. Authors reach the
  artifact type indirectly through `/explore`'s produce phase, with
  no shirabe-native entry point and no validation discipline. The
  strategic chain's parent skill `/charter` documents an optional
  competitive sub-phase but has no child to delegate to, so the
  competitive framing step is documented yet unenforced.
goals: |
  COMP becomes a first-class shirabe artifact type alongside VISION,
  STRATEGY, ROADMAP, BRIEF, PRD, DESIGN, and PLAN, with the same
  shape of infrastructure each of the others has: a loadable phased
  `/comp` skill, a format reference resident in shirabe, a Phase 4
  jury, `shirabe validate` CLI coverage for `comp/v1`, and CI
  validation through the existing reusable workflow. Visibility
  enforcement layers at three independent points (skill refusal,
  validate-CLI, CI guardrail) so COMP's private-only convention is
  enforced regardless of which path an author takes. The `/charter`
  competitive sub-phase gets a real child to delegate to through a
  defined contract.
upstream: docs/briefs/BRIEF-shirabe-comp-skill.md
---

# PRD: shirabe-comp-skill

## Status

Done

This PRD picks up the requirements work scoped by
`docs/briefs/BRIEF-shirabe-comp-skill.md`. It owns the artifact-format
details, the `/comp` skill structure, the Phase 4 jury rubric, the
`shirabe validate` extension, the visibility enforcement architecture,
the `/charter` delegation contract, and CI activation. Implementation
(the skill body, the format-reference content, the Go-side Formats
map entry, the custom visibility check, the transition script) lands
in a downstream DESIGN doc plus implementation issues.

The PRD closes the five open questions the brief raised: lifecycle
ladder, jury reviewer count and rubric, visibility enforcement
implementation, format-spec source of truth, and the `/charter`
delegation contract shape. Positions are recorded in the Decisions
and Trade-offs section, grounded in existing artifact-type
precedents. Three of the five decisions are reopened as
architectural alternatives the downstream design should re-litigate
(visibility enforcement mechanism, jury structure shape, and format
source of truth) because their implementation surfaces span Go code,
skill structure, and content authoring; the PRD picks a preferred
direction without locking the design.

## Problem Statement

shirabe recognizes seven artifact types today — VISION, STRATEGY,
ROADMAP, BRIEF, PRD, DESIGN, PLAN — each with a dedicated loadable
skill, a format reference at
`skills/<name>/references/<name>-format.md`, a Phase 4 jury where
applicable, and `shirabe validate` Formats-map coverage. The taxonomy
spans long-term aspiration through implementation steps.

Competitive analysis sits outside this taxonomy as an artifact
category proven by example: prior COMP documents have been authored,
and a format reference for the type lives in an existing
workspace-level skill that captures the COMP shape. The artifact type
works in practice. What's missing is a shirabe-native authoring path.
An author who wants to write competitive analysis today reaches it
indirectly through `/explore`'s produce phase, or by reading prior
examples and hand-authoring the structure.

The gap matters more now because the strategic chain has a parent
skill — `/charter` — whose architecture commits to an optional
competitive-analysis phase between vision and strategy. `/charter`'s
brief and design name competitive framing as a private-repo
sub-phase the chain can route into when the conversation warrants
it. There is no child skill to delegate to. `/charter` ships against
this gap by leaving the competitive sub-phase documented but
unenforced: the chain skips competitive framing silently in public
repos and has no `/comp` to invoke privately.

The proof-of-concept exists already (in the form of competitive
documents authored at this altitude in practice), and the structural
pattern is stable. What's missing is durability:

- **No skill entry point.** An author who wants to author competitive
  analysis has no `/comp` to load. They invoke `/explore` and rely on
  its produce-phase routing, or they read prior examples and
  reverse-engineer the structure.
- **No shirabe-resident format reference.** The COMP format lives in
  a workspace-level skill outside shirabe's
  `skills/<type>/references/` layout. Adopters who reach shirabe
  through the marketplace see no COMP format spec at all.
- **No validation discipline.** `shirabe validate` does not yet
  recognize a `comp/v1` schema. Lifecycle transitions lack tooling
  enforcement, and the private-only visibility rule for COMP relies
  on author and reviewer discipline rather than a CI check.
- **No parent-skill integration contract.** `/charter`'s competitive
  sub-phase has no defined delegation contract to bind against;
  without a `/comp` child, the sub-phase is a placeholder.

Each of these is small in isolation. Together they're the gap
between "competitive analysis can be authored" and "competitive
analysis is first-class shirabe infrastructure."

## Goals

1. **Codify COMP as a first-class artifact type.** Define the
   frontmatter schema (`schema: comp/v1`), required and optional
   sections, lifecycle states, and visibility rules — all in a format
   reference that follows the existing `strategy-format.md`,
   `prd-format.md`, and `brief-format.md` skeleton.

2. **Author `/comp` as a loadable phased skill.** Follow the
   `/strategy` and `/brief` precedent: plain-English SKILL.md, phase
   files under `references/phases/`, progressive disclosure,
   wip/-based intermediates, and a Phase 4 jury that aggregates
   parallel reviews before the artifact transitions to Accepted.

3. **Enable validation at both layers.** Add `comp/v1` to the
   `shirabe validate` Formats map so the CLI validates locally; the
   existing reusable `validate-docs.yml` workflow then activates the
   same checks in CI for both shirabe and downstream adopters.

4. **Enforce private-only visibility at three layers.** The `/comp`
   skill refuses to author in public repos at its setup phase;
   `shirabe validate` rejects `comp/v1` files in public-repo paths;
   the reusable CI workflow inherits the validate-CLI check so PRs
   that commit a COMP file in a public repo fail validation.

5. **Define the `/charter` → `/comp` delegation contract.** Specify
   the inputs `/comp` accepts when invoked as a child, the outputs
   it returns, and the failure modes the parent skill handles so
   `/charter`'s competitive sub-phase has a stable interface.

6. **Close the five open questions from the brief.** Take positions
   on lifecycle ladder, jury reviewer count and rubric, visibility
   enforcement implementation, format-spec source of truth, and the
   `/charter` delegation contract shape. Record alternatives and
   rationale in the Decisions and Trade-offs section.

## User Stories

**As a competitive-analysis author in a private repo**, I want to
invoke `/comp` cold with a short topic description so that I can
draft a competitive analysis without having to read prior examples
and reverse-engineer the format.

**As a competitive-analysis author working through the phased
skill**, I want Phase 4's jury to catch content-quality defects
(marketing language, weak opportunity framing) and structural
defects before the document transitions to Accepted, so that COMP
documents land with the same quality gating other artifact types
get.

**As a `/charter` user reaching the optional competitive sub-phase
in a private repo**, I want `/charter` to delegate to `/comp` with
a defined contract (scoped topic, upstream STRATEGY or VISION
reference, expected return shape) so that competitive framing
becomes a durable artifact the chain carries forward into the
downstream `/strategy` phase.

**As an author who invokes `/comp` in a public repo by mistake or
through a misrouted `/charter` call**, I want the skill to refuse
at setup with a clear redirect to alternative artifact types (a
design doc with competitive findings folded into context, or a
spike report), so that no COMP file ever gets committed to a public
repo.

**As a reviewer of a COMP PR in a private repo**, I want CI to fail
when the document is missing a required section, has an invalid
status, or is somehow committed in a public-repo context, so that
I don't have to verify structural correctness or visibility
discipline by hand on every competitive-analysis document.

**As a shirabe adopter who pins the reusable doc-validation
workflow**, I want COMP validation to activate automatically when I
bump the pinned shirabe release, so that my consumer repo catches
COMP format defects on PR without my needing to author custom
validation logic.

**As an adopter whose workflow path-filters narrowly on artifact
directories**, I want shirabe's release notes for the version that
ships `comp/v1` to call out that I need to widen my path filter to
include `docs/competitive/**`, so that my CI picks up COMP files on
PR without my needing to discover the gap empirically.

## Requirements

### Functional Requirements

**R1: COMP artifact type definition.** The format reference file at
`skills/comp/references/comp-format.md` defines `schema: comp/v1`
with the following frontmatter:

- Required fields:
  - `status` — lifecycle state; string matching one of the valid
    statuses named in R4.
  - `problem` — paragraph-length YAML literal block scalar (`|`)
    articulating the market segment or competitive question the
    analysis addresses. Same value the Market Overview section
    elaborates in prose.
  - `scope` — string enum, one of `market` or `tool`, identifying
    whether the analysis covers a market segment (multiple
    competitors compared on shared dimensions) or a single
    adjacent tool (one-to-one comparison against shirabe or a
    shirabe-adjacent project).
- Optional fields: `upstream` (path to an upstream STRATEGY or
  VISION, possibly cross-repo using the `owner/repo:path`
  convention defined in `references/cross-repo-references.md`).

**R2: Required sections.** COMP documents include the following
top-level sections, in order:

1. Status
2. Market Overview
3. Competitors
4. Comparative Matrix
5. Opportunities
6. Implications
7. References

The Market Overview frames the segment and its key competitive
dimensions. The Competitors section provides per-competitor analysis
under H3 sub-headings. The Comparative Matrix presents a side-by-side
table on shared dimensions. Opportunities names gaps the analysis
surfaces. Implications connects findings to product or technical
choices. References lists external sources cited.

**R3: Optional sections.** COMP documents may additionally include:

- **Open Questions** (Draft status only; must be empty or removed
  before Draft → Accepted transition)
- **Decisions and Trade-offs** (records framing decisions the
  analysis made, mirroring the PRD/STRATEGY convention)
- **Downstream Artifacts** (added when STRATEGY or DESIGN docs cite
  this COMP as an input)

**R4: Lifecycle states and transitions.** COMP uses the BRIEF-style
three-state lifecycle:

| State | Meaning | Transition Trigger |
|-------|---------|--------------------|
| Draft | Under development; may have open questions | Created by `/comp` |
| Accepted | Analysis locked; jury PASS recorded; ready for downstream reference | Phase 4 jury all-PASS + explicit human approval |
| Done | A downstream STRATEGY, DESIGN, or other artifact has cited this COMP; or the analysis has been explicitly superseded | Manual transition via `skills/comp/scripts/transition-status.sh` |

The transition script follows the per-skill convention established
by `skills/brief/scripts/transition-status.sh`. COMP does not
introduce cross-repo graph-watching infrastructure — transitions are
operator-invoked, consistent with shirabe's core-layer "ships using
current shirabe patterns" constraint.

**R5: `/comp` skill structure.** The skill is a plain-English
SKILL.md at `skills/comp/SKILL.md` with phase files at
`skills/comp/references/phases/phase-<N>-<name>.md`. Phase structure
mirrors `/brief` and `/strategy`:

- Phase 0: Setup (entry mode, visibility detection with early
  refusal in public repos, upstream detection, wip/ initialization)
- Phase 1: Scope (conversational scoping of the market segment or
  tool to be analyzed)
- Phase 2: Discover (per-competitor research, comparative dimension
  identification)
- Phase 3: Draft (Market Overview, per-competitor entries,
  Comparative Matrix, Opportunities, Implications)
- Phase 4: Validate (jury review; see R6)
- Phase 5: Finalize (status transition, cleanup, PR)

The skill performs the Draft → Accepted status change in code after
the user explicitly approves via the standard finalization
AskUserQuestion dialogue (mirroring `/strategy` and `/brief`). Jury
PASS is a necessary precondition for the approval prompt; jury PASS
alone does not transition status.

**R6: Phase 4 jury structure.** Phase 4 spawns three parallel review
agents (using the Agent tool with `run_in_background: true`, matching
`/strategy` and `/prd` precedent), each writing a verdict to
`wip/research/comp_<topic>_phase4_<role>.md`:

- **Competitive-framing reviewer.** Verifies per-competitor entries
  read as frank strengths-and-weaknesses comparisons rather than
  marketing language. Verifies Opportunities names concrete gaps
  rather than aspirational language. Verifies Implications connects
  findings to specific product or technical choices the analysis
  enables, rather than restating Opportunities in different prose.
- **Content-quality reviewer.** Verifies the Market Overview names
  competitive dimensions explicitly and the Comparative Matrix
  applies the same dimensions across competitors. Verifies sources
  cited in References are external (no private workspace
  references), accessible, and dated where relevant.
- **Structural-format reviewer.** Verifies all required sections
  are present and in order; frontmatter fields and status value
  are valid; Open Questions is empty or removed if status is
  Accepted; per-competitor entries use H3 sub-headings under the
  Competitors section; the Comparative Matrix is a Markdown table.

Verdict aggregation matches `/strategy` Phase 4.3: all three PASS
to proceed; 1-2 FAIL with minor issues fixed in place by the
authoring agent with a brief user-facing summary; any FAIL with
significant issues surfaces to user via AskUserQuestion, with the
option to loop back to drafting (Phase 3) for substantial rework.

The three-reviewer choice (versus two-reviewer parity with /brief)
is recorded in Decision 2 with the alternatives. The downstream
DESIGN doc may revise the reviewer count if implementation surfaces
warrant; this requirement specifies the default.

**R7: Visibility enforcement at three layers.** COMP is private-only
by convention. Enforcement happens independently at three layers so
no single bypass weakens the rule:

- **Skill setup-phase refusal.** Phase 0 of the `/comp` skill detects
  the repo's visibility (per the existing detection convention from
  CLAUDE.md `## Repo Visibility` and the `private/` / `public/` path
  heuristic). If visibility is Public, the skill refuses to author
  the artifact, names the rule (COMP is private-only), and suggests
  alternative artifact types: a design doc with competitive findings
  folded into context, or a spike report investigating a specific
  technical approach. No COMP file is created.
- **Validate-CLI rejection.** `shirabe validate` reads the
  `--visibility` flag (already implemented for VISION's
  Competitive-Positioning section gating) and rejects any `comp/v1`
  file outright when `cfg.Visibility == "public"`. The check fires
  before the per-section checks so misuse is surfaced with a clear
  whole-doc visibility error rather than a downstream missing-section
  cascade.
- **CI guardrail through the reusable workflow.** The existing
  reusable `validate-docs.yml` workflow shells out to
  `shirabe validate` with the repo's declared visibility. The
  validate-CLI rejection (above) therefore propagates to CI without
  additional workflow code changes.

The validate-CLI mechanism — schema-level whole-doc visibility
gating versus path-based visibility check versus generic visibility
framework — is recorded in Decision 3 as a deliberate decision
surface for the downstream DESIGN.

**R8: `shirabe validate` Formats-map entry.** Add `comp/v1` to the
`Formats` map in `internal/validate/formats.go`:

```go
"comp/v1": {
    Name:           "Competitive Analysis",
    Prefix:         "COMP-",
    SchemaVersion:  "comp/v1",
    RequiredFields: []string{"status", "problem", "scope"},
    ValidStatuses:  []string{"Draft", "Accepted", "Done"},
    RequiredSections: []string{
        "Status",
        "Market Overview",
        "Competitors",
        "Comparative Matrix",
        "Opportunities",
        "Implications",
        "References",
    },
},
```

The existing `DetectFormat` longest-prefix-match routing picks up
`COMP-*.md` files automatically. Checks FC01 (required fields), FC02
(valid statuses), FC03 (frontmatter status matches body Status
section), and FC04 (required sections present) activate with no
additional Go code beyond the map entry. The R7 whole-doc visibility
check requires a small addition to the format-dispatch switch in
`ValidateFile`, modeled on the existing VISION section-visibility
custom check.

**R9: CI validation enablement.** The reusable `validate-docs.yml`
workflow shells out to `shirabe validate` on PR-changed files
matching its `paths:` filter. No workflow code changes are required
for COMP validation to activate; the Formats-map entry (R8) is the
load-bearing change. Two operational obligations follow:

- **Shirabe self-caller** (`validate-shirabe-docs.yml`) already
  path-filters on `docs/**`, so it picks up
  `docs/competitive/COMP-*.md` automatically.
- **Release-notes obligation.** The shirabe release that ships the
  Formats-map entry must call out that adopter workflows
  path-filtering narrowly (e.g., `docs/briefs/**`,
  `docs/strategies/**`) need to widen the filter to include
  `docs/competitive/**` to pick up COMP documents on PR.

**R10: `/charter` → `/comp` delegation contract.** The skill exposes
a defined invocation surface when called from a parent skill (today,
`/charter`'s optional competitive sub-phase):

- **Inputs `/comp` accepts:** a topic slug (kebab-case, matching
  `^[a-z0-9-]+$`), an optional `--upstream <path>` argument pointing
  at the parent's STRATEGY or VISION document, and an optional
  parent-orchestration sentinel in `wip/<parent>_<topic>_state.md`
  carrying handoff metadata.
- **Outputs `/comp` returns:** the artifact path
  (`docs/competitive/COMP-<topic>.md`), the artifact's final status
  (`Draft` or `Accepted`), and a one-paragraph summary the parent
  can inject into its downstream phase prose.
- **Failure modes the parent handles:**
  - *Public-repo refusal:* `/comp` exits at setup with a refusal
    diagnostic. The parent records the skip in its state and
    continues without the competitive sub-phase.
  - *Validation failure on forced acceptance:* `/comp` surfaces the
    FC error from `shirabe validate` and exits without ratifying.
    The parent halts and prompts the user to resolve before
    continuing.
  - *User rejection at Phase 4:* `/comp` produces a discard commit
    per `/prd`'s Reject branch precedent and exits. The parent reads
    the discard commit from `git log` and routes to the same skip
    path as public-repo refusal.

This requirement specifies the `/comp` side of the contract. The
`/charter` side (its competitive sub-phase prose, the state-file
fields it reads, the decision branch that invokes `/comp`) lives in
`/charter`'s own scope.

**R11: Shirabe CLAUDE.md guidance.** Add a short paragraph to
`public/shirabe/CLAUDE.md` (the planning-context section or the
adjacent artifact-types listing) explaining when to reach for
`/comp` versus alternatives. The guidance covers the visibility
constraint (COMP is private-only; public-repo authors are redirected
to design docs with competitive findings folded in, or to spike
reports) and the typical trigger (a competitive conversation that
needs framing before a STRATEGY can commit to a bet, or a comparison
against an adjacent tool that informs a DESIGN decision).

### Non-Functional Requirements

**R12: Skill structure consistency.** The `/comp` skill follows the
existing shirabe skill conventions: SKILL.md is plain English, phase
files use progressive disclosure, intermediates live in `wip/`, and
the cleanup phase deletes `wip/` artifacts before the PR can merge
per the workspace-wide wip-hygiene rule documented at
`references/wip-hygiene.md`.

**R13: No new validation infrastructure.** All validation reuses
the existing `internal/validate/` package and the existing reusable
`validate-docs.yml` workflow. No new CLI binary, no parallel
validation pipeline, no new GitHub Actions reusable workflow. The
whole-doc visibility check is implemented as a custom check
alongside the existing VISION section-visibility check, not as a new
infrastructure layer.

**R14: Evals coverage.** The `/comp` skill ships with evals at
`skills/comp/evals/evals.json` covering the structural happy path,
a missing-required-section rejection path, an invalid-status
rejection path, and a public-repo whole-doc visibility rejection
path. Evals follow the format documented in shirabe's CLAUDE.md.

**R15: Format-spec authored fresh against shirabe conventions.** The
`comp-format.md` reference is authored to match the structural shape
of `strategy-format.md`, `prd-format.md`, and `brief-format.md`
(Frontmatter, Required Sections, Optional Sections, Lifecycle,
Validation Rules, Quality Guidance, Common Pitfalls). Prior
example COMP documents inform the content guidance but the file is
not a verbatim copy from any pre-existing format spec. This
requirement deliberately leaves the alternative reconciliation
strategies (verbatim port versus rewrite) as a design-level decision
recorded in Decision 4.

## Acceptance Criteria

- [ ] `skills/comp/references/comp-format.md` exists and defines the
  frontmatter schema, required and optional sections, lifecycle
  states, visibility rules, validation rules, and per-section
  quality guidance, following the skeleton of `strategy-format.md`
  and `brief-format.md`.
- [ ] `skills/comp/SKILL.md` exists and runs end-to-end against a
  fresh private repo (manual smoke test plus evals scenarios
  passing).
- [ ] `skills/comp/references/phases/` contains phase files for
  Phase 0 through Phase 5, with Phase 0 specifying the public-repo
  visibility refusal and Phase 4 specifying the three-reviewer jury
  structure named in R6.
- [ ] `skills/comp/scripts/transition-status.sh` exists and handles
  Draft → Accepted, Accepted → Done, and Draft → Done transitions
  following the precedent of `skills/brief/scripts/transition-status.sh`.
- [ ] `internal/validate/formats.go` includes the `comp/v1` entry
  exactly as specified in R8.
- [ ] `internal/validate/checks.go` includes a whole-doc visibility
  check for `comp/v1` that rejects the file when
  `cfg.Visibility == "public"`.
- [ ] Running `shirabe validate` against a fresh
  `COMP-<name>.md` with all required sections passes with exit code
  0 when invoked with `--visibility private`.
- [ ] Running `shirabe validate` against a `COMP-<name>.md` with a
  missing required section fails with an FC04 error.
- [ ] Running `shirabe validate` against a `COMP-<name>.md` with an
  invalid status value fails with an FC02 error.
- [ ] Running `shirabe validate --visibility public` against any
  `COMP-<name>.md` fails with the R7 visibility error before any
  per-section checks fire.
- [ ] The shirabe self-caller workflow `validate-shirabe-docs.yml`
  runs `shirabe validate` against changed `docs/competitive/**`
  files on PR (no workflow file changes needed; the path filter
  already covers `docs/**`).
- [ ] Invoking `/comp <topic>` in a public repo refuses at Phase 0
  with a redirect to alternative artifact types; no `COMP-*.md` file
  is created.
- [ ] Invoking `/comp <topic>` in a private repo runs end-to-end and
  produces a `docs/competitive/COMP-<topic>.md` artifact at Draft
  status with all required sections populated.
- [ ] When invoked with a `--upstream <path>` argument pointing at a
  STRATEGY or VISION document, `/comp` records the upstream in
  frontmatter and references it in the Market Overview.
- [ ] `public/shirabe/CLAUDE.md` includes a paragraph explaining
  when to use `/comp` versus alternatives, naming the private-only
  visibility constraint and the typical triggers.
- [ ] The shirabe release that ships `comp/v1` includes release notes
  calling out the `docs/competitive/**` path-filter widening
  obligation for adopter workflows.
- [ ] `skills/comp/evals/evals.json` exists with at least four
  scenarios covering the cases named in R14, and
  `scripts/run-evals.sh comp` reports all assertions passing.

## Out of Scope

This PRD scopes the `/comp` skill, the COMP artifact type, the
validation infrastructure needed to make both first-class, and the
`/comp` side of the `/charter` delegation contract. The scope
explicitly excludes:

- **`/charter` skill changes.** `/charter`'s competitive sub-phase
  prose, its visibility-detection logic, and the parent-side
  delegation flow live in `/charter`'s own scope and ship under its
  own artifact track. This PRD specifies only the `/comp` side of
  the contract.
- **Migration of existing competitive-analysis documents.** Prior
  COMP artifacts remain at their current paths under their current
  shape. If the format spec diverges from prior examples in detail,
  the downstream DESIGN names the reconciliation; this PRD does not
  commit to migration work.
- **Workspace-level COMP tooling deprecation.** Any existing
  workspace-level skill that carries the COMP format stays in place.
  Whether and when to consolidate after `/comp` ships is a
  downstream call, not a requirement of this PRD.
- **External-adopter behavior.** Whether external shirabe adopters
  reach for `/comp` in their own repos is a downstream signal worth
  measuring but isn't a requirement this PRD must satisfy.
- **`/explore` produce-phase rewiring.** `/explore`'s existing
  routing to competitive analysis continues to work. Whether
  `/comp`'s arrival warrants `/explore` changes is a separate
  scope.
- **Cross-repo COMP upstream validation.** The PLAN format's R6-style
  check (verifies the `upstream:` path exists and is git-tracked) is
  not extended to COMP in this PRD. COMP's upstream may be cross-repo
  (a private VISION feeding a private COMP, for example), which the
  existing check would handle inconsistently. Cross-repo upstream
  validation is a separate initiative across all artifact types.
- **Public-repo competitive-analysis-equivalent artifact.** If a
  public-repo need arises for an artifact that captures competitive
  framing without the private-only constraint, it ships as a separate
  artifact type. COMP is private-only; the redirect for public-repo
  use is to existing types (design docs, spike reports), not a
  parallel COMP variant.

## Known Limitations

- The visibility-enforcement layers are independent but not
  cryptographically separate; an author who runs `shirabe validate`
  with `--visibility private` against a file checked into a public
  repo can theoretically defeat the validate-CLI check. The CI
  guardrail closes this gap in the reusable workflow path by
  declaring the visibility from the repo's CLAUDE.md, but a
  bespoke CI setup that hardcodes `--visibility private` would
  bypass the check. Mitigation: the skill-level refusal and the
  CI default-visibility-from-CLAUDE.md path remain in effect; the
  bespoke-misuse failure mode is documented but not blocked.
- COMP is a point-in-time snapshot. Competitive landscapes change;
  a COMP at status Accepted from 18 months ago may be factually
  stale even though its lifecycle state suggests current relevance.
  The lifecycle does not encode freshness; the `Done` state is
  reached when downstream work cites the COMP, not when the
  analysis ages out. Authors and reviewers carry the
  point-in-time-snapshot caveat as a documentation discipline rather
  than a tooling enforcement.
- The R6 jury's competitive-framing reviewer applies subjective
  rubrics (marketing-language detection, opportunity substance,
  implications tie-back). Verdict consistency across reviewers
  depends on rubric clarity in the phase-4-validate.md reference.
  Treat the rubric as revisable as jury verdict patterns
  accumulate; revisions belong in the phase file, not in this PRD.

## Decisions and Trade-offs

### Decision 1: BRIEF-style three-state lifecycle

**Decision.** COMP uses `Draft → Accepted → Done` (mirroring BRIEF).
Draft is the authoring state; Accepted is reached when the Phase 4
jury PASSes and the user ratifies; Done is reached when a downstream
STRATEGY, DESIGN, or other artifact has cited the COMP or when the
COMP is explicitly superseded.

**Alternatives considered.**

- *Two-state (`Draft → Final`).* Matches prior COMP examples. Treats
  COMP as a terminal snapshot with no downstream-aware semantic.
  Rejected: leaves no signal that downstream work picked up the
  analysis, and the absence of an `Accepted` state forces the
  authoring skill to either skip the post-jury ratification step or
  invent a hybrid state outside the format. Inconsistent with every
  other shirabe artifact type, all of which separate "ready for
  downstream reference" from "downstream work has begun or completed."
- *Four-state (`Draft → Accepted → Active → Sunset`).* Matches
  STRATEGY and VISION. Rejected: the Active/Sunset semantics encode
  bet validity, which doesn't fit a point-in-time competitive
  snapshot. A COMP isn't invalidated by the competitor releasing a
  new version; it ages out as a snapshot but doesn't reverse.

**Rationale.** COMP is closer to BRIEF in semantic shape (framing
artifact, not falsifiable bet) than to STRATEGY/VISION. The
three-state ladder is the natural fit: authoring → ready-for-
downstream-reference → cited-or-superseded. The choice keeps the
transition script symmetric with BRIEF's and avoids inventing a
COMP-specific lifecycle shape.

### Decision 2: Three-reviewer Phase 4 jury

**Decision.** Phase 4 spawns three parallel review agents:
competitive-framing, content-quality, and structural-format. All
three PASS to ratify; 1-2 FAIL with minor issues get fixed inline;
any FAIL with significant issues loops back to Phase 3.

**Alternatives considered.**

- *Two-reviewer parity with /brief* (content-quality plus
  structural-format). Rejected: competitive-analysis content
  failures (marketing language masquerading as analysis,
  opportunities that read as aspirations rather than gaps,
  implications that don't tie back to product or technical choices)
  are distinct from the content-quality dimensions BRIEF reviews.
  Folding both into one reviewer either over-loads the
  content-quality role or leaves competitive-framing failures
  caught only by author discipline.
- *One reviewer (structural-format only).* Rejected: structural
  correctness without competitive-content review produces COMP
  documents that pass validation but read as marketing brochures.
  The structural-format reviewer alone catches the wrong defects.

**Rationale.** The competitive-framing failure mode is real and
documented in the upstream brief's Journey 4 ("the content-quality
reviewer challenges a competitor analysis that reads as marketing
language"). Splitting it from generic content-quality gives the
jury a reviewer whose rubric is explicitly tuned for the framing
defects competitive analysis is prone to. Three reviewers also
matches the /strategy and /prd precedent for artifact types where
content quality matters substantively, not just structurally.

**Architectural alternative left for /design.** The reviewer rubrics
themselves (specific marketing-language heuristics, opportunity-
substance criteria) are content the downstream DESIGN authors; this
PRD names the reviewer count and roles but leaves rubric specifics
for the design to settle.

### Decision 3: Schema-level whole-doc visibility gating

**Decision.** The validate-CLI visibility enforcement for COMP is
implemented as a schema-level whole-doc check: the `FormatSpec` for
`comp/v1` carries a private-only flag (or equivalent mechanism),
and `ValidateFile` checks the flag against `cfg.Visibility` before
running per-section checks. The check fires for any `comp/v1` file
regardless of path.

**Alternatives considered.**

- *Path-based visibility gating.* `docs/competitive/` is valid only
  in private repos; any file matching the path in a public repo
  fails validation. Simpler to implement (one path check, no
  schema flag), but couples enforcement to file location. An
  author who places a COMP file outside `docs/competitive/` would
  defeat the check. Rejected for the validate-CLI layer because
  shirabe's format detection is prefix-based (`COMP-*.md`), not
  path-based; using path for visibility but prefix for format is
  inconsistent.
- *Generic visibility-gated artifact framework.* Add a
  `RequiresVisibility []string` field to `FormatSpec` (e.g.,
  `["private"]`) and a generic check that reads it for any format.
  Most extensible — future artifact types can opt in by setting the
  field. Rejected as the initial implementation because no other
  current artifact type needs whole-doc visibility gating;
  generalizing the mechanism without a second consumer adds
  surface area without immediate payoff. The downstream DESIGN may
  choose to ship the schema-level flag in a generic shape (a single
  field on `FormatSpec` rather than a `comp/v1`-specific check) to
  leave the door open without committing to a full framework.

**Rationale.** Schema-level gating keeps the visibility rule
declarative (the `comp/v1` spec encodes "this artifact type is
private-only") rather than imperative (a separate check per
type). It's the natural extension of the existing VISION
section-visibility custom check pattern from per-section to
whole-doc, and it's prefix-based like the rest of format detection.

**Architectural alternative left for /design.** The exact mechanism
— a `comp/v1`-specific custom check function in `checks.go`, or a
generic `Private bool` (or `RequiresVisibility []string`) field on
`FormatSpec` consumed by a shared check — is a Go-side
implementation decision the downstream DESIGN settles. This PRD
names the layer (schema-level, not path-based) without locking the
field shape.

### Decision 4: Format spec authored fresh against shirabe conventions

**Decision.** `comp-format.md` is authored to match the structural
shape of `strategy-format.md`, `prd-format.md`, and `brief-format.md`.
Content guidance draws on prior COMP examples and any pre-existing
workspace-level format reference as input, but the file is not a
verbatim copy.

**Alternatives considered.**

- *Verbatim copy from the workspace-level skill that captures the
  COMP format.* Fastest. Rejected: workspace-level format
  references and shirabe-resident format references have different
  conventions (section ordering, frontmatter shape, validation-
  rules section format, quality-guidance density). A verbatim copy
  would import workspace-level shape into shirabe's
  `skills/<type>/references/` layout, creating a visible
  inconsistency.
- *Rewrite from scratch using prior COMP examples as input, ignoring
  the existing workspace-level format reference entirely.* Cleanest
  break, but discards prior dogfooding signal. Rejected: prior
  format choices encode lessons about what does and doesn't work
  for COMP authoring; ignoring them is wasteful.

**Rationale.** Shirabe's format-reference files have a stable
structural shape (Frontmatter, Required Sections, Optional Sections,
Lifecycle, Validation Rules, Quality Guidance, Common Pitfalls).
Authoring `comp-format.md` against that shape from the outset
produces a reference that reads consistently with the rest of
shirabe. Content guidance still benefits from prior workspace-level
work as input; the structural shape is shirabe-native.

**Architectural alternative left for /design.** The downstream
DESIGN decides exactly how much workspace-level format content to
port verbatim into the body of the new shirabe-resident format file
versus to rewrite from prior COMP example evidence. This PRD names
the structural skeleton without locking the content-porting
strategy.

### Decision 5: `/charter` delegation contract is `/comp`-side specified

**Decision.** R10 specifies the `/comp` side of the `/charter` →
`/comp` delegation contract: the inputs `/comp` accepts when invoked
as a child, the outputs it returns, and the failure modes the parent
handles. The `/charter` side (its competitive sub-phase prose, the
state-file fields it reads, the decision branch that invokes
`/comp`) lives in `/charter`'s own scope.

**Alternatives considered.**

- *Specify both sides in this PRD.* Tighter coupling, single source
  of truth for the contract. Rejected: `/charter` ships under its
  own artifact track with its own design and plan; co-specifying
  both sides here creates an ordering dependency between the two
  features' designs and forces this PRD to take positions on
  `/charter` internals it doesn't own.
- *Defer the contract entirely to `/charter`'s scope.* Cleanest
  separation, no overlap. Rejected: the `/comp` skill must know
  what inputs to accept and what outputs to return, regardless of
  which parent invokes it. The `/comp` side is load-bearing for the
  `/comp` skill's own structure.

**Rationale.** R10 names the freeze line between the two features:
`/comp` specifies what it accepts and returns; `/charter` specifies
when and how it invokes. The freeze line lets the two features
ship under independent artifact tracks without coordinating on a
single design document.

## Downstream Artifacts

Forthcoming work flowing from this PRD:

- **`DESIGN-shirabe-comp-skill.md`** (likely; lands in
  `docs/designs/current/`). Implementation specifics — file layouts
  under `skills/comp/`, phase file contents, the Go-side
  `FormatSpec` literal and the whole-doc visibility check
  implementation, the transition script, the CLAUDE.md guidance
  text. Picks up the Decisions and Trade-offs positions and
  operationalizes the three architectural alternatives surfaced
  here (jury rubric specifics, visibility-check field shape,
  format-content porting strategy).
- **`skills/comp/scripts/transition-status.sh`** — per-skill
  lifecycle transition script following the precedent of
  `skills/brief/scripts/transition-status.sh`. Handles Draft →
  Accepted, Accepted → Done, and Draft → Done.
- **Release notes** for the shirabe version that ships the
  Formats-map entry, calling out the path-filter widening adopters
  may need to apply (per R9). Authored as part of the shirabe
  release that lands these changes, not as a PR-time check.
- **Implementation issues** — created from the design via `/plan`,
  covering skill authoring, format-reference authoring,
  validate-CLI changes, visibility-check authoring,
  transition-script authoring, CLAUDE.md update, evals authoring,
  and the release-notes entry.

## Related

- **Upstream brief:** `docs/briefs/BRIEF-shirabe-comp-skill.md`
  (Accepted on this branch).
- **Closest precedent — promoting an example-proven type to
  first-class:** `docs/prds/PRD-shirabe-strategy-skill.md` and
  `docs/prds/PRD-shirabe-brief-skill.md`. Both PRDs ship the same
  shape this PRD ships: format reference, skill structure, jury
  rubric, validate-CLI entry, CI activation, release-notes
  obligation, CLAUDE.md guidance.
- **Format-spec template precedents:**
  `skills/strategy/references/strategy-format.md`,
  `skills/prd/references/prd-format.md`,
  `skills/brief/references/brief-format.md`.
- **Phase 4 jury precedents:**
  `skills/strategy/references/phases/phase-4-validate.md`,
  `skills/brief/references/phases/phase-4-validate.md`,
  `skills/prd/references/phases/phase-4-validate.md`.
- **Validation precedents:** `internal/validate/formats.go`
  (Formats-map pattern), `internal/validate/checks.go` (custom
  visibility check precedent — VISION's section-visibility gating
  is the model R7's whole-doc check generalizes).
- **Cross-repo reference rules:**
  `references/cross-repo-references.md` (governs how COMP's
  `upstream:` value resolves when the upstream lives in a different
  repo).
- **wip hygiene:** `references/wip-hygiene.md` (governs the
  `/comp` skill's intermediate-artifact cleanup obligation).
