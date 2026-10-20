---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-jev-scrutiny-batches.md
milestone: "Jev batches for scrutiny review"
issue_count: 4
---

# PLAN: Jev batches for scrutiny review

## Status

Active

## Scope Summary

Decomposes `DESIGN-jev-scrutiny-batches` into four work items that land as one
pull request in shirabe: a Jev slice contract for every `/work-on` scrutiny seat
question (three rejected with their figures, one untrusted), the not-graded rule
in jev-pass-trust's live bar, one shadow decider batch on the `scrutiny` state
that grades the run's recorded decisions, and the findings ledger importing that
batch's verdicts by mode. No seat changes; the rule for replacing one is
written, not built.

## Decomposition Strategy

**Horizontal.** The four pieces sit in separate code with clear boundaries: the
registry and its checker, the live-bar reader, the `work-on` template and a new
slice script, and `panel-scope.sh`'s decider path. Each builds one piece to
completion. There is no integration-risk path a walking skeleton would exercise
early: the batch runs in shadow and changes no route, and the ledger import is
tested against stubbed logs. Two edges order the work: the batch's measurement
uses the `--slice` option Item 1 adds, and the ledger's tests record under the
registry id Item 3 registers. Item 2 is independent.

## Issue Outlines

### Issue 1: feat(jev-criteria): record contracts for the scrutiny questions nothing can run

**Goal**: Give each scrutiny seat question that no slice can carry a Jev
contract with its figures (rs-018 evidence claims, rs-019 justification, rs-020
intent), measured by a new `measure sessions --slice` option, and write the
"Replacing a seat" rule into the Jev criteria reference.

