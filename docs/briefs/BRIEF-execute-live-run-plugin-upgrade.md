---
schema: brief/v1
status: Accepted
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

Accepted

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
they hear that and why before anything changes. They can still let the run
finish on its old version, or start a fresh run, just as they can today.

## User Journeys

### Moving a held run onto the fix

The person driving a coordinated execute run sees a node stuck at its
verification deferral because the run's copy of the script ignores the public
wording. They install the shirabe release that fixes it, reopen the run and
ask for it to move. The run reports that it moved onto the installed version,
and the node's next step runs the fixed script and gets past the deferral. The
run's request leg, its child runs and its record are the ones it had before.

This journey is the one #1556 asks for: a fix that exists can reach the run
that needs it.

### Reopening after an upgrade without asking to move

The same person upgrades shirabe for an unrelated reason and reopens a live
execute run as they always do, without asking for a move. The run carries on
under the version it was opened under, exactly as it does today, and the
reopen says whether the run could be moved and how to ask for it.

This journey keeps an upgrade from changing a run nobody asked to change.

### A fix that a per-issue child needs

The bug sits in a script the per-issue `/work-on` run calls, not one the
parent execute run calls. The person moves the run as in the first journey,
and the child that's in flight picks up the installed version along with the
parent. Its next step runs the fixed script. Nobody has to reopen the child
separately or find out afterwards that only the parent moved.

This journey makes sure the move reaches every part of the run that can hit
the bug, not just the top.

### A release the run can't follow

A newer release changes the execute template's shape, not only a script it
calls. The person asks to move a live run onto it. Before anything changes,
they're told the run can't move onto this release and why. The run stays on
its version, untouched, and finishing it or starting a fresh run are both
still open.

This journey keeps a move from leaving a run half-moved or quietly broken.

## Scope Boundary

**In scope:**

- Moving a live coordinated execute run onto the shirabe version that's
  installed now, keeping it the same run.
- Keeping what the run is tied to through the move: the request it answers,
  the run above it, the per-issue work runs in flight under it, and its
  record.
- Moving only when the person asks, and telling them on an ordinary reopen
  whether a move is possible.
- Turning down a move the run can't safely make, before anything changes,
  with the reason, and leaving the run as it was.
- Releases the run's existing workflow can follow as it stands, such as one
  that fixes a script the run calls.

**Out of scope:**

- Releases that change the shape of the run's workflow itself. A run can't
  follow those in place; they'd need a replacement run that takes over from
  the old one, which is separate follow-on work.
- Moving a run automatically whenever a newer version is installed. An
  upgrade changing a live run nobody asked to change is what the explicit
  request guards against.
- Finished runs. Reopening a finished execute run already replaces it and
  carries its record forward.
- Coordinate runs. They already have their own ways to move onto a newer
  version; this brief names them only as the comparison.
- Moving a run back onto an older version on purpose. The feature is for
  picking up fixes, not for downgrades.

## Downstream Artifacts

- `docs/designs/DESIGN-execute-live-run-plugin-upgrade.md`: the technical
  approach for moving a live execute run and its children onto the installed
  version.

## References

- `docs/briefs/BRIEF-settled-branch-record.md`: the settled branch record a
  hand-run supersede would break by changing the run's name.
