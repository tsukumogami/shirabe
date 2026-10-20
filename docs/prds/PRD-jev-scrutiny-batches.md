---
schema: prd/v1
status: In Progress
problem: |
  /work-on's scrutiny panel spawns three reviewer subagents on every standard
  or full run, and no one has measured which of their questions a script-built
  slice could settle within the 2,560-byte budget Jev's accuracy evidence
  supports, how a Jev verdict would land in the findings ledger the panel gate
  reads, or what a run does when the decider can't answer. Without that, a
  seat is either replaced on an unmeasured slice or the question stays open.
goals: |
  Every scrutiny seat question carries a measured slice contract in the rule
  registry, and the ones that don't fit are recorded as rejected with their
  figures. The one that fits runs as an untrusted shadow batch on the scrutiny
  state, its verdicts land in the findings ledger under a seat's closing
  rules, and an unanswered batch never passes. No seat changes, and the rule
  for replacing one is written down for the first promotion that needs it.
absorbed:
  - docs/briefs/BRIEF-jev-scrutiny-batches.md
---

# PRD: Jev batches for scrutiny review

## Status

In Progress

The completeness, clarity and testability reviewers passed it over two rounds.
The downstream DESIGN owns the approach.

Absorbed [BRIEF-jev-scrutiny-batches](docs/briefs/BRIEF-jev-scrutiny-batches.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so a maintainer can say, with figures, which scrutiny
reviewers a Jev check could stand in for, and so the one check that fits runs
where its verdicts are counted and closed like a reviewer's without ever
standing in for review it didn't do. The brief framed two gaps: nobody had
measured the scrutiny seats' questions against jev-pass-trust's slice-contract
test, and nothing said how a Jev verdict reaches the findings ledger or what a
run does when the decider can't answer. The Problem Statement and Measured
Context carry both, with the figures.

The outcome it set: every scrutiny question on record with its contract and
figures, rejected ones kept with the numbers that rejected them; the one that
fits runs beside the three seats for users whose decider is on; its findings
land where a seat's do, advisory until trusted; a missing verdict is never a
pass; users see no change in which seats run; and the rule for replacing a seat
is written before any seat qualifies. Goals and User Stories carry it.

Its journeys were a maintainer asking which reviewers Jev could replace, a
`/work-on` run with an active decider reaching scrutiny, the decider failing to
answer, the batch failing a decision, and a maintainer promoting the batch.
User Stories carry them, with the decider-off user added; R1, R7, R9 and R12
make them testable.

Its scope boundary put the contracts, one shadow batch, ledger reporting, the
fallback, the live bar's not-graded rule and the written seat-replacement rule
in; and seat replacement, larger budgets, the spike re-run, promotion,
withholding, per-unit checks, other panels and juries, koto changes, offline
evals and dashboards out. Requirements and Out of Scope carry it.

## Problem Statement

`/work-on`'s scrutiny panel spawns three reviewer subagents on every run at the
`standard` or `full` review level: completeness, justification and intent, each
a model-backed agent with a 15-call budget. Most rounds pass, and every round
still costs three agents. The people affected are shirabe's maintainers, who
decide which reviews a check could stand in for, and `/work-on` users, whose
runs pay for every seat.

shirabe can hand a closed question to Jev, a classifier model that answers pass
or fail about a slice of text, through a koto decider check, and
[jev-pass-trust](PRD-jev-pass-trust.md) (#921) sets what a Jev criterion has to
show first: its sources, the script that builds its slice, a written case that
the slice holds everything the question needs, and its size on real runs, with
a budget no higher than 2,560 bytes, about the 2,507 the Jev accuracy spike
validated. Nobody has applied that test to scrutiny, so nobody can say which
seat, if any, a check could replace. Replacing one on an unmeasured slice would
let a Jev pass stand in for review its slice never carried; leaving it
unmeasured keeps every run paying for three seats with no evidence either way.

Two parts of the path are undefined too. A seat's findings land in the
[findings ledger](PRD-findings-ledger.md) (#714) by content id, and the panel
gate and the retry budget read them there. The ledger can take a decider entry
today, but it marks every decider fail blocking whatever the check's mode,
raises a blocking finding on any outcome that isn't a verdict, and records only
what the agent copies into its round file. So a shadow check, which is never
meant to block, would block the panel, and a fail the agent left out would
never land. And jev-pass-trust's live bar counts an evaluation whose slice was
empty, which koto records as not graded, as unanswered, so a question that
often has nothing to grade could never earn trust.

## Measured Context

Measured on 2026-10-20 (UTC), with no call to Jev, over the `/work-on` sessions
one maintainer's host had recorded (180 sessions with recorded review facts)
and the earlier review-shadow trial's records on the same host:

| Seat | Question | Smallest slice it needs | Runs measured | Over 2,560 |
|---|---|---|---|---|
| completeness | does every acceptance criterion have an implementation (`rs-015`) | the criteria beside their anchored hunks | 398 trial records | 382 |
| completeness | are the evidence claims verifiable from the diff | the agent's own claims, which nothing records | none | n/a |
| justification | are deviations explained, do the reasons hold up | the criteria, the plan and the diff; lower bound measured: criteria and plan | 180 sessions | 154 |
| intent | does the change do what the design describes | the design context and the diff; lower bound measured: design context | 172 sessions | 91 |
| justification, closed part | does each recorded decision give a reason | the decisions recorded in analysis and implementation | 180 sessions (88 with a decision) | 5 |

The coverage question doesn't fit even one criterion at a time: the trial's
per-criterion slices had to drop hunks to stay under the bound in 2,933 of
3,363 units. A koto decider check can't ask one unit per evaluation either: a
self-transition opens no new visit, and one `koto next` allows four
consultations. So no seat's questions are all closed within the budget. One
closed question fits: a run records its decisions with `koto decisions record`
while it analyses and builds the change, and whether each gives a reason,
rather than restating its choice, can be judged from the decision's own text.
It is the part of the justification seat's question a script can hand over
whole. Over the same 180 sessions the three seats raised seven blocking
findings in all.

## Goals

- A maintainer can read, for every question the scrutiny seats ask, its slice
  contract, its measured figures and its state, and CI holds each contract to
  jev-pass-trust's rules.
- The one question that fits runs as a batch on the scrutiny state for any user
  whose decider is on, untrusted and in shadow, beside every seat.
- The batch's verdicts land in the findings ledger by content id, under the
  closing rules a seat's findings follow, advisory until the batch is trusted
  and in veto.
- A batch that can't be answered never passes: the run answers it itself and
  every seat the round plans still runs.
- The live bar can be met by a criterion that is often empty, without an empty
  run ever counting toward trust.
- The rule for replacing a seat, and what the promotion that first does it has
  to build, is written down.

## Terms

- **Session**: one koto session of a `/work-on` run. A contract's **run** is
  one session, as jev-pass-trust defines its `koto-sessions` population.
- **Visit**: koto's visit of a state: it opens on an arrival from another
  state, and a self-transition doesn't open a new one.
- **Evaluation**: one (session, visit, gate, criterion) tuple with at least one
  `decider_checked` or `decider_fallback` event, as jev-pass-trust's R10
  defines it.
- **Graded**: an evaluation, or a session's slice, with something to grade. An
  evaluation is **not graded** when every one of its events is a
  `decider_checked` with outcome `not_graded`, which koto writes only for an
  empty or whitespace-only slice.
- **Decider on**: the user's effective decider mode (jev-pass-trust's Terms) is
  `shadow` or `auto`. For a user whose decider is off, koto never runs a
  decider check's command and treats the state as if the check weren't
  declared. A criterion the template declares in `shadow` runs in shadow for
  every user whose decider is on, `auto` included; only a `veto` criterion
  acts differently under `auto`.
- **Full round**: a panel round in which `panel-scope.sh --plan` gives every
  seat the decision `full`, as the findings ledger defines it.

## User Stories

- As a shirabe maintainer weighing the cost of the scrutiny panel, I want each
  seat's questions on record as contracts with measured figures, so that I can
  see which seat a decider could replace (none today) and what evidence would
  change that.
- As a `/work-on` user whose decider is on, I want the batch to grade my run's
  recorded decisions at scrutiny while all three seats run, so that my run
  feeds the batch's live figures without changing what reviews it.
- As a `/work-on` user whose decider is off, I want scrutiny to behave exactly
  as it does today, so that a check I never opted into costs me nothing.
- As a `/work-on` user whose decider can't answer the batch, I want to answer
  the question myself and have every seat the round plans still review, so that
  a missing verdict never stands in for review.
- As a `/work-on` user whose recorded decision Jev fails, I want the finding in
  the panel's ledger under the batch's name, marked advisory while the batch is
  untrusted, so that an unproven check can't block my run but its finding is
  kept where a reviewer's would be.
- As a shirabe maintainer promoting the batch later, I want the rule for
  replacing a seat and the criteria its promotion pull request has to meet
  already written, so that I build against them rather than settle the safety
  rules in the change that relies on them.

## Requirements

### Functional

**R1. A contract for every scrutiny seat question.** Each question the scrutiny
seats ask in `skills/work-on/references/phases/phase-4a-scrutiny.md` maps to a
rule-registry entry carrying a jev-pass-trust contract (sources, slice script,
budget, completeness case and verdict, measured figures or a `not_measured`
reason, state):

| Question | Registry id | State |
|---|---|---|
| completeness: every criterion has an implementation | `rs-015` (exists, unchanged) | `rejected` |
| completeness: evidence claims verifiable from the diff | `rs-018` | `rejected` |
| justification: deviations explained, reasons hold up | `rs-019` | `rejected` |
| intent: the change does what the design describes | `rs-020` | `rejected` |
| recorded decisions give reasons | `work-on/scrutiny-decision-reasons` | `untrusted` |

A question no template declares is a review-shadow criterion, as `rs-007` to
`rs-017` are: `rs-018` to `rs-020` join `scripts/review-shadow/criteria.json`
with observer `jev` and `enabled: false`, so nothing runs them. The one
question the batch asks is a decider entry. Each entry's written case lives in
`references/jev-criteria.md` under a heading equal to its id, and says what the
slice holds, why it is or isn't enough, and the figures.

**R2. A rejected contract keeps its figures.** `rs-019` and `rs-020` record a
measured lower bound: the part of their slice a script can build from what a
`/work-on` session keeps (the criteria text and the plan; the design context),
measured over every recorded session by a shipped command. Each written case
contains the sentence "These figures are a lower bound: the full slice also
carries the diff." `rs-018` records `not_measured: no-real-run-record` and a
completeness verdict of `insufficient`: the claims are the agent's own words
about its work, which nothing records for a script to read and which
jev-pass-trust's R3 keeps out of every slice.

**R3. The batch.** `/work-on`'s `scrutiny` state declares one `decider-check`
gate, `scrutiny_decider`, with `max_bytes` 2,560, label `decisions`, and one
criterion in `mode: shadow` whose key is its registry id,
`work-on/scrutiny-decision-reasons`, so koto's events and the ledger name the
same rule. Its text is:

- question: "Does every decision listed here give a reason for its choice: a
  constraint, a fact about the code or the system, or an alternative it
  rejected, rather than a restatement of the choice?"
- pass: "Each decision's reason or rejected alternatives say why the choice
  was made, in terms other than the choice itself."
- fail: "At least one decision's reason only restates or paraphrases its
  choice, or gives no reason at all."
- escape: "The list can't be read as decisions, so it can't be judged."

No `when` clause, `skip_if` condition or context assignment reads the gate.

**R4. The slice.** The gate's command runs a shipped slice script that reads
koto's session log for the session and prints every `decision_recorded` event
whose `state` is `analysis` or `implementation`, on any visit, in log order, as:

```
- choice: <choice>
  reason: <rationale>
  rejected: <alternative>; <alternative>
```

with the `rejected:` line only when the decision names an alternative, each
field's whitespace (newlines and tabs included) collapsed to single spaces and
trimmed, and the bytes otherwise unchanged. A missing or empty choice or
rationale prints as the label with nothing after it (`  reason:`), so the
decider sees that the reason is absent. When the session recorded no such
decision it prints nothing and exits 0. It never reads a file the agent names
or selects, nor any context key.

**R5. Measured on real runs.** `work-on/scrutiny-decision-reasons`'s contract
records the slice measured over every recorded `/work-on` session, population
`koto-sessions`, at least 100 runs, by a shipped command that prints the same
figures (runs, maximum, nearest-rank p90, runs over budget) given the same
session logs. The contract's state follows
jev-pass-trust's rule over those runs (over budget on more than 5% of them is
`rejected`): on 2026-10-20 that was 5 of 180, 2.8%, so `untrusted`. Its written
case also states the share over graded sessions only, 5 of 88 (5.7%), past
the 5% line, so a reviewer sees both and the next measurement with more graded
runs can be compared with it.

**R6. Fixtures.** `work-on/scrutiny-decision-reasons` has a fixture file meeting
jev-pass-trust's fixture profile (at least 10 good, 20 seeded-bad and 5
adversarial cases, at least 3 adversarial techniques from that profile's set),
each case's input given as the session-log events the slice script reads and
its slice as the script prints it. Adversarial cases include decision text
written to steer the answer (an instruction, a fake answer, a role line); the
decision text is the graded artifact and reaches Jev only as the labelled
slice.

**R7. An unanswered batch never passes.** When koto lists the criterion under
the check's `awaiting` (an over-budget slice, a failed extraction, a provider
or transport error, an unreadable answer, a spent cap, a busy lock), the state
holds, on a carried round as on any other, until the agent records its own
answer with `koto decider answer`. The `scrutiny` directive tells it how. The
agent's answer is never a decider verdict: the ledger records no entry from it
(it is a `decider_check_answered` event, which backs no ledger entry) and the
live bar never counts it as answered. Every seat the panel's scope plans still
runs, whatever the batch answered or failed to answer. For a user whose decider
is off, the gate does nothing at all.