**Acceptance Criteria**:
- [ ] `jev_criteria.py measure sessions` takes `--slice` with `review-facts`
      (the default, whose output is byte-identical to today's), `criteria-plan`
      (the byte lengths of a session's `ctx/review_level_criteria.txt` plus
      `ctx/plan.md`) and `design-context` (`ctx/context.md`), over every session
      directory under `--dir` that has `ctx/review_facts.json`, reading regular
      files only; the recorded `command` names the slice; a test runs each slice
      over a fixture corpus and gets the runs, maximum, p90 and over-budget count
      that corpus should give, and a symlinked key is skipped and counted.
- [ ] `scripts/review-shadow/criteria.json` holds rows `rs-018`, `rs-019`,
      `rs-020` with observer `jev`, `artifact_kind: local-change`, `enabled:
      false` and slice kinds `ac-claims`, `plan-hunks`, `design-hunks`, which
      `review-shadow.py`'s `local-change` list admits; `review-shadow.py`'s
      tests pass and its `scan` still runs `rs-001` to `rs-006` only.
- [ ] `references/rule-registry.json` holds `rs-018`, `rs-019`, `rs-020` in
      state `rejected` (`check.kind: review-shadow`, `level: shadow`,
      `withhold: never`, `text`
      on the seat's line in `phase-4a-scrutiny.md`, empty `baseline_keys` with a
      note), and `rs-015`'s entry is byte-identical to the base branch's.
- [ ] `rs-018` records `not_measured: no-real-run-record` and completeness
      verdict `insufficient`; `rs-019` and `rs-020` record `measured` figures,
      population `koto-sessions`, with `over_budget` above 5% of `runs`.
- [ ] `references/jev-criteria.md` has a `## rs-018`, `## rs-019` and
      `## rs-020` section (sources, slice, completeness, figures, state), and the
      `rs-019` and `rs-020` cases each contain "These figures are a lower bound:
      the full slice also carries the diff."
- [ ] `references/jev-criteria.md` has a `## Replacing a seat` section stating
      the five conditions (every question trusted and declared in veto on the
      panel's state; jev-pass-trust's withhold conditions hold for the session;
      a criterion unanswered in the visit plans the seat `full`; the batch's
      blocking findings stand in for the seat's; a test for each of conditions 1
      to 4), and a doc test fails if the heading or a condition's phrase is
      missing.
- [ ] `scripts/rule-registry_test.sh`'s pinned counts reflect the new entries,
      and `jev_criteria.py check`, `scripts/check-rule-registry.sh` and the
      registry tests pass.
- [ ] `shirabe validate --visibility=public` passes on every changed document.

**Dependencies**: None

**Files**: `scripts/jev-criteria/jev_criteria.py`, `scripts/jev-criteria/test_jev_criteria.py`, `scripts/review-shadow/review-shadow.py`, `scripts/review-shadow/criteria.json`, `references/rule-registry.json`, `references/jev-criteria.md`, `scripts/rule-registry_test.sh`

### Issue 2: feat(jev-criteria): leave not-graded evaluations out of the live bar

**Goal**: Make jev-pass-trust's live bar leave out an evaluation whose slice was
empty (every event `decider_checked` with outcome `not_graded`), count it
separately, and state the rule in both Jev criteria documents, for every Jev
criterion.

**Acceptance Criteria**:
- [ ] `live_figures` leaves an all-`not_graded` evaluation out of
      `evaluations`, `sessions` and `answered`, and returns it as `not_graded`;
      `jev_criteria.py figures` prints `not_graded` in its `live` JSON.
- [ ] An evaluation with `not_graded` and a later `pass` counts as answered;
      one with `not_graded` and a `decider_fallback`, or `not_graded` and
      `escape`, counts as an unanswered evaluation; tests name each case.
- [ ] The bar fails at 29 graded evaluations beside 50 not-graded ones and at
      4 graded sessions beside 10 sessions holding only not-graded ones, and
      passes at 30 graded evaluations across 5 sessions with 95% answered.
- [ ] `check_promotion` refuses a `trusted` entry whose `live` record lacks a
      non-negative integer `not_graded`.
- [ ] The not-graded tests use a criterion other than
      `work-on/scrutiny-decision-reasons`.
- [ ] `references/jev-criteria.md` ("The bars") and `docs/guides/jev-criteria.md`
      ("Reading the live figures": the definitions and the query steps) state
      the rule and name `koto.decider.outcome` `not_graded`; a doc test fails if
      either loses it, and the guide's pinned headings, phrases and attribute
      names stay.

**Dependencies**: None

**Files**: `scripts/jev-criteria/jev_criteria.py`, `scripts/jev-criteria/test_jev_criteria.py`, `references/jev-criteria.md`, `docs/guides/jev-criteria.md`

### Issue 3: feat(work-on): grade recorded decisions with a shadow decider batch on scrutiny

**Goal**: Add `decision-reasons.sh`, the `scrutiny_decider` gate on `/work-on`'s
`scrutiny` state that sends its slice to Jev in shadow, the
`work-on/scrutiny-decision-reasons` contract with its fixtures and measurement,
and the directive, phase-file, mermaid and eval text that tell the agent how to
answer a pending batch.

**Acceptance Criteria**:
- [ ] `skills/work-on/scripts/decision-reasons.sh slice <log>` prints every
      `decision_recorded` event of state `analysis` or `implementation`, any
      visit, in log order, as `- choice:` / `  reason:` lines (alternatives
      never printed, even when a decision names some), each field's whitespace
      collapsed and trimmed, a missing field as the bare label, multibyte text
      unchanged; prints nothing and exits 0 with no such event; exits 66 for a
      missing or unreadable log; reads no other file and no context key. Its
      test pins the exact output for a log with decisions in `analysis` (two
      visits), `implementation` and `verification`.
- [ ] The compiled `work-on.md` declares, on `scrutiny`, `scrutiny_decider`
      (`decider-check`, `max_bytes` 2,560, label `decisions`, command running
      `decision-reasons.sh slice "{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"`)
      with one criterion keyed `work-on/scrutiny-decision-reasons`, `mode:
      shadow`, and the PRD's question, pass, fail and escape text; no `when`,
      `skip_if` or context assignment reads it; the reserved-slot comments on
      `scrutiny`, `review`, `qa_validation` and `light_review` describe what is
      declared.
- [ ] `references/rule-registry.json` holds `work-on/scrutiny-decision-reasons`
      in state `untrusted` (`check.kind: decider`, the template, state, gate and
      criterion, `declared.sha256` current, `level: gate`, `timing:
      ["work-on:scrutiny"]`, `withhold: never`), measured by
      `measure sessions --slice decision-reasons` over at least 100 graded runs
      with at most 5% over 2,560; that slice reads every `--dir` given (it may
      repeat) and gzipped logs, counts a session once by its id and only when
      its slice is not empty, and a test over two fixture roots (one gzipped
      log, one session in both) gets the figures they should give;
      `references/jev-criteria.md` has its section, with the all-sessions figure
      beside the graded one, a statement that the fit is marginal, and the case
      for leaving alternatives out; `jev_criteria.py check` passes.
- [ ] `scripts/jev-criteria/fixtures/work-on-scrutiny-decision-reasons.jsonl`
      holds at least 10 good, 20 seeded-bad and 5 adversarial cases (at least 3
      techniques, inline layout mimicry among them), each with its input as log
      events and its slice as the script prints it; a test runs the script on
      every case and gets the case's slice.
- [ ] The `scrutiny` directive and `phase-4a-scrutiny.md` each say the batch
      runs beside the seats for a user whose decider is on, that its findings
      are advisory while it is untrusted, and that a pending batch is answered
      with `koto decider answer {{SESSION_NAME}} --gate scrutiny_decider
      --criterion work-on/scrutiny-decision-reasons --answer <pass|fail|unclear>`
      only for a criterion under `awaiting`, carried rounds included; a test
      fails if either loses one of those.
- [ ] A koto-level test (decider in shadow, a placeholder key after unsetting
      any inherited one, an unreachable loopback endpoint) shows: a session at
      `scrutiny` with a recorded decision holds with the criterion under
      `awaiting`, on a carried round as on a full one, and advances after an
      `unclear` answer; with no decision it advances without holding; a 2,561-
      byte slice falls back for `over_budget`; with the decider off the session
      passes `scrutiny` as on the base branch and its log holds no
      `decider_checked` event for the gate.
- [ ] `koto-templates/work-on.mermaid.md` carries the gate's note under
      `scrutiny`; `skills/work-on/evals/evals.json` gains a scenario for a
      pending batch; `scripts/assert-koto-floor.sh` still reads 0.20.0.

**Dependencies**: Blocked by <<ISSUE:1>>

**Files**: `skills/work-on/scripts/decision-reasons.sh`, `skills/work-on/scripts/decision-reasons_test.sh`, `skills/work-on/scripts/scrutiny-decider-routes_test.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/references/phases/phase-4a-scrutiny.md`, `skills/work-on/evals/evals.json`, `scripts/jev-criteria/jev_criteria.py`, `scripts/jev-criteria/test_jev_criteria.py`, `scripts/jev-criteria/fixtures/work-on-scrutiny-decision-reasons.jsonl`, `references/rule-registry.json`, `references/jev-criteria.md`, `scripts/rule-registry_test.sh`

### Issue 4: feat(work-on): record batch verdicts from koto's log by mode

**Goal**: Make `panel-scope.sh --record <panel>` import every unused
`decider_checked` event of the panel's state from koto's session log, and set a
decider finding's severity from the event's mode, so a shadow batch's fail is
advisory and never blocks the panel or spends a retry.

**Acceptance Criteria**:
- [ ] With a round file naming no decider entry, `--record scrutiny` records a
      `fail` event from the log as a finding raised by `decider`
      `scrutiny_decider/work-on/scrutiny-decision-reasons` under rule id
      `work-on/scrutiny-decision-reasons`: `advisory` for `mode: shadow`,
      `blocking` for `veto` and for an event with no mode.
- [ ] After a veto fail, a later `pass` adds a decider `reverified` record and
      `--verdict scrutiny` exits 0 for a panel with nothing else open; after a
      shadow fail, a later `pass` adds `reverified` and the finding stays
      advisory; a `pass` with no earlier finding adds nothing.
- [ ] A shadow `escape`, `unanswered` or `not_graded` adds no finding and no
      record; a veto `escape` with no earlier finding raises a blocking finding
      whose only record is `unverified`.
- [ ] Of several events with one (state, visit, gate, criterion, declaration
      hash), a `fail` is the one recorded; events from an earlier visit of the
      panel's state that no entry used are recorded by the next `--record`;
      events of another state are not; `--record` twice over one log records
      each event once; a round file naming an event the log already backed
      exits 65 with the ledger byte-identical; a round file's own `fail` entry
      matching a shadow event raises an advisory finding; one import for the
      `qa` panel's `qa_validation` state is exercised.
- [ ] No ledger entry is created from a `decider_check_answered` event; a
      missing session log imports nothing; an existing log that can't be read
      exits 65 with the ledger unchanged.
- [ ] With one blocking and one advisory batch finding open, `--open-count
      scrutiny` prints 1, `--verdict scrutiny` exits 1 printing only the
      blocking one, and `panel-retry-budget.sh` reads 1.
- [ ] `--plan scrutiny` writes byte-identical decisions with and without batch
      events of every outcome in the log; no seat's commissioning line and no
      code packet change.
- [ ] The existing decider-entry tests still pass, updated only where they
      assert a severity the mode now decides.

**Dependencies**: Blocked by <<ISSUE:3>>

**Files**: `skills/work-on/scripts/panel-scope.sh`, `skills/work-on/scripts/panel-scope_test.sh`

## Implementation Sequence

- **Independent:** Item 2 touches only the live bar and its documents; it can
  land first or in any order (it shares `jev_criteria.py`,
  `test_jev_criteria.py` and `references/jev-criteria.md` with Items 1 and 3,
  so those files serialize).
- **Critical path:** Item 1 (the `--slice` option and the registry rows) then
  Item 3 (the batch, its contract measured with `--slice decision-reasons`)
  then Item 4 (the ledger, whose tests record under Item 3's registry id).
- **No koto change, no decider key:** every item's tests run on stubbed logs
  or a loopback stub, and hosted CI is the build of record.
