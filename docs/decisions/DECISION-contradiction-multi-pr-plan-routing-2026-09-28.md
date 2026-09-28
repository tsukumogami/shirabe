---
status: Accepted
decision: |
  The policy owner picked "Refuse, point to /work-on". execute-open.sh refuses a multi-pr PLAN and names /work-on as the entry point.
rationale: |
  /execute's SKILL.md says multi-pr PLANs are out of scope and belong to
  /work-on, and /deliver and /scope route them there, but execute-open.sh ran
  any non-coordinated PLAN, multi-pr included, on the single-pr template. A
  multi-pr PLAN means one pull request per issue, landed through /work-on;
  running it on the shared-branch template lands it as one pull request.
  Refusing it makes /execute agree with every other entry point.
---

# DECISION: /execute refuses a multi-pr PLAN

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `multi-pr-plan-routing` item: whether /execute runs multi-pr
PLANs.

`skills/execute/SKILL.md` says multi-pr is out of scope and sends the user to
/work-on, and says koto is the only judge of the arguments, with no refusal
before `koto init` except three listed cases. /deliver and /scope route
multi-pr PLANs to /work-on. What runs:
`skills/execute/scripts/execute-open.sh` picks the template from the PLAN's
`execution_mode` and runs anything not coordinated, multi-pr included, on
`execute.md`, and `plan-to-tasks.sh` can build tasks for it.

## Decision

The policy owner picked "Refuse, point to /work-on". execute-open.sh refuses a multi-pr PLAN and names /work-on as the entry point.

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- This is the DESIGN's option 1, which was the recommendation.
- The refusal is listed with /execute's other pre-init refusals in
  `skills/execute/SKILL.md` and gets a test in `execute-open.sh`'s suite. It
  lands in the execute pull request of the contradiction-settlement PLAN.

## Options Considered

- **Option 1: Refuse multi-pr in `execute-open.sh`, and add it to the listed
  refusals.** Matches /deliver's and /scope's routing and the meaning of
  multi-pr.
- **Option 2: Correct SKILL.md to say /execute runs multi-pr PLANs on the
  shared-branch template.** No behavior change, but a multi-pr PLAN then lands
  as one shared-branch pull request, which is not what the mode means
  elsewhere.

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, `/execute` on a multi-pr PLAN stops before `koto init` and tells
the user to run /work-on, where it used to proceed.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `skills/execute/SKILL.md`
- `skills/execute/scripts/execute-open.sh`
