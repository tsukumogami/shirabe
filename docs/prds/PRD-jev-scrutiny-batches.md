---
schema: prd/v1
status: Draft
problem: |
  /work-on's scrutiny panel spawns three reviewer subagents on every standard
  or full run, and no one has measured which of their questions a script-built
  slice could settle within the 2,560-byte budget Jev's accuracy evidence
  supports, how a Jev verdict would land in the findings ledger the panel gate
  reads, or what a run does when the decider can't answer. Measured on
  2026-10-20, no seat's questions are all closed within that budget; one
  closed question fits: whether the decisions a run recorded give reasons.
goals: |
  Every scrutiny seat question carries a measured slice contract in the rule
  registry, and the ones that don't fit are recorded as rejected with their
  figures. The one that fits runs as an untrusted shadow batch on the scrutiny
  state, its verdicts land in the findings ledger under a seat's closing
  rules, and an unanswered batch never passes. No seat changes, and the rule
  for replacing one is written down for the first promotion that needs it.
upstream: docs/briefs/BRIEF-jev-scrutiny-batches.md
---

# PRD: Jev batches for scrutiny review

## Status

Draft

## Problem Statement

`/work-on`'s scrutiny panel spawns three reviewer subagents on every run at the
`standard` or `full` review level: completeness, justification and intent, each
a model-backed agent with a 15-call budget. Across the 180 `/work-on` sessions
recorded on one maintainer's host, measured on 2026-10-20, the panel's seats
raised seven blocking findings in all, so almost every round passes and still
costs three agents. The people affected are shirabe's maintainers, who decide
which reviews a check could stand in for, and `/work-on` users, whose runs pay
for every seat.

