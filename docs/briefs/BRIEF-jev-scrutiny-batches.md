---
schema: brief/v1
status: Draft
problem: |
  /work-on's scrutiny panel spawns three reviewer subagents on every
  standard or full run, and nobody has measured which of their questions a
  script-built slice could settle within the 2,560 bytes Jev was validated on.
  Nothing says how a Jev verdict would reach the findings ledger, or what a
  run does when Jev can't answer.
outcome: |
  A maintainer can read, for every scrutiny question, whether Jev could decide
  it and why, from measured figures. The one question that fits runs beside the
  reviewers for users whose decider is on, and its findings and evidence land
  where a reviewer's do. Users keep every reviewer, and the rule for replacing
  one is written down before any seat qualifies.
---

# BRIEF: Jev batches for scrutiny review

## Status

Draft

## Problem Statement

Every `/work-on` run at the `standard` or `full` review level reaches the
scrutiny panel, which spawns three reviewer subagents: completeness (does every
acceptance criterion have an implementation), justification (are deviations
explained, and do the reasons hold up) and intent (does the change do what the
design describes). Each is a model-backed agent with a 15-call budget, on every
run and again on a full retry round. Across the 180 `/work-on` sessions recorded
on one maintainer's host, measured on 2026-10-20, the three seats raised seven
blocking findings in all. Almost every round passes, and it costs three agents.

