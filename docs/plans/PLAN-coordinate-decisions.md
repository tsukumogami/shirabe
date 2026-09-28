---
schema: plan/v1
status: Active
execution_mode: single-pr
tracking_level: none
split_mode_source: none
upstream: docs/designs/DESIGN-coordinate-decisions.md
milestone: "Coordinate decisions"
issue_count: 8
---

# PLAN: coordinate-decisions

## Status

Active

Authored at Active because this PLAN files no issues. Implementation starts only from a
default branch that already holds the dispatch path (shirabe#404) and reconcile
(shirabe#406): the fourth, sixth and seventh outlines extend states and scripts those features
add (`take_report`, `worker_report`, `render-brief.sh`, the reconcile pass), and the sixth and
eighth edit the template and the rule-coverage fixture they also change.

## Scope Summary

Implement decisions and escalation in the `coordinate` skill as designed in
`docs/designs/DESIGN-coordinate-decisions.md`: the Decisions record section, the one write
script that changes it, the renderer, the question extractor, the routing check and the
template states that use them, the progress table's decision rows, the brief's channel
sentence, the skill text, and the niwa#330 replay, in one pull request.

## Decomposition Strategy

**Horizontal, in one pull request.** The DESIGN fixes each script's interface (its modes,
arguments, exit codes, verdict words and the detail keys it writes), so each is built and
tested on its own before the template states that call it. The order follows what calls
what: the phrasing list is read by three scripts; every entry is written through the codec
and the shared write core; the renderer and the extractor are called by the write script's
`--sent` and `--open-from-report`; the template states can only be written against scripts
that exist; the progress table reads what `pick-facts.sh` adds; and the skill text and the
replays describe and exercise the finished flow.

One pull request, under the repository's default `consolidated` delivery preference. No
split branch fires: no piece lands anything useful alone (a record section nothing writes, a
renderer no state calls), and nothing forces an order across pull requests. The dependency on
the two sibling features is on work outside this PLAN; it gates when this pull request starts,
not how it's split.

## Issue Outlines

### Issue 1: feat(coordinate): the decision-phrasing list

**Goal**: Add `skills/coordinate/references/decision-phrasings.tsv` and its fixtures, the one
closed list of decision phrasings and person-addressing patterns that `progress-view.sh`,
`report-questions.sh` and `need-check.sh` read.

**Acceptance Criteria**:
- [ ] Each row is an extended regular expression with no back-references and a kind,
  `decision` or `addressed`; a test fails when a row uses a back-reference or an unknown kind.
- [ ] `scripts/testdata/decision-phrasings/` holds at least three refused decision phrasings
  ("decide whether to ship", "needs your decision", "please decide"), three accepted needs
  ("needs an npm token", "run the release", "waiting on the release decision from the
  vendor"), and at least three addressed questions ("the human should decide", "your call",
  "up to you"); a shared matcher in `record-common.sh` refuses every refused fixture, accepts
  every accepted one, and marks every addressed one, matched case-insensitively with
  `grep -E`.
- [ ] The matcher's test runs in the repository's script-test CI.

**Dependencies**: None

**Type**: code
**Files**: `skills/coordinate/references/decision-phrasings.tsv`, `skills/coordinate/scripts/record-common.sh`, `skills/coordinate/scripts/testdata/decision-phrasings/`

### Issue 2: feat(coordinate): the Decisions record section and shared write core

**Goal**: Add the fifth record section to the codec, rendered only when it holds an entry or
a `Next decision` above 1, with section-aware cell grammars, per-state required columns, the
shared escalation validator, and the handoff filter; move the write core into
`record-common.sh`; make `record-write.sh` refuse any change to the section; add the
close-out stage and the predecessor copy.

**Acceptance Criteria**:
- [ ] A record body written before this feature (four sections, no Decisions) parses to no
  entries and a next identifier of 1 and renders back byte for byte, and `record-find.sh`
  adopts it (golden file).
- [ ] A record with entries in each of the four states renders the section with its
  `Next decision:` line and nineteen columns and parses back byte for byte.
- [ ] The codec refuses, as non-canonical, an entry with an unknown state, a non-integer
  identifier, a repeated identifier, an identifier at or above `Next decision`, a grounds
  value outside `scope`, `supplied-decision`, `reserved-step`, an `escalated` entry missing
  recommendation, reason, context, problem, grounds or target, and a `settled` entry missing
  outcome or decided by; each case has a test.
- [ ] The Decisions columns named `reason`, `target` and `state` use their own grammars, and
  the Reversals `reason` and Side effects `target` grammars and the refused
  GitHub-recomputable column names are unchanged for their own sections (tests for each).
- [ ] `@` in a Decisions free-text cell renders encoded and parses back to `@`; a cell with a
  pipe or a line break round-trips.
- [ ] The shared validator (one jq definition) refuses a recommendation outside the options,
  a reason, context or problem empty after trimming, no ground, and a target other than the
  one given; it passes a complete verdict.
- [ ] The named-repository scan covers the Decisions text columns, and a cell with a home
  directory path or a token-shaped string is refused.
- [ ] `record-write.sh` refuses (exit 65) a body whose Decisions section differs from the live
  one's and accepts one whose section is unchanged; its existing tests still pass through the
  shared write core.
- [ ] The handoff renders only unsettled entries with the same `Next decision`, and a
  predecessor copy keeps the section as it stands.
- [ ] `closeout-read.sh` at roadmap scope reports a `decisions` stage, ahead of `ready`, while
  any entry isn't settled.

**Dependencies**: None

**Type**: code
**Files**: `skills/coordinate/scripts/record-codec.jq`, `skills/coordinate/scripts/record-common.sh`, `skills/coordinate/scripts/record-write.sh`, `skills/coordinate/scripts/closeout-read.sh`, `skills/coordinate/scripts/predecessor-handoff.sh`

### Issue 3: feat(coordinate): render decision messages from the entry

**Goal**: Add `decision-render.sh`, which renders an escalation, a withdrawal, a reply or a
redirect from the live entry through the shared validator, and seals the text's digest in its
verdict.

**Acceptance Criteria**:
- [ ] For a fixture escalated entry, the escalation's first line is
  `Decision <n> round <r> from <topic>.`, followed by the context paragraph, the problem
  paragraph, then the question with the recommended option listed first carrying its reason,
  then the answer line; it carries one decision.
- [ ] Rendering is refused (verdict `refused`) for each of: empty recommendation, reason,
  context or problem; a recommendation outside the options; a target other than the run's
  `REPORTS_TO`; an entry that doesn't owe the kind asked for (including a second rendering
  after the owing was cleared).