shirabe can hand a closed question to Jev through a koto decider check, and
[jev-pass-trust](PRD-jev-pass-trust.md) (#921) sets what a Jev criterion has to
show first: its sources, the script that builds its slice, a written case that
the slice holds everything the question needs, and its size on real runs, with
a budget no higher than 2,560 bytes, about the 2,507 the Jev accuracy spike
validated. Nobody has applied that test to scrutiny. Measured against it:

| Seat | Question | Smallest slice it needs | Real runs | Over 2,560 |
|---|---|---|---|---|
| completeness | does every acceptance criterion have an implementation (`rs-015`) | the criteria beside their anchored hunks | 398 recorded runs | 382 |
| completeness | are the evidence claims verifiable from the diff | the agent's own claims, which no script writes | none | n/a |
| justification | are deviations explained, do the reasons hold up | the criteria, the plan and the diff (lower bound: criteria and plan) | 180 sessions | 154 |
| intent | does the change do what the design describes | the design context and the diff (lower bound: design context) | 172 sessions | 91 |
| (justification, closed part) | does each recorded decision give a reason | the decisions recorded in analysis and implementation | 180 sessions | 5 |

The coverage question doesn't fit even one criterion at a time: the earlier
review-shadow trial's per-criterion slices had to drop hunks to stay under the
bound in 2,933 of 3,363 units. A koto decider check can't ask one unit per
evaluation either: a self-transition opens no new visit, and one `koto next`
allows four consultations. So no seat's questions are all closed within the
budget, and replacing a seat would mean a Jev pass standing in for review its
slice never carried.

One closed question fits. A run records its decisions with `koto decisions
record` while it analyses and builds the change, and whether each one gives a
reason, rather than restating its choice, can be judged from the decision's own
text. It is the part of the justification seat's question that a script can
hand over whole.

Two parts of the path are also undefined. A seat's findings land in the
[findings ledger](PRD-findings-ledger.md) (#714) by content id, and the panel
gate and the retry budget read them there. The ledger can take a decider entry
today, but it marks every decider fail blocking whatever the check's mode,
raises a blocking finding on any outcome that isn't a verdict, and records only
what the agent copies into its round file. So a shadow check, which is never
meant to block, would block the panel, and a fail the agent left out would
never land. And jev-pass-trust's live bar counts an evaluation whose slice was
empty, which koto records as not graded, as unanswered, so a question that
often has nothing to grade could never earn trust.

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
  every seat still runs.
- The live bar can be met by a criterion that is often empty, without an empty
  run ever counting toward trust.
- The rule for replacing a seat, and what the promotion that first does it has
  to build, is written down.

## User Stories

- As a shirabe maintainer weighing the cost of the scrutiny panel, I want each
  seat's questions on record as contracts with measured figures, so that I can
  see which seat a decider could replace (none today) and what evidence would
  change that.
- As a `/work-on` user whose decider is on, I want the batch to grade my run's
  recorded decisions at scrutiny while all three seats run, so that my run
  feeds the batch's live figures without changing what reviews it.
- As a `/work-on` user whose decider can't answer the batch, I want to answer
  the question myself and have every seat still review, so that a missing
  verdict never stands in for review.
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
| completeness: every criterion has an implementation | `rs-015` (exists) | `rejected` |
| completeness: evidence claims verifiable from the diff | `rs-018` | `rejected` |
| justification: deviations explained, reasons hold up | `rs-019` | `rejected` |
| intent: the change does what the design describes | `rs-020` | `rejected` |
| recorded decisions give reasons | `work-on/scrutiny-decision-reasons` | `untrusted` |

A question no template declares is a review-shadow criterion, as `rs-007` to
`rs-017` are: `rs-018` to `rs-020` join `scripts/review-shadow/criteria.json`
with observer `jev` and are marked so that nothing runs them. The one question
the batch asks is a decider entry. Each entry's written case lives in
`references/jev-criteria.md` under a heading named for its id, and says what
the slice holds, why it is or isn't enough, and the figures.

**R2. A rejected contract keeps its figures.** `rs-019` and `rs-020` record a
measured lower bound: the part of the slice a script can build from what a
`/work-on` session keeps (the criteria and the plan; the design context),
measured over every recorded session, with a completeness case that says the
full slice also needs the diff and so can only be larger. `rs-018` records
`not_measured: no-real-run-record` and a completeness verdict of
`insufficient`: the claims are the agent's own words about its work, which
nothing records for a script to read and which jev-pass-trust's R3 keeps out of
every slice anyway.

**R3. The batch.** `/work-on`'s `scrutiny` state declares one `decider-check`
gate, `scrutiny_decider`, with `max_bytes` 2,560, label `decisions`, and one
criterion in `mode: shadow` whose key is its registry id,
`work-on/scrutiny-decision-reasons`, so koto's events and the ledger name the
same rule. Its question asks whether every decision the slice lists gives a
reason for its choice (a constraint, a fact about the code or the system, or an
alternative it rejected) rather than restating the choice; its escape covers a
slice it can't judge.

**R4. The slice.** The gate's command runs a shipped slice script that prints,
in the order koto recorded them, every decision the session recorded while in
the `analysis` and `implementation` states, each as its choice, its rationale
and any alternatives it names, with each field's whitespace collapsed to single
spaces, and prints nothing when there are none. It reads only koto's session
log for the session; it never reads a file the agent names or selects.

**R5. Measured on real runs.** `work-on/scrutiny-decision-reasons`'s contract
records the slice measured over every recorded `/work-on` session (population
`koto-sessions`, at least 100 runs) by a shipped command that prints the same
figures given the same session logs. The contract also records, in its written
case, the same figures over only the sessions with something to grade, so a
reviewer sees both: on 2026-10-20 that was 180 sessions with 5 over the budget,
and 88 graded sessions with the same 5 over.

**R6. Fixtures.** `work-on/scrutiny-decision-reasons` has a fixture file meeting
jev-pass-trust's R8 profile (at least 10 good, 20 seeded-bad and 5 adversarial
cases, at least 3 adversarial techniques), each case's input given as the
session-log events the slice script reads and its slice as the script prints
it.

**R7. An unanswered batch never passes.** When koto lists the criterion under
the check's `awaiting` (an over-budget slice, a failed extraction, a provider
or transport error, an unreadable answer, a spent cap, a busy lock), the state
holds, on a carried round as on any other, until the agent records its own
answer with `koto decider answer`; the `scrutiny` directive tells it how, and
nothing reads that answer as the decider's. Every seat the panel's scope plans
still runs, whatever the batch answered or failed to answer. The slice script
exits 0 with no output when the session recorded no decision, so a run with
nothing to grade never holds.

**R8. No change in which seats run.** `panel-scope.sh --plan`'s decisions are
the same with or without the batch's events in the session log, and no seat,
prompt or packet changes.

**R9. Batch verdicts land in the ledger.** `panel-scope.sh --record <panel>`
records, as decider entries, every `decider_checked` event koto's session log
holds for the panel's state that no earlier entry used, whether or not the
agent's round file names it. Each entry's finding:

- is raised by the decider, named `<gate>/<criterion>`, under the criterion's
  registry id, by content id as any finding is;
- on `fail`, is `advisory` when the event's effective mode is `shadow` and
  `blocking` otherwise;
- on `pass`, gets a `reverified` record from the decider when it exists, which
  closes it under the existing rule that a decider may close its own finding;
- on any other outcome, in `shadow`, gets nothing; otherwise, keeps today's
  `unverified` record.

