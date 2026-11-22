---
schema: brief/v1
status: Draft
problem: |
  A /work-on run's koto session is meant to be its own ledger, written by the
  run alone. Test-change acceptance lets a minted seat, a person at a terminal
  or a coordinator's overrule write their own verdicts into that ledger, and its
  seat repeats the review panels' question about edited tests with less to go on.
outcome: |
  An author running /work-on gets every edited test and observation judged by
  the review panels, and judged again when it changes after they looked, with
  the run recording each result itself. Nobody mints, waits on or relays an
  acceptance seat, and every ledger line is the run's own, its source named.
motivating_context: |
  An exploration of who writes a run's koto session found that test-change
  acceptance is the one routine place where a party other than the run writes
  its judgment there. The owner chose to retire the seat into the review panels
  rather than keep it and have the run relay its verdict.
---

# BRIEF: acceptance-write-drift

## Status

Draft

## Problem Statement

shirabe works on the producer side of a pull request. Its gates and review
panels exist so that one author sends the strongest PR it can, and trust in
that PR is established where it's reviewed. koto is the producer's ledger: the
run writes it, and each decision in it is attributed to the run, to a session
above it, or to a person. A reviewer who can read the ledger gets proof of
work; one who can't still has a PR that stands on its own.

Test-change acceptance doesn't fit that model. It was built as certification:
when a fix passes with an edited test or an observation instead of a red-first
reproduction, the pass is held until "someone other than the run" accepts it.
To make that claim, outside parties write their own lines into the run's
`test_change_ledger.jsonl`: a minted acceptance seat (`test-change.sh seat`,
then `accept` or `decline` under the seat's identity), a person at a terminal in
a repository that requires one, and a coordinator's `overrule`, which can land
after the run has already finished. That's the only routine place in shirabe
where an outside party writes its judgment into a producer's ledger, and it
contradicts koto's own rule that one session has one writer.

The judgment it buys is mostly a duplicate. The panels already ask whether
each edited test corrects or weakens what it checked, with the production diff
in front of them and several reviewers at once. The seat asks the same
question of the test hunks alone, as a single agent that runs nothing. What the
seat covers that the panels don't is narrow: observations, and tests edited
after the panel round, which today only the seat's digest-bound recheck
catches. Around that narrow value sits a large machine (the seat brief, the
authority rules in `scripts/lib/acceptance-rule.sh`, the person path's
terminal guards, the overrule) and a long tail of open bugs against it.

## User Outcome

The author running `/work-on`, whether an agent or the person behind it, gets
a run that judges its own test changes the same way it judges everything else.
Every edited test and every observation goes in front of the review panels, and
anything that changes after a panel seat last looked at it goes back through a
re-verifier before the run counts its checks. The author doesn't mint a seat,
wait on one, or relay its verdict, and a run no longer stalls because the seat
machinery misread a brief.

A reviewer who opens the run's koto session finds a ledger the run wrote: every
line came from the run, and where an outside party's input mattered (a person
overriding a panel gate, say) the run recorded it with that person named. The
PR still stands on its own for a reviewer who never opens koto.

## User Journeys

### An issue whose fix edits a test

An agent runs `/work-on` on an issue, and the fix has to change an existing
assertion. The review panels judge the edit as part of their round, alongside
the production change it serves, and the run records the verdict in its own
ledger. The run reaches its PR without an acceptance seat being minted or
waited on.

### A test edited after the panels looked

Late in a run, a CI failure leads to a commit that edits a test the panels
already judged. Before the run counts its checks at `pr_precheck` or
`ci_pass_counting`, a re-verifier judges the changed test, and a `weakens`
verdict sends the run back rather than letting the commit through. The same
holds when the CI fix is pushed from `/execute`'s monitoring path instead of
from `/work-on` itself.

### A person overrides a panel gate

A person decides a panel verdict gate should be passed and records an
override. The override lands in the run's ledger with the person named and the
surface they used, so a later reader knows exactly who made that call and that
the run didn't make it on its own.

### A plan review run beside a live plan

An author who wants a second opinion runs `/review-plan` directly on a plan that a `/plan` session is still
writing. Instead of writing its verdict into the live session it doesn't own,
`/review-plan` refuses or hands the review off, and the `/plan` run stays the
only writer of its ledger.

## Scope Boundary

### In scope

- Retiring the acceptance seat in `/work-on`: minting a seat, the seat's
  accept and decline verdicts, the coordinator overrule, the seat's brief and
  the authority rules behind them, or reducing them to what the requirements
  decide to keep.
- Moving the judgment only the seat provides into the review panels'
  re-verifier: edited tests and observations whose content changed since a
  panel seat last judged them.
- The check that replaces the acceptance status read at the three points where
  a run counts its checks, kept under the same gate names.
- Sending late commits back through a re-verifier, both from `/work-on`'s
  counting points (shirabe#1931) and from `/execute`'s CI-fix path
  (shirabe#1730).
- What happens to outside input that is kept: recorded by the run with its
  source named, or kept in the decider's own session.
- The two smaller outside writers: a person's override of a panel verdict
  gate, and `/review-plan` run directly on a live `/plan`.
- Keeping the producer-side parts of red-first: red and green recording,
  classifying the unit's test changes, the run's notes on why it edited a test,
  and the record a run reads back.
- Superseding the parts of the red-first requirements and design that assume
  an outside acceptor.

### Out of scope

- A coordinator's land step taking the worker's ledger panel round as the
  review. That is intended: the producer stands behind its own work, and the
  coordinator need not redo the worker's checks.
- Widening the post-panel freshness check from tests to every late commit. A
  production commit made during a CI fix still reaches the PR without a fresh
  panel look; that gap is real but separate work.
- Changes to koto itself (owner checks, anchors, hooks, or a cross-session
  decision listing). This work uses the koto that ships today.
- Instructions that live outside shirabe and still describe the seat. Their
  owners update them once this lands.
- `/work-on`'s states and edges. They stay as they are unless the design finds
  a reason to change them.

## Open Questions

- Repositories that declare `## Test Change Acceptance: person`: is the
  person path dropped, kept as a person decision the run records, or replaced
  by a forge-side approval such as a required review from a second account?
- The coordinator overrule: dropped, or kept as a koto reversal in the
  coordinator's own session?
- Are panel verdicts also recorded as typed koto decisions, attributed per
  seat, alongside the verdict ledger the gate reads?
- Does a re-verifier `weakens` on a late test edit count against the panel
  retry budget, or keep its own per-path limit?

None of these block the brief; each is a requirements decision for the PRD.

## References

- `docs/prds/PRD-red-first-fixes.md` and
  `docs/designs/current/DESIGN-red-first-fixes.md`: where test-change
  acceptance was specified.
- `skills/work-on/references/red-first.md`: how a run handles red-first,
  edited tests and acceptance today.
