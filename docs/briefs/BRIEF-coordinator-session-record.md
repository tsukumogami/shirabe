---
schema: brief/v1
status: Accepted
problem: |
  A restarted coordinator rebuilds its run from a GitHub record, and one moved to
  another host loses what that record can't carry: each worker's request leg and
  result, and what a replacement needs after a crash rather than a planned handoff.
outcome: |
  A restarted coordinator carries on where it was; one moved to another host passes
  the handover gate and continues with no other file. A record its owner hasn't
  moved keeps working on GitHub, unchanged.
---

# BRIEF: coordinator-session-record

## Status

Accepted

## Problem Statement

A coordinator keeps its state in two places, and the one it throws away is the
one it runs in. Every start of the coordinate skill is a new koto session named
for the run; it cancels the previous run's session, finds the record on GitHub,
and reconciles from it. The record (an issue at roadmap scope, a draft pull
request per rotation at discipline scope) holds the holdings, deferrals, side
effects in flight, reversals, holds, the stored set a replacement needs (Run,
Standing, Work), the decisions ledger, and, as comments, the account of what
happened. Its body carries a `Written:` time, and a restart trusts it only as a
snapshot of that moment. The session holds the run's journal and every check's sealed output,
and none of it reaches the next run.

That split worked while a coordinator lived on one host and the record was the
only thing that crossed. It stops working in three places.

First, the record isn't fully portable either. A holding's return path names a
koto request leg, and koto's request store and its wakes are local to the host
that created them. A coordinator adopted on another host reads the row and
can't follow it: the worker's result, if it came through the leg, is on the old
host, and nothing tells the new one whether it ever arrived.

