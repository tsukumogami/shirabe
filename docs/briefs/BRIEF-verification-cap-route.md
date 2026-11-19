---
schema: brief/v1
status: Accepted
problem: |
  A /work-on or /execute run whose change reaches most coordinate suites can't
  get through local verification: the check-skill row's 3,600 s budget is also
  the map format's maximum, the selected suites cost more than that on a shared
  host, and a load-timeout failure has no route to the green hosted CI run.
outcome: |
  An agent on such a change still reaches a verification verdict, by a route the
  workflow itself provides and records, that covers every suite the change can
  affect, each one executed by some run at the change's head, with real failures
  still sent back to implementation.
motivating_context: |
  Three changes close to landing (shirabe#1196, shirabe#1166 and shirabe#1548)
  cannot finish their local verification inside the budget. shirabe#1876 and
  shirabe#1930 each describe half of the gap; this brief frames them as one.
---

# BRIEF: Verification cap route

## Status

Accepted

The brief frames the gap shared by shirabe#1876 and shirabe#1930 as one feature,
because neither half alone gives a run a way through. How the two routes relate
is left to the design.

Accepted under `/scope`'s non-interactive mode: the structural reviewer passed
the draft, and the content reviewer's one finding, scope bullets written in
terms of commands and limits rather than plain words, was fixed in place.

## Problem Statement

A `/work-on` or `/execute` run ends its implementation work in a `verification`
state that runs the repository's verification map on the local host. In shirabe,
one map row runs `scripts/check-skill.sh --changed`, which picks the skill suites
a diff can affect. That row has a 3,600 s budget, and 3,600 s is also the most the
map format allows a row, so the budget can't simply be raised (shirabe#1876).

The suites a change selects can cost far more than that. Map reads at shirabe
commit fe04d94e selected 121 of the 127 coordinate suites for one example diff,
about 6,163 s by the cost rows in `skills/coordinate/check-skill.tsv`; 56 suites
(about 3,051 s) for a change to `coord-verdict.sh`; and all 127 (about 6,194 s)
for a change to `run-tests.sh`. The run for shirabe#1548 was stopped after
3,601 s with 10 of 127 suites finished and none of them failed, and the read for
shirabe#1196 selected all 127. On a busy shared host, wall time is worse than the
summed cost suggests, not better.

When the local command fails only because it ran out of time, the run has no way
forward. The state can't tell a load timeout from an assertion failure, and it has
no route that accepts a green hosted CI run of the same command at the same head
as the record for that check (shirabe#1930). A rerun on the same host costs
another hour and hits the same wall. Blocking ends the run even though hosted CI
has already shown the change passes. Treating the timeout as a failure sends the
run back to implementation for something the change never broke.

So a change whose diff reaches most coordinate suites, which is any change to a
koto template or a shared script, has no path through verification at all. That
is the situation three changes close to landing are in today (shirabe#1196,
shirabe#1166 and shirabe#1548), and every future change of the same shape will be
in it too.

## User Outcome

The agent running `/work-on` or `/execute` on such a change reaches a verification
verdict instead of a wall. It gets there by a route the workflow itself offers,
not by an operator overriding the state by hand, and the run's own record says
which route it took and why.

The verdict still means what it means today. Every suite the change can affect is
executed by some run at the change's head, locally or in hosted CI, and nothing is
counted as passed that no run executed. A real assertion failure still sends the
run back to implementation. A change that reaches every suite is checked against
every suite, as it is now.

A reviewer or coordinator reading the run afterward can see where each check ran
and can tell a timeout from a failure, so a verdict reached this way is one they
can trust without re-running it.

## User Journeys

### A shared-script change that selects most suites

An agent running `/work-on` on an issue whose fix touches a script the coordinate
suites share, or a koto template, reaches `verification`. `--changed` selects
well over an hour of suites. Today the run is killed at the budget and blocked.
With this feature the run still reaches a verdict covering every selected suite,
and goes on to open its pull request, or goes back to implementation if a suite
really failed.

### A local load timeout with hosted CI green at the same head

An agent's local map command fails, and the only failures are timeouts that a
loaded host caused; no assertion failed. Hosted CI has run the same checks at the
same commit and passed. The run records that the local failure was a timeout,
takes a named route that uses the hosted result for those checks, and carries on.
If hosted CI had not run them, or had failed them, the run would not take that
route.

### A coordinator or reviewer reading the record

A coordinator deciding whether to land a change, or a reviewer checking a run
that went past verification this way, opens the run's record. They can see which
checks ran locally, which were settled by hosted CI and at which head, and that
the local failure was a timeout. They don't have to re-run the suites to trust the
verdict.

## Scope Boundary

**In scope:**

- Reaching a verification verdict when the checks a change selects cost more
  time than one local check is allowed (shirabe#1876).
- Using a green hosted CI result for a check whose local run failed only by
  running out of time on a loaded host, and telling such a timeout apart from a
  real failure (shirabe#1930).
- Leaving a record of which route a run took and where each check ran, so a
  coordinator or reviewer can read it afterward.
- Single-issue runs and whole-plan runs alike, since both end in the same
  verification step.

**Out of scope:**

- Narrowing which suites a change to a shared script selects (shirabe#1934). That reduces how often the cap is hit; it is a separate
  change and this feature must work whatever the selection is.
- Raising or removing the limit on how long one local check may run. The limit
  stays; the feature is a route past it, not its removal.
- A general override for local failures that aren't the change's fault, such as
  a real assertion failure in a file the change doesn't touch (shirabe#1098).
  This feature covers timeouts only; an assertion failure still routes back to
  implementation.
- Rerunning a timed-out verification at the same head (shirabe#1855) and holding
  verification entry for a shared test slot (shirabe#1477).
- Changing runs already in flight. A run picks up the new route only after it is
  released and installed.
