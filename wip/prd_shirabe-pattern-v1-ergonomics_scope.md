# /prd Scope: shirabe-pattern-v1-ergonomics

Operating context: dispatched by /scope as a sub-agent
(`parent_orchestration.invoking_child: prd`,
`suppress_status_aware_prompt: true`, `rationale: fresh-chain`). The
conversational opener is suppressed; the BRIEF
(`docs/briefs/BRIEF-shirabe-pattern-v1-ergonomics.md`, status
Accepted) supplies the scope framing.

## Problem Statement

Shirabe's parent-skill pattern v1 — the contract letting `/scope`,
`/charter`, and the workflow children compose into chain workflows
— has dogfooded silent degradation across about 24 inside-pattern
observations affecting nine child skills, the parent-pattern
reference, four format references, and the validator. The
observations share a failure shape (silent degradation under
non-ideal operating conditions: sub-agent dispatch, cold-start
topics, automated approval, validators that miss what authors
miss) and accumulate compounding chain tax when treated as
one-offs.

## Initial Scope

### In Scope

- Per-observation requirements + acceptance criteria for the
  ~24 observations across the six fix-surface clusters the
  BRIEF names.
- The chain-handoff symmetry between sub-agent dispatch and
  top-level invocation: every Phase 4 jury, Phase 5 approval
  site, Resume Logic table, and validator check that the
  pattern's prose silently assumed ideal conditions for.
- Mechanical writing-style and content-budget enforcement at
  validation time so authors can't ship overshoots silently.
- The CLI version-skew preflight observation that sits
  between cluster groups.

### Out of Scope

- Track B (vision#535) amplifier-layer substrate primitives.
  Hard-blocked on koto composability extensions.
- Standalone shirabe BUG-class issues (shirabe#155, #157,
  #158, #160, #161, #163, #164) — though the PRD may name an
  acceptance criterion that intersects #157 (the schema
  silent-skip).
- The per-skill artifact-decision contract, tracked
  separately on the shirabe roadmap.
- The mechanism per observation. PRD names the contract;
  DESIGN picks the pattern.

## Research Leads

1. **Cluster 1 — Sub-agent dispatch fallbacks**: enumerate
   which child skills' Phase-N juries and Phase-N approval
   sites need fallback prose; for each, the contract that
   must hold (what gets recorded, what's NOT covered).
2. **Cluster 2 — Resume Logic sentinel-awareness**: identify
   the children whose Resume Logic tables must consult the
   `parent_orchestration` sentinel; the row position; the
   sentinel-present vs absent behavior contract.
3. **Cluster 3 — Format-reference clarifications**: the
   specific surfaces in brief-format, prd-format,
   design-format, plan-format that need clarification
   (public-issue-number grammar, Decisions-and-Trade-offs as
   canonical Open Questions closure, Implementation Issues
   ownership, etc.).
4. **Cluster 4 — Validator extensions**: shirabe#157 schema
   silent-skip exit code; content-budget enforcement;
   mechanical writing-style banned-word grep; structural-format
   reviewer extension for `/design` Phase 6.
5. **Cluster 5 — Cross-skill consistency rules**: PLAN/DESIGN
   field consistency, `/design` Phase 6 wip/-hygiene
   carve-out, eval-fixture line-1 marker.
6. **Cluster 6 — Convention updates**: slug-prefix detection
   at Phase 0, release-notes adopter-doc home, structural-format
   reviewer for `/design` Phase 6.
7. **Adjacent observation — CLI version-skew preflight**: the
   contract child skills must hold when their prose prescribes
   a `shirabe` subcommand that may not exist in the installed
   binary.
8. **Sub-agent dispatch parallel-jury fan-out**: the
   load-bearing requirement that serial-self-jury satisfies
   the jury contract under sub-agent dispatch with the
   independence-loss caveat surfaced in the verdict.

## Coverage Notes

- **Who is affected**: shirabe operators running `/scope` and
  `/charter`; downstream authors invoking child skills
  directly; the skills themselves under sub-agent dispatch.
- **Current situation**: skills assume ideal operating
  conditions (Agent tool fan-out, AskUserQuestion, empty wip/,
  matched CLI version, validator catches structural drift).
- **What's missing**: explicit fallback paths at every
  boundary where the assumption silently degrades.
- **Why now**: two dogfooding rounds (v0.7.0-era and
  v0.9.0-era) have surfaced the pattern; the chain tax
  compounds across child skills.
- **Scope boundaries**: PRD enumerates contracts; DESIGN
  picks mechanisms.
- **Success criteria**: every dispatched child runs with
  explicit signal at every boundary the pattern's prose
  silently degraded at.