A round file's own decider entries keep working, checked against the log as
today and taking their mode from the event they match, and an event backs one
entry whichever way it arrives.

**R10. The panel gate and retry budget read batch findings like any other.**
`--verdict`, `--open-count` and `panel-retry-budget.sh` count a blocking
finding the batch raised exactly as they count a seat's, and never count an
advisory one.

**R11. The live bar leaves out runs with nothing to grade.** In jev-pass-trust's
live bar, an evaluation whose every `decider_checked` event has outcome
`not_graded` (koto's outcome for an empty or whitespace-only slice, decided by
what the slice script printed, never by the decider) is left out of the
evaluations, the sessions and the answered share, and never counts as a pass
toward trust or withholding. The minimum counts (30 evaluations, 5 sessions)
count graded evaluations only. Every other unanswered reason, fallbacks and
`over_budget` included, still counts against the bar. This holds for every Jev
criterion. The reference reader (`jev_criteria.py figures`) prints the number
of evaluations it left out, the promotion's `live` record carries it, and
`references/jev-criteria.md` and `docs/guides/jev-criteria.md` state the rule
with the exported field that tells a not-graded evaluation apart
(`koto.decider.outcome` = `not_graded`).

**R12. The seat-replacement rule is written, not built.** `references/jev-criteria.md`
gains a section saying when a seat may be left unspawned and what the pull
request that first does it must build: every question the seat asks has a
`trusted` contract declared on the panel's state in `veto`; the seat is left
out only for a session where jev-pass-trust's R14 conditions hold for every one
of those criteria; any criterion of the batch left unanswered in the visit
plans the seat as `full` for that round; the batch's blocking findings take the
seat's place in the ledger and the gate; and the change ships with tests for
each of these. No code in this feature leaves a seat out.

**R13. The agent is told.** `phase-4a-scrutiny.md` and the `scrutiny`
directive say that the batch runs beside the seats for a user whose decider is
on, that its findings are advisory while it is untrusted, and how to answer it
when it is pending, in the pattern `review_level_check` uses.

### Non-functional

**R14. No koto change.** The feature uses koto 0.20's decider checks, fallback
and events as they are: no new koto field, event or exported attribute, and no
koto floor change.

**R15. No decider in CI.** Tests that exercise the batch, the slice, the
ledger or the bar run against stubbed session logs and never see a decider key;
the fixture runner keeps jev-pass-trust's loopback guard. CI runs no
measurement against real data.

**R16. Public repository.** Contracts, fixtures, figures and documents name no
private repository, path or record; figures are aggregate counts and sizes.

## Acceptance Criteria

Contracts:

- [ ] `references/rule-registry.json` holds `rs-018`, `rs-019` and `rs-020` in
  state `rejected` and `work-on/scrutiny-decision-reasons` in state
  `untrusted`, `rs-015` is unchanged, `scripts/review-shadow/criteria.json`
  holds rows for `rs-018` to `rs-020` that nothing runs, and
  `jev_criteria.py check` and `scripts/check-rule-registry.sh` pass on the
  tree. (R1)
- [ ] `references/jev-criteria.md` has a heading for each of the four new ids,
  and each entry's `completeness.heading` names it. (R1)
- [ ] `rs-018` records `not_measured: no-real-run-record` and verdict
  `insufficient`. (R2)
- [ ] `rs-019` and `rs-020` record measured figures with more than 5% of runs
  over 2,560, and their written cases say the figures are a lower bound. (R2)

The batch:

- [ ] `work-on.md`'s `scrutiny` state declares `scrutiny_decider` with
  `max_bytes` 2,560, label `decisions` and one criterion,
  `work-on/scrutiny-decision-reasons`, in `mode: shadow`; the registry entry's
  `check` names that template, state, gate and criterion with a current
  `declared.sha256`; and no `when` clause, `skip_if` or context assignment
  reads the gate. (R3)
- [ ] Given a session log with decisions recorded in `analysis`,
  `implementation` and another state, the slice script prints only the first
  two states' decisions, in recorded order, each field on one line with its
  whitespace collapsed; given a log with none, it prints nothing; a test pins
  the exact output. (R4)
- [ ] The slice script's output doesn't change when a file named in a decision,
  or any context key, changes. (R4)
- [ ] `work-on/scrutiny-decision-reasons` records at least 100 measured
  `koto-sessions` runs, and the shipped command reproduces its figures from a
  fixture corpus in a test. (R5)
- [ ] Its fixture file passes jev-pass-trust's fixture checks, and a test runs
  the slice script on every case's input and gets the case's slice. (R6)

