---
schema: brief/v1
status: Draft
problem: |
  shirabe gives every first-class artifact type — VISION, STRATEGY,
  ROADMAP, BRIEF, PRD, DESIGN, PLAN — a loadable authoring skill, but
  competitive analysis (COMP) is recognized by example only. Authors
  reach it indirectly through `/explore`'s produce phase and rely on
  workspace-level tooling for the format. Without a named `/comp`
  skill, parent flows like `/charter` have no shirabe-native child to
  delegate to when competitive framing belongs in the conversation.
outcome: |
  Skill authors reach for `/comp` the same way they reach for
  `/strategy` or `/prd`: a loadable child skill with phased authoring,
  a referenced format spec, a Phase 4 jury, visibility enforcement
  (COMP is private-only), and `shirabe validate` CLI coverage for the
  `comp/v1` schema. `/charter`'s optional competitive-analysis phase
  has a real child to invoke, and competitive analysis becomes durable
  shirabe infrastructure rather than an example-proven pattern.
---

# BRIEF: shirabe-comp-skill

## Status

Draft

This brief frames the `/comp` competitive-analysis child skill before
its requirements are written. The downstream PRD owns the format-spec
contents, the Phase 4 jury rubric, the validate-CLI extension shape,
and the precise `/charter` delegation contract. Open questions below
defer those decisions explicitly.

## Problem Statement

shirabe recognizes seven artifact types as first-class today — VISION,
STRATEGY, ROADMAP, BRIEF, PRD, DESIGN, PLAN — each with a loadable
authoring skill, a referenced format spec, a Phase 4 jury, and
`shirabe validate` CLI coverage at lifecycle transitions. The
taxonomy covers long-term aspiration through implementation steps,
but it does not cover competitive analysis.

Competitive analysis exists in the workspace as an artifact category
proven by example: prior `COMP-*.md` documents have been authored,
and a format reference for the type lives in an existing
workspace-level skill that captures the COMP shape. The artifact
type works in practice. What's missing is a shirabe-native authoring
path. Today an author who wants to write competitive analysis reaches
it indirectly: `/explore`'s produce phase can crystallize a
conversation into a COMP document, and the workspace-level format
reference supplies the structure. Neither path is named, discoverable,
or first-class.

The gap matters more now because the strategic chain has a parent
skill — `/charter` — whose architecture commits to an optional
competitive-analysis phase between vision and strategy. `/charter`'s
brief and design name competitive framing as a private-repo
sub-phase that the chain can route into when the conversation
warrants it. There is no child skill to delegate to. `/charter`
ships against this gap by leaving the competitive sub-phase
documented but unenforced: the chain skips competitive framing
silently in public repos and has no `/comp` to invoke privately.

The remaining gap has four parts:

- **No skill entry point.** Future competitive-analysis authors have
  no `/comp` to load. They invoke `/explore` and hope its produce
  phase routes to the COMP artifact type, or they read prior
  examples and hand-author the structure.
- **No shirabe-resident format reference.** The COMP format lives in
  a workspace-level skill outside shirabe's `skills/<type>/references/`
  layout. Authors who reach shirabe through the marketplace see no
  COMP format spec at all.
- **No validation discipline.** `shirabe validate` does not yet
  recognize a `comp/v1` schema. Lifecycle transitions lack tooling
  enforcement, and the private-only visibility rule for COMP relies
  on author and reviewer discipline rather than a CI check.
- **No parent-skill integration contract.** `/charter`'s competitive
  sub-phase has no defined delegation contract to bind against.
  Without `/comp`, `/charter`'s competitive phase is a placeholder.

The problem isn't that competitive analysis cannot be authored. It's
that without `/comp`, the artifact type stays second-class — reached
indirectly, lacking structural enforcement, and unable to participate
in the strategic chain's parent-skill orchestration.

## User Outcome

