# Design Summary: shirabe-progression-authoring

## Input Context (Phase 0)

**Source PRD:** `docs/prds/PRD-shirabe-charter-skill.md` (Accepted at commit 8c17099, transitioned to In Progress on 2026-05-24).

**Design scope:** SHARED across the parent-skill pattern's three features (`/charter`, `/scope`, `/work-on` migration). Lifts the 10 pattern-level requirements from `/charter`'s PRD (R1, R3, R9, R10, R11, R12, R13, R14, R17a, R18) into pattern-level scope. `/charter`-specific bindings stay in `/charter`'s PRD.

**Problem (implementation framing):** Commit to a parent-skill contract that satisfies the 10 pattern-level requirements, accommodates two core-layer constraints (wip/-based intermediates, TeamCreate single-team-per-leader blocks nested `/decision` sub-teams), and leaves room for the future amplifier-layer substrate without forcing redesign — by treating the contract as the freeze line and implementations as substitution variables.

## SE4 directives in effect

- **NO wip/ cleanup at Phase 6.** wip/ artifacts (this summary, coordination manifest, per-decision reports, security report, review verdicts) persist as durable evidence.
- **NO PR creation at Phase 6.** Branch accumulates brief + PRD + design + plan; single PR after the full tactical chain completes.
- Status transition Proposed → Accepted IS done at Phase 6 on team-lead approval.
- Team `design-shirabe-progression-authoring` is NEVER destroyed (persists for re-spawning + `/plan` team queries).
- Nested `/decision` sub-teams NOT supported in core layer. Each decision-researcher walks `/decision` inline.

## Decision drivers identified (input queue for Phase 1)

15 drivers across four groups (PRD deferred questions ×6, pattern-level requirements ×4 collapsed buckets, SE4 directives ×3, implementation-specific ×2). Phase 1 will decompose these into N independent decision questions and apply the standard/critical classification.

## Current Status

**Phase:** 0 — Setup (PRD mode) complete.
**Last Updated:** 2026-05-24.
**Next:** Phase 1 — Decision Decomposition. Present decomposition to team-lead before spawning decision-researchers.