- [ ] A withdrawal names the decision and round and says no answer is needed; a reply names the
  decision, round, outcome, reason and who decided; a redirect tells the worker its questions
  go to the coordinator, which answers them or escalates them with a recommendation.
- [ ] On success the text is written as a detail key and the verdict is
  `rendered <kind> <n> <round> <sha256>`, sealed through `lib_emit`; the digest matches the
  key's bytes.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `skills/coordinate/scripts/decision-render.sh`

### Issue 4: feat(coordinate): extract a worker report's questions

**Goal**: Add `report-questions.sh`, which extracts a report's questions from its Questions
part, question-shaped lines and phrasing matches, caps them, honors citations and fixed first
lines only from their own holding, and seals the list's digest.

**Acceptance Criteria**:
- [ ] A report with a `Questions:` part yields its numbered items; a `(decision <n>)` citation
  is kept only when entry `<n>`'s Source is the reporting worker, and dropped (item uncited)
  otherwise.
- [ ] A line outside the part ending in `?`, and one matching a `decision` phrasing ("please
  decide whether to ship"), are each extracted; lines inside fenced code and `>` quotes are not.
- [ ] Items matching an `addressed` pattern are marked `addressed`.
- [ ] A report with more than ten questions, or one over 400 characters, gets `overflow` and no
  list; unreadable input gets `unreadable`; a report with none gets `none`.
- [ ] A fixed `Decision <n> round <r> from <topic>.` first line is read as one question with a
  coordinator source only when the reporting holding's entry point is `/shirabe:coordinate` and
  `<topic>` is its worker topic; from any other holding it is ordinary text. A `Withdrawn:`
  first line from such a holding is read as evidence on the entry with that source. A second
  escalation with a topic, entry and round already opened yields no question, and an
  `Answer:` first line in a report is read as ordinary text.
- [ ] On `questions` the list is written as `coord/questions.json` and the verdict is
  `questions <sha256>`, sealed; the digest matches.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>

**Type**: code
**Files**: `skills/coordinate/scripts/report-questions.sh`

### Issue 5: feat(coordinate): record-decision.sh, the one writer of decisions

**Goal**: Add `record-decision.sh` with every mode of the DESIGN's mode table, bound to the
workflow state and to the entry the workflow routed, with visit stamps, evidence resets and
release; add `coord-log.sh current`. Its tests read `REPORTS_TO` and the current state from
fixture session logs, since the template variable arrives with Issue 6.

**Acceptance Criteria**:
- [ ] `--open` in `decision_raise` writes a `proposed` entry with Source `self [raise <seq>]`
  (from `failure` or `surface`) or `dispatcher [raise <seq>]` (from a `wait` raise), the next
  identifier, and `Next decision` up by one; it refuses an empty question or options.
- [ ] `--take` moves `proposed` to `coordinator-verdict`. `--settle` moves
  `coordinator-verdict` to `settled` with Outcome and Decided by set, and `Owed: reply` exactly
  when the Source is a worker, a coordinator or the dispatcher; it refuses an empty outcome or
  an empty reason. `--escalate` moves `coordinator-verdict` to `escalated` with Round up by one,
  `Owed: escalation` and Target equal to the run's `REPORTS_TO` (or `a person`).
- [ ] Refused with exit 65 and the stored record byte for byte unchanged: `--escalate` or
  `--settle` on a `proposed`, `escalated` or `settled` entry; `--take` on anything but
  `proposed`; `--escalate` failing the shared validator (one case per failing part); any mode
  run in a state other than its own (by `coord-log.sh current`); a mode reached from
  `decision_next` naming an entry other than the one its sealed capture names; any single item
  containing a carriage return or line feed.
- [ ] `--evidence` on an entry in each of the four states leaves it in `coordinator-verdict`
  with the Verdict column blank and the new line appended after every earlier Evidence line,
  carrying its time, source and `[wait <seq>]` stamp. On a settled entry the previous outcome
  and decider are appended first and Outcome, Decided by and an owed reply are cleared; on an
  escalated entry whose message was sent `Owed` becomes `withdrawal`; on one never sent `Owed`
  is cleared. No sequence of `--evidence` writes leaves an entry `escalated`.
- [ ] `--open-from-report` refuses when an item is uncovered or covered twice, when the list's
  digest doesn't match its sealed capture, and when the report visit was already written; on
  success it writes one `proposed` entry per uncited item and one evidence line per cited one,
  each stamped `[report <seq>.<i>]`, `addressed` noted on addressed items, with
  `{question, options}` from the coordinator's file.
- [ ] With one entry escalated, `--escalate` on a second leaves it in `coordinator-verdict` with
  Verdict `escalate`; settling or adding evidence to the escalated entry escalates the queued
  entry with the lowest identifier in the same write, or blanks its verdict when it no longer
  validates.
- [ ] `--answer` on an escalated entry naming its round and an option settles it with Decided by
  written from the run's target (for an answer relayed from a coordinator above, the target
  followed by the final decider the reply names), and `Owed: reply` as for `--settle`; for an
  earlier round, or on a non-escalated entry, it appends evidence as `--evidence` does; an
  answer identical to the one that settled the entry changes nothing.