A skill author opens Claude Code in a private repo where a
competitive-framing conversation needs to happen. They invoke
`/comp`. The skill walks them through the same phased authoring
pattern they know from `/strategy` and `/prd`: discovery, drafting,
jury review, finalization. The output lands in
`docs/competitive/COMP-<topic>.md` with `schema: comp/v1`
frontmatter, all required sections present, and the Phase 4 jury's
PASS verdicts recorded.

Downstream, when a `/charter` run reaches its optional competitive
sub-phase in a private repo and decides the conversation warrants
competitive framing, the parent skill delegates to `/comp` with a
defined contract: scoped topic, upstream STRATEGY or VISION
reference (when present), and the expectation that `/comp` returns a
Draft or Accepted COMP document `/charter` can carry forward.
`shirabe validate` on a COMP file exercises the same Formats-map
lookup path that any other artifact type uses today; a missing
required section fails validation; an invalid status fails
validation; a COMP file committed in a public repo fails validation
with a visibility violation.

Public-repo authors who invoke `/comp` directly hit an early refusal
with a redirect to alternative artifact types (typically a design doc
with competitive findings folded into context, or a spike report
investigating a specific technical approach). The redirect mirrors
how the existing workspace-level COMP reference handles the same
case. Visibility is layered defense: the skill refuses in public
repos, `shirabe validate` blocks public-repo COMP files at CI, and
`/charter` skips its competitive sub-phase silently in public
contexts.

Adopters who install shirabe through the marketplace get `/comp`
alongside the rest of the taxonomy. The competitive-analysis altitude
becomes a tool authors can reach for the moment their work warrants
it, without having to consult workspace-level skills or read a prior
example to learn the shape.

## User Journeys

The brief calls out four journeys that exercise the artifact and the
skill from different entry points. Each names the user, the trigger,
and the outcome shape.

### Journey 1: Competitive-analysis author, standalone invocation

A skill author working in a private repo identifies a competitive
conversation that needs framing — a new entrant in the same market
segment, a comparison against an adjacent tool, or a snapshot of how
competitors solve a shared problem. They invoke `/comp` cold, with a
short input describing the market segment they want to analyze. The
skill walks them through Market Overview drafting (the segment and
its key competitive dimensions), Competitors (per-competitor
analysis), Comparative Matrix (side-by-side comparison on key
dimensions), Opportunities (gaps the analysis surfaces), and
Implications (how the findings connect to product or technical
choices). Phase 4 jury runs reviewers (content quality and
structural format) and returns PASS verdicts. Author ratifies and
commits the artifact at `docs/competitive/COMP-<topic>.md`.

This is the primary mode at ship-time. It validates that `/comp`
gives the COMP altitude a first-class entry point the same way
`/strategy` did for STRATEGY.

### Journey 2: `/charter` delegating to `/comp` in a private repo

A `/charter` run reaches its optional competitive sub-phase in a
private repo and decides the conversation warrants competitive
framing. The parent skill invokes `/comp` with a scoped topic
derived from the strategic conversation, an upstream STRATEGY or
VISION path (when present), and the expectation that `/comp`
produces a COMP document the parent can carry forward into the
downstream `/strategy` phase. `/comp` runs its phased authoring,
produces a Draft (or Accepted, if the chain runs to acceptance), and
returns control to `/charter`. The chain continues into `/strategy`
with the competitive context grounded in a durable artifact rather
than an inline conversation.

This journey validates that `/comp` slots into the strategic chain
as a named, contracted child rather than as an ad-hoc detour.

### Journey 3: Public-repo refusal and redirect

A skill author invokes `/comp` in a public repo, either by direct
invocation or because a `/charter` run misroutes. The skill detects
the visibility mismatch at its setup phase and refuses to author the
artifact. The refusal names the rule (COMP artifacts are private-only
by convention) and suggests alternative artifact types: a design doc
with competitive findings folded into context, or a spike report
investigating a specific technical approach. No COMP file is created.
If the author somehow commits a COMP file in a public repo by hand,
`shirabe validate` in CI catches it and fails the PR.

This journey validates that visibility enforcement is layered
defense — the skill, the validator, and the CI check each catch the
case independently.

