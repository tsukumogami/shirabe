---
schema: brief/v1
status: Accepted
problem: |
  How much review a /work-on run spends doesn't depend on the change. Every
  code-typed issue gets seven panel seats per round, and any edit to a skill
  or koto template is code by definition, so a one-line template fix costs
  what an engine change costs, and a coordinator has no way to say otherwise.
outcome: |
  A worker running /work-on, and the coordinator that dispatched it, get
  review sized to the change: light work gets a light panel, risky work can't
  slip through one, and every level picked or raised is on record so the
  thresholds can be tuned from what actually happened.
motivating_context: |
  shirabe's own work is mostly skills and templates, so nearly every unit
  takes the full seven-seat path. Seat models and packets (#595) and sticky
  verdicts across retries (#596) cut the cost per seat and per retry; the
  number of seats a change starts with is the cost neither touched. #521 asked
  for the coordinator half of the same problem and is folded in here.
---

# BRIEF: review-level-up-front

## Status

Accepted

Framed under `/scope` from shirabe#591, which absorbs shirabe#521.

## Problem Statement

A `/work-on` run decides how much review a change gets from one question:
is the issue code, docs, or task? Code runs the scrutiny, review and QA
panels, seven seats per round. The code answer covers any skill or koto
template that drives a workflow, even when every changed path ends in `.md`.
In shirabe that's most of the work, so a one-line wording fix in a template
directive spends what a change to the panel-routing engine spends.

Nothing earlier in the run can say otherwise. The issue's size, the paths it
touches, and whether it changes tests or acceptance criteria are all known
after implementation, but no step reads them to decide how much review the
change needs. The only lever is the type, and the type only knows "behaviour
changed".

The coordinator that dispatched the worker can't help either. It may judge a
unit low-risk while writing the brief, but the brief template has no place to
say so and the worker's rendered instructions carry no bound, so the worker
picks its own panel size by its own defaults (#521 records a documentation
and scripts unit that ran five panel rounds this way).

And when the cost is wrong in either direction, nobody can tell from the
record. Runs keep a spawns-per-round history and a retry ledger, but nothing
says what level the run thought it was at, why, or whether a fact overruled
it. Without that, any threshold someone picks for "small enough to review
lightly" is a guess that never gets checked.

## User Outcome

A worker on a small, contained change spends a small review on it, decided
once, early, instead of discovering the cost through seven seats and their
retries. A worker that picks too light a level for what it touched gets
raised by a check on facts it can't argue with, and can always raise its own
level when the work turns out bigger; going down after the plan costs a
stated reason. A coordinator that judges a unit low- or high-risk can put
that judgment in the brief and see the worker's choice land inside it.
Maintainers reading the run record afterwards can see the level each run
picked, any bound it ran under, and every time the facts overruled the
choice, which is what they need to move the thresholds with evidence rather
than taste.

## User Journeys

### A worker fixes one directive line

A worker picks up an issue asking for a one-sentence wording fix in a
template directive. Early in the run it records a light level with a
one-line reason. After implementation the facts show one changed line in
one file, no engine or gate paths, no tests or acceptance criteria touched;
nothing objects. The run spawns one bounded seat instead of seven, and the
record shows the level, the facts and that no veto fired.

### The facts overrule a light choice

A worker records a light level for what the issue describes as a small
change, but the implementation ends up touching a gate script and a
security-sensitive path. The check on the gathered facts objects, the run
is raised before any panel spawns, and the record shows the original choice,
the fact that raised it, and the level the panels actually ran at.

### A coordinator bounds a unit

A coordinator writing a brief for a documentation-and-scripts unit judges
it low-risk and sets a ceiling; for a unit that rewrites a gate it sets a
floor instead. The rendered brief carries the bound into the worker's
instructions, the worker's chosen level falls inside it, and the bound is
in the run record next to the choice.

### A maintainer tunes the thresholds

Weeks later a maintainer wants to know whether the size threshold for a
light level is set right. They read the per-run records from the retained
sessions with a script: the levels chosen, the vetoes that fired, the
bounds in force, and the seats each run spawned. They can see, for example,
that a veto fired on most light choices over some size, and move the
threshold with that in hand.

## Scope Boundary

**IN:**

- `/work-on` choosing a named review level per issue early in the run, and
  each level saying which of scrutiny, review and QA it runs and with how
  many seats.
- Gathering objective facts about the change by script, and a check on those
  facts that can only raise the level.
- The asymmetry rule: raising is free at any point, lowering after the plan
  needs a reason the run records.
- A coordinate brief field that sets a ceiling or floor on the level, its
  rendering into the worker's instructions, and `/work-on` honouring it
  (closing #521).
- A per-run record of the level, the bound, and every veto, next to the
  existing spawns-per-round and retry records, readable by a script.
- Ending the rule that a change touching only skills or koto templates
  forces the full panel by classification alone.

**OUT:**

- Moving any review seat to the koto decider or changing which model a seat
  runs on; the check only raises a level (closed-criteria checks are #592,
  waiting on a separate trust ruling).
- A new koto engine primitive. The level rides on koto's existing routing on
  variable values and veto-only decider checks.
- Reshaping the seat commissioning from #595 or the sticky verdicts from
  #596, or changing the retry cap that #588 governs.
- Any coordinate change beyond the brief field and its rendering, such as a
  coordinator reading the record to pick levels for it.
- Live telemetry capture; the run record and a local scan of retained
  sessions are the measurement source.
- Picking the levels for `/plan`'s issues at planning time, as a field the
  PLAN writes. `/work-on` makes the choice; a PLAN may pass a hint later.