**R8. No change in which seats run or what they read.** `panel-scope.sh --plan`
writes the same decisions with or without the batch's events in the session
log, and no seat's prompt, commissioning line or packet changes.

**R9. Batch verdicts land in the ledger.** `panel-scope.sh --record <panel>`
records, as decider entries, every `decider_checked` event koto's session log
holds for the panel's state (`scrutiny`, `review`, `qa_validation` or
`light_review`) whose (state, visit, gate, criterion, declaration hash) no
earlier entry used, in any visit since the session began, whether or not the
agent's round file names it. A round file's own decider entries keep working,
checked against the log as today and taking their mode from the event they
match; an event already used by an earlier entry is skipped when it comes from
the log and refused (exit 65, ledger unchanged) when a round file names it.
Each entry's finding is raised by the decider, named `<gate>/<criterion>`,
under the criterion's registry id, and its id is the content id the ledger
already computes for a decider entry (panel, raiser and criterion), so every
event of one criterion speaks to one finding:

| Outcome | Mode `shadow` | Mode `veto`, or no mode |
|---|---|---|
| `fail` | raise or re-raise the finding as `advisory` | raise or re-raise it as `blocking` |
| `pass` | when the finding exists, add a `reverified` record from the decider | the same, which closes a blocking finding |
| `escape`, `unanswered`, `not_graded`, or any other value | nothing | when the finding exists, add an `unverified` record; otherwise raise it `blocking` with first record `unverified`, as today |

