---
schema: brief/v1
status: Accepted
problem: |
  The coordinate skill hands work to other sessions and takes it back through
  prose alone. Each worker brief is written freehand, the dispatch is typed by
  hand, and the rule to record the dispatch before anything else has nothing
  behind it, so a worker can be launched that neither GitHub nor the record knows.
outcome: |
  A coordinator hands a unit of work to a fresh session that starts with
  everything it needs, can't move on until that worker is on its record, and
  gets the worker's result back through whichever path the worker could use,
  with its workflow advancing the same way on either.
motivating_context: |
  The coordinate skill shipped as prose in #397, and its "What This Version
  Leaves for Later" section names tooling for the dispatch path as later work.
  The skill is becoming a koto workflow template whose dispatch and wait
  states will, at first, call that prose. This brief frames what those two
  states need to do on their own.
---

# BRIEF: coordinate-dispatch-path

## Status

Accepted

Framed for the `/scope` chain. The downstream PRD owns the requirements; the
DESIGN owns the states, gates and scripts, including two questions this brief
leaves open: whether the holding is written by the dispatch step's own action
or by a separate record write it gates on, and how the wait step tells, per
holding, which return path applies.

Scope widened after acceptance, at the dispatcher's request: the dispatch
path now ends at teardown, so the inventory a coordinator takes before
destroying a worker's instance is in scope. The problem and outcome are
unchanged; a worker's instance is the last thing a dispatch leaves behind.

## Problem Statement

A coordinator's whole job is moving units of work out to other sessions and
back. In the `coordinate` skill today, both directions run on the agent's
memory of a reference file.

Going out, the coordinator composes each worker's brief by hand from a
template. The brief is the worker's only context, and it has a lot to carry:
the goal and the entry point, the decisions the worker can't see anywhere it
will read, pointers to what's already pushed, the acceptance criteria, what's
out of scope, the checkpoints, the run mode, and two report channels that
must not be confused (status and blockers go to the dispatching coordinator,
the only source of direction; papercuts go to the discipline coordinator that
owns the surface, with a copy to the dispatcher). Any of those can be left
out, and the worker, starting cold, has no way to notice what it wasn't told.

The dispatch itself is a command the coordinator types, and the skill says to
record the dispatch as a holding (a row in the coordinator's record naming the
worker and its unit) "before any other action". Nothing enforces that. A
worker that has been launched but hasn't opened a pull request yet exists
nowhere GitHub can show, so if the coordinator forgets the holding, or its
session ends between the dispatch and the record write, that worker is lost to
reconcile (the step that re-checks the record after a restart) and to any
successor. The bound on concurrent workers is
also counted from the record, so an unrecorded worker makes the coordinator
over-dispatch.

Coming back, a worker's result arrives as a message plus whatever it pushed.
The coordinator reads each message and decides by eye whether the unit is
done, blocked, or needs a fix, and there's no record of that call beyond what
it does next. Some workers can also report through the workflow engine's
request store by binding a leg of the coordinator's request (a slot the
coordinator opens that the worker's session attaches to, and on which its
final result is recorded), which carries the result as data rather than as
prose, but nothing in the coordinator's loop
would read a leg if one were bound.

## User Outcome

The coordinator, and the person or coordinator above it, stop depending on
the coordinator's recall at the two moments where a slip costs the most.

A worker starts in a fresh session with a brief that is complete by
construction: every section filled from the coordinator's record and the
human's decisions, both channels named, pointing at pushed artifacts rather
than pasted text. The coordinator can't leave the dispatch step with a worker
out there that its record doesn't show, so a restart or a successor always
finds every worker it launched, and the worker-count bound counts what's
actually running.

When the worker comes back, the coordinator's workflow advances on the result
whether it arrived by message or through a bound leg, and a suggested reading
of the report (done, blocked, needs a fix) sits beside the coordinator's own
call, which is the one that routes.

## User Journeys

### A roadmap coordinator sends a feature out

A roadmap coordinator has picked the next unblocked feature and reaches the
dispatch step. It renders the worker's brief from its record, the roadmap
entry and the human's decisions, and dispatches it through the workspace
manager under the feature's topic. The same step writes the holding: the
worker's topic, the repository, the run mode, and whether the worker is
scoping ahead or executing. The coordinator moves on to waiting only once
that holding is on the record.

### A coordinator restarts after dying mid-dispatch

A coordinator's session ends right after it launched a worker. Its successor,
or the same coordinator restarted, reads the record and finds the holding for
that worker with "none yet" for a pull request, because the dispatch step
wrote it before returning. Reconcile looks the worker up by its topic, rather
than the worker surfacing days later as an unexplained pull request.

### A worker resolves a leg it was bound to

A coordinator dispatches a feature to a worker whose entry point can bind a
leg of the coordinator's request. The worker finishes and its terminal result
lands on the leg. The coordinator's next tick of its wait state finds the leg
resolved and moves on to verification with the worker's result as data, not
parsed out of a message.

### A worker with no leg reports that it's blocked

A worker running an entry point that can't bind a leg sends the coordinator a
message: it's blocked on a failing check it can't clear. The coordinator ticks
its wait state on the message, writes the report where the workflow can read
it, and sees a suggested classification of "blocked" next to the choice it
has to make. It submits its own call, re-dispatch with what was learned, and
that's what the workflow follows.

## Scope Boundary

**IN:**

- Compiling a worker's brief from the record and the invocation, with every
  section the brief template names, both report channels, the pointer to the
  target repository's conventions, and the workspace manager's note that the
  keep-alive is already scheduled.
- Dispatching through the workspace manager and getting the holding onto the
  record within the dispatch step, by whichever mechanism the DESIGN picks,
  including whether the worker is scoping ahead or executing.
- A check that refuses to leave the dispatch step until the holding is on the
  record, reading the record rather than the coordinator's claim.
- Declaring the workspace manager as a tool the skill needs, with an install
  route.
- The wait step for both return paths: a bound leg, and a message plus what
  was pushed.
- Before a coordinator destroys an instance it dispatched, or asks the human
  to, an inventory of what that instance holds that exists nowhere else, and
  a teardown that names that one instance, never a sweep.
- A suggested classification of a worker's report that runs in shadow beside
  the coordinator's own call.

**OUT:**

- Reconcile: re-checking the record against GitHub and the host after a
  restart. The restart journey above ends where reconcile begins.
- The record's container, its sections and how it's rendered. This feature
  writes a holding through the record's own tooling.
- The coordinator's loop as a template, and its other states (pick, verify,
  land). This feature fills two states it doesn't own.
- Letting `/deliver` and `/work-on` bind a leg, and having the engine wake
  the coordinator when a leg resolves. Both are filed against their owners;
  this feature is built to use them when they land.
- Legs across hosts, which the request store doesn't carry by design.
- Making the report classification decide on its own. It stays a suggestion.
- Checking whether a worker's session is still alive, whether another
  coordinator holds the same unit, and what a coordinator's actions cost other
  efforts.
- Any change to the workflow engine or the workspace manager.

## References

- `skills/coordinate/SKILL.md` -- the prose loop, steps 3 and 4.
- `skills/coordinate/references/brief-template.md` -- the brief's sections and the dispatch command.
- `skills/deliver/koto-templates/deliver.md` -- a template that waits on a child's result.
