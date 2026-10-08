---
status: Accepted
decision: |
  The policy owner answered: "one cap per step, but replaced by koto when ready". Each step has one retry cap, stated once in its step's directive: review panels take 2 blocking retries and then escalate, CI repair takes 3 fix pushes and then stops as unresolvable, and an unattended run never asks the user.
rationale: |
  The retry loops each stated a limit somewhere, and the limits disagreed: 2,
  2+, 3, 2-3, or none. Nothing in koto counts visits, so the agent had no
  single number to apply, and the CI instruction to ask the user after 2-3
  iterations can't be followed in an unattended run. Putting one cap in the
  directive of the state that loops puts the number where the agent reads it
  when it decides, without waiting on koto. Saying the prose is temporary
  marks it for deletion once koto enforces the same numbers.
---

# DECISION: one retry cap per step, stated in its directive

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

The review panel cap is superseded by
`DECISION-work-on-panel-retry-progress-cap-2026-10-01.md` (Accepted
2026-10-01): 2 unconditional blocking retries, a third only when the panel's
blocking count fell, and never more than 3. Everything else here stands.

## Context

This is the `retry-caps` item. It touches /work-on and /execute's single-PR
runs.

The review panels, analysis, implementation, PR creation and CI loops each
state a limit, in different places and with different numbers:

- `skills/work-on/references/review-panel-orchestration.md`: after 2
  `blocking_retry` outcomes the next pass must escalate.
- `skills/work-on/references/phases/phase-4a-scrutiny.md` and
  `phase-4c-qa.md`: escalate after 2+ retry cycles.
- `skills/work-on/references/phases/phase-4b-review.md`: no cap.
- `skills/work-on/koto-templates/work-on.md`: up to 3 for analysis and for
  implementation.
- `skills/work-on/references/phases/phase-6-pr.md`: for CI, ask the user after
  2-3 iterations; for PR creation, retry up to 3.

What runs: every retry edge in `work-on.md` is unconditional and nothing
counts visits, and /execute's `ci_monitor` fix pushes go through
`push-and-record.sh` with no counter. The agent has no single cap to apply,
whether the panel cap is per panel or shared is unstated, and under `--auto`
the CI instruction to ask the user can't be followed.

## Decision

The policy owner answered: "one cap per step, but replaced by koto when ready". Each step has one retry cap, stated once in its step's directive: review panels take 2 blocking retries and then escalate, CI repair takes 3 fix pushes and then stops as unresolvable, and an unattended run never asks the user.

The question put to the policy owner did not name the third cap, the one for
analysis, implementation and pull request creation. The policy owner ruled on
it separately on 2026-09-28: the third cap is 3.

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- The number 3 for the third cap first came from the DESIGN's recommended
  option by way of the PLAN, before the policy owner's ruling under Decision
  confirmed it.
- The implementer's reading, not the policy owner's words: the panel cap is 2
  blocking retries per run, shared across scrutiny, review and qa_validation,
  as /work-on's template states it. The answer names 2 retries for review
  panels without saying whether each panel counts its own.
- The caps apply in both /work-on and /execute.
- The prose caps are replaced by koto's enforcement from its attempt counts
  when koto supports it, with the same numbers.
- This is the DESIGN's option 1, state each cap once in the looping state's
  directive, which was the recommendation.
- "Stops as unresolvable" for CI means the agent submits
  `ci_outcome: failing_unresolvable` in the `ci_monitor` state, which routes
  to the `done_blocked` state in both templates.
- The caps land in /work-on's template and phase files, and in /execute's
  `ci_monitor` directive, in the work-on and execute pull requests of the
  contradiction-settlement PLAN.

## Options Considered

- **Option 1 (chosen): State each cap once, in the looping state's directive.** The
  directive is what the agent reads when it decides.
- **Option 2: Have koto count visits and enforce the caps.** Enforced rather
  than stated, but needs koto support that does not exist for this yet. The
  decision names it as the eventual replacement.
- **Option 3: Drop the caps.** Removes the contradiction by removing the
  limit; loops are then bounded only by the agent's judgment.

## Consequences

Each looping step now carries one number in its directive, the other
restatements are gone, and no loop asks the user during an unattended run;
the work-on and execute pull requests of the contradiction settlement applied
this (#557, #545). When
koto enforces retry caps from its attempt counts, the directive prose becomes
a deletion candidate and the numbers carry over unchanged.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `skills/work-on/references/review-panel-orchestration.md`
- `skills/work-on/references/phases/phase-6-pr.md`
- `skills/work-on/koto-templates/work-on.md`
- `skills/execute/koto-templates/execute.md`
