---
schema: brief/v1
status: Draft
problem: |
  A live coordinated /shirabe:execute run keeps the plugin version it was
  opened under, so a fix in a newer installed release never reaches it. A node
  held by that bug stays held, and the only ways forward are to finish on the
  old version or to abandon the run and start over.
outcome: |
  The person driving the run can ask to move it onto the installed version and
  carry on past the bug, with its request leg, its work-on children and its
  record intact. A run that can't move safely says so before anything changes.
motivating_context: |
  shirabe#1556 reports the gap: a coordinated execute run in flight couldn't
  use the fix #1541 shipped for #1537, and execute offers no route that a
  coordinate run in the same position already has.
---

# BRIEF: Moving a live execute run onto a newer installed plugin version

## Status

Draft

## Problem Statement

A coordinated `/shirabe:execute` run can go on for a long time. It works
through a plan's issues one node at a time, and each node opens a per-issue
`/work-on` run under it. Installing a newer shirabe release while it's running
changes nothing for it. The run keeps the plugin version it was opened under,
and every script its steps call comes from that version until the run finishes.

That holds up until the run trips over a bug the newer release already fixed.
Then whoever is driving the run is stuck. shirabe#1556 names the concrete case:
a node whose stored verification deferral needs public wording, which the fix
in #1541 (for #1537) supplies. The installed release has the fix. The run still
calls its old copy of the script, which ignores the public wording, so the node
stays at the deferral step.

Reopening the run doesn't get the fix in. The execute opener has one way back
into a live run, and when the run's compiled template differs from the
installed one, it refuses the open. Nothing in execute offers to supersede,
continue or upgrade a live run. Doing it by hand is worse: a hand-run
supersede can't take the run's request leg or its parent link, so it would drop
the leg, orphan the run's work-on child, and break the run's settled branch
record with a new session name.

That leaves two ways forward, and both cost something. Let the run finish on
the old version, which can force exactly the text the fix was written to avoid.
Or abandon the run and start again, which throws away the progress it has made.
A `/shirabe:coordinate` run in the same spot has a way out: it can rebind its
plugin root, or be taken over with its record carried into the replacement.
An execute run has neither.

## User Outcome

The person driving a coordinated execute run installs a release that fixes what
the run is stuck on, asks for the run to move onto it, and carries on. The held
node gets past the bug on its next step. It's still the same run: its request
leg, its work-on children and its record come along, so nothing that tracks the
run loses it. And the children pick up the fix too, not just the parent, since
a fix can land in a script either one calls.

Moving is something they ask for. A run that's reopened without asking stays on
its version and tells them whether it could move, so an upgrade never changes
a run out from under anyone. When a run can't move safely, for example because
the new release changed the run's template in a way the old run can't follow,
they hear that and why before anything changes. The two ways forward they have
today, finishing or starting over, are still there.

## User Journeys

<Phase 3 will name the concrete journeys that exercise the feature.>

## Scope Boundary

<Phase 3 will record what this feature holds in and pushes out.>
