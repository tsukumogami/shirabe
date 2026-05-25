---
status: Proposed
upstream: docs/prds/PRD-shirabe-charter-skill.md
problem: |
  shirabe ships strategic and tactical children (`/vision`,
  `/strategy`, `/roadmap`, `/prd`, `/design`, `/plan`) as loadable
  skills with no parent layer to walk authors through them as a
  sequence. The first parent skill (`/charter`) is queued to ship,
  with two siblings (`/scope` and the `/work-on` migration) following
  it. Without a shared design that lifts the pattern-level mechanics
  out of any one feature, each parent re-derives orchestration,
  resume, state-schema, and visibility behavior in isolation; the
  pattern fragments before the second parent ships. The design
  problem is to commit to a shared, storage-agnostic parent-skill
  contract while accommodating the current core-layer constraints
  (wip/-based intermediates, no nested `/decision` sub-teams under
  TeamCreate's single-team-per-leader rule) and leaving room for
  the future amplifier-layer substrate the `/work-on` migration
  will live in.
decision: |
  Adopt a parent-skill pattern with a fixed contract surface (state
  schema, resume ladder, three exit paths, child-doc inspection
  rules, CLAUDE.md surfacing, eval requirement) shared across all
  three parents, plus per-parent bindings (delegation graph, chain
  shape, slug rules) that each feature owns. Ship the shared engine
  references and the core-layer wip/-based implementation now;
  declare the amplifier-layer substitution surface in the contract
  so the future migration is mechanical. Resolve the discover/
  converge engine extraction, the nested-decision-team adaptation,
  and the cross-branch state-file scope inline; defer competitive
  signal detection and shared-design re-author timing as scoped
  open questions.
rationale: |
  The pattern-level requirements (R1, R3, R9-R14, R17a, R18) are
  already articulated in `/charter`'s PRD; lifting them into a
  shared design now — while `/charter` is the only concrete
  consumer — costs less than re-litigating them when `/scope` lands.
  Contract-first design lets the core layer ship against current
  shirabe patterns without locking out the amplifier layer the
  workflow-substrate work depends on. The core-layer adaptations
  (inline `/decision`, no nested teams) are framed as explicit
  limitations the design exposes rather than hidden in
  implementation, so the amplifier layer's value proposition is
  pre-justified.
---

# DESIGN: shirabe-progression-authoring

## Status

Proposed. Authored 2026-05-24 against the In Progress PRD
`docs/prds/PRD-shirabe-charter-skill.md`. The design is **shared**
across the parent-skill pattern's three features: `/charter` (the
concrete consumer driving this design), `/scope` (a parallel parent
sibling, separate PRD), and the future `/work-on` migration from
its current substrate into the same pattern (separate PRD when
substrate work is bounded). The design lifts every requirement
tagged `[pattern-level]` in `/charter`'s PRD (R1, R3, R9, R10, R11,
R12, R13, R14, R17a, R18) into pattern-level scope; the
`[/charter-specific]` requirements stay in `/charter`'s PRD.

## Context and Problem Statement

The shirabe skill catalog ships two altitude bands of artifact
producers as standalone slash commands. Strategic-altitude children
(`/vision`, `/strategy`, `/roadmap`) and tactical-altitude children
(`/prd`, `/design`, `/plan`) each run as one-shot conversations the
author invokes by hand. No parent skill currently walks an author
through a sequence of children, holds state across child
boundaries, or enforces invariants that span the chain (terminal
artifact, exit shape, resume).

`/charter` is queued as the first parent skill, with `/scope` and
the `/work-on` migration named in `/charter`'s PRD as the next two
parent-skill consumers. Three forces shape the design problem:

- **Pattern reuse is load-bearing for the next two parents.**
  `/charter`'s PRD tags ten of its requirements `[pattern-level]`
  precisely because the same mechanics need to apply to `/scope`
  and `/work-on`. Without a shared design that lifts those
  requirements out of `/charter`'s scope, the second parent
  re-derives them and the third drifts further.
- **The core-layer execution environment has hard constraints
  the design must accommodate.** Two are load-bearing: shirabe's
  current intermediate-storage substrate (`wip/`-based files
  committed to feature branches, deleted before merge) and a
  Claude Code TeamCreate constraint (`single-team-per-leader` —
  one team per agent leader, no nested team creation). The
  TeamCreate constraint means a `/decision`-style sub-team inside
  a `/design` decision-researcher cannot be spawned today; the
  decision skill must run inline in the researcher's own context.
- **The amplifier-layer substrate the `/work-on` migration
  depends on is not bounded yet.** Whatever workflow-composition
  substrate the migration will live in is outside this design's
  shipping scope, but the contract must not foreclose it. The
  freeze line is the contract surface; the implementations are
  the substitution variables.