- [ ] `--sent` refuses unless the render capture sealed at the latest entry into the matching
  render state names this entry, kind and round and its digest matches; on success it clears
  `Owed` and stamps `Sent`, or writes the `[redirect report <seq>]` line.
- [ ] `--carry` copies the previous rotation's unsettled entries and `Next decision` before the
  run's first dispatch and refuses afterwards or when already present.
- [ ] A second write for the same visit stamp is refused, so a retry after exit 12 never
  duplicates an entry or an evidence line.

**Dependencies**: Blocked by <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:4>>

**Type**: code
**Files**: `skills/coordinate/scripts/record-decision.sh`, `skills/coordinate/scripts/coord-log.sh`

### Issue 6: feat(coordinate): route the decision loop in the template

**Goal**: Add `decision-next.sh`, `need-check.sh`, the `decision-owed` guard in
`deferral-check.sh`, the `decisions` verdict and unsettled entries in `pick-facts.sh`,
`REPORTS_TO` and `--reports-to`, the new states and edges, the verdict codes, and the shadow
decider on `decision_verdict`.

**Acceptance Criteria**:
- [ ] `decision-next.sh` prints each of `carry`, `unrecorded-open`, `unrecorded-answer`,
  `unrecorded-evidence`, `unrecorded-raise`, `withdraw`, `reply` (including an owed redirect),
  `escalate`, `take`, `verdict`, `clear-report` and `clear` from a fixture record and log. For
  each adjacent pair of rules, a fixture owing both yields the higher rule, and the test suite
  fails when run against a copy of the script with two adjacent rules swapped.
