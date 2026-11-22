---
schema: design/v1
status: Draft
problem: |
  /work-on's three counting gates read test-change.sh status, which counts an
  edited test or observation only once a seat, a person or a coordinator has
  written an acceptance line into the run's own koto session. The panels
  already judge edited tests but store no freshness, the re-verifier judges
  none, observations reach no packet, and two late-commit paths never pass a
  panel, so retiring the seat needs the panels to own that judgment end to end.
upstream: docs/prds/PRD-acceptance-write-drift.md
---

# DESIGN: acceptance-write-drift

## Status

Draft

## Context and Problem Statement

`/work-on` counts a unit's passing checks three times: at `pass_counting`
after local verification, at `pr_precheck` just before the pull request, and at
`ci_pass_counting` after CI passes on the open PR. At each of those, a gate
named `tests_counted` (`tests_still_counted` at `pr_precheck`) runs
`test-change.sh status`. That command classifies the unit's test files over
`impl_base..HEAD` with `scripts/lib/test-classify.sh`, and holds the unit while
any `edited` test or any recorded observation lacks a live acceptance in the
context key `test_change_ledger.jsonl`. An acceptance is a line written by a
minted seat (`test-change.sh seat`, then `accept` or `decline`), by a person
from an interactive terminal, or by a coordinator, and it is judged by the rule
library `scripts/lib/acceptance-rule.sh`. A coordinator can also `overrule` an
acceptance, after the run has finished. The PRD requires all of that to go
(R1 to R3): no outside party writes into the run's session for test-change
acceptance (R26), and no ledger line other than the header can change whether a
unit counts (R18).

The judgment itself already happens elsewhere. `panel-scope.sh --record`
requires every panel seat that ran to judge each edited test `corrects` or
`weakens`, refuses a round that doesn't, and records a `weakens` as a blocking
finding under rule `review/test-edit-weakens`. Each seat entry in the panels'
verdict record (the `verdict_ledger.json` context key) stores `judged_at`
(HEAD when it judged) and `test_edits: [{path, judgment}]`. Three things are
missing for the panels to replace the seat:

1. **Freshness.** Nothing compares what a seat judged with what is at HEAD. The
   blob a seat judged is recoverable as `git rev-parse <judged_at>:<path>`, and
   a rewritten history already forces a full round, so `judged_at` stays
   resolvable for as long as the record holds a verdict. But no code computes
   whether an edited test is **due**: the PRD's term (R9) for an item no seat or
   re-verifier of a panel judged at its current content.
2. **The re-verifier.** A retry that touches fewer than 200 lines plans only the
   panel's re-verifier, and the re-verifier judges no test edit: its packet has
   no test-changes section and `--record` drops its `test_edits`. So a test
   edited in a small retry is never judged again by anyone but the seat today.
3. **Observations.** A fix whose failure no check can reproduce records an
   observation pair in `red_first.json` (`before` and `after`). No panel packet
   carries it, and `red-first.sh check-green` (the `fix_green` gate) counts the
   pair only through `test-change.sh covered`, which reads seat acceptances.

Two routes also skip the panels entirely. At `ci_pass_counting`, a held run's
only rework edges lead to `ci_monitor`, which never plans a re-verifier
(shirabe#1931). And `/execute`'s `ci_monitor` pushes CI fixes to the plan's
shared branch itself, after its children reached `done`, so nothing classifies
or judges a test those fixes edit (shirabe#1730).

The PRD also asks for two smaller outside writers to be closed: a person's
override of a panel verdict gate must be recorded by the run naming the person
(R22), and `/review-plan` run directly must not write into a live `/plan`
session (R23).

## Decision Drivers

- **One writer.** Every line in a `/work-on` session about test changes comes
  from that run's own scripts, driven by that run's own directives (R18, R26).
- **Same gates, same edges.** The gate names stay, the command behind
  `tests_counted` stays byte-identical wherever it appears (the mermaid
  validator's check 4), no state is added or removed, and the only new edges
  leave `ci_pass_counting` on `counting_status: test_gap` (R12, R25).
- **The panels' record is the source.** A judgment counts because the run
  recorded it from a panel seat or re-verifier in the verdict record, not
  because a line in the test-change ledger says so (R9, R18).
- **Exit codes keep their meanings.** 0 counted, 1 held, 2 can't decide, and
  3 held with no way left to clear it (R14).
- **One retry budget.** A late `weakens` is a blocking finding under
  `panel-retry-budget.sh`'s existing two-plus-one budget, not a second
  per-path limit (R21).
- **Fail closed.** A record that can't be read, a commit that can't be
  resolved, or a re-verifier that returns nothing holds the unit; it never
  counts it (R11, R14).
- **Bash 3.2 and the existing toolchain.** The work-on scripts run on bash 3.2
  hosts with `jq` and `git`; no new dependency.
- **Smallest blast radius.** Keep `test-change.sh` as the gate's entry point so
  the registry entry, the route tests that stub it and the template's gate
  commands change as little as possible.

## Considered Options

Not written yet: a later /design phase replaces this line.

## Decision Outcome

Not written yet: a later /design phase replaces this line.

## Solution Architecture

Not written yet: a later /design phase replaces this line.

## Implementation Approach

Not written yet: a later /design phase replaces this line.

## Security Considerations

Not written yet: a later /design phase replaces this line.

## Consequences

Not written yet: a later /design phase replaces this line.