A re-raise keeps a finding blocking once it has been blocking, as today.

**R10. The panel gate and retry budget read batch findings like any other.**
`--verdict`, `--open-count` and `panel-retry-budget.sh` count a blocking
finding the batch raised exactly as they count a seat's, and never count an
advisory one.

**R11. The live bar leaves out evaluations with nothing to grade.** In
jev-pass-trust's live bar, a not-graded evaluation is left out of the
evaluations, the sessions and the answered share, and never counts as a pass
toward trust or withholding. The minimum counts (30 evaluations across 5
sessions) count graded evaluations only. An evaluation with a `not_graded`
event and any other event is graded and follows the existing rule: answered
when one of its `decider_checked` events is `pass` or `fail`, unanswered
otherwise, so `escape`, `unanswered` and every `decider_fallback` reason,
`over_budget` included, still count against the bar. The rule applies to every
Jev criterion. The reference reader (`jev_criteria.py figures`) prints the
number of evaluations it left out as `not_graded`, a promotion's `live` record
carries that count, and `references/jev-criteria.md` and
`docs/guides/jev-criteria.md` state the rule with the exported field that tells
a not-graded evaluation apart: `koto.decider.outcome` equal to `not_graded`.

**R12. The seat-replacement rule is written, not built.**
`references/jev-criteria.md` gains a section, "Replacing a seat", saying a seat
may be left unspawned only when every condition holds, and that the pull
request that first does it builds them:

