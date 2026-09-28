---
status: Accepted
decision: |
  The policy owner answered: "wire it into the koto workflow itself, ditch the file, make it readable through koto calls".
rationale: |
  /execute advertises carrying earlier children's summaries forward to later
  ones, and its evals assert it, but the file it builds has no reader: koto
  schedules the children and no /work-on file opens current-context.md. The
  summaries already live in koto, so reading them through koto calls makes
  the capability real without a loose file in the work tree, which /execute's
  closed write-target set doesn't allow for.
---

# DECISION: carry earlier children's summaries through koto

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `cross-issue-context-no-consumer` item: cross-issue context is
built but nothing reads it. It touches /execute's single-PR runs.

`skills/execute/references/cross-issue-context.md` tells the agent, before
dispatching each child, to concatenate earlier children's summaries into
`current-context.md`, and `skills/execute/koto-templates/execute.md`'s
`spawn_and_await` points at that reference. The same template tells the
agent not to inspect children, and `skills/execute/SKILL.md`'s closed
write-target set has no loose file at the checkout root.

What runs: `skills/plan/scripts/plan-to-tasks.sh` gives children only task
variables, and koto schedules them. No /work-on file reads
`current-context.md`; only evals assert it. Deleting the step drops a
capability the skill advertises, and keeping it leaves an instruction with no
effect and a stray file in the work tree.

## Decision

The policy owner answered: "wire it into the koto workflow itself, ditch the file, make it readable through koto calls".

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- Drop `current-context.md`.
- First check whether a child session can read the parent's koto context
  today. If that needs a koto capability, report it before building
  anything, and make no koto change under this feature.
- Checked on koto 0.14.1: `koto context get <session> <key>` reads another
  session's context from a different worktree, and sessions record their
  parent workflow, so no koto capability is needed.
- This is a variant of the DESIGN's option 2, which wired /work-on's analysis
  phase to read the built context from outside the work tree. The answer
  keeps the wiring and replaces the file with koto calls.
- The /execute side lands in the execute pull request of the
  contradiction-settlement PLAN and the /work-on reader in the work-on pull
  request.

## Options Considered

- **Option 1: Delete the step.** Honest about what runs today; drops the
  advertised carry-forward.
- **Option 2: Wire /work-on's analysis phase to read it, built outside the
  work tree.** Makes the capability real; needs a template change in both
  skills.
- **Option 3: Leave it.** No work, but the instruction keeps claiming an
  effect it does not have.
- **New option (chosen): Wire the carry-forward through koto calls, with no
  file.**

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, no loaded file tells the agent to build `current-context.md`, and
a child's analysis reads earlier children's summaries through koto. koto
itself doesn't change under this feature.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `skills/execute/references/cross-issue-context.md`
- `skills/execute/koto-templates/execute.md`
- `skills/plan/scripts/plan-to-tasks.sh`
