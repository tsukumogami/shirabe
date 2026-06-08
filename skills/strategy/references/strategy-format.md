# Strategy Document Format Reference

Structure, lifecycle, validation rules, and quality guidance for Strategy
documents.

## Table of Contents

- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Optional Sections](#optional-sections)
- [Visibility-Gated Sections](#visibility-gated-sections)
- [Section Matrix](#section-matrix)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Frontmatter

Every strategy document begins with YAML frontmatter:

```yaml
---
schema: strategy/v1
status: Draft
bet: |
  1 paragraph: the falsifiable hypothesis the strategy commits to.
  Same value the Defensibility Thesis section elaborates in prose.
scope: project | org
upstream: docs/visions/VISION-<parent>.md  # optional
---
```

Required fields: `schema`, `status`, `bet`, `scope`. Optional: `upstream`.

- **schema** -- `strategy/v1`. Pins the artifact-type contract.
- **status** -- lifecycle state (Draft, Accepted, Active, Sunset).
- **bet** -- the falsifiable hypothesis. Paragraph-length YAML literal
  block scalar (`|`). Matches the Defensibility Thesis section body.
- **scope** -- `project` (operationalizes a project-level VISION) or
  `org` (operationalizes an org-level VISION).
- **upstream** -- path to an upstream VISION. Optional because org-scope
  strategies may ground their context in first-principles framing or
  multiple antecedents rather than a single parent. Cross-repo upstream
  references use the `owner/repo:path` convention; see
  `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md` for the
  visibility-direction rules.

Frontmatter status must match the Status section in the body -- agent
workflows parse frontmatter to determine lifecycle state, so divergence
causes silent errors.

## Required Sections

Every strategy document has these sections in order:

1. **Status** -- current lifecycle state and any transition context
2. **Strategic Context** -- the framing that motivates the bet, carrying
   forward upstream VISION content essential to making the document
   stand alone
3. **Defensibility Thesis** -- the bet articulated as a falsifiable
   hypothesis with explicit invalidation conditions
4. **Building Blocks** -- the coherent units of work the strategy
   decomposes into, each leading with a name heading and description
5. **Coordination Dependencies** -- how the building blocks relate,
   sequence, or rely on each other, presented as prose plus a visual
6. **Bet-Specific Falsifiability** -- per-direction invalidation
   conditions and corrective actions for each load-bearing claim
7. **Non-Goals** -- what this strategy deliberately is NOT, each with
   reasoning that ties back to the bet
8. **Downstream Artifacts** -- typed link list of ROADMAP, DESIGN, or
   PRD documents that operationalize this strategy

### Per-section content rules

The rules below are mechanically applicable by the Phase 4 jury. They
specify what content must appear, not how prose must be shaped.

- **Strategic Context.** Required content properties: (1) carry-forward
  of the essential framing from the upstream VISION (or, for org-scope
  strategies without a single upstream VISION, framing grounded in the
  org's other strategic artifacts or in first-principles reasoning);
  (2) the document must stand alone -- a reader who has not opened the
  upstream can still grasp what's at stake and why this bet matters.
  Sub-structure is free; no mandatory sub-headings.

- **Defensibility Thesis.** Prose form of the `bet` frontmatter value.
  States the falsifiable hypothesis with explicit invalidation
  conditions ("This bet fails if..." or equivalent). The thesis is a
  hypothesis, not a problem statement.

- **Building Blocks.** Each block leads with a name heading (`###`)
  and a description paragraph that names the block and what it does.
  Expansion below the lead pair is free -- prose, sub-bullets,
  trade-off framing, or examples are all permitted. The lead heading
  + description gives the granularity rubric something scannable.

- **Coordination Dependencies.** Required prose framing describes the
  dependency directions between building blocks (which depends on
  which, in what order, with what coupling). Required visual
  accompanying the prose: either an ASCII layered diagram OR a Mermaid
  graph. Authors choose -- the prose carries the layered semantics
  regardless of which visual form lands.

- **Bet-Specific Falsifiability.** Bullet list per load-bearing claim
  using the template:

  ```markdown
  - *If <invalidation condition>*, <description of consequence>
    -> *Corrective:* <corrective action>
  ```

  Each direction the bet could fail gets its own bullet. The italic
  markers `*If ...*` and `*Corrective: ...*` are load-bearing -- the
  bet-quality reviewer parses them to verify each claim has both an
  invalidation condition and a corrective.

- **Non-Goals.** Bulleted list. Each non-goal names what the strategy
  won't do AND why, tying back to the bet's framing. Identity-shaped
  exclusions, not scope-shaped ones.

- **Downstream Artifacts.** Typed link list mirroring VISION's pattern.
  Each entry is a path (durable, repo-relative) and a one-sentence
  description of what the linked artifact does. Entries must point at
  durable paths -- not `wip/...` paths, not private-from-public
  references. The structural reviewer parses each entry for durability.

## Optional Sections

Include when relevant:

- **Open Questions** -- present only in Draft status. Records the
  unresolved questions the strategy is still working through. Must be
  empty or removed before Draft -> Accepted transition.
- **Decisions and Trade-offs** -- records strategic decisions made
  during drafting with alternatives and reasoning, mirroring the PRD
  convention. Each entry captures what was decided, what alternatives
  existed, and why the chosen option won. Gives downstream consumers
  the rationale behind the strategic shape so they don't re-litigate
  settled questions.

## Visibility-Gated Sections

Private repos only:

- **Competitive Considerations** -- market alternatives, differentiation
  framing, and competitor-specific positioning that supports the
  defensibility thesis.

This section must NOT appear in public repos. If present in a public
repo during validation, the visibility-gating check flags it with error
code R8. In public-visibility STRATEGY documents, content that would
otherwise belong here folds into Defensibility Thesis at the level of
abstraction the public framing tolerates -- mirroring how VISION's
public/private split works.

## Section Matrix

| Section | Public | Private | Project | Org |
|---------|--------|---------|---------|-----|
| Status | Required | Required | Required | Required |
| Strategic Context | Required | Required | Required | Required |
| Defensibility Thesis | Required | Required | Required | Required |
| Building Blocks | Required | Required | Required | Required |
| Coordination Dependencies | Required | Required | Required | Required |
| Bet-Specific Falsifiability | Required | Required | Required | Required |
| Non-Goals | Required | Required | Required | Required |
| Downstream Artifacts | Required | Required | Required | Required |
| Open Questions | Draft only | Draft only | Draft only | Draft only |
| Decisions and Trade-offs | Optional | Optional | Optional | Optional |
| Competitive Considerations | -- | Optional | Optional | Optional |

## Content Boundaries

STRATEGY does NOT contain:

- **Roadmap-level feature sequencing** -- belongs in a ROADMAP. Building
  Blocks identify the coherent units of work, but ordering features
  with explicit dependencies and sequencing rationale is downstream
  ROADMAP work.
- **PRD-level requirements** -- belongs in a PRD. Strategy bets at the
  defensibility altitude; per-feature functional requirements,
  acceptance criteria, and user stories live one level down.
- **Design-level architecture** -- belongs in a DESIGN doc. Strategy
  may name building blocks and their coordination, but technical
  decisions about how to build any one block (interface shapes, data
  flow, infrastructure choices) are downstream design territory.
- **Implementation tasks** -- belongs in a PLAN. Strategy doesn't
  decompose into atomic issues; that's the planning altitude.
- **Long-term thesis re-justification** -- belongs in the upstream
  VISION. Strategy carries the VISION forward; it doesn't re-articulate
  why the project should exist.

If a STRATEGY draft starts accumulating feature lists, requirements,
technical decisions, or implementation breakdowns, those belong
downstream. Extract them into Downstream Artifacts pointers (when the
downstream doc exists) or Open Questions (when it doesn't yet).

## Lifecycle

### States

| State | Meaning |
|-------|---------|
| Draft | Under development. May have Open Questions. |
| Accepted | Bet endorsed. Open Questions resolved. Jury PASS recorded. Ready for downstream work. |
| Active | Downstream artifacts (ROADMAPs, DESIGNs) reference and operationalize this STRATEGY. |
| Sunset | Bet invalidated, pivoted, or abandoned. Terminal state. |

### Transitions

All transitions are executed by `shirabe transition`. The subcommand
validates preconditions, updates status in both frontmatter and body, and
moves files between directories when status changes.

| Transition | Preconditions | Directory Movement |
|-----------|---------------|-------------------|
| Draft -> Accepted | Open Questions empty or removed; Phase 4 jury PASS; explicit human approval | None (stays in `docs/strategies/`) |
| Accepted -> Active | At least one downstream artifact references this STRATEGY | None (stays in `docs/strategies/`) |
| Accepted -> Sunset | Reason provided (abandoned, pivoted, or invalidated) | Moves to `docs/strategies/sunset/` |
| Active -> Sunset | Reason provided (abandoned, pivoted, or invalidated) | Moves to `docs/strategies/sunset/` |

`Accepted -> Sunset` is permitted as a lifecycle refinement: a
strategic bet can be invalidated by external events before any
downstream artifact consumes it. Forbidding this transition would
force a contrived `Accepted -> Active -> Sunset` path through a
never-realized Active state.

**Command interface:**

```
shirabe transition <strategy-doc-path> <target-status> [--reason "<text>"]
```

`<target-status>` is one of `Accepted | Active | Sunset`. The
`--reason` flag is required for Sunset transitions and is captured
in the body Status section.

**Forbidden transitions:**

- Draft -> Active (must accept first)
- Draft -> Sunset (delete instead -- unendorsed drafts don't need a
  paper trail)
- Active -> Accepted or Draft (regression)
- Accepted -> Draft (regression)
- Sunset -> any (terminal, irreversible)

### Edit Rules

Active STRATEGYs can be edited in place for everything except the
Defensibility Thesis. A thesis change signals that the bet itself has
shifted -- create a new STRATEGY and Sunset the old one with the
superseding document recorded in the Status section.

One Active STRATEGY per bet at a time. Multiple STRATEGYs may operate
under one upstream VISION when they make distinct bets.

### Directory Mapping

| Status | Directory |
|--------|-----------|
| Draft, Accepted, Active | `docs/strategies/` |
| Sunset | `docs/strategies/sunset/` |

## Validation Rules

### During /strategy (drafting)

- Frontmatter has `schema`, `status`, `bet`, `scope` fields
- `schema` is `strategy/v1`
- `scope` is `project` or `org`
- Frontmatter `status` matches the Status section in the body
- All 8 required sections present (FC04) and in canonical order (FC15)
- Status is `Draft`
- Open Questions section may contain unresolved items
- If `Competitive Considerations` is present, repo visibility must be
  private

### During /strategy finalization (approval)

- Open Questions section must be empty or removed
- Phase 4 jury verdicts all PASS
- Building Blocks section contains at least one block with a name
  heading and description paragraph
- Coordination Dependencies section contains both prose framing and a
  visual (ASCII layered diagram or Mermaid graph)
- Bet-Specific Falsifiability section contains at least one
  `*If ...*` / `*Corrective: ...*` bullet
- Downstream Artifacts entries are durable paths (not `wip/...`)
- Status transitions to `Accepted` on explicit human approval

### When referenced by downstream workflows

- Status must be `Accepted` or `Active` to serve as upstream context
- If status is `Draft`: STOP and inform the user the STRATEGY needs
  approval first
- If status is `Sunset`: STOP and inform the user the STRATEGY has
  been terminated; the downstream workflow should reference a current
  STRATEGY instead

### Status consistency

- Frontmatter `status` and body Status section must always match
- Sunset documents include the reason (abandoned, pivoted, or
  invalidated) in the body Status section
- `Competitive Considerations` must not appear in public-visibility
  contexts (R8 check)

## Quality Guidance

Each required section has specific quality criteria. Reviewers and
authors should check these during drafting and validation.

### Strategic Context

- Carries forward the essential framing from upstream context without
  re-justifying the long-term thesis. If the section reads like a
  re-write of the upstream VISION, fold it back; if a reader can't
  follow the bet without first reading the upstream, expand.
- Stands alone. A reviewer landing on the STRATEGY cold should be able
  to grasp what's at stake from this section alone.
- Sub-structure is the author's call. Free-flowing prose is fine;
  numbered antecedents are fine; situation/complication/question is
  fine. Pick what serves the framing.

### Defensibility Thesis

- Articulated as a falsifiable hypothesis with explicit invalidation
  conditions. "This bet rests on..." or "We commit to... because..."
  are typical openings. "The problem is..." is wrong -- problem
  statements live in PRDs.
- Names the medium-term horizon. Strategy sits between VISION
  (long-term) and ROADMAP (sequenced features); the thesis should
  reflect that altitude.
- Matches the `bet` frontmatter value. Divergence between the prose
  thesis and the YAML field signals one is stale.

### Building Blocks

- Each block leads with a name heading (`###`) and a description
  paragraph. The lead pair is what the granularity rubric reads.
- Blocks are coherent units of work -- each one has plausible
  downstream design follow-up. Framing statements without
  decomposition aren't blocks.
- Granularity rubric (default; revisable):
  - **Block count.** 5-8 blocks is typical. Fewer than 3 risks
    under-decomposition (a single block masquerading as a strategy);
    more than 10 risks being a roadmap in disguise.
  - **Downstream-artifact ratio.** Each block should map to 1-2
    downstream design docs minimum. Blocks with no plausible
    downstream design are framing statements rather than coherent
    units of work; blocks decomposing into 5+ design docs are likely
    conflating multiple blocks.
  - **Scope coherence.** Single-product blocks are the norm.
    Cross-product blocks (spanning 2 repos) are permitted but should
    be exceptional (under 20% of total). Blocks that span 3 or more
    repos signal two strategies sharing a document and warrant
    decomposition.

  These defaults are extrapolated from limited proof-by-example
  evidence and are adjustable in this reference file as jury verdict
  patterns accumulate. Revisions land as PRs to this file -- no PRD
  amendment required.

### Coordination Dependencies

- Prose framing describes the dependency directions: which blocks
  depend on which, in what order, with what coupling (hard technical
  dependency vs. softer value-delivery preference).
- Accompanied by a visual: either an ASCII layered diagram or a
  Mermaid graph. The visual is required; the form is the author's
  choice.
- Acknowledges where parallel execution across blocks is possible.

### Bet-Specific Falsifiability

- Names each load-bearing claim the bet makes. A bullet per claim.
- Each bullet uses the `*If <invalidation condition>*, ... ->
  *Corrective:* ...` template. Both the invalidation and the
  corrective are required -- naming an invalidation without a
  corrective leaves the reader without an action; a corrective
  without an invalidation doesn't connect to the bet.
- Each invalidation is a real, plausible failure mode -- not a
  rhetorical "if everything goes wrong." Specific enough that a
  reader can imagine the world where the bet fails.

### Non-Goals

- About identity, not scope. Each non-goal explains WHY the strategy
  won't do something, tying back to the bet. "Not a system package
  manager -- we target developer tools specifically because system
  packages have different reliability requirements" is the pattern.
- Helps prevent scope creep during downstream operationalization.

### Downstream Artifacts

- Typed link list. Each entry: durable path + one-sentence purpose.
- Paths are repo-relative and durable. `wip/...` paths fail the
  structural-reviewer check.
- Empty at draft creation; populated as downstream ROADMAPs, DESIGNs,
  and PRDs land that reference this STRATEGY.

### Competitive Considerations (private only)

- Names market alternatives and explains defensibility differentiation
  against each. References, but does not duplicate, full competitive
  analysis artifacts.
- Folds back into Defensibility Thesis at a higher level of
  abstraction in public-visibility contexts.

### Common Pitfalls

- **Re-justifying the long-term thesis.** Strategy operationalizes a
  piece of an upstream VISION at medium-term altitude. If Strategic
  Context turns into a re-write of why the project should exist,
  step back -- that's VISION territory.
- **Premature feature decomposition.** If Building Blocks turn into
  prioritized feature lists with sequencing, that's ROADMAP altitude.
  Defer to a downstream ROADMAP.
- **Falsifiability theater.** Listing invalidation conditions that
  could never actually occur ("if the universe ends...") satisfies
  the template but defeats the rubric. Each invalidation must be a
  plausible failure mode.
- **Cross-product blocks at scale.** A few cross-product blocks are
  fine; more than 20% of total signals the strategy is straddling
  multiple coherent bets.
- **Stale Downstream Artifacts.** The section should be updated as
  downstream work lands. Empty when no downstream artifacts exist
  yet is fine; outdated paths are not.
