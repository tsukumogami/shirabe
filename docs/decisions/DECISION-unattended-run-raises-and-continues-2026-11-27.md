---
status: Accepted
decision: |
  An unattended run with no coordinator no longer stops at its first question.
  When its evidence does not settle a choice, it judges whether the choice is
  cheap or costly to undo and records that judgment: a cheap one it decides
  provisionally and continues; a costly one it raises to the owner on the
  record and continues with the work that does not depend on the answer. What
  stands from the superseded record: a session settles what it can as close
  to the problem as it can, and the rest climbs to its coordinator and then to
  the person.
rationale: |
  Stopping at the first question leaves every later step of an unattended run
  undone for a choice that often touches only the run's own unpublished work,
  and when the choice does matter, the stop records nothing a person can
  answer later. The decision-escalation-ladder requirements replace the stop
  with a test the run can apply and a record it leaves either way: R8 says an
  unattended session decides a cheap choice provisionally and raises a costly
  one; R17 says a question reaches a person only in a turn the person started,
  and otherwise waits on the record while the session continues; R31 names the
  stop among the rules the work supersedes. The cheap-or-costly test is stated
  once, in references/question-procedure.md, and shirabe question attempt
  refuses a provisional decision whose session declares itself attended or
  calls the choice costly; it checks those declarations for consistency, not
  for truth.
---

# DECISION: an unattended run raises its question and continues

## Status

Accepted on 2026-11-27. It supersedes the clause of
`DECISION-contradiction-worktree-intent-change-owner-2026-09-28.md` that has
an unattended run with no coordinator stop at its first escalation. The rest
of that record stands.

## Context

`DECISION-contradiction-worktree-intent-change-owner-2026-09-28.md` settled
who judges an intent-changing upstream change: the running agent decides and
records its call, and what it can't settle climbs to its coordinator, then to
the person. Its implementation notes gave each setup an escalation target and
gave the unattended run with no coordinator none: "under `--auto` with no
coordinator, an escalation stops the run."

That stop was the only way out the skills had for an unattended run that
couldn't settle something. The other way they took was worse: the decision
protocol told an unattended run to follow its own recommendation and continue
without waiting, so a close call became an assumption nobody was asked about.
The decision-escalation-ladder requirements
(`docs/prds/PRD-decision-escalation-ladder.md`) and design
(`docs/designs/DESIGN-decision-escalation-ladder.md`) replace both with a
record: a question raised on koto's decision record has an identity, a
recipient and stored content, and waits there for an answer from a turn the
person started.

## Decision

An unattended run with no coordinator doesn't stop at its first question.
When its evidence doesn't settle a choice, it applies the cheap-or-costly test
in `references/question-procedure.md` and records the result with
`shirabe question attempt`:

- **Cheap to undo** (undoing needs only changes inside the session's own
  unpublished work): it decides, records the attempt as `provisional`, writes
  the choice as an `assumed` block, and continues. A provisional decision is
  listed for review and is not a question.
- **Costly to undo**: it records the attempt as `undecided`, raises the
  question with `shirabe question raise --attempt`, addressed to its
  dispatcher or, with none, to `person:owner`, and continues with the work
  that doesn't depend on the answer. When nothing else is left it ends its
  turn with the question open.

A cheap choice the session may still not settle (it contradicts an answer,
changes the scope, is outward-facing, or is a step reserved to someone else)
is raised as a costly one is. An attended run decides nothing provisionally:
it asks the person in a turn the person started, and where it can't ask, the
decision ends `UNDECIDED`.

What stands from the superseded record: a session settles what it can as
close to the problem as it can, records each call with its reason, and the
rest climbs to its coordinator and then to the person.

## Enforcement and its limits

`shirabe question attempt` refuses a `provisional` result in a session that
doesn't read as unattended, when the two run-mode variables name opposite
modes, with `--undo costly`, without an `--undo-reason`, or without
`--chosen`, and refuses an unattended `undecided` attempt that records no
undo judgment, or calls the choice cheap without a ground. It refuses a `;`
in `--chosen` and `--undo-reason`, so the entry's reason reads one way.
`shirabe question raise --attempt` refuses an attempt that isn't `undecided`.

The limits are these. The command reads the run mode from the environment
(`KOTO_RUN_MODE`, `CLAUDE_CODE_SESSION_ATTENDED`), because koto 0.42.0 keeps
no run mode per session for it to read; a skill started with `--auto` sets
neither, and a caller can set either one for a single call. The run mode and
the cheap-or-costly judgment are therefore the session's own declarations:
the command checks that they are consistent with the result, not that they
are true. Nothing but the procedure stops a session recording `decided` for
a matter it should have raised.

## Options Considered

- **Keep the stop.** Nothing unreviewed is decided, but every later step of
  the run waits on a choice that may touch only its own branch, and the stop
  leaves no question on the record for anyone to answer.
- **Follow the recommendation and continue.** The run finishes, but a costly
  choice is made as an assumption nobody was asked about.
- **Chosen: decide what's cheap provisionally, raise what's costly, and
  continue.** The run keeps moving on what doesn't depend on the answer, a
  cheap call is listed for review, and a costly one waits on the record for
  the person.

## Consequences

From this change, `/decision` can end `UNDECIDED`, the lightweight decision
protocol has three outcomes, and `/design` and `/explore` raise a question a
decision hands back. The skills whose own passages still state the stop or
the follow-the-recommendation rule change in later steps of the same work:
`/work-on`'s covered exits record an attempt before they stop (step 10),
`/execute` and `/scope` do the same, `skills/scope/SKILL.md` and its chain
orchestration reference included (step 11), the coordinator's scripts and
passages follow (step 12), and provisional decisions get their own listing
(step 13). Until those land, those skills' statements stay as they are.

## References

- `docs/decisions/DECISION-contradiction-worktree-intent-change-owner-2026-09-28.md`
- `docs/prds/PRD-decision-escalation-ladder.md` (R8, R17, R31)
- `docs/designs/DESIGN-decision-escalation-ladder.md`
- `references/question-procedure.md`
- `docs/guides/question-commands.md`