Second, a real host migration showed what the loop can't recover from on its
own. A holding whose worker vanished with its host couldn't be relaunched or
retired through the loop (shirabe#732); a worker whose leg was spent had no
route for its later reports (shirabe#711); and an `/execute` run resumed on a
fresh host couldn't adopt its own merged pull requests because the run id
didn't carry across (shirabe#733). Each was worked around by hand.

Third, the stored set was shaped by a planned handoff, where the outgoing
coordinator could still write a line. After a crash nobody writes that line.
What a replacement then needs and the record doesn't hold includes where the
coordinator's rules and briefs live and which versions it ran with, its friction
log, each worker's branch and last pushed head, and who it reports to, named as
a role rather than as a session name that only exists on one host.

Why now: koto can now move a session between hosts, context keys included,
and mark the old copy so it refuses to run, which makes a host move something a
coordinator could survive. Nothing in the coordinate skill takes advantage of it.

The change can't be a switch thrown under everyone. Live coordinators run a
pinned release and other lanes' records sit on GitHub mid-run, read by people
and tools outside the loop: a join on each unit's cost entries, a reviewer who
reads the holdings, decisions and verdicts before a merge, and the rows that
mark a milestone as waiting for its verdict, which live on the record by design.

## User Outcome

The person or coordinator that runs a coordinator stops treating a restart as a
reconstruction. When a coordinator crashes, starting it again resumes its own
session on the same host, with its holdings, decisions and account where it left
them. When it has to move hosts, the operator imports its session on the new
host, and the replacement passes the handover gate (the check at every start
that the record names its arguments, its cap, its address, a next step per
piece of work, and that every live worker has been told where to report) and
carries on without a handoff file, a tools directory or the old session's
memory: a worker it
imported alongside is watched again, a worker left behind reports by message, and
a worker that vanished is recovered through the loop rather than by hand.

A lane owner whose coordinator is mid-run on a GitHub record sees nothing change.
Their record stays on GitHub, and the cost join, the final reviewer and the
verdict readers keep reading it where they read it today, until the owner moves
it on purpose. The move itself is a setting the owner chooses for their record,
not a default that arrives with an upgrade.

## User Journeys

### A coordinator restarted after a crash

The maintainer of a roadmap coordinator finds its session dead after the host
rebooted mid-loop. They start the coordinate skill again with the same roadmap.
Instead of opening a new run, cancelling the old one and rebuilding from the
record, the skill resumes the coordinator's own session: the holdings, the
standing answers, the decisions and the account are the ones it had, the checks
it sealed are still sealed, and reconcile re-checks the claims against GitHub
as it always has before acting.

### A replacement on another host

The owner of the workspace retires a machine that ran a coordinator and three
workers. On the new machine the operator imports the coordinator's session,
naming the old workspace path, with the template compiled from the same release.
The replacement opens on the imported session, and the handover gate holds it
until the stored set is complete and every live worker knows the new address.
One worker, imported too, is given a fresh leg on the new host and its result
arrives there. One left running on the old host can't be watched from here, so
its holding moves to the message path and the worker is told to report by
message. One whose host is gone is marked stranded, and the loop retires its
row and dispatches the unit again under a new topic, keeping the branch and
last head the worker pushed.

### A lane that stays on its record

The coordinator of another lane is mid-run on a GitHub record when this ships.
Its owner upgrades nothing in that run, and when the next release reaches it,
nothing about its record changes: no setting on the record asks to move it, so it
stays on GitHub. Its holds and pauses are still read from the record immediately
before every merge. When the owner later decides to move it, they add that
setting once, and the next start carries the record's state into the session.

### A reader outside a moved coordinator

A coordinator's state has moved into its session. A reviewer about to merge one
of its ready pull requests reads its holdings, its decisions and the milestone
verdicts it posted, and a nightly job joins every unit's cost entry against
usage data. The job finds the cost entries on the same GitHub issue as before,
and the reviewer finds the verdicts there too; the holdings and decisions they
read from the coordinator's session, through koto's view of it, and nothing on
GitHub contradicts what the session holds.

## Scope Boundary

**IN:**

- The coordinator's whole state (holdings, deferrals, side effects in flight,
  reversals, holds, the stored set, the decisions ledger and the account) kept
  in its own koto session, so it survives a restart and an import.
- Resuming that session on a restart, and importing it on another host as koto's
  session import ships it, with what the import needs (the source workspace
  path, a template of the same hash) recorded where a replacement reads it.
- Each worker's result and request leg kept as keys the import carries, and
  what a migrated coordinator does with a leg it can no longer watch.
- What a replacement needs after a crash: where the rules and briefs live, the
  friction log, each worker's branch and last pushed head, and the reporting
  chain named as roles.
- A holding whose worker vanished, recovered through the loop (shirabe#732), and
  a worker's later reports reaching the coordinator once its leg can't carry
  them (shirabe#711).
- A choice of state source made per record, where the record's owner moves it
  explicitly and every existing record stays on GitHub by default.
- The protections the record's writes give today, kept in the session: only
  this run writes, nothing is written after a skipped check, no write lands over
  a newer one, the state stays bounded, and each part has one writer.
- A home for the entries that readers outside the loop consume once a record
  moves, with cost and verdict entries able to stay on GitHub.

**OUT:**

- Removing the GitHub record as a store, or deleting the record scripts and
  their codec. This feature moves state behind a seam and leaves the GitHub path
  working for records that stay on it; the removal is later work.
- Moving any existing record's state, another lane's included. Only the record's
  owner moves it.
- Any change to koto. A store that needs a format koto lacks is proposed as a
  koto feature, and koto's session listing and pruning are koto's own work.
- Carrying a pause to dispatched sessions, which stays the workspace manager's
  (tsukumogami/niwa#362).
- `/execute`'s cross-host adoption of merged node pull requests
  (shirabe#733), which belongs to `/execute`; this feature carries the
  coordinator's own run identity across hosts, not a worker's.
- Recording a delta review seat in the panel table (shirabe#758) and confirming
  a pull request merged outside the land step (shirabe#710): both are loop
  defects that hold whatever store the state lives in.
- The discipline rotation's committed handoff file and its pull request, which
  stay as they are.
- The teardown archive and transcripts, which aren't coordinator state.