- [ ] A report whose questions were all cited counts as recorded; a stale report after
  `overflow` yields `clear`, not `clear-report`; the `verdict` arm writes `coord/decision.json`
  and its `context-exists` gate refuses the arm without it.
- [ ] `deferral-check.sh` prints `decision-owed` before the run's first dispatch for each thing
  owed, and after it only for an unrecorded write or an owed message; an entry awaiting a
  verdict after the first dispatch doesn't block.
- [ ] `pick-facts.sh` adds unsettled entries to `coord/pick.json` and prints `decisions` when
  anything in `decision-next.sh`'s rules 1 to 7 is owed, and its usual verdicts otherwise.
- [ ] `need-check.sh` reads the need from the latest `surface` evidence, refuses a decision
  phrasing and accepts a non-decision need.
- [ ] `coordinate-open.sh --reports-to <topic>` sets `REPORTS_TO`; a malformed topic is refused
  at `koto init`; without the flag it is empty.
- [ ] The template compiles; every new state and edge in the DESIGN's table exists; every
  verdict word has a code in `coord-verdict.sh` and an arm, pinned by
  `coord-verdict-table_test.sh`; `reconcile`, `pick_facts`'s `decisions` and
  `roadmap_close`'s `decisions` stage reach `decision_next`; `report_facts` reaches
  `report_questions`; `failure: escalate` reaches `decision_raise`.
- [ ] An engine test answers an escalated entry with an answer that reverses a decision the
  dispatcher supplied: the entry settles, the run passes `decision_apply` with
  `change: reversal`, and the record holds a new Reversals row confirmed by `record`.
- [ ] `decision_verdict`'s decider on `verdict` is declared shadow in
  `scripts/decider-declarations.tsv`, with at least one fixture per answer, and flipping its
  answer changes no transition.
- [ ] An engine test restarts a run against a record with an entry in each state and shows,
  before the first dispatch, the proposed entry taken up, the unjudged one routed to a verdict,
  an escalated entry with `Sent` left alone, and one without `Sent` rendered once.
- [ ] The skill's declared koto floor (`skills/coordinate/requires.tsv`) is the one shirabe
  declares on the default branch this work starts from; nothing in the template needs a later
  koto.

