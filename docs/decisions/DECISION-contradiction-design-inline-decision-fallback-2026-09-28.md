---
status: Accepted
decision: |
  The policy owner picked "Checkable tiers". Under a parent skill, standard-tier questions resolve inline and critical ones go to /decision, and the provenance field is added to the format reference.
rationale: |
  The dispatch reference let /design resolve decisions inline when a parent
  routes decisions back to itself, while /design's own Phase 2 always spawns
  /decision, and nothing said when the fallback applied. Whether a /scope run
  bypassed /decision was left to the agent. Splitting on the question's tier
  gives the agent a condition it can check, keeps /decision's full treatment
  for the questions that are hard to undo, and recording provenance makes
  each resolution traceable.
---

# DECISION: /design under a parent resolves standard questions inline

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `design-inline-decision-fallback` item: /design's inline-decision
fallback under a parent.

`references/fixes/sub-agent-dispatch.md` says that under a parent, /design
resolves decisions inline and records `decision_provenance`. /design's own
Phase 2 (`skills/design/references/phases/phase-2-execution.md`) always
spawns one /decision agent per question, and `skills/design/SKILL.md` says
Phase 2 delegates each question to the decision skill. Nothing defines when
the fallback applies, and the provenance field appears in no format reference
or validator, although a /scope test fixture carries
`decision_provenance: inline-resolved`. Whether a /scope run bypasses
/decision was left to the agent's judgment.

## Decision

The policy owner picked "Checkable tiers". Under a parent skill, standard-tier questions resolve inline and critical ones go to /decision, and the provenance field is added to the format reference.

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- This is the DESIGN's option 2, which was the recommendation.
- /design's Phase 2 and format reference change in the design pull request of
  the contradiction-settlement PLAN; the dispatch reference and the /scope
  fixture change in the scope pull request.

## Options Considered

- **Option 1: Delete the fallback.** Every run spawns /decision agents; most
  expensive.
- **Option 2: Under the sentinel, standard-tier questions resolve inline and
  critical ones go to /decision; add the field to the format reference.** A
  condition the agent can check, and irreversible questions still get the
  full treatment.
- **Option 3: Resolve every question inline under /scope.** Cheapest; loses
  /decision's rigor on the questions that need it.

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, /design under a parent resolves standard-tier questions itself
and sends critical ones to /decision, and every resolution records where it
came from. A direct /design run is unchanged.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `references/fixes/sub-agent-dispatch.md`
- `skills/design/references/phases/phase-2-execution.md`
- `skills/design/SKILL.md`
