---
schema: brief/v1
status: Draft
problem: |
  The completion cascade walks a finished PLAN's upstream chain,
  transitioning DESIGN and PRD nodes to their terminal states. It has
  no handler for a BRIEF node, so a chain that includes a BRIEF dies
  with an "unrecognized filename prefix" error and never finalizes.
outcome: |
  A PLAN whose upstream chain runs through a BRIEF cascades cleanly to
  completion: the BRIEF transitions to Done alongside the DESIGN and
  PRD, and the walk continues up to the ROADMAP without erroring.
---

# BRIEF: scope-completion-cascade

## Status

Draft

## Problem Statement

When a PLAN's work is implemented, the completion cascade
(`skills/work-on/scripts/run-cascade.sh`) deletes the PLAN and walks
the `upstream` chain, transitioning each node to its terminal status:
DESIGN to Current, PRD to Done, ROADMAP to Done. The walk dispatches
on the node's filename prefix.

The dispatch has no case for a BRIEF. Since `/scope` started producing
chains shaped BRIEF → PRD → DESIGN → PLAN, a BRIEF now sits as the
PRD's upstream. When the cascade reaches that BRIEF node, the prefix
doesn't match DESIGN, PRD, ROADMAP, or VISION, so it hits the catchall
branch and fails with "unrecognized filename prefix." The walk stops
there.

The consequence isn't cosmetic. The cascade is the mechanism that
finalizes a `/scope`-produced chain once its PLAN is done. With the
BRIEF node unhandled, that chain can never fully finalize: the BRIEF
stays in a non-terminal status forever, the cascade reports a failure,
and the ROADMAP above the BRIEF is never reached. Every chain that
includes a BRIEF — the default shape `/scope` produces — is affected.

## User Outcome

A skill author finishes implementing a PLAN that `/scope` produced
from a BRIEF → PRD → DESIGN → PLAN chain. The completion cascade runs,
deletes the PLAN, and walks the chain to its end without erroring. The
BRIEF transitions to Done, just as the DESIGN reaches Current and the
PRD reaches Done. The walk continues past the BRIEF to its upstream
ROADMAP and finalizes the whole chain. The author sees a clean
completion, not a "unrecognized filename prefix" failure on the
artifact `/scope` was built to produce.

## User Journeys

### Journey 1: A /scope-produced chain completes end to end

A skill author specified a feature through `/scope`, producing a chain
BRIEF → PRD → DESIGN → PLAN. They implement the PLAN's work, and the
completion cascade fires. It deletes the PLAN and walks upstream: the
DESIGN moves to Current, the PRD moves to Done, the BRIEF moves to
Done, and the walk reaches the ROADMAP and finalizes it. The whole
chain settles in one cascade run, with no manual cleanup of the BRIEF
left behind.

### Journey 2: The cascade finalizes the BRIEF alongside DESIGN and PRD

A skill author's PLAN cascade reaches the BRIEF node that sits as the
PRD's upstream. Instead of failing the run, the cascade transitions
the BRIEF to Done — its terminal status, with no directory move — and
records the step the same way it records the DESIGN and PRD
transitions. The BRIEF doesn't move directories; it stays in
`docs/briefs/`. The walk reads the BRIEF's upstream field and
continues up to the ROADMAP. The author's completion summary shows the
BRIEF transition as a successful step beside the others.

## Scope Boundary

This brief covers the BRIEF handler in the completion cascade and the
hardening needed for the walk to pass through a BRIEF node cleanly.

The scope holds the following inside:

- **A BRIEF handler in `run-cascade.sh`** that transitions a BRIEF
  node to its terminal status (Done), stages the change, records the
  step, and lets the walk continue to the BRIEF's upstream. The
  handler mirrors the existing PRD handler's shape, since a BRIEF —
  like a PRD — transitions in place with no directory move.
- **Hardening the chain walk** so a BRIEF node is a recognized prefix
  rather than a catchall failure. This includes the dispatch branch
  and the parallel prefix-matching used for the walk's error messaging,
  so a BRIEF no longer reads as "unrecognized."
- **A paired test** covering a chain whose walk passes through a BRIEF
  node, asserting the BRIEF transition step succeeds and the walk
  continues upstream, following the existing cascade test scenarios.

The scope explicitly excludes:

- **The strategic-chain cascade.** A STRATEGY artifact is durable and
  has no discrete completion trigger the way a PLAN does, so there's no
  terminal cascade to extend for it. Deferred.
- **Changing PLAN deletion or the existing DESIGN, PRD, and ROADMAP
  behavior.** Those nodes already cascade correctly. This work adds the
  missing BRIEF case without touching how the other nodes transition,
  move, or terminate the walk.

## References

- Cascade script with the handler gap:
  `skills/work-on/scripts/run-cascade.sh`.
- Paired cascade test harness:
  `skills/work-on/scripts/run-cascade_test.sh`.
- BRIEF lifecycle and terminal status:
  `crates/shirabe-validate/src/transition.rs`.
- BRIEF format reference (no directory move, Draft → Accepted → Done):
  the brief format reference under the brief skill's references.
</content>
</invoke>