1. every question the seat asks has a `trusted` contract declared on the
   panel's state in `veto`;
2. for that session, every condition of jev-pass-trust's R14 (its withhold
   conditions) holds for each of those criteria;
3. when any of those criteria is unanswered in the panel state's current
   visit (no `decider_checked` event with outcome `pass` or `fail`),
   `panel-scope.sh --plan` gives the seat `full` for that round;
4. the batch's blocking findings stand in the ledger and the panel gate where
   the seat's would;
5. the change ships a test for each of conditions 1 to 4.

No code in this feature leaves a seat out.

**R13. The agent is told.** The `scrutiny` directive and `phase-4a-scrutiny.md`
each say that the batch runs beside the seats for a user whose decider is on,
that its findings are advisory while it is untrusted, and that a pending batch
is answered with `koto decider answer`, giving the command, and only for a
criterion listed under `awaiting`.

### Non-functional

**R14. No koto change.** The feature uses koto 0.20's decider checks, fallback
and events as they are, including the `mode` field `decider_checked` already
carries (exported as `koto.decider.mode`): no new koto field, event or
exported attribute, and no koto floor change.

**R15. No decider in CI.** Tests that exercise the batch, the slice, the ledger
or the bar run against stubbed session logs or a loopback decider stub and
never see a decider key; the fixture runner keeps jev-pass-trust's loopback
guard. CI runs no measurement against real data.

