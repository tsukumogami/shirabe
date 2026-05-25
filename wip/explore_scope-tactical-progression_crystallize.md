# Crystallize Decision: scope-tactical-progression

## Chosen Type

**BRIEF** (per post-SE6 shirabe convention; framework substitutes PRD).

The /explore crystallize framework lists ten supported types but does NOT
list BRIEF as a target. This is a documented gap: SE6 (shirabe#95) added
the /brief skill and BRIEF artifact type, but /explore's Phase 5 was not
updated with a `phase-5-produce-brief.md` route. (Worth filing as SE12
ergonomics item.) In post-SE6 shirabe, the tactical chain is `BRIEF →
PRD → DESIGN → PLAN`, with BRIEF as the chain's preamble carrying problem
statement, user outcome, user journeys, and scope boundary.

Per the user's explicit goal ("a brief that walks us in that direction on
all advanceable fronts"), the produce artifact is a BRIEF. The PRD-route
phase reference is the closest framework template; Phase 5 will use that
structure as a guide while producing a BRIEF-shaped artifact at
`docs/briefs/BRIEF-shirabe-scope-skill.md` in shirabe.

## Rationale

The exploration produced an architectural orientation choice (extend the
parent-skill pattern to preserve full /charter symmetry) plus a set of
cascading decisions (new gate type, Phase-N Reject contracts in /prd +
/design, top-level worktree-discipline reference, BRIEF-as-chain-member,
design doc rename, L9 reclassification). These decisions need to land in
a durable artifact that grounds the rest of the tactical chain.

BRIEF is the right altitude because:
1. The exploration framed a problem (how to ship /scope), identified an
   approach orientation, and surfaced what the chain needs to address —
   classic BRIEF content (problem + outcome + scope + journey).
2. PRD-level requirements emerged DURING exploration (gate types, exit
   shapes, fold items) but they're not yet enumerated at AC granularity —
   that's PRD authoring work.
3. DESIGN-level decisions emerged in the orientation (extend vs narrow)
   but the concrete artifact rewrites haven't been specified — that's
   DESIGN authoring work.

The BRIEF carries the architectural choices made during exploration so
later artifacts (PRD, DESIGN, PLAN) build on a settled foundation rather
than re-litigating the orientation.

## Signal Evidence

### PRD-Route Signals Present (used as proxy for BRIEF)

- **Single coherent feature emerged from exploration**: `/scope`, the
  tactical-chain parent skill, is the one feature.
- **Multiple stakeholders need alignment on what to build**: maintainer
  + future inheritors of the pattern (SE8 `/work-on` migration). The
  orientation choice has cross-skill implications.
- **The core question is "what should we build and why?"**: with
  qualifications — "why" is partially answered by upstream SE7 roadmap
  entry, "what" was refined by this exploration.

### PRD-Route Anti-Signals Checked

- **Requirements were provided as input to the exploration**: partial.
  The high-level requirement (parent skill for tactical chain) was given
  by the roadmap; the specific requirements (gate types, exit shapes,
  fold items) emerged from exploration. Borderline — does NOT cleanly
  demote.

### Why Not Plain PRD

The user's explicit goal was a BRIEF, and shipping a PRD without a
BRIEF would skip the tactical chain's entry preamble. SE4's precedent
(BRIEF-shirabe-charter-skill.md shipped alongside the PRD) ratifies
the BRIEF-first ordering.

## Alternatives Considered

- **Design Doc**: Some architectural decisions were made during
  exploration (orientation choice). However, the broader DESIGN work
  (each phase reference content, eval shape, exit-artifact template
  layouts) hasn't been specified. DESIGN authoring follows BRIEF →
  PRD in the tactical chain. Ranked lower as the immediate target.

- **Plan**: No upstream PRD or DESIGN exists yet for SE7. The work
  isn't ready for issue decomposition. Anti-signal demoted: "Open
  architectural decisions need to be made first" (the per-phase-doc
  authoring decisions remain).

- **No Artifact**: Strongly demoted. Multiple architectural choices
  were made during exploration (orientation, BRIEF-as-chain-member,
  gate type addition, contract extensions). These need a durable
  home; wip/ gets cleaned at merge. The crystallize framework
  explicitly names "Any architectural, dependency, or structural
  decisions were made during exploration" as a No-Artifact anti-signal.

- **Decision Record**: A single decision (orientation) was made, which
  is a Decision Record signal. But multiple interrelated downstream
  decisions cascade from it (contract extensions, doc rename, fold
  selections). Anti-signal applies: "Multiple interrelated decisions
  need a design doc" — or in this case, a BRIEF that grounds the
  cascade.

- **VISION**: Anti-signal: project exists, requirements emerged.
  Demoted.

- **Rejection Record / Roadmap / Spike / Competitive**: Anti-signals
  apply to all. Demoted.

## Deferred Type Note

**BRIEF**: Not formally listed in `references/quality/crystallize-framework.md`.
Should be added to /explore's crystallize framework as a supported
type post-SE6. Recommended SE12 ergonomics fold:

- Add BRIEF to the Supported Types section of the framework
- Author `phase-5-produce-brief.md` with handoff structure (modeled on
  `phase-5-produce-prd.md`)
- Add BRIEF disambiguation rules (BRIEF vs PRD: BRIEF is preamble;
  PRD is requirements contract)

Until that ships, /explore exits that conceptually want a BRIEF should
use the PRD-route reference as a guide while producing a BRIEF-shaped
artifact, as we do here.

## Phase 5 Routing

Use `phase-5-produce-prd.md` as the structural reference, with these
substitutions:

- Target artifact: `docs/briefs/BRIEF-shirabe-scope-skill.md` (not PRD)
- Target skill: `/brief` (not `/prd`)
- Artifact shape: BRIEF (Problem / User Outcome / User Journeys / Scope
  Boundary), not PRD (Requirements / Acceptance Criteria)
- Target visibility: Public (shirabe), so all private-only content must
  be filtered at handoff (the research files cited only public paths,
  so no filtering is currently required)
- Handoff includes the architectural orientation, the cascading
  decisions, the chain shape, the 6-item fold list, and the BRIEF-as-
  chain-member framing
