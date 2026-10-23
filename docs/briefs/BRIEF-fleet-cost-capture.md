---
schema: brief/v1
status: Accepted
problem: |
  A dispatched unit's cost entry exists only when the coordinator's own
  teardown pass removes the unit. A unit removed any other way leaves no entry,
  or one that can't be joined to its pull requests, so cost per merged pull
  request by plan shape can't be read across everything the fleet ships.
outcome: |
  Whoever reads the fleet's cost series finds an entry for every dispatched
  unit however it was removed, each naming its dispatch id, milestone and plan
  shape, with a failing-head count that is either whole or marked as a floor,
  and by default no pull request carries any of it.
motivating_context: |
  A week of fleet pull requests read after capture was switched on found most
  of them with no milestone or plan shape. The gap was mostly units torn down
  by hand or by a reap, which never reach the teardown pass, plus a
  failing-head count that silently stopped at 300 CI runs (#1093).
---

# BRIEF: Fleet cost capture

## Status

Accepted

Framed under `/scope`; the requirements follow in the PRD.

## Problem Statement

The coordinate skill writes a unit's `unit-cost/1` entry in exactly one place:
its teardown pass, between the archive and `niwa destroy`. That pass is one way
a unit ends, and in practice not the usual one. A coordinator retires a worker
by hand when the pass refuses it (a pull request still open, nothing merged),
or because it was told to remove finished sessions as soon as their work
lands. A person deletes a finished session in the Agent View and `niwa reap`
reclaims its instance. Another coordinator reaps its own workers with its own
steps. None of these paths runs the capture, so the unit has no cost entry at
all, and its pull requests have no record of the milestone or plan shape they
belonged to.

Even the paths that do capture lose what the fleet's series joins on. The
entry's `niwa.dispatch.id` comes from `niwa list` at teardown, so a unit the
pass finds already removed is posted with that key null and can't be joined.
Its milestone comes from the record's Holdings row, which is gone once the unit
is retired. On the session store the entry is posted as a comment on the
unit's own pull request, putting coordinator bookkeeping in front of a
repository's reviewers, who may not use these tools at all.

The one figure the capture does read for every pull request is short on long
branches: failing heads are counted from at most 300 workflow runs, so a branch
with many pushes reports a fraction of its failing heads and presents it as the
whole count (#1093).

The result is that the fleet's cost per merged pull request, split by plan
shape, can be computed over only a minority of the pull requests it is meant
to cover, and nothing says which ones are missing.

## User Outcome

The person reading the fleet's cost series, across every coordinator on the
host, finds one cost entry for each dispatched unit, whether the teardown
pass removed it, a coordinator removed it by hand, or a reap reclaimed it. Each
entry carries the dispatch id the series joins on, the milestone the unit
advanced (or `none`), its plan shape, and every pull request it opened, so
each pull request can be counted under its plan shape. Nobody runs a step for
the capture. Where a failing-head count couldn't be read whole, the entry says
it is a floor rather than passing a short count off as the figure. A reviewer
of the repository the unit changed sees none of this on the pull request.

## User Journeys

### A coordinator retires a worker by hand

A coordinator's teardown pass refuses a unit whose draft pull request will
never merge, so the coordinator saves the worker's files and removes its
instance and session itself, outside the pass. The unit still gets its cost
entry, on that coordinator's record, naming the dispatch id and the milestone
the unit was dispatched for. The coordinator ran nothing for it, and taking
the unit off its list of live workers afterwards doesn't change the entry.

### A finished session is deleted and reaped

The owner deletes a dozen finished worker sessions from the Agent View at the
end of a day. The next `niwa reap`, or the reap the next `niwa dispatch` runs
first, reclaims their instances. Each removal leads to one entry on the record
of the coordinator that dispatched the unit, including units whose holdings
were already taken off the coordinator's list of live workers days before,
which the hand-removal case never meets. A unit no coordinator dispatched gets
no entry and leaves a line saying why.

### The fleet's series reads a week of pull requests

Whoever computes the series reads every coordinator's cost entries for a week,
joins each on its dispatch id, and lists every merged pull request with its
milestone and plan shape. A unit that landed several pull requests (a
coordinated plan's node pull requests and its coordination pull request)
contributes each of them. A unit captured before its last pull request merged
still names it, so the pull request is counted when it merges. Where an entry
marks a figure as a floor, or as one whose source was gone, the reader leaves
it out of the sums instead of guessing.

### A reviewer reads a pull request a dispatched worker opened

A maintainer of a repository that adopted shirabe reviews a pull request a
coordinator's worker opened. Its comments hold the review conversation and
nothing else: no cost entry, no session name, no capture key. A workspace that
wants the entry on the pull request turns that on in its own configuration.

### A long-lived branch's failing heads

The person computing the series compares rework across units by failing heads.
One unit's single pull request went through 65 pushes, many with a red run.
Its entry counts the failing heads over every head up to the green one, so the
reader compares 17 with 17, not with the 5 that fit in one page of runs. If the
capture ran out of time first, the count is marked as a floor and the entry
names that figure as incomplete, and the reader leaves it out.

## Scope Boundary

**IN:**

- A cost entry for every unit a coordinator dispatched, whatever removed it:
  the teardown pass, `niwa destroy` run by hand, or a reap, with no step run by
  hand for the capture.
- The dispatch id on every entry, including a unit removed before the pass ran,
  and one entry per unit when the pass and a removal both see it.
- The milestone kept for a unit whose Holdings row is already gone, and every
  pull request the unit opened listed, merged or not yet merged at capture.
- The failing-head count read over every head of the unit's pull requests, or
  marked as a floor when it couldn't be.
- Cost entries kept off pull requests by default, with a workspace setting that
  turns posting on a pull request back on.
- A reader of the cost reference can tell, for each entry, how the unit was
  removed and whether each figure is whole, a floor, or unreadable.

**OUT:**

- The fleet's cost series itself and its join over coordinator records: it
  belongs to whoever builds the series, and only reads what this writes.
- Changes to koto or niwa. niwa already runs a workspace-declared command when
  it removes a session, with the session's dispatch id; this uses it as it is.
- The rest of the tool content shirabe writes into pull requests (the Review
  panel table, handoff comments, verification notes): a separate change owns
  making those opt-in.
- Units nobody dispatched through a coordinator, such as a session a person
  started by hand: they have no record to post to.
- Back-filling entries for units removed before this lands.
- The land half of a holding that tracks several pull requests (#712's
  remaining part): this records each pull request's attribution, not how the
  loop lands them.
