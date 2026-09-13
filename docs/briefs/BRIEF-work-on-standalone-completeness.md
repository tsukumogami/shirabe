---
schema: brief/v1
status: Accepted
problem: |
  A /work-on run invoked on its own opens a pull request and stops short of
  what makes the change mergeable. One capability is absent outright (the
  document-chain cascade) and the rest of the finishing obligations exist as
  prose a run may skip rather than as gated states a run cannot pass.
outcome: |
  Someone running /work-on on a single issue reaches a genuinely mergeable pull
  request without a supervisor supplying steps from memory, or the run stops
  and names what is missing instead of looking finished.
motivating_context: |
  Three dispatched worker sessions ran /work-on standalone on 2026-09-12 and
  2026-09-13. Each one ended looking complete and was not, and each needed the
  session supervising it to know the remaining steps and say them out loud.
---

## Status

Accepted

Accepted after a two-reviewer jury returned PASS on both content quality and
structural format, with `shirabe validate` clean.

Framing derived from a two-round exploration (tracking issue #361) that
overturned two of the six gaps the issue originally claimed. Requirements,
the technical approach, and the decomposition are the downstream PRD's,
DESIGN's and PLAN's to settle.

Three framing questions were deferred rather than answered here, and the
downstream PRD's Decisions and Trade-offs section is where each one closes:
what a person pointing the single-issue skill at a multi-pr plan should see
once that route is inverted; whether an issue with no documents behind it
changes what "done" means or is purely a pass-through; and whether the two
accepted documents this feature contradicts are superseded by a decision
record or amended in place.

## Problem Statement

A `/work-on` run invoked on its own opens a pull request and then stops,
leaving a change that looks finished and is not. Whoever is supervising has to
know what is still missing and say it out loud, every time. That happened three
times in two days across three separate repositories: one run had to be told to
open its pull request at all, to put the closing keyword in the body, and to
watch CI; another had to be told its document chain needed pulling to its
terminal state before the pull request could merge.

The obvious reading of this is that the steps live in the wrong skill — that
`/execute` owns a pile of finishing logic `/work-on` lacks. That reading is
half wrong, and the wrong half is the half people have been acting on.
`/work-on` never creates a draft pull request, so there is nothing for it to
mark ready. It already carries the closing keyword and the pull-request body
contract, in a reference file that `/execute` consumes too. Those obligations
are not missing.

What is actually wrong is two narrower things. **One capability is genuinely
absent**: nothing in `/work-on` touches the document chain, so a BRIEF, PRD,
DESIGN, PLAN or ROADMAP that should be pulled to its terminal state when the
work lands simply is not. And **the obligations that do exist are written as
prose rather than enforced as gates**. In `/execute` the same obligations are
workflow states with evidence schemas that a run cannot advance past without
submitting evidence. In `/work-on` they are instructions in a reference file.
The instruction to include the closing keyword reached all three of those runs
and all three skipped it, which is what tells you the gap is enforcement and
not delivery.

There is a third thing that makes the first two hard to fix in the wrong place.
A child workflow is seeded directly from its compiled template and never loads
the skill's own `SKILL.md`, so an obligation written there is not merely
skippable by a child — it is unreachable. A fix written in the wrong file would
appear to work under direct invocation and silently never reach a child run,
failing only on the path nobody watches.

## User Outcome

Someone who runs `/work-on` against a single issue ends up with a pull request
that is actually mergeable: the work is done, the chain of documents behind it
has been pulled to its terminal state, and nothing is waiting on a person to
remember a step. When the run cannot get there — because something genuinely
blocks it — it stops and says which obligation it could not discharge, rather
than reaching a terminal state that reads as success.

The same holds when nobody is supervising. A dispatched agent running the skill
unattended either finishes the change or reports precisely what stopped it, and
a person reviewing the result afterwards can tell those two cases apart without
reconstructing what the skill should have done.

Running a whole plan is unaffected in cadence: the plan-level finalization
still happens once for the plan rather than once per issue.

## User Journeys

### A maintainer fixes a one-off bug with no documents behind it

A maintainer picks up an ordinary issue — a bug report, no BRIEF, no PRD, no
DESIGN, no PLAN — and runs `/work-on` on it. The work lands, CI goes green, and
the pull request is mergeable. Because there is no document chain, the
finalization step recognizes that and passes through cleanly rather than
failing or emitting noise about documents that were never going to exist. The
maintainer never learns that a cascade step was involved, which is the point.

### A maintainer implements the last issue behind a design

A maintainer runs `/work-on` on an issue that belongs to a document chain: a
PLAN that sequences it, a DESIGN above that, a PRD and BRIEF above that. The
implementation lands as before, and this time the chain is pulled to its
terminal state as part of the same run — the PLAN removed, the documents above
it moved to their terminal statuses, all in the finalization the pull request
carries. The maintainer does not have to know that this was owed, and the
reviewer does not find a merged change with a stale chain behind it.

### An orchestrator runs a plan and the cascade fires once

An orchestrator drives a multi-issue plan and dispatches a child run per issue.
Each child does its issue's work and stops there: it does not pull the document
chain to its terminal state, because that is the plan's business and not the
issue's. When the last child finishes, the orchestrator finalizes once. The
observable behaviour of a plan run is unchanged from today — the point of the
journey is that adding finishing logic to the single-issue path did not change
the cadence of the plan path.

### Someone points the single-issue skill at a whole plan

A person does what the documentation told them to do yesterday and hands a
multi-pr plan to the single-issue entry point. Under the new arrangement that
is no longer how a plan is run. They land somewhere that tells them so and
names the entry point that does run it, rather than getting a confusing partial
result or a failure that reads as a defect. Their plan then runs through the
skill that owns plan execution, one pull request at a time.

## Scope Boundary

### In

- The document-chain cascade becoming reachable from a single-issue run,
  including the case where there is no chain to cascade.
- The finishing obligations `/work-on` already states in prose becoming gated
  states that a run cannot advance past without evidence.
- Where the shared cascade machinery lives, given that both entry points need
  it and only one owns it today.
- Multi-pr plan execution moving to the skill that owns plan execution, with
  the routing surface that currently says otherwise moved with it.
- A signal that tells a child run not to finalize, distinct from the one that
  already covers children sharing a branch.
- Keeping every new obligation somewhere a child run can actually receive it.

### Out

- **The definition-of-done gate returning cannot-verify.** A per-repository
  configuration gap: the gate reads a verification map that most repositories
  have never written. Both entry points run the same state, so nothing about
  this feature changes anyone's exposure to it.
- **The staleness gate calling a script that is not shipped.** A separate
  missing-file defect, already recorded as an open question elsewhere.
- **Terminal workflow states destroying their own context record.** Filed
  separately, cheap, independent of this feature, and already solved in a
  transferable form by another skill. Assigned elsewhere.
- **Gates being unable to observe whether a review panel ran.** Deliberately
  deferred until this feature settles which skill owns the panels, so the
  redesign happens once rather than twice.
- **The naming fossils left by the earlier split of these two skills.** Worth
  correcting, but not what this feature is for.
- **Merging the pull request.** The feature ends at a mergeable pull request;
  who merges it and when is unchanged.

## References

- `docs/designs/current/DESIGN-execute-skill.md` — records the earlier split
  that moved the plan-level orchestrator and the cascade out of the
  single-issue skill, and the option set considered at the time. Two of its
  recorded decisions are the ones this feature has to revisit.
- `docs/prds/PRD-execute-skill.md` — carries the accepted requirement that
  multi-pr execution is independent per-issue single-issue runs, which the
  scope boundary above inverts.
- `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md` — the
  recorded posture-detection mechanism for deciding which pull request in a
  chain completes the work.
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md` — rejects
  inferring that posture from the issues table, on drift and race grounds, in
  favour of an explicit author gesture.