**Dependencies**: Blocked by <<ISSUE:5>>

**Type**: code
**Files**: `skills/coordinate/scripts/decision-next.sh`, `skills/coordinate/scripts/need-check.sh`, `skills/coordinate/scripts/deferral-check.sh`, `skills/coordinate/scripts/pick-facts.sh`, `skills/coordinate/scripts/coordinate-open.sh`, `skills/coordinate/scripts/coord-verdict.sh`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/koto-templates/coordinate.decision_verdict.verdict.decider.jsonl`, `scripts/decider-declarations.tsv`

### Issue 7: feat(coordinate): decision rows in the progress table, and the brief's channel

**Goal**: Render decision rows in the progress table from the entries `pick-facts.sh` adds,
refuse free-text decision needs, and put the fixed channel sentence and the `Questions:`
shape in every rendered brief.

**Acceptance Criteria**:
- [ ] An entry escalated to a person renders a "Blocked on you" row with its question, status
  `decide`, and its recommendation and reason; the renderer refuses the row when either is
  empty.
- [ ] An entry escalated to a coordinator renders an "Ongoing" row naming that coordinator and
  asking nothing; a proposed or coordinator-verdict entry renders "with me for a verdict".
- [ ] `--blocked <session>=<need>` refuses each refused phrasing fixture, including "decide
  whether to ship", and accepts each accepted one.
- [ ] Every brief `render-brief.sh` renders contains the fixed channel sentence and the
  `Questions:` shape; its test fails on a brief without them.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:6>>

**Type**: code
**Files**: `skills/coordinate/scripts/progress-view.sh`, `skills/coordinate/scripts/render-brief.sh`

### Issue 8: docs(coordinate): skill text, references, rule coverage, and the replays

**Goal**: Describe the decision flow in SKILL.md by the template's states and checks, update
the references and rule coverage, add an eval, and add the three-level round trip and the
niwa#330 replay as engine tests.

**Acceptance Criteria**:
- [ ] SKILL.md has a decisions section that names only template states and checks, and a check
  fails when it names a state or check the template doesn't have (with a failing fixture).
- [ ] `references/loop.md`'s escalation shape points at the rendered form; `record-template.md`
  shows the Decisions section; `testdata/rule-coverage.tsv` carries rows for the new rules, and
  `rule-coverage_test.sh` passes.
- [ ] An eval covers a worker report asking the human to decide and expects the question
  opened as an entry, not surfaced.
- [ ] The three-level engine test (a person, a workspace coordinator, a roadmap coordinator)
  shows the roadmap coordinator's escalation opened as a `proposed` entry above with its
  source, and its settlement rendered back down so the lower entry settles naming the final
  decider; a withdrawal from below reopens the upper entry.
- [ ] The niwa#330 replay drives: an entry settled on option (d); a mixed check result recorded
  as evidence; the worker's "please decide whether to ship" in a report. It passes when the
  log shows `decision_verdict` entered before any render state, no escalation rendered, and no
  progress table in the sequence with a decision row lacking a recommendation; the same replay
  against a template variant whose evidence edge goes to `escalate` fails.
- [ ] Every test the PR adds runs in CI, read job by job.

**Dependencies**: Blocked by <<ISSUE:6>>, <<ISSUE:7>>

**Type**: docs
**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/references/loop.md`, `skills/coordinate/references/record-template.md`, `skills/coordinate/scripts/testdata/rule-coverage.tsv`, `skills/coordinate/evals/evals.json`, `skills/coordinate/scripts/coordinate_engine_test.sh`

## Implementation Sequence

The critical path is 2, 3, 5, 6, 7, 8 (with 4 joining at 5). Issue 1 and Issue 2 start
together; Issue 3 and Issue 4 can run side by side once 2 is done. Everything lands in one pull request,
started from a default branch that holds shirabe#404 and shirabe#406.
