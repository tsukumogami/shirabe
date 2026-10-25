---
schema: brief/v1
status: Draft
problem: |
  A coordinator's session is replaced often, and the session that takes over
  can't continue the run it inherits. It opens a new run, copies part of the
  record, cancels the original and leaves the operator to rebind, rewrite the
  coordinator address, resume idle workers and re-arm leg watches by hand.
outcome: |
  An operator hands a coordinator run to a fresh session with one command and
  the run carries on: one session ticks it, nothing it held is lost, workers
  and legs reach the new session, and tools that trace the run's history follow
  the recorded succession instead of guessing from names.
motivating_context: |
  koto is gaining a relation by which one session names the session it
  continues (tsukumogami/koto#479). The coordinate skill's succession is the
  first consumer that needs it, and the coordinators that run this
  organisation's work hit the current carry path on every recycle.
---

# BRIEF: A coordinator's successor continues its run

## Status

Draft

## Problem Statement

A `/coordinate` run lives for days, but the Claude session driving it doesn't.
The session's context fills, the host restarts, a newer shirabe lands, or the
run is moved to another workspace, and a new session has to take the run over.
That handover is routine; on a busy roadmap it happens more than once a day.

Today the new session can't continue the run it takes over. The opener finds
the earlier run by its name prefix, opens a second run, cancels the first and
copies only its `record/` and `legs/` keys (the record entries and the request
legs it opened) across. Everything else the run held stays behind: what its
last reconcile established, the keys that track in-flight dispatches, the
links koto keeps for it, and the checks it already sealed in its log. The only trace of where the new run
came from is a guess: the lineage scripts walk back through earlier runs with
the same name prefix for as long as each one was cancelled.

Several parts of the handover fail outright or fall to the operator. An import
onto a host where the plugin sits at another path is refused on provenance
(tsukumogami/shirabe#806), and so is an import across a template change that
made no difference to the run (tsukumogami/shirabe#1144); both force a manual
carry. The new session's execution directory has to be rebound by hand before
its first tick. The coordinator address on the record (the session workers
report to) and the told set (the workers that have been sent that address) are
rewritten by hand, and a worker that stopped idle can only be
told by resuming it for that one purpose, so the handover gate holds the run
until it is (tsukumogami/shirabe#1245). Legs the earlier run opened still name
it as their requester, so when a worker finishes after the handover, the new
session's `koto request watch` never wakes; the operator re-arms watches and
kills orphaned watcher processes by hand.

Nothing in this path stops two sessions from driving one run. If the earlier
session is still alive when its successor opens, both can tick, and the only
defence is operators checking for live processes and agreeing who restarts
whom.

## User Outcome

An operator, or a coordinator handing over its own run, starts the successor
with one command from a fresh instance and the run simply continues. It works
from another checkout, after a plugin upgrade, and after the run was imported
onto another host, as long as the template the run was built from is one the
successor can keep driving; when it isn't, the successor says so and names the
template rather than half-continuing.

At no point do two sessions drive the run. The earlier session is stopped
before the successor takes over, or the takeover refuses, and an earlier
session that tries to tick afterwards is told who holds the run now. The
successor's first tick works with nothing rebound or edited by hand, and it
starts from everything the run held, so its first reconcile finds the holdings
its predecessor had already reconciled.

Workers and legs follow the run to its new driver. New briefs report to the
successor; a worker that finishes after the handover wakes the successor's
watch; the old watcher goes away instead of lingering. An idle worker isn't
resumed just to be told the new address; it is recorded as pending, the
handover goes ahead, and it learns the address the next time it starts. The
tools that look back over a run's history, such as the deferral check's chain
start and the teardown cost sweep, read the recorded succession and get the
same answer whatever the sessions happen to be called.

## User Journeys

### A coordinator recycles while its predecessor is still running

A coordinator whose context is nearly full asks for a successor, and the
successor is launched in a fresh niwa instance that has a newer shirabe than
the one the run started on. The predecessor is still ticking when the
successor opens. The successor's open stops the predecessor (or refuses and
says why), takes the run over, and ticks straight away. The predecessor's next
`koto next` refuses and names the successor. Dispatches made after the
handover carry the successor's address. This journey validates single-writer
takeover across instances and plugin versions.

### A worker the predecessor dispatched finishes after the handover

A `/work-on` worker that the predecessor briefed and opened a request leg for
completes its pull request an hour after the handover. Its terminal result
lands on the leg and the successor's `koto request watch` wakes within one
wait, so the successor lands or surfaces the work without the operator
noticing the leg had gone quiet. This journey validates that legs ring the
session that now holds the run.

### An idle worker is pending when the run changes hands

A worker parked for an owner pause has no running session when the successor
takes over. The successor records it as pending rather than told, and the
handover gate lets the run move on. When the worker is next resumed for its
own work, the resume carries the successor's address and the worker is then
recorded as told. This journey validates that a handover never waits on, or
wakes, a worker that has nothing to do.

### A run is continued on another host after an import

A run is imported into a second workspace on another host that shares the
cloud session store, with the plugin at a different absolute path. The
successor opened there continues the imported run under the same rules as a
same-host takeover. A successor whose shirabe ships an incompatible coordinate
template refuses and names the template instead. This journey validates the
provenance and template rules across paths and hosts.

### A coordinator settles a removed worker's cost and a deferral

A coordinator that has been through two successions tears down a finished
worker, and the teardown's cost sweep has to charge the worker's cost to the
coordinator run that dispatched it. Later the same coordinator checks whether
a standing deferral still holds, which depends on when the run's chain began.
On a run whose sessions' names and recorded succession disagree, both answers
follow the recorded succession and reach the same lineage. This journey
validates that lineage comes from the relation, not from naming.

## Scope Boundary

**In scope:**

- The coordinate skill's takeover path: how a successor opens its own koto
  session and records that it continues the predecessor's run, through koto's
  continues relation, in place of today's carry and cancel.
- Single-writer behaviour during a takeover: stopping a live predecessor or
  refusing, and what the predecessor sees afterwards.
- What the successor starts from: everything the run holds, not only the
  `record/` and `legs/` keys, within koto's action limits.
- Execution anchors that are right after a takeover without a hand rebind.
- Template compatibility across plugin paths, plugin upgrades and imports
  (tsukumogami/shirabe#806, tsukumogami/shirabe#1144).
- The coordinator address moving to the successor, the told set, and a
  pending state for workers that can't be told yet (tsukumogami/shirabe#1245).
- Legs the predecessor opened waking the successor, which needs a change in
  koto's request store, and leg watches re-armed by the successor's open.
- The lineage scripts that walk back by name prefix and cancel event
  (`chain-start`, the on-reap cost sweep) reading the relation instead.
- The same takeover after `coordinate-open.sh --import` into another
  workspace.

**Out of scope:**

- The continues relation itself, its retention rules and how imports keep
  their source (tsukumogami/koto#479 and its implementation). This feature
  consumes the relation; it doesn't define it.
- Prune's name rule for `coordinate-` sessions and other removal guards in
  koto. They are separate koto work that also reads the relation.
- niwa keeping an instance alive while a session in it hasn't been continued,
  and resuming a held worker whose directory was removed. That is niwa's
  reap and destroy work, not the coordinator's takeover.
- Other skills' succession (`/execute`, `/work-on`, `/deliver` runs taken over
  by another session). They share the relation but have their own openers.
- Retiring the operators' interim workarounds and recording when each one
  stopped. That accounting happens once this feature and its neighbours are
  installed.
- The teardown pass's job lookup for a worker resumed from inside its
  instance (tsukumogami/shirabe#1243). It touches the same scripts but is an
  independent fix.

## Open Questions

- The guarantee is fixed (never two sessions driving one run); what is open
  is the handshake: does the successor's open stop a live predecessor
  itself, or refuse until the predecessor has stopped? The design picks it.
- What counts as a compatible template when the plugin path or the template's
  bytes differ? The PRD states the cases that must continue and the case that
  must refuse.
- What does a pending worker look like on the record, and what turns pending
  into told?

None of these block the brief: each defers a detail the PRD or design owns.

## References

- `docs/designs/current/DESIGN-coordinator-session-record.md`: the current
  resume-or-carry rule this feature replaces.
- `docs/designs/current/DESIGN-coordinate-paused-state.md`: the leg watch the
  successor re-arms.
- `docs/designs/current/DESIGN-fleet-cost-capture.md`: the cost sweep whose
  coordinator lookup moves to the relation.
