---
status: Accepted
decision: |
  The policy owner answered: "Agent decides, escalates -- note two things: 1) these skills aren't to be used only when developing tsukumogami itself. They are general purpose and built to be used by any devs. 2) a session operating a shirabe workflow is not different than a developer working on their own branch: obviously upstream will change over time, and they will have to rebase/merge and reconcile things, it's part of the job. The decision of that should be with whoever holds deciding power over the work, which locally is the agent, then its coordinator (and any coordinator of its coordinators) all the way to the user. At each step, shirabe:decision should be used to try to minimize churn and decide as close to the problem as possible, avoiding unnecessary communication between layers." (one spelling corrected)
rationale: |
  /scope's SKILL.md sent every intent-changing upstream change to the author,
  while its Phase 2 reference let the running agent settle it in place, and
  no code enforced either. Settling questions as close to the problem as
  possible keeps runs moving, and recording each call with its classification
  and reason leaves the judgment open to review by whoever sits above the
  agent. Naming who that is in each setting, a coordinator, the user, or a
  stop under --auto, makes the escalation something the agent can follow
  whether or not a coordinator exists.
---

# DECISION: the running agent reconciles upstream changes and escalates the rest

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `worktree-intent-change-owner` item: who judges an
intent-changing rebase under /scope.

When main moves under a /scope run in a way that changes something the chain
relies on, `skills/scope/SKILL.md` says the run halts and goes to the author.
`skills/scope/references/phases/phase-2-chain-orchestration.md` lets the team
lead resolve it in place when intent still holds and escalate to the author
only otherwise; under /scope the team lead is the same agent running the
chain. SKILL.md also says team-lead discipline is vacuous under /scope,
since /scope spawns nothing. Whether the running agent may approve its own
continuation after an upstream change is a question of who approves, and no
code enforces either side.

## Decision

The policy owner answered: "Agent decides, escalates -- note two things: 1) these skills aren't to be used only when developing tsukumogami itself. They are general purpose and built to be used by any devs. 2) a session operating a shirabe workflow is not different than a developer working on their own branch: obviously upstream will change over time, and they will have to rebase/merge and reconcile things, it's part of the job. The decision of that should be with whoever holds deciding power over the work, which locally is the agent, then its coordinator (and any coordinator of its coordinators) all the way to the user. At each step, shirabe:decision should be used to try to minimize churn and decide as close to the problem as possible, avoiding unnecessary communication between layers." (one spelling corrected)

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- The answer's shirabe:decision is the /decision skill.
- Record each such decision (/decision or `koto decisions record`)
  with its classification and reason.
- Make the escalation path concrete in the skills' text: under a
  coordinator, the coordinator; running solo, the user; under `--auto` with
  no coordinator, an escalation stops the run.
- Escalation is also described in
  `DECISION-contradiction-child-steps-under-scope-2026-09-28.md` and
  `DECISION-contradiction-design-inline-decision-fallback-2026-09-28.md`.
- This departs from the DESIGN's recommendation, option 1, which put every
  intent-changing rebase to the author. It is closest to option 2, the
  running agent resolves in place and escalates otherwise, and extends it
  with a chain of authority, a recorded decision per call, and an escalation
  target for each way a run can be set up.
- The /scope statements change in the scope pull request of the
  contradiction-settlement PLAN. Upstream changes arrive by merging main, per
  `DECISION-contradiction-force-push-after-rebase-2026-09-28.md`.

## Options Considered

- **Option 1: Always put an intent-changing rebase to the author.** Keeps a
  person on every change that alters what the chain committed to; an
  `--auto` run stops there.
- **Option 2: The running agent resolves in place when it judges intent
  unchanged, and escalates otherwise.** Fewer stops, but the agent judging
  the change is the one whose work it would invalidate.
- **New option (chosen): The running agent reconciles and records; escalation climbs the
  chain of authority.**

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, a /scope run settles upstream changes it can settle, records each
call with its classification and reason, and escalates the rest to its
coordinator, or to the user when running solo. An `--auto` run with no
coordinator stops at its first escalation.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `docs/decisions/DECISION-contradiction-force-push-after-rebase-2026-09-28.md`
- `skills/scope/SKILL.md`
- `skills/scope/references/phases/phase-2-chain-orchestration.md`
