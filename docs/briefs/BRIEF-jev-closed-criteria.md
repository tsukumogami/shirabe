---
schema: brief/v1
status: Accepted
problem: |
  Many review seats in the scope chain and in /work-on check closed criteria
  against documents and diffs that already exist, yet each runs as a full
  agent. Nobody has recorded which seats those are, and no record shows
  whether a one-shot decider reading the same artifacts would reach the
  seat's verdict, so a maintainer can't say where cheaper review is safe.
outcome: |
  A maintainer deciding whether a decider can stand in for a review seat
  reads, for that seat, its verdicts and the decider's verdicts on the same
  artifacts side by side, collected without any agent writing input for the
  decider and without any run changing course.
---

# BRIEF: Closed-criteria review checks in decider shadow

## Status

Accepted

Framed from shirabe#592, run in shadow mode only. The flip from shadow to
trust is a later ruling and is outside this brief.

## Problem Statement

A coordinator-driven feature runs nine to thirteen jury reviewers in the
scope chain alone: two on the brief, three on the PRD, one security and three
final-review seats on the design, one in `/review-plan`, plus about eight per
critical design question. `/work-on` adds scrutiny, review, QA and the light
review seat on every implementation. Much of what those seats check is
closed: a required section is present, a frontmatter field agrees with the
body, an acceptance criterion answers yes or no, a PLAN issue traces to the
design it claims to cover. A typed decider can answer questions of that kind
for a small fraction of an agent seat's cost, and koto already calls one.

The maintainers can't act on that today, for three reasons.

First, nobody has written down which seats are candidates. A decider answers
in one shot and can't ask for more, so it fits only where a script can gather
its input from artifacts that already exist. Where the main agent would have
to write a summary for the decider to judge, the writing costs more than the
seat saved, and the decider sees only what the agent chose to include. Which
side of that line each seat falls on is a per-seat question with no recorded
answer.

Second, there is no evidence. The review-shadow trial records a decider's
verdict beside a pull-request panel's, but no seat in the scope chain, and
none of `/work-on`'s per-criterion checks, has a decider verdict recorded
beside its own. Without that record, any move from seat to decider would be
taken on faith.

Third, the review that is missing has no home. No gate in the chain asks
whether an artifact should exist at all, or whether its framing holds, before
requirements are written against it.

## User Outcome

The maintainer who rules on moving a seat to the decider gets a history to
rule on. For each seat a script can feed, every run leaves the seat's verdict
and the decider's verdict on the same artifacts next to each other, in the
same record the pull-request trial already keeps, so the out-of-sample runs
for a seat kind can be read together in one report.

The agent running a chain notices nothing new: no route, gate, retry or seat
count moves because of a decider verdict, and it never writes a word of the
decider's input. A reviewer reading the design can see, for every jury and
review site, whether it is a decider candidate and why, and the question of a
framing seat before the PRD has a recorded answer instead of an open issue.

## User Journeys

### The maintainer weighs a flip

A maintainer has watched the brief jury run on twenty features and wants to
know whether its structural seat could become a decider call. They read the
recorded agreement between that seat and the decider across those runs, and
make a ruling backed by recorded verdicts instead of an
impression of how often the seat ever blocked.

### An agent runs a scope chain unchanged

A worker runs `/scope` on a new feature. At each jury the seats run exactly
as before; beside them a script gathers the document, its format reference
and its upstream, sends the closed criteria to the decider and records the
answer. The worker's routing reads only the seats' verdicts, and when the
decider has no key or no answer, the run is no different from one before this
feature.

### A reviewer audits the classification

A reviewer is about to approve a pull request that adds a shadow check to
scrutiny's completeness seat. They open the design's site table, find that
seat classified as decider-fit with its inputs named (the diff and the
acceptance criteria), find the intent reviewer classified agent-only with the
reason (it reads beyond the diff), and judge the change against a written
rule rather than a guess.

### A maintainer asks why there is no framing seat

A maintainer remembers the issue asked for a judgment seat between brief and
PRD and finds none in the chain. The recorded decision tells them why it was
not added in this unit and what would have to be true for it to be added.

## Scope Boundary

**IN:**

- A classification of every jury and review site in the scope chain and in
  `/work-on` (brief, PRD, design security and final review, `/review-plan`,
  scrutiny's completeness check, review's closed criteria, QA, the intent
  reviewer, the light review seat) as decider-fit or agent-only, with the
  artifacts the input comes from or the reason it can't.
- For each decider-fit site, a script that assembles the decider's input from
  artifacts on disk.
- Shadow runs at those sites that record the decider's verdict beside the
  seat's, in the review-shadow trial's record or a sibling of it.
- An answer, built or recorded, to whether a framing seat belongs at the step
  from brief to PRD.

**OUT:**

- Flipping any seat from shadow to trust. That is a later ruling, made per
  seat kind on out-of-sample data.
- Removing a seat, or changing any seat's count, model or budget, even where
  the shadow data might later justify it.
- Release-time evals for these criteria; that is shirabe#593.
- The review-level rules and thresholds from the review-level change; those
  stay as they are.
- Structural checks that `shirabe validate` already makes. A criterion that
  repeats a validator check spends decider tokens to learn nothing.
