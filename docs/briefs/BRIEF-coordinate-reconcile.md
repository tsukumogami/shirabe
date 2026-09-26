---
schema: brief/v1
status: Accepted
problem: |
  A coordinator that starts, restarts or takes over a rotation inherits a
  record of claims written at some earlier time. The coordinate skill tells
  it, in prose, to re-check each claim before acting, but nothing makes that
  happen or shows whether it did, so a stale row can be acted on as fact.
outcome: |
  Before a coordinator picks its next unit, it holds a report of what changed
  since the record was written and what it holds, built from live reads by a
  script rather than recalled by the agent, and the workflow won't let it
  pick without that report.
---

# BRIEF: coordinate-reconcile

## Status

Accepted

Frames the reconcile step of the `coordinate` skill for the koto workflow
that carries the coordinator's loop. The downstream PRD owns the
requirements, including which source tells a holding that is scoping ahead
from one that is executing.

## Problem Statement

A coordinator keeps a record on GitHub of the things GitHub can't
recompute: which units of work it dispatched (its holdings), what it chose
not to act on yet (deferrals), what it started and never saw finish (side
effects in flight, such as a merge it attempted), and why it reversed
earlier decisions. Every row in that record was true when it was written.
By the time a coordinator reads it again (after a crash, after its context
was lost, when it's restored on another host, or when a new rotation takes
over a discipline) any of those rows can be wrong. A pull request merged. A
branch moved on. A worker's instance was reclaimed along with work that was
never pushed. A merge that was attempted either landed or didn't.

The `coordinate` skill already says what to do about this. Its first loop
step, reconcile, tells the coordinator to treat every row as a dated
snapshot, re-check it against GitHub and the host, and report what changed.
That instruction is prose, and prose is carried out by the agent's
diligence alone. Three things go wrong with that:

- **Nothing shows whether the re-check happened.** An agent that reads the
  record and treats it as current leaves the same trace as one that
  re-checked every row. The most dangerous input in a restore is the
  coordinator's own last report, because it reads like a summary of the
  present rather than a snapshot of the past, and it's the first thing a
  restored session reaches for.
- **The re-checks are the fiddly kind agents get subtly wrong.** A merge in
  flight has to be confirmed against the head that was verified before the
  merge, not against wherever the branch points now. A board that shows
  green can hold jobs that never ran. A session missing from one listing of
  the workspace manager may be back on the next read. Each of these has a
  right answer that a mechanical check gets right every time and an agent gets right
  most of the time.
- **It spends the scarcest thing a coordinator has.** A coordinator is the
  longest-running session in the workspace, and its context is for
  judgment. Dozens of raw GitHub and host reads at every start fill that
  context with output that mostly says nothing changed.

The holding GitHub can't see at all makes this sharper: a worker that was
dispatched and hasn't opened a pull request yet exists only on the host.
If the coordinator doesn't re-check it there, nobody does, and whatever
that worker holds that exists nowhere else is lost at the next cleanup.

## User Outcome

A coordinator that has just started, restarted or taken a rotation reads,
before it picks any work, one report that tells it what's different from
its record and what it's responsible for right now. Each claim in the
report came from a live read made by a script: for each holding, what
changed since the record was written; which holdings exist nowhere but on
the host; which attempted side effects are now confirmed and which are
still open; which deferrals nobody has disposed of; and what happens next
and what waits on a person. The coordinator can't move on to picking work
until that report exists and was written by the script.

The person or coordinator it reports to gets a first report whose claims
are measured rather than remembered. A successor rotation also gets its
predecessor's reasoning, read as prose, and never mistakes it for a
re-checked fact.

## User Journeys

### Restart after a crash finds a holding that finished while it was down

A roadmap coordinator's session died mid-afternoon. The workspace starts it
again with the same scope, and the workflow arrives at its reconcile step.
The record says one holding's pull request is open and parked, waiting on a
merge. The reconcile report says that pull request merged two hours after
the record was written, and lists it as done rather than held. The
coordinator never dispatches a fix for work that already landed, and its
first report up says the holding finished while it was down.

### Restart finds a worker with no pull request whose instance is gone

The record lists a holding dispatched the day before with no pull request
yet. On restart the report can't find the worker's session in the
workspace manager's listing and can't find its instance on disk. It says
the holding was "not found on this read" rather than "gone", names it among
the holdings that exist nowhere but the host, and says it couldn't list
what the worker held. The coordinator reads the listing again before
deciding anything, and either finds the worker back or treats the unit as
needing re-dispatch, with the loss reported up.

### Restart settles a merge it attempted just before it died

The record's side effects in flight hold one merge, attempted just before
the crash, with the head the coordinator verified before attempting it.
The report compares the default branch against that verified head. When
the head is on the default branch, the merge is confirmed and the row
clears. When the branch has since moved past that head and the head is not
on the default branch, the report says "not confirmed", never "merged",
because what landed wasn't what was verified.

### A new rotation starts from its predecessor's handoff

A discipline's rotation ended and a new coordinator takes the next one. It
reads the predecessor's dated handoff file. The tables in it go through the
same re-checks as any record. The handoff's reasoning section, the one
input a restart lacks, reaches the coordinator's context as prose, marked
as the predecessor's view, and no gate reads it. When the predecessor left
no reasoning, the successor records that none was received and never
writes it on the predecessor's behalf. Every deferral the predecessor left
shows up as undisposed until the successor files it, closes it or carries
it forward with a reason.

### The person above reads the first report

The person, or the coordinator above, that dispatched this coordinator
receives its first report after a restart. It leads with what changed and
what the coordinator holds, grades each claim as measured, and lists what
waits on them. They don't have to ask whether the coordinator checked
before acting, because the report couldn't have been written otherwise.

## Scope Boundary

**In:**

- The reconcile state of the coordinator's workflow: what it reads, what it
  re-checks and against which source of truth, what it writes, and the gate
  that holds the workflow in that state until the report exists.
- Reading the record as dated snapshots, at roadmap scope and at
  discipline scope, reusing the record reader the record feature builds.
- Re-checking every holding, every side effect in flight and every
  deferral: against GitHub for pull requests, branches, issues and the CI
  board, and against the workspace manager and the instance directory for
  holdings with no pull request yet.
- The report written into the workflow's context, which the pick step reads,
  including whether each holding is scoping ahead or executing, since the
  pick step counts that against its cap.
- The rotation-handoff variant: the predecessor's reasoning carried as
  prose, and a successor recording that none was received.
- Tests with stubbed GitHub and workspace-manager reads, and evals for a
  restart and a rotation start.

**Out:**

- Whether a worker session is still running (liveness). Reconcile asks
  whether a session or instance exists and what it holds, not whether it's
  making progress.
- Whether the effort already has another coordinator (the double-held
  check). It's optional, never blocks, and is a separate follow-on.
- What a coordinator's merges cost other efforts it can't see.
- Acting on anything the report finds. Reconcile reads; it never merges,
  closes, tears down, re-dispatches or edits the record. The loop's later
  steps act.
- Where the record lives, its container and how it's rendered: the record
  feature settles those. Reconcile consumes its reader.
- The dispatch path, including binding a worker's result to a workflow
  leg.
- The lighter per-turn re-check of a holding the coordinator is about to act
  on. That belongs to the verify step.
- Any change to the workflow engine or the workspace manager.