**R16. Public repository.** Contracts, fixtures, figures and documents name no
private repository, path or record; figures are aggregate counts and sizes.

## Acceptance Criteria

Contracts:

- [ ] `references/rule-registry.json` holds `rs-018`, `rs-019` and `rs-020` in
  state `rejected` and `work-on/scrutiny-decision-reasons` in state
  `untrusted`; `rs-015`'s entry is byte-identical to the base branch's;
  `scripts/review-shadow/criteria.json` holds rows `rs-018` to `rs-020` with
  `observer: jev` and `enabled: false`; and `jev_criteria.py check` and
  `scripts/check-rule-registry.sh` exit 0 on the tree. (R1)
- [ ] `references/jev-criteria.md` has a `## ` heading equal to each of the four
  new ids, and each entry's `completeness.heading` names it. (R1)
- [ ] `rs-018` records `not_measured: no-real-run-record` and verdict
  `insufficient`. (R2)
- [ ] `rs-019` and `rs-020` record `measured` with `over_budget` above 5% of
  `runs`, and each written case contains "These figures are a lower bound: the
  full slice also carries the diff." (R2)
- [ ] `work-on/scrutiny-decision-reasons`'s `measured` records population
  `koto-sessions`, `runs` at least 100 and `over_budget` at most 5% of `runs`,
  and its written case states the graded-session share. (R5)

The batch and its slice:

- [ ] The compiled `work-on.md` has, on `scrutiny`, a `decider-check` gate
  `scrutiny_decider` with `max_bytes` 2,560, label `decisions` and one
  criterion, `work-on/scrutiny-decision-reasons`, in `mode: shadow`, with R3's
  question, pass, fail and escape text; the registry entry's `check` names that
  template, state, gate and criterion with a current `declared.sha256`; and no
  `when` clause, `skip_if` or context assignment reads the gate. (R3)
- [ ] Given a session log holding decisions recorded in `analysis` (two
  visits), `implementation` and `verification`, the slice script prints the
  `analysis` and `implementation` decisions only, in log order, in R4's
  layout; a decision with no alternative has no `rejected:` line; a field with
  newlines, tabs and runs of spaces prints on one line with single spaces; a
  multibyte character prints unchanged. (R4)
- [ ] Given a log with no such decision, the slice script prints nothing and
  exits 0; given a log it can't read, it exits non-zero. (R4, R7)
- [ ] The slice script's output doesn't change when a file named in a decision,
  or any context key of the session, changes. (R4)
- [ ] `jev_criteria.py measure sessions` with the decision-reasons slice prints,
  over a fixture corpus of session directories, the runs, maximum, p90 and
  over-budget count that corpus should give, counting a session with no
  decision as a run of 0 bytes. (R5)
- [ ] The fixture file passes jev-pass-trust's fixture checks (at least 10
  good, 20 seeded-bad and 5 adversarial cases, at least 3 techniques), and a
  test runs the slice script on every case's input and gets the case's slice.
  (R6)