The technical challenge is to commit to a parent-skill contract
that satisfies the ten pattern-level requirements, accommodates the
core-layer constraints explicitly, and leaves the amplifier-layer
substitution surface defined as a substitution variable rather than
a future redesign.

System boundaries touched by this design:

- The shirabe `skills/` directory layout (does the discover/converge
  engine move out of `skills/explore/`?) and the top-level
  `references/` directory (where shared content already lives:
  `cross-repo-references.md`, `decision-protocol.md`,
  `wip-hygiene.md`, etc.).
- The `wip/` intermediate-storage substrate (the state file
  `wip/<parent>_<topic>_state.md`, per-child wip artifacts each
  child currently writes, the wip-hygiene rule from workspace
  `CLAUDE.md`).
- The child-skill contract surface for inspection: a parent reads
  child doc frontmatter `status:` and computes git blob hashes;
  it does NOT read child internals (`wip/research/<child>_*.md`).
- The CLAUDE.md visibility-detection pattern (`## Repo Visibility:`
  header read by `/strategy`, `/explore`, and others).
- The skill-evals substrate (`skills/<name>/evals/evals.json`,
  `scripts/run-evals.sh`).

The downstream PRD for `/charter` has already drafted concrete
state-file schemas, resume-ladder ordering, and validation rules.
This design must either ratify those specifics as pattern-level
(promoting them out of `/charter`'s PRD into the shared contract)
or substitute equivalent pattern-level forms.

## Decision Drivers

Drivers fall into four groups. Items 1-6 trace to PRD §"Questions
Deferred to Design"; items 7-10 trace to the 10 pattern-level
requirements; items 11-13 trace to SE4 directives in the
team-coordinator brief; items 14-15 are implementation-specific
drivers the PRD does not cover.

### From the PRD's deferred questions

1. **Discover/converge engine extraction.** Whether the engine
   lives at `skills/explore/references/phases/` (cross-skill
   reference) or moves to a top-level `references/` location
   (signaling shared infrastructure). Affects the parent-skill
   `references/phase-1-*.md` path conventions and how `/scope` /
   `/work-on` consume the same discovery engine.

2. **Dual-implementation substitution contract.** The freeze line
   between the wip/-based core-layer implementation and the
   future amplifier-layer implementation. The resume contract is
   storage-agnostic; wip/-specific hygiene rules are orthogonal.
   The driver is identifying which parts of the contract are
   substitution variables and which are invariant.

3. **Shared-design authoring timing.** Whether this design ships
   before `/scope` and `/work-on` are bounded (now, validating
   only against `/charter`) or after. The SE4 directive answers:
   author it now, against `/charter`'s pattern-level requirements
   as written. The driver is what that commitment costs (pattern
   may need revision when `/scope` lands) versus defers
   (re-litigating pattern-level claims later).

4. **Cross-branch state-file behavior under `wip/`.** The state
   file is branch-coupled today (PRD R10, R11). Future scenarios
   (merge a child PR, resume parent on main to invoke next child)
   break the wip/-based model. The driver is whether the v1
   contract acknowledges branch-coupling as a known limitation
   or specifies a substitution surface to fix it later.

5. **Competitive-framing signal detection in private repos.** When
   `/comp` ships, `/charter` must detect competitive-framing
   signals during Phase 1. The driver is whether the detection
   contract is part of the pattern (so `/scope` inherits) or
   specific to `/charter` and its `/comp` integration.

6. **Team persistence across the parent-skill chain.** The
   TeamCreate single-team-per-leader constraint blocks downstream
   teams (`/prd`, `/design`, `/plan`) from holding upstream teams
   (`/brief`) alive for query. The contract today is file-handoff.
   The driver is whether the pattern names the substrate the
   resolution will live in (amplifier-layer workflow substrate)
   or leaves it as a generic future-work flag.

### From the 10 pattern-level PRD requirements

7. **Skill-loading surface (R1).** Parent skills load as
   `skills/<name>/SKILL.md` slash commands following the shipped
   template (Input Modes, execution-mode flags, slug constraint,
   Workflow Phases diagram, Resume Logic ladder, Phase Execution
   list, Reference Files table). The driver is whether the design
   ratifies this verbatim or substitutes a contract-level form
   that allows amplifier-layer parents to ship outside this
   template.

8. **Slug constraint (R3).** Topic-slug regex `^[a-z0-9-]+$`,
   hard-rejected at Phase 0. Pattern-level commitment ratified by
   ratifying R3.

9. **State-file schema and resume ladder (R9, R10, R11).** These
   three requirements together specify a concrete schema (YAML
   with `.md` extension, named fields like `chain_started`,
   `planned_chain`, `chain_ran`, `chain_skipped`, `exit`,
   `decision_record_sub_shape`, `exit_artifacts`,
   `child_snapshots`), a hard finalization check (R9), and a
   resume-ladder ordering with multi-source consultation (R11).
   The design driver: ratify as pattern-level (every parent uses
   the same schema with parent-specific field extensions), or
   abstract to a substitution-variable form. The PRD's
   pattern-level tagging signals "ratify"; the design must agree
   or explain why not.

10. **Visibility detection (R12), manual-fallback (R13),
    child-internals isolation (R14), CLAUDE.md surfacing (R17a),
    evals (R18).** Each is a contract-surface commitment. The
    design must either ratify all five into pattern-level scope
    or explain which need parent-specific bindings.

### From SE4 directives

11. **Nested-team adaptation for `/decision` sub-skills.** The
    `/design` SKILL.md expects Phase 2 to spawn decision-researcher
    peers that each invoke `/decision` as a sub-skill with its own
    validator team. TeamCreate's single-team-per-leader constraint
    blocks this nested-team creation. The adaptation: each
    decision-researcher walks `/decision`'s phases inline (no
    nested team, no parallel alternative-research agents, no
    persistent validators). The driver: how the design surfaces
    this limitation — as a transient implementation note, or as
    an explicit architectural property of the core layer that
    motivates an amplifier-layer capability.