shirabe can now hand a closed question to Jev through a koto decider check.
koto 0.20.0 falls back to the agent when Jev can't answer, and
[jev-pass-trust](../prds/PRD-jev-pass-trust.md) (#921) requires every Jev
criterion to show its sources, the script that builds its slice, a written case
that the slice is enough, and its size on real runs. Its budget is no more than
2,560 bytes, about the 2,507 the Jev accuracy spike validated, and it starts
untrusted until fixture and live evidence promote it. Nobody has applied that
test to scrutiny, so nobody can say whether any reviewer could hand its work to
Jev. A guess in either direction is costly:

- **Replace a seat on an unmeasured slice**, and a Jev pass stands in for
  review of material the slice never carried. A koto gate sends one slice per
  evaluation, so a question asked of every acceptance criterion or every hunk
  has to fit them all at once, or be cut, and a cut slice can pass what it
  never saw.
- **Leave it unmeasured**, and the question stays open: every run keeps paying
  for three seats with no evidence about which of them a check could stand in
  for, or what it would take.

Two parts of the path are also undefined. A seat's findings land in the
[findings ledger](../prds/PRD-findings-ledger.md) (#714) by content id, and the
panel gate and the retry budget read them there. Nothing says how a Jev verdict
would land beside them, so a check could raise a finding the panel never
counts, or count one nobody can close. And nothing says what a run does when
the decider can't answer: an over-budget slice, a failed extraction, a provider
error or a spent cap must never read as a pass, and the review it was meant to
stand in for still has to happen.

## User Outcome

A shirabe maintainer who asks which scrutiny reviewers Jev could stand in for
gets an answer they can check. Every scrutiny question has a contract in the
rule registry, with its sources, slice, completeness case and figures measured
on real runs. A question that needs more than 2,560 bytes, or more than a
script can hand over, is recorded as rejected with the numbers that rejected
it, rather than shipped on a cut slice.

The question that does fit runs as one batch on the scrutiny state for any user
whose decider is on, beside the three seats. Its findings land in the ledger by
content id and close the way a seat's do, so the panel gate and the retry
budget read them like any other finding. The decider events it produces are
the evidence a later promotion reads. When the decider can't answer, the run
answers the question itself and the seats still review, so a missing verdict
is never a pass.

A `/work-on` user sees no change in which seats run. The maintainer who
eventually promotes a batch finds the rule for replacing a seat already written
down, with what that promotion has to build, so the first seat that qualifies
doesn't have to work out its own safety rules.

## User Journeys

### A maintainer asks which reviewers Jev could replace

A shirabe maintainer weighing the cost of the scrutiny panel opens the rule
registry and the Jev criteria reference. Each seat's questions are there as
contracts with their measured slice sizes and states: the acceptance-criterion
coverage question rejected because its slice has to drop hunks to fit the
budget, the intent question rejected because the design context alone is over
budget on most runs. The question about recorded decisions is there too,
untrusted, with figures inside the budget. The maintainer reads which seat
could be replaced (none yet) and what evidence would change that.

### A /work-on run with an active decider reaches scrutiny

A user whose koto decider is on runs `/work-on` on an issue. At scrutiny, the
three seats spawn as before, and the batch sends Jev the decisions the run
recorded while it analysed and built the change, asking whether each gives a
reason rather than restating its choice. Jev passes them, the panel passes on
the seats' findings, and the run's decider events now count toward the batch's
live figures.

### The decider can't answer

A user's run reaches scrutiny while the decider's provider is failing. The
batch gets no verdict and koto holds the check pending. The run answers the
question itself, as koto's fallback asks, and the three seats review the
change in full, so the panel's verdict rests on reviewers, not on a check that
never answered. The fallback is recorded with its reason, where a maintainer
tuning the slice can count it.

### The batch fails a decision

A run records a decision whose rationale only repeats the choice. Jev fails it.
The finding lands in the scrutiny findings ledger under the batch's name, by
content id, and stays advisory while the batch is untrusted and in shadow, so
it can't block a run on an unproven check. After promotion, in veto, the same
failure would be a blocking finding that the panel gate holds and the retry
budget counts, closed only by a later pass from the batch, as a seat's finding
is closed only by a reviewer.

### A maintainer promotes the batch

Months later the batch's fixture run and live figures meet the trust bar. The
maintainer opens the promotion pull request, and the registry check holds the
record to the bar. If the promotion is meant to retire a seat, the rule for
doing so is already written down: what has to hold before a seat is skipped,
how a run falls back to the seat when the batch can't answer, and the criteria
the promotion pull request has to meet. The maintainer builds against them
rather than deciding the safety rules in the same change that uses them.

## Scope Boundary

**In scope:**

- A slice contract, in jev-pass-trust's format, for each question the scrutiny
  seats ask, measured on real runs, with any question that isn't closed or
  doesn't fit recorded as rejected and its figures kept.
- One batch on the scrutiny state for the question that fits (whether the
  run's recorded decisions give reasons), starting untrusted and in shadow,
  for users whose decider is on.
- How the batch's verdicts land in the findings ledger: by content id, with
  the same closing rules as a seat's findings, advisory while in shadow and
  blocking only in veto.
- What a run does when the batch can't answer: the run answers the question
  itself, as koto's fallback asks, and every seat still runs.
- The live bar's handling of a run with nothing to grade: an empty slice,
  which koto records as not graded, is left out of the answered share and the
  minimum counts, and never counts as a pass.
- A written rule for replacing a seat, and the criteria the first promotion
  that retires one has to meet.

**Out of scope:**

- Replacing any seat, and building the seat-replacement and fall-back-to-seat
  path. No seat's questions are all closed within the budget, so nothing is
  eligible; the path is specified for the first promotion that needs it.
- Any budget above 2,560 bytes, and re-running the Jev accuracy spike, which
  is what a diff-sized slice would need first.
- Promoting the batch or any other criterion, and withholding any rule.
- Checking one unit (one acceptance criterion, one hunk) per evaluation. koto
  opens no new visit on a self-transition and allows four consultations per
  `koto next`, so a per-unit loop would need koto changes this feature doesn't
  make.
- The review, QA and light panels, and the juries of `/brief`, `/prd`,
  `/design` and `/review-plan`, which have no koto state to run a check in.
- Any new koto field or event, offline ablations, long eval runs, and
  dashboards over the exported events.