Fallback and seats:

- [ ] With a real koto, the decider in `shadow` and a loopback stub that fails
  every request, a session reaching `scrutiny` with a recorded decision holds
  there with the criterion under `awaiting`, on a carried round as on a full
  one, and advances after `koto decider answer ... --answer unclear`; with no
  decision recorded the same session advances without holding; with a decision
  whose slice is 2,561 bytes the check falls back for `over_budget`, and at
  2,560 bytes it asks the stub. (R7)
- [ ] With a real koto and the decider off, a session with recorded decisions
  passes `scrutiny` exactly as on the base branch, and its log holds no
  `decider_checked` event for `scrutiny_decider`. (R7)
- [ ] `panel-scope.sh --record scrutiny` creates no ledger entry from a
  `decider_check_answered` event. (R7)
- [ ] `panel-scope.sh --plan scrutiny` writes byte-identical
  `scrutiny_scope.json` decisions for a session whose log holds batch events of
  every outcome as for the same session without them, and the diff of this
  feature leaves every seat's commissioning line and `review-packet.sh`'s code
  packet unchanged. (R8)

Ledger:

- [ ] `--record scrutiny` with a round file that names no decider entry records
  a `fail` event from the log as a finding raised by `decider`
  `scrutiny_decider/work-on/scrutiny-decision-reasons` with rule id
  `work-on/scrutiny-decision-reasons`: `advisory` for a `shadow` event,
  `blocking` for a `veto` event and for an event with no mode. (R9)
- [ ] After a `veto` fail, a later `pass` event adds a `reverified` record and
  `--verdict scrutiny` exits 0 for a panel with no other open finding; after a
  `shadow` fail, a later `pass` adds a `reverified` record and the finding
  stays advisory; a `pass` with no earlier finding adds no finding. (R9, R10)
- [ ] A `shadow` event of outcome `escape`, `unanswered` or `not_graded` adds
  no finding and no record; a `veto` `escape` with no earlier finding raises a
  blocking finding whose only record is `unverified`. (R9)
- [ ] Events from an earlier visit of `scrutiny` that no entry used are
  recorded by the next `--record scrutiny`; events of another panel's state
  are not; running `--record` twice over the same log records each event once;
  a round file naming an event the log already backed exits 65 and leaves the
  ledger byte-identical; a round file's own `fail` entry matching a `shadow`
  event raises an advisory finding. (R9)
- [ ] With one blocking batch finding and one advisory one open,
  `--open-count scrutiny` prints 1, `--verdict scrutiny` exits 1 and prints
  only the blocking one, and `panel-retry-budget.sh` reads a count of 1. (R10)

Live bar:

- [ ] `jev_criteria.py figures` over a fixture log leaves an all-`not_graded`
  evaluation out of evaluations, sessions and answered, and prints the count
  as `not_graded`; an evaluation with `not_graded` and a later `pass` counts as
  answered; one with `not_graded` and a `decider_fallback`, or with
  `not_graded` and `escape`, counts as an unanswered evaluation. (R11)
- [ ] The bar fails at 29 graded evaluations beside 50 not-graded ones and at
  4 graded sessions beside 10 sessions with only not-graded ones; it passes at
  30 graded evaluations across 5 sessions with 95% answered. (R11)
- [ ] `jev_criteria.py check` fails a `trusted` entry whose `live` record lacks
  `not_graded`. (R11)
- [ ] The not-graded rule is exercised on a criterion other than
  `work-on/scrutiny-decision-reasons` in the tests. (R11)
- [ ] Both Jev-criteria documents state the not-graded rule and name
  `koto.decider.outcome` `not_graded`, and a doc test fails if either loses
  it. (R11)

Telling the agent and the seat rule:

- [ ] The `scrutiny` directive and `phase-4a-scrutiny.md` each contain
  `koto decider answer`, `--gate scrutiny_decider`, the criterion id,
  `awaiting` and `advisory`, and a test fails if either loses one. (R7, R13)
- [ ] `references/jev-criteria.md` has a `## Replacing a seat` section naming
  each of R12's five conditions, a doc test fails if the heading or any
  condition's phrase is missing, and no script or template change in the
  feature makes `panel-scope.sh --plan` give any scrutiny seat a decision other
  than today's. (R12)

Floor, CI and visibility:

- [ ] `scripts/assert-koto-floor.sh` still reads 0.20.0, and the feature
  changes no file in the koto repository. (R14)
- [ ] `git grep -n KOTO_DECIDER_API_KEY` over the feature's test files and
  `.github/workflows/` finds no assignment, the fixture runner's loopback-guard
  test still passes, and no workflow runs `jev_criteria.py measure`. (R15)
- [ ] `shirabe validate --visibility=public` passes on every document the
  feature adds or changes. (R16)

## Out of Scope

- Replacing any scrutiny seat, and building the seat-replacement and
  fall-back-to-seat path: R12 writes the rule for the first promotion that
  needs it.
- Any budget above 2,560 bytes, and re-running the Jev accuracy spike, which a
  diff-sized slice would need first.
- Promoting `work-on/scrutiny-decision-reasons` or any criterion, switching it
  to `veto`, and leaving any rule's text out of what a run loads.
- Checking one unit (one criterion, one hunk) per evaluation, which needs koto
  changes.
- The review, QA and light panels' own batches, and the juries of `/brief`,
  `/prd`, `/design` and `/review-plan`, which have no koto state to run a check
  in. R9's ledger change applies to every panel, but only scrutiny declares a
  check.
- New koto fields or events, offline ablations, long eval runs, and dashboards
  over the exported events.

## Known Limitations

- The batch judges whether a recorded reason is a reason, not whether it is
  true; that still needs the code, and stays with the seats.
- A deviation the agent never recorded as a decision is outside the batch's
  slice. Finding one is the justification seat's job, which is why the seat
  stays.
- A run that records no decision gives the batch nothing to grade, which was
  92 of 180 sessions on 2026-10-20, so live figures accumulate at about half
  the rate of runs.
- Live figures exist only where a host opts its decider in, and the measured
  figures come from one host's sessions.
- A carried scrutiny round records nothing, so a batch verdict from a carried
  visit reaches the ledger only when a later round of the panel is recorded.
  In shadow such a finding would be advisory, so nothing that blocks is lost.
- A batch the decider can't answer holds the state even on a carried round,
  until the agent answers it. That is koto's fallback working as designed, and
  it happens only when the decider fails, not on a run with nothing to grade.

## Decisions and Trade-offs

**Specify seat replacement rather than build it.** No seat is eligible, so
code that leaves one out would ship with nothing to run on, and its safety rules
are better settled against the first real case. The rule is written now so that
case doesn't invent it.

**Leave not-graded evaluations out of the live bar.** Counting an empty slice as
unanswered would hold a criterion that is often empty below 95% forever, and
counting it as answered would let empty runs earn trust. Leaving them out, with
the minimum counts over graded evaluations only and every real fallback still
counted, keeps the bar about whether the decider answers what it is asked. Only
the slice script's output decides that a slice is empty; the decider never
does.

**One section, not one per state.** Splitting the decisions into analysis and
implementation slices doesn't lower the share of graded runs over budget
(implementation's alone was 3 of 34) and doubles the calls.

**The run denominator is the session; the graded share is recorded beside
it.** jev-pass-trust defines a run as a session and holds a contract to more
than 5% of runs over budget, and its 100-run minimum is over the same runs, so
the contract's state is decided over every session (2.8%). Over graded
sessions only it is 5.7%, past the line. Both are written down so the review of
this change, and the next measurement, can weigh them; deciding the state over
graded sessions alone would also leave the contract under the 100-run minimum.

**Record the ledger entries from koto's log.** Leaving the batch's verdicts to
the agent's round file would let a fail go unrecorded; reading them from the
log the decider wrote keeps the agent out of what the ledger says about it.

**Rejected questions are review-shadow rows.** jev-pass-trust admits a Jev
contract only on a decider entry or a review-shadow criterion, and a decider
entry is declared by a template, so it can't be rejected. The three questions
nothing can run join `rs-007` to `rs-017` as review-shadow rows with
`enabled: false`, rather than adding a third kind of Jev entry, and `rs-018`
uses the existing `no-real-run-record` reason rather than a new one.

**The criterion key is the registry id.** koto allows any key up to 128 bytes
and its documentation asks for the registry's id. Using it makes the event, the
ledger finding and the registry name one rule, so the ledger needs no lookup
from a template key to a registry id.