12. **wip/ persistence as durable evidence.** SE4 overrides the
    `/design` skill's Phase 6 wip/ cleanup. wip/ artifacts (this
    design's coordination manifest, per-decision reports, security
    report, review verdicts) persist as durable evidence rather
    than getting deleted. The driver: documented expectation that
    pattern-level designs accumulate inspectable evidence trails
    in wip/ that survive the cleanup phase.

13. **PR-creation hold.** SE4 holds PR creation until the full
    tactical chain (brief + PRD + design + plan) completes. The
    branch accumulates artifacts and a single PR ships them
    together. Implication for this design: status transitions
    happen in-branch on team-lead approval, but the design's
    discoverability doesn't require its own PR — readers consult
    the branch.

### Implementation-specific

14. **Maintainability across the three parents.** Pattern-level
    references (e.g., a shared `references/parent-skill-pattern.md`
    listing the contract surface, the resume-ladder template, the
    state-file schema) must be authored such that each parent
    cites them rather than re-implementing them. The design must
    name the location and content of those shared references.

15. **Eval coverage of pattern-level behavior.** Per R18, each
    parent ships evals at `skills/<name>/evals/evals.json`. The
    design must commit to a pattern-level eval scenario set (slug
    rejection, malformed state file, child-internals isolation,
    visibility default) that each parent inherits, plus
    parent-specific scenarios on top.

## Considered Options

[Phase 3 will populate this section per-decision after Phase 2
spawns decision-researchers against each driver above.]

## Decision Outcome

[Phase 3 will populate this section after cross-validating the
per-decision outcomes from Phase 2.]

## Solution Architecture

[Phase 4 will populate this section.]

## Implementation Approach

[Phase 4 will populate this section.]

## Security Considerations

[Phase 5 will populate this section.]

## Consequences

[Phase 4 / Phase 6 will populate this section.]

## Open Questions

The following are explicit limitations and forward-looking notes
the design exposes. They are not deferred from this document; they
are architectural properties the reader should know about.

- **Nested-team support for `/decision` sub-skill invocation.**
  The Claude Code TeamCreate primitive enforces
  single-team-per-leader, which blocks the `/design` skill's
  intended Phase 2 model (each decision-researcher spawns its own
  `/decision` validator sub-team). The current core-layer
  workaround is to walk `/decision`'s phases inline inside each
  decision-researcher's own context — this means no persistent
  validator agents, no parallel alternative-research, and no
  cross-decision validator memory. This is an architectural
  property of the core layer, not a transient bug. The
  amplifier-layer workflow substrate is the expected resolution
  surface; this design exposes the limitation rather than
  papering over it.

- **Team persistence across the parent-skill chain.** A direct
  consequence of the same TeamCreate constraint: a downstream
  parent skill cannot query an upstream parent's team because
  the upstream team must be destroyed before the downstream
  leader can create its own. The current contract is
  file-handoff (each parent's artifacts live in docs/ and wip/;
  the downstream parent reads them). This is acceptable for the
  pattern-level shared design but limits the inspection depth a
  downstream team can achieve. The amplifier-layer substrate
  is the expected resolution surface.

