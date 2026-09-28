---
status: Accepted
decision: |
  The policy owner picked "Loop back to CI". The failing_fixed outcome loops back to ci_monitor, and the fallback edge goes to done_blocked.
rationale: |
  /work-on promises a pull request with passing CI, and callers rely on that
  promise. Today a CI fix ends the run without CI being checked again, so a
  run can report success on red or unfinished CI. Looping back enforces the
  skill's own contract at the cost of one more poll per fix, and sending the
  fallback to a failure terminal stops the run from reporting success it
  hasn't earned. The CI cap from the retry-caps decision keeps the loop
  bounded.
---

# DECISION: a CI fix goes back to CI monitoring

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `ci-fix-ends-run-unverified` item: a CI fix ends the run without
re-checking CI. It touches /work-on.

/work-on promises its output is an open, ready pull request with passing CI
(`skills/work-on/SKILL.md`). `phase-6-pr.md` says to monitor CI until all
checks pass, the `done` directive in `work-on.md` assumes green CI, and
`finishing-obligations.md` lists green CI as enforced by `ci_monitor`'s
`ci_passing` gate. The `ci_monitor` directive tells the agent to fix what it
can and submit `failing_fixed` when the gate fails.

What runs: in `skills/work-on/koto-templates/work-on.md`, the `ci_monitor`
state's `ci_outcome: failing_fixed` evidence routes to the `done` state with
no gate, and the state's unconditional fallback edge also reaches `done`.
Only `ci_outcome: failing_unresolvable` reaches the `done_blocked` state. A
run can end reporting success on red or unfinished CI.

## Decision

The policy owner picked "Loop back to CI". The failing_fixed outcome loops back to ci_monitor, and the fallback edge goes to done_blocked.

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- This is the DESIGN's option 1, which was the recommendation.
- The loop is bounded by the retry-caps decision's CI cap, the one in
  `DECISION-contradiction-retry-caps-2026-09-28.md`: after 3 fix pushes the
  agent submits `ci_outcome: failing_unresolvable`, which routes to the
  `done_blocked` state.
- The routing change lands in /work-on's template in the work-on pull request
  of the contradiction-settlement PLAN.

## Options Considered

- **Option 1 (chosen): `failing_fixed` loops back to `ci_monitor` and the
  fallback goes to `done_blocked`.** Enforces the skill's own contract at
  the cost of one more poll per fix.
- **Option 2: Keep the routing and correct the prose to say CI is not
  re-checked.** No behavior change, but the output contract gets weaker.

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, a run that pushes a CI fix polls CI again in `ci_monitor` before
it can reach the `done` state, and a run that can't get CI green ends at the
`done_blocked` state instead of `done`.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `docs/decisions/DECISION-contradiction-retry-caps-2026-09-28.md`
- `skills/work-on/koto-templates/work-on.md`
- `skills/work-on/references/phases/phase-6-pr.md`
