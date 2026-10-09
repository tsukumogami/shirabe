---
schema: brief/v1
status: Accepted
problem: |
  When a /work-on review panel blocks and the fix comes back, the retry pays
  for whole reviewer seats rather than for the findings the fix touched, and
  nothing tracks a single finding from the round that raised it to the run
  that closed it.
outcome: |
  A /work-on run that fixes one finding out of several pays for re-checking
  that finding and one look at the fix's own diff, every finding can be
  followed from the round that raised it to the record that closed it, the
  agent still can't declare a panel passed on its own word, and a later
  non-reviewer check has somewhere to report.
---

# BRIEF: findings-ledger

## Status

Accepted

Framing for the first step of review offload in /work-on: cutting what a
panel retry costs without letting any pass skip a first-round panel.

## Problem Statement

/work-on sends a change through review panels (scrutiny, review, QA, or the
single light seat). When a panel blocks, the coder fixes the work and the run
walks forward into the panels again. Each panel already keeps a ledger of its
seats' verdicts, so a seat whose ground the fix didn't touch keeps its pass.
That ledger is kept per seat, though, and the cost of a retry follows from it:

- A seat that blocked is spawned again to re-check its findings.
- A seat that passed is re-run as a full review when the fix touched anything
  it cited or any location of a finding it raised. One edited line in a file a
  passed seat cited buys a whole fresh review from that seat.
- Across scrutiny, review and QA that is up to seven reviewer runs per retry,
  and a run may retry up to three times.

The second gap is accounting. A finding exists only inside one seat's record
for one round. Nothing gives it an identity that lasts across rounds, so
nobody can say which round raised it, which run closed it, or whether it was
closed at all rather than dropped from a later answer. The panel's pass is
computed from whether each seat is still blocking, not from whether each
blocking finding was closed by something other than the agent's say-so.

The same gap leaves a finding from anything other than a reviewer seat with
no home. A cheaper check that answers some of a reviewer's closed questions
could fail a criterion today, and the panel gate would have nowhere to read
that failure from.

## User Outcome

The agent running /work-on, and the maintainer paying for its reviewer runs,
see a retry cost what the fix touched. A fix to one of several findings
re-verifies that finding and gets one review of the fix's own diff; findings
the fix left alone keep their verdict without a reviewer run, and a fix that
breaks something elsewhere is still caught by that diff review.

A maintainer reading a finished run can follow each finding from the round
and reviewer that raised it to the reviewer or check run that closed it, and
can see that the panel passed only because every blocking finding was closed
by such a record. The agent's own claim that it fixed something never closes
anything.

The author of the next offload step finds a ledger that already accepts
findings from a decider, so a batched decider check can report into it
without the panel gate changing again.

## User Journeys

### A fix that touches one of several findings

The /work-on agent's scrutiny round blocks with three findings in three
files. The coder fixes the one in `a.sh` and commits. On re-entry the panel
re-verifies only the `a.sh` finding and runs one review over the fix's diff;
the other two findings are untouched, keep their open status, and the panel
blocks again on them, at the cost of two reviewer runs rather than three
seats' worth. When the next fix touches the other two files, the same rule
re-verifies those two, and the panel passes once every blocking finding has a
verdict record from a reviewer.

### A fix that breaks something it wasn't aimed at

The coder fixes a finding in `parse.sh` and, in passing, changes a helper
another file depends on. The finding re-verifies as closed, but the review
of the fix's own diff raises a new blocking finding about the helper. It
enters the ledger as open, and the panel blocks on it even though no earlier
seat ever cited that helper.

### A finding with no place to point at

The /work-on agent gets back a scrutiny block whose finding says "the change
doesn't do what the design describes" and names no file. After the fix, the
agent sees the retry still send that finding to a reviewer, because no diff
can show a finding with no location untouched, and the run can't pass around
it until a reviewer closes it.

### Reading a run after it ends

A maintainer checking why a run took four reviewer runs on its second round
opens the ledger in the session's context. Each finding shows the reviewer
seat that raised it, its severity, the round, its location kind, any
registry rule it carries, and the record that closed it with the run that
wrote it. A finding the agent marked fixed but no reviewer re-verified is
visibly still open.

### Adding a decider later

The maintainer building the next offload step wires a decider into the
scrutiny state. A criterion the decider fails shows up at the same panel gate
as a reviewer's finding, with no change to the gate. A criterion the decider
can't answer goes back to a reviewer instead of quietly counting as passed.

## Scope Boundary

**IN:**

- A per-finding record inside the panels' existing verdict ledger: identity
  that lasts across rounds, severity, round, the reviewer or check that raised
  it, a location of a declared kind (lines, file, or none), and a status
  history.
- Targeted re-verification on a retry: re-check the findings whose location
  the fix touched, re-check every finding whose location is none or can't be
  resolved, and run one review of the fix's own diff whose findings enter the
  ledger.
- The panel gate passing only on verdict records written by a reviewer or
  check run, decided by the gate koto already runs at each panel state.
- Naming each finding's rule in the rule registry's terms, so the gate never
  prints a rule the registry doesn't know.
- A place in the ledger for findings a decider raises, defined but not yet
  produced by anything.
- Evidence that a retry runs fewer reviewers than a full panel did.

**OUT:**

- The batched decider check for scrutiny itself. This feature defines where
  its findings go; building it is the next feature.
- Skipping or shrinking any panel's first round. Every panel still runs in
  full the first time it is reached.
- Withholding any rule from an agent's default context. The wider offload
  plan may later trim what an agent loads up front; nothing here does.
- Any change to koto. The feature uses what koto 0.15.0 already runs and
  records.
- Changing the retry cap's numbers (two free retries, a third only on
  progress, three at most).
- Re-scoping the review and QA panels' seat roles or prompts beyond what the
  ledger needs from their answers.
