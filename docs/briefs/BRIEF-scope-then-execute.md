---
schema: brief/v1
status: Accepted
problem: |
  An author can't start one session that scopes a feature and then lands it:
  whether one session can finish is decided late, inside /scope's planning
  hop, nothing carries a session from a PLAN to merged code, and the modes
  blur work shape with whether anyone stays to drive the work.
outcome: |
  An author says up front whether they want the work driven to completion or
  stopped at a PLAN, and every run under that intent ends somewhere useful: a
  merged PR when the session may merge, a ready PR handed off when it can't,
  or a landed PLAN with issues ready for per-PR sessions.
motivating_context: |
  Authors hand whole features to background sessions with a standing goal
  ("scope this, then build it, done when merged"). The goal is only
  satisfiable for some PLANs, and the author can't tell which kind they'll get
  until /scope has already run.
---

# BRIEF: scope-then-execute

## Status

Accepted

The downstream PRD owns the requirements; this brief frames the problem and
where the feature's edges sit.

## Problem Statement

Shirabe's tactical chain ends at a PLAN, and a separate skill takes a PLAN to
code. An author who wants both in one go, typically by starting a background
session with the goal "scope this feature, then implement it, and don't stop
until it's merged", has no way to know at launch whether that goal can be met.

Whether one session can finish depends on the PLAN's execution mode, and that
mode is picked late, inside `/scope`'s planning hop. A single-pr PLAN fits in
one session. A multi-pr PLAN doesn't: every PR has to merge before the next
one can start. A coordinated PLAN, despite looking like the single-session
case, also advances only as its earlier PRs merge, and the coordination PR
itself merges last. The author finds out which situation they're in only after
scoping is done.

Four gaps make even the easy case fail today. `/scope` never pushes its
branch or opens a PR, so `/execute` can't pick up the scoping branch the way
its own docs expect. Nothing in the chain merges anything: `/execute` stops at
a ready PR with green CI, even though its description and `/work-on`'s both
describe the end state as "merged". `/scope` ends on a bare status line that
names no next step. And `/plan`'s closing advice and `/scope`'s resume path
still send single-pr PLANs to `/work-on` rather than `/execute`.

Underneath all of this, the modes mix two separate things. One is work shape:
does the change land as one PR or several? The other is whether anyone stays
with the work after the PLAN exists. Multi-pr assumes nobody does: the PLAN
lands on main and independent sessions each pick up an issue. Coordinated
assumes a driver who holds the PLAN on an unmerged PR and closes it out last.
Today coordinated is also tied to multi-repo work, which hides that its real
difference is the driver. Because that second axis is implicit, the caller
can't state it, and so the chain can't honor it.

## User Outcome

An author starting a feature says, at launch, whether they want it driven to
completion or stopped once the PLAN exists. They don't need to guess how the
work will split. Whatever shape the PLAN takes, the run ends at a place that
matches what they asked for:

- asked to drive it and the session may merge: the work is merged;
- asked to drive it and the session can't merge: a ready PR with green CI is
  waiting for a human, with the run resumable from that PR;
- asked to stop at the PLAN: the PLAN is landed with its issues ready, and the
  author knows which ones can start now in their own sessions.

An author who just wants today's behavior (scope a feature, stop at a PLAN,
decide later) sees no change.

## User Journeys

### Background session, drive it to done

A maintainer hands a well-understood feature to a background session with the
single goal "take this from scoping to merged". The trigger is that they're
stepping away and want the whole thing handled. The session scopes the feature
and the same session implements it, gets CI green, and merges it because the
session is allowed to. That holds whether the PLAN came out as one PR or as
several merged in order. The maintainer returns to merged changes and the
scoping documents that explain them.

### Driven run in a repo where agents can't merge

A contributor runs the same "drive it to done" request in a repository where
agent sessions have no merge rights. The PLAN splits into several PRs. Instead
of stalling silently after the first one, it ends with every PR it could
open ready for review and a plain account of which merges are waiting on a
human. Once those land, the contributor re-runs the same request and it picks
up where it stopped, without re-scoping. The contributor sees exactly what's
blocked on them.

### Scope now, fan out later

A lead wants a feature scoped today and built over the next week by several
people or sessions in parallel. They invoke the tactical chain with the intent
to stop at the PLAN. The PLAN lands on main with its issues filed, and the run
reports which issues have no unmerged dependencies. The lead starts one session
per unblocked issue; no single session is expected to carry the whole thing.

### Plain scoping, no intent stated

An author runs `/scope` the way they always have, with no intent flag. The
chain behaves as it does today and ends at a PLAN, now with a next step that
names the right skill for the PLAN's mode rather than a stale one.

## Scope Boundary

**IN:**

- A way for the caller to declare, when launching the tactical chain, whether
  the run continues into execution or stops at the PLAN.
- Honoring that intent when the work splits into several PRs: a continuing
  run gets the coordinated shape (one driver, the PLAN merging last), a
  stopping run gets the multi-pr shape (the PLAN active on main). A single PR
  stays preferred either way.
- Letting the coordinated shape apply within a single repository, since the
  driver, not the repo count, is what distinguishes it.
- A thin entry point that runs scoping with the continue intent and then
  drives the resulting PLAN, with `/scope` itself staying directly callable,
  with or without the intent.
- The scoping branch reaching a PR so execution continues on it instead of
  starting a second branch.
- Merging when the session is permitted to, and a clean hand-off when it
  isn't.
- A driven multi-PR run pausing on its coordination PR and resuming from it.
- A stop-at-PLAN run that ends with the PLAN landed and the unblocked issues
  reported.
- Correcting the stale next-step advice and "merged" claims the chain gives
  today.

**OUT:**

- Automatically launching one session per unblocked issue after a
  stop-at-PLAN run. It's a natural follow-on, but it depends on per-issue runs
  behaving correctly against an active PLAN, which hasn't been checked with a
  real run.
- Moving multi-pr execution into the execution skill. That's separate
  in-flight work, and a multi-pr run still goes one issue at a time.
- Changing when and why the planning hop splits work into several PRs. The
  split reasons stay as they are; only which multi-PR shape a split resolves
  to changes.
- Letting any session merge by default. Merging stays tied to what the
  session is permitted to do; this feature doesn't grant permission.
- Changing the strategic chain or how it hands off into the tactical one.
