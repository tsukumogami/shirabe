---
status: Accepted
decision: |
  The policy owner picked "No plan on abandon". An abandoned run writes no PLAN, only the upstream documents.
rationale: |
  An abandonment exit triggered during /plan wrote a Draft PLAN, which the
  same reference, /plan's rules and the lifecycle check all treat as a
  violation, so the exit meant to preserve work left a red branch. Writing no
  PLAN needs no validator exemption, and a PLAN that never finished has
  little a later run could reuse.
---

# DECISION: an abandoned /scope run writes no PLAN

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `scope-abandonment-draft-plan` item: /scope's abandonment exit
writes a Draft PLAN that fails the lifecycle check. It touches /scope.

`skills/scope/references/phases/phase-3-exit-finalization.md`'s
abandonment-forced exit, when triggered while /plan is running, writes the
PLAN at Draft at its canonical path with a marker. The same reference, and
`skills/plan/SKILL.md`, say a committed Draft PLAN is a violation. What runs:
`crates/shirabe-validate/src/lifecycle.rs` requires a single-pr PLAN to be
Active, and its L01 rule has no abandonment exemption. An abandoned run's
branch fails the lifecycle check.

## Decision

The policy owner picked "No plan on abandon". An abandoned run writes no PLAN, only the upstream documents.

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- This is the DESIGN's option 2, which was the recommendation.
- A partial PLAN's content is lost unless the upstream drafts carry it.
- The /scope change lands in the scope pull request of the
  contradiction-settlement PLAN, and the `skills/plan/SKILL.md` statement in
  the plan pull request. The validator does not change.

## Options Considered

- **Option 1: The validator skips a PLAN carrying the abandonment marker.**
  Keeps the partial PLAN; adds an exemption to the validator.
- **Option 2 (chosen): Abandonment never writes a PLAN, only the upstream artifacts.**
  No exemption; the partial PLAN's content is lost unless the upstream drafts
  carry it.

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, an abandoned /scope run commits its upstream documents and no
PLAN, and its branch passes the lifecycle check.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `skills/scope/references/phases/phase-3-exit-finalization.md`
- `skills/plan/SKILL.md`
- `crates/shirabe-validate/src/lifecycle.rs`