### Journey 4: COMP review and acceptance

A drafted COMP document sits at status `Draft`. Phase 4 jury runs
against it. The content-quality reviewer challenges a competitor
analysis that reads as marketing language rather than as a frank
strengths-and-weaknesses comparison; the structural reviewer catches
a missing Comparative Matrix and flags an Implications section that
doesn't connect findings to product or technical choices. The author
addresses each, re-runs Phase 4, and the document transitions to
`Accepted` (or `Final`, depending on the PRD's chosen lifecycle name)
once both reviewers PASS.

This journey validates that the jury catches real defects of the kind
caught by reviewer discipline in prior COMP documents.

## Scope Boundary

This brief, and the downstream PRD it points at, cover the
standalone `/comp` skill and the COMP doc format as it lives inside
shirabe. The scope holds the following inside:

- COMP artifact type definition resident in shirabe: frontmatter
  schema (`schema: comp/v1`), required and optional sections,
  lifecycle states.
- `comp-format.md` reference file at
  `skills/comp/references/comp-format.md`, following the structural
  skeleton of `strategy-format.md`, `prd-format.md`, and
  `brief-format.md`.
- `/comp` skill as a loadable plain-English SKILL.md following the
  `/strategy` and `/prd` pattern (input modes, phased authoring,
  resume logic, critical requirements, reference files table).
- Phase 4 jury structure with reviewers covering content quality
  (per-competitor framing, opportunity identification, implications
  tie-back) and structural format (required sections, frontmatter,
  status-line convention).
- `shirabe validate` CLI extension: add `comp/v1` to the Formats map
  in `internal/validate/formats.go` so the CLI recognizes
  `COMP-*.md` files by longest-prefix match and runs the standard
  FC-series checks. `DetectFormat` already handles longest-prefix
  routing on a new filename prefix once the entry lands.
- Visibility enforcement at three layers: setup-phase refusal in
  public repos, validate-CLI visibility check that fails COMP files
  in public-repo paths, CI inheritance through shirabe's reusable
  `validate-docs.yml` workflow.
- CI validation enablement. Shirabe's self-caller path-filters on
  `docs/**` and picks up `docs/competitive/COMP-*.md` automatically
  once the Formats entry lands. Adopter repos that path-filter
  narrowly need to widen the filter to include
  `docs/competitive/**`; call this out in the release notes for the
  version that ships the Formats entry.
- The `/comp` side of the `/charter` → `/comp` delegation contract:
  the inputs `/comp` accepts from `/charter`, the outputs it returns,
  and the failure modes (public-repo refusal, validation failure)
  the parent handles.
- Light updates to shirabe CLAUDE.md (and downstream-adopter
  guidance) explaining when to reach for `/comp` versus alternatives
  in public repos.

The scope explicitly excludes:

- **`/charter` skill changes.** `/charter` consumes `/comp` through
  the delegation contract this brief scopes; updates to `/charter`
  itself (its competitive sub-phase prose, its visibility-detection
  logic) live in `/charter`'s own scope and ship under its own
  artifact track.
- **Migration of existing COMP documents.** Prior COMP artifacts
  remain at their current paths under their current shape. If the
  format spec diverges from prior examples in detail, the PRD names
  the reconciliation; this brief does not commit to migration work.
- **Workspace-level COMP tooling deprecation.** The existing
  workspace-level skill that captures the COMP format stays in
  place. Whether and when to consolidate after `/comp` ships is a
  downstream call, not in this brief.
- **External-adopter behavior.** Whether external shirabe adopters
  reach for `/comp` in their own repos is a downstream signal, not a
  requirement of this brief. The skill must work for adopters, but
  driving adoption is out of scope.
- **The `/explore` produce-phase route to COMP.** `/explore`'s
  existing routing to competitive analysis continues to work; this
  brief does not commit to deprecating or rewiring it. If `/comp`'s
  arrival warrants `/explore` changes, that's a separate scope.
- **Lifecycle state count and naming.** Prior COMP examples used a
  two-state lifecycle (`Draft` -> `Final`); shirabe's other artifact
  types use a three- or four-state ladder. The PRD picks one; this
  brief does not commit to either.

## Open Questions

These surface for the downstream PRD to resolve. None block this
brief.

1. **Lifecycle ladder.** Prior COMP examples used `Draft` -> `Final`
   (two states, terminal). Shirabe's other artifact types use
   richer ladders: BRIEF runs `Draft` -> `Accepted` -> `Done`;
   STRATEGY adds `Active` and `Sunset`. The PRD picks one. Candidates:
   keep two states because COMP is a point-in-time snapshot that
   doesn't evolve; adopt the three-state BRIEF-style ladder for
   consistency; or invent a COMP-specific shape. The choice affects
   the transition-script interface and the validate-CLI status check.

2. **Jury reviewer count and rubric.** Other artifact types run two
   to three Phase 4 reviewers. The PRD picks the COMP reviewer set
   and their rubrics. Candidates: two reviewers (content quality +
   structural format), three reviewers (adding a competitive-framing
   reviewer that checks for marketing language and opportunity
   substance), or one reviewer (structural format only, because
   competitive content quality is harder to mechanize).

3. **Visibility enforcement implementation.** The setup-phase
   refusal is straightforward (check visibility, refuse if public).
   The validate-CLI visibility check is novel — it's the first
   shirabe artifact type with a hard private-only constraint
   enforceable at validation time. The PRD picks the mechanism:
   path-based (`docs/competitive/` only valid in private repos),
   schema-based (a `comp/v1`-specific visibility check in the
   Formats map), or a generic visibility-gated artifact framework.

4. **Format-spec source of truth.** The COMP format reference lives
   today in an existing workspace-level skill. The PRD picks whether
   to copy the format into `skills/comp/references/comp-format.md`
   verbatim, port it with shirabe-conformant edits (matching
   `strategy-format.md`'s structural shape), or rewrite from scratch
   using prior COMP examples as input. Each path has a different
   reconciliation surface against the existing workspace tooling.

5. **`/charter` delegation contract shape.** `/charter`'s existing
   competitive sub-phase is documented as a placeholder. The PRD
   picks the exact contract: what `/charter` passes in (topic,
   upstream paths, scope hints), what `/comp` returns (artifact path,
   status, summary), and how `/charter` handles `/comp` failures
   (public-repo refusal in a misrouted call, validation failure on a
   forced acceptance). The contract is the freeze line between the
   two features.

## Downstream Artifacts

- **`PRD-shirabe-comp-skill.md`** — requirements articulation for
  the `/comp` skill, the comp-format reference, the Phase 4 jury
  rubric, the validate-CLI extension, and the `/charter` delegation
  contract. Lives in `docs/prds/`.
- **(Likely) `DESIGN-shirabe-comp-skill.md`** — implementation
  shape, picked up after PRD lands if the architectural surface
  warrants a design doc. Lives in `docs/designs/current/`. Authored
  at PRD-time judgment.

## References

- Brief format precedents:
  `docs/briefs/BRIEF-shirabe-strategy-skill.md` (the SE3 precedent
  for promoting an example-proven artifact type to a first-class
  shirabe skill),
  `docs/briefs/BRIEF-shirabe-charter-skill.md` (the parent skill
  whose competitive sub-phase delegates here).
- Format-spec template precedents:
  `skills/strategy/references/strategy-format.md`,
  `skills/prd/references/prd-format.md`,
  `skills/brief/references/brief-format.md`.
- Phase 4 jury precedent:
  `skills/brief/references/phases/phase-4-validate.md`,
  `skills/strategy/references/phases/phase-4-validate.md`.
- Skill structure template: `skills/strategy/SKILL.md`,
  `skills/brief/SKILL.md`.
- Validate CLI extension point: `internal/validate/formats.go`.
- Cross-repo visibility rules: `references/cross-repo-references.md`.