Fallback and seats:

- [ ] The `scrutiny` directive names `koto decider answer {{SESSION_NAME}}
  --gate scrutiny_decider --criterion work-on/scrutiny-decision-reasons
  --answer <pass|fail|unclear>` and says to answer only a criterion listed
  under `awaiting`. (R7, R13)
- [ ] With a real koto and a decider stub that fails every request, a session
  reaching `scrutiny` on a carried round holds there with the criterion under
  `awaiting`, and advances to `review` after `koto decider answer`; with no
  decision recorded, the same session advances without holding. (R7)
- [ ] `panel-scope.sh --plan scrutiny` writes the same decisions for a session
  whose log holds batch events of every outcome as for the same session
  without them. (R7, R8)

Ledger:

- [ ] `--record scrutiny` with a round file that names no decider entry records
  a `fail` event from the log as a finding raised by `decider`
  `scrutiny_decider/work-on/scrutiny-decision-reasons` with rule id
  `work-on/scrutiny-decision-reasons`: `advisory` for a `shadow` event,
  `blocking` for a `veto` one or one with no mode. (R9)
- [ ] A later `pass` event closes the batch's blocking finding (`--verdict`
  then exits 0 for a panel with no other open finding); a `shadow` event of
  outcome `escape`, `unanswered` or `not_graded` adds no finding and no record.
  (R9, R10)
- [ ] An event recorded once, through the round file or the log, is refused
  or skipped the second time, and the ledger is byte-identical after a refused
  write. (R9)
- [ ] `--verdict` and `--open-count` count a blocking batch finding as open
  and an advisory one not at all, and `panel-retry-budget.sh` reads the same
  count. (R10)

Live bar:

- [ ] `jev_criteria.py figures` over a fixture log leaves an all-`not_graded`
  evaluation out of evaluations, sessions and answered and reports it as
  `not_graded`; a tuple with `not_graded` and a later `pass` counts as answered;
  a `not_graded` tuple with a fallback counts as unanswered. (R11)
- [ ] The bar fails at 29 graded evaluations beside any number of not-graded
  ones, and at 4 graded sessions; it passes at 30 and 5. (R11)
- [ ] Both Jev-criteria documents state the not-graded rule and name
  `koto.decider.outcome` `not_graded`, and a doc test fails if either loses it.
  (R11)

Seat replacement:

- [ ] `references/jev-criteria.md` has a section on replacing a seat that
  states each condition R12 lists, and no script or template leaves a scrutiny
  seat unspawned. (R12)

Floor, CI and visibility:

- [ ] `scripts/assert-koto-floor.sh` still reads 0.20.0, and no koto change is
  part of the feature. (R14)
- [ ] No test or workflow sets `KOTO_DECIDER_API_KEY` or calls a decider
  endpoint, and no workflow runs a measurement over real data. (R15)
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
- The review, QA and light panels, and the juries of `/brief`, `/prd`,
  `/design` and `/review-plan`, which have no koto state to run a check in.
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
- Live figures exist only where a host opts its decider in.
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

**Leave not-graded runs out of the live bar.** Counting an empty slice as
unanswered would hold a criterion that is often empty below 95% forever, and
counting it as answered would let empty runs earn trust. Leaving them out,
with the minimum counts over graded runs only and every real fallback still
counted, keeps the bar about whether the decider answers what it is asked.

**One section, not one per state.** Splitting the decisions into analysis and
implementation slices doesn't lower the share of graded runs over budget
(implementation's alone was 3 of 34) and doubles the calls.

**Record both measurement denominators.** jev-pass-trust defines a run as a
session, so the contract's figures are over every session (5 of 180 over
budget, 2.8%). Over graded sessions only it is 5 of 88 (5.7%), past the 5%
rejection line. Both are written down; the next measurement with more graded
runs decides whether the slice needs to shrink.

**Record the ledger entries from koto's log.** Leaving the batch's verdicts to
the agent's round file would let a fail go unrecorded; reading them from the
log the decider wrote keeps the agent out of what the ledger says about it.

**Rejected questions are review-shadow rows.** jev-pass-trust admits a Jev
contract only on a decider entry or a review-shadow criterion, and a decider
entry is declared by a template, so it can't be rejected. The three questions
nothing can run join `rs-007` to `rs-017` as review-shadow rows that nothing
runs, rather than adding a third kind of Jev entry.

**The criterion key is the registry id.** koto allows any key up to 128 bytes
and its documentation asks for the registry's id. Using it makes the event, the
ledger finding and the registry name one rule, so the ledger needs no lookup
from a template key to a registry id.
