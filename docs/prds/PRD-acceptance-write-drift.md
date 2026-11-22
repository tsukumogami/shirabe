---
schema: prd/v1
status: Accepted
problem: |
  A /work-on run's koto session is meant to be the run's own ledger, but
  test-change acceptance has a minted seat, a person at a terminal or a
  coordinator's overrule write their own verdicts into it, sometimes after the
  run finished. The seat repeats the review panels' judgment of edited tests
  with less input, while the one thing only it catches (a test or observation
  that changes after the panels looked) has no other check.
goals: |
  Every edited test and observation is judged by the review panels, and judged
  again by a re-verifier when it changes after a panel seat last looked, before
  the run counts its checks. The run is the only writer of its ledger: the seat,
  the person path and the overrule are gone, and the outside input that stays (a
  person overriding a panel gate) is recorded by the run with the person named.
upstream: docs/briefs/BRIEF-acceptance-write-drift.md
---

# PRD: acceptance-write-drift

## Status

Accepted

## Problem Statement

shirabe works on the producer side of a pull request. Its gates and review
panels help one author send the strongest PR it can, and trust in that PR is
established where it's reviewed. koto is the producer's ledger: the run writes
it, and each decision in it is attributed to the run, to a session above it, or
to a person. A reviewer who can read the ledger gets proof of work; one who
can't still has a PR that stands on its own.

Test-change acceptance doesn't fit that model. When a fix passes with an edited
test or an observation, `/work-on` holds the pass at `pass_counting`,
`pr_precheck` and `ci_pass_counting` until "someone other than the run" accepts
it, and to make that claim outside parties write into the run's
`test_change_ledger.jsonl`: a seat the run mints, which then runs `accept` or
`decline` under its own identity; a person at a terminal in a repository that
declares `## Test Change Acceptance: person`; and a coordinator's `overrule`,
which can arrive after the run is done. It's the only routine place in shirabe
where an outside party writes its judgment into a producer's ledger.

The judgment is mostly a duplicate. Every real panel seat already judges each
edited test `corrects` or `weakens`, with the production diff in front of it,
and a `weakens` is a blocking finding. The seat asks the same question of the
test hunks alone. What only the seat covers today is narrow: observations,
which no panel packet carries, and tests that change after the panels judged
them, which only the seat's digest-bound recheck catches. The panels' own
re-verifier judges no test edit, and two late paths never pass a panel at all: a
test fix made at `ci_pass_counting` (shirabe#1931) and a CI fix pushed from
`/execute`'s monitoring state (shirabe#1730). Nobody uses the rest: no
repository declares the person header, and nothing reads an overrule once a run
has finished.

Two smaller outside writers follow the same pattern. A person's override of a
panel verdict gate is recorded with no decider named, and `/review-plan` run
directly on a plan that a live `/plan` session owns writes its verdict into that
session, which makes `/plan` skip its own review.

## Goals

- An author running `/work-on` gets every edited test and observation judged by
  the panels, and re-judged when it changes after the panels looked, without
  minting, waiting on or relaying an acceptance seat.
- A late test edit, whether `/work-on` makes it while counting or `/execute`
  pushes it as a CI fix, reaches a re-verifier before the run counts it.
- A reader of a run's koto session finds only lines the run wrote, with any
  outside input named by its source.

## User Stories

- As an agent running `/work-on` on an issue whose fix changes an existing
  assertion, I want the panels to judge the edit with the production change it
  serves, so that I reach my PR without commissioning an acceptance seat.
- As an agent whose CI fix late in a run edits a test the panels already
  judged, I want a re-verifier to judge the changed test before `pr_precheck` or
  `ci_pass_counting` counts it, so that a weakened test can't ride in after the
  review.
- As `/execute` driving a plan, when I push a CI fix that touches a test, I want
  that test judged the same way a child run's own edit would be, so that the
  rule doesn't depend on which session made the commit.
- As a maintainer who overrides a panel verdict gate, I want the override
  recorded with my handle and the surface I used, so that a later reader knows
  the run didn't make that call on its own.
- As an author who runs `/review-plan` on a plan a `/plan` session is still
  writing, I want it to refuse rather than write into that session, so that
  `/plan` stays the only writer of its ledger and runs its own review.
- As a reviewer reading a run's koto session, I want every test-change line in
  it to be the run's own, so that I can read it as the producer's proof of work.

## Definitions

- **Panel seat**: a reviewer seat a review panel (scrutiny, review, QA or the
  light panel) spawns for a round, as opposed to the panel's re-verifier.
  shirabe's panel-scope code calls these "real" seats.
- **Re-verifier**: the single seat a panel plans to re-check due findings and,
  after this work, due tests and observations.
- **Judgment**: a `corrects` or `weakens` verdict on an edited test, or a
  `shown` or `not shown` verdict on an observation pair, recorded by the run in
  the panels' verdict record with the seat (or re-verifier) and the commit it
  judged at.
- **Item**: an edited test file in the unit's diff, or a fix's observation pair.
  An item's **content** is its blob at the run's head (or `deleted`), or the
  observation pair's recorded digests.
- **Open adverse judgment**: a `weakens` or `not shown` judgment whose blocking
  finding the panels' own finding lifecycle hasn't closed.
- **Panel retry budget**: the per-run limit on panel retries that
  `panel-retry-budget.sh` enforces today (two unconditional retries, three at
  most, shared across the panels).

## Requirements

### Retiring the seat

- **R1.** `/work-on` no longer mints, commissions or waits on an acceptance
  seat. The `seat`, `accept`, `decline` and `overrule` subcommands of
  `test-change.sh`, the seat brief, and the authority rules in
  `scripts/lib/acceptance-rule.sh` are removed, and no directive, reference or
  eval tells a run to use them.
- **R2.** The person-required path is removed: the `## Test Change Acceptance:`
  declaration is no longer read or listed as a convention, and nothing waits at
  a terminal or checks a terminal code or tag. A repository that still carries
  the header runs as one without it.
- **R3.** The coordinator overrule is removed. Nothing in shirabe writes, or
  tells a coordinator to write, a judgment into another run's session.
- **R4.** The producer-side pieces of red-first stay: recording the red and the
  green, the ledger header (`init`), classifying the unit's test files
  (`classify`), the run's notes on why it edited a test (`note`), the record a
  run reads back (`record`), and the test classifier. Their existing tests pass
  with only the cases that exercise removed subcommands or removed record lines
  deleted.
- **R5.** Seat, accept, decline, refuse and overrule lines already present in a
  ledger from a run started before this change are ignored by the counting
  check (R12). `record` may still list them as history.

### Judging tests and observations

- **R6.** Every panel seat that runs judges every edited test `corrects` or
  `weakens`, as today; a round missing a judgment is refused, and each
  `weakens` is a blocking finding.
- **R7.** The run's note on why it edited a test reaches every panel seat and
  re-verifier that judges that test.
- **R8.** A fix's observation pair reaches the panel seats, which judge it
  `shown` (the before observation shows the reported failure and the after
  observation shows it gone) or `not shown`. `not shown` is a blocking finding.
  The after observation is recorded before the panels run, or the pair is due
  under R9 once it is.
- **R9.** An item is **due** for a panel when that panel has no judgment of it
  at its current content: no panel seat or re-verifier of that panel judged it
  at a commit where its content equals the content at head. Judgments at other
  commits don't count, whichever seat made them.
- **R10.** When an item is due for a panel and the panel runs a round, the round
  plans a re-verifier if it would otherwise plan only seats that keep their old
  verdicts. The re-verifier's packet lists each due item (the test's hunks and
  note, or the observation pair), it judges each one with the verdicts R6 and R8
  use, and the run records those judgments. A judgment for an item that wasn't
  in the packet is refused.
- **R11.** A re-verifier that returns no judgment for a due item leaves the item
  due.

### Counting

- **R12.** At `pass_counting`, `pr_precheck` and `ci_pass_counting`, the gates
  that read `test-change.sh status` today (`tests_counted` and
  `tests_still_counted`) read a check that holds the unit while any item is due
  for any panel the unit's review level runs (the panels the verdict record
  shows planned for the unit), or carries an open adverse judgment. The gates keep their names, and the command stays identical
  wherever one gate name appears.
- **R13.** The check also holds a unit with no ledger header, with an
  uncommitted change to a tracked file, or with an untracked file the test
  classifier counts as a test.
- **R14.** The check exits 0 when nothing holds the unit and 1 when it holds,
  naming each held item and why (due, `weakens`, `not shown`, no header,
  uncommitted, untracked). It exits 2 when it can't decide: the work tree is
  gone, the session or the panels' verdict record can't be read, or the stored
  classifier rules are missing. It exits 3 when it holds the unit for an open
  adverse judgment or a due item and the panel retry budget is spent, so no
  further panel round can clear it.
- **R15.** The evidence values the counting states accept keep their names and
  edges. `declined` now means the unit is held by an adverse judgment or a due
  item, and sends the run back the way it does today: to implementation from
  `pass_counting`, which passes the panels again, and to `ci_monitor` from
  `ci_pass_counting`. `blocked` and exit 3 end the run at `done_blocked`.
- **R16.** From `pr_precheck`, a hold sends the run to `pass_counting` through
  the existing `recount`, which then routes it as R15 says.
- **R17.** A fix whose red was an observation reaches its green (`fix_green`,
  checked at `pass_counting`, after the panels have run) only when its
  observation pair is not due and carries no open adverse judgment.
- **R18.** Apart from the header `init` writes (R13), no line in
  `test_change_ledger.jsonl` changes whether the unit counts. The only ways past a hold are a judgment the run records from a
  panel or re-verifier, or a change to the code or tests that removes the item.

### Late commits

- **R19.** A test edited at `ci_pass_counting` reaches a re-verifier before CI
  and counting run again (shirabe#1931). `ci_pass_counting` gains the
  `test_gap` evidence value `pass_counting` already has, with an edge that
  takes the run back through the panels. A commit there that edits a test and
  production code together has its test judged this way; the production change
  gets no fresh panel look (see Out of Scope).
- **R20.** A CI fix that `/execute` makes from its monitoring state and that
  edits a test isn't pushed by `/execute` directly: it goes to the step's
  `/work-on` run as a fix round, which re-enters that run (finished or not) so
  its panels' re-verifier judges the test and the run records the judgment in
  its own session (shirabe#1730). `/execute` treats the step as passing only
  once that run's counting check exits 0, and writes nothing into the run's
  session itself. A CI fix that edits no test is unaffected.
- **R21.** A re-verifier's `weakens` or `not shown` on a late item counts
  against the panel retry budget like any blocking finding. There is no
  separate limit on declines of the same set of files.

### Outside writers

- **R22.** A person's override of a panel verdict gate (`scrutiny_verdict`,
  `review_verdict`, `qa_verdict`, `light_verdict`) is recorded by the run with
  `koto overrides record --by person:<handle> --surface <terminal|forge|relay>`,
  with `--link` to the person's words when the surface is `relay`. Each of those
  gates' directives spells out the command, the run records it rather than the
  person, and the skill's declared koto requirements include the flags.
- **R23.** When `/review-plan` is run directly and the `plan-<topic>` session is
  live (`skill-session.sh status` reports `live`), it writes no key into that session and removes none. It says the `/plan` run owns
  the session and runs its own review, and it may review the plan read-only,
  printing findings without storing them. When the session is absent or
  finished, `/review-plan` behaves as today.

### Documents

- **R24.** The red-first PRD and design carry a note naming the parts this PRD
  supersedes (the acceptance seat, the person path, the overrule and the
  interim acceptance rule) and pointing here. The red-first reference describes
  the panel judgment of edited tests and observations, the due rule and the
  re-verifier in their place.

### Non-functional

- **R25.** `/work-on`'s template adds and removes no state. The only edges it
  gains leave `ci_pass_counting` on `counting_status: test_gap`, for R19.
- **R26.** No shirabe script or directive outside `/work-on`'s own run writes
  into a `/work-on` session for test-change acceptance.
- **R27.** An autonomous run never stops to wait for a person at a test-change
  hold; an adverse judgment loops it back or ends it blocked.

## Acceptance Criteria

### Retiring the seat

- [ ] R1: `grep -rnE "test-change\.sh (seat|accept|decline|overrule)" skills/ references/ scripts/`
      finds nothing, `scripts/lib/acceptance-rule.sh` doesn't exist, and
      `test-change.sh seat <session>` exits 64 as an unknown subcommand.
- [ ] R1: no eval in `skills/work-on/evals/evals.json` asserts that a seat is
      minted, commissioned or briefed.
- [ ] R2: in a fixture repository whose `CLAUDE.md` declares
      `## Test Change Acceptance: person`, an edited-test fix's counting check
      output is identical to the same fixture without the header, and
      `grep -rn "Test Change Acceptance" references/ scripts/ skills/` finds
      nothing.
- [ ] R3: `grep -rniE "overrul" skills/ references/ scripts/` finds no
      instruction or code for overruling a test-change acceptance (hits about
      `koto overrides` on gates are allowed).
- [ ] R4: the existing test cases for `init`, `classify`, `note`, `record` and
      red/green recording pass, with only cases for removed subcommands or
      removed record lines deleted, and none edited.
- [ ] R5: a ledger holding hand-written `seat`, `accept`, `decline` and
      `overrule` lines for an edited test leaves the counting check's result for that test the same as a ledger
      without the line.

### Judging tests and observations

- [ ] R6: a panel round over a diff with one edited test is refused when a
      panel seat omits a judgment for it, and a `weakens` from any seat records
      a blocking finding.
- [ ] R7: the code packet and the re-verifier packet for a diff with an edited
      test both carry the run's note for that test.
- [ ] R8: for a fix whose red was an observation, the panel packet carries both
      observations; a seat's `not shown` (whether the before observation lacks
      the failure or the after one still shows it) records a blocking finding.
- [ ] R9: a test judged by every seat at commit A and unchanged at head is not
      due; the same test changed at a later commit B is due; a test first edited
      after the round is due; with seat 1 judging at A and seat 2 at B, and the
      test unchanged since B, the test is not due (seat 2's judgment is at
      current content).
- [ ] R9: an observation pair judged at one digest and re-recorded with a new
      after digest is due.
- [ ] R10: with one due test and no other change, the next round of that panel
      plans a re-verifier whose packet lists the test with its hunks and note;
      recording its `corrects` makes the test not due; recording a judgment for
      a test not in the packet is refused.
- [ ] R10: with a due observation pair, the re-verifier packet lists the pair,
      and its `shown` makes the pair not due.
- [ ] R11: a re-verifier round recorded with no judgment for a due test leaves
      the test due and the counting check holding.

### Counting

- [ ] R12: at each of `pass_counting`, `pr_precheck` and `ci_pass_counting`, a
      unit with a due edited test makes the gate exit 1 and name the test; after
      a re-verifier records `corrects` at its current content, the same gate
      exits 0.
- [ ] R12: the `tests_counted` gate's command is byte-identical at
      `pass_counting` and `ci_pass_counting`, and
      `scripts/validate-template-mermaid.sh` passes on the template.
- [ ] R12: a unit whose test carries an open `weakens` stays held until the
      finding is closed or the test changes and is judged `corrects`.
- [ ] R12: a unit with a due observation pair, or one judged `not shown`, is
      held.
- [ ] R13: the check holds a unit with no ledger header, one with an
      uncommitted change to a tracked file, and one with an untracked file under
      a test path.
- [ ] R14: the check exits 2 when the work tree is gone, when the session can't
      be read, and when the stored classifier rules are missing; it exits 3 when
      it holds the unit and `panel-retry-budget.sh` reports the budget spent.
- [ ] R15: at `pass_counting`, submitting `declined` for a held unit moves the
      run to implementation; at `ci_pass_counting` it moves the run to
      `ci_monitor`; exit 3 moves the run to `done_blocked`.
- [ ] R16: a test edited after `pass_counting` makes `pr_precheck`'s gate hold,
      and `recount` returns the run to `pass_counting`.
- [ ] R17: an observation-based fix whose pair no panel judged fails
      `fix_green`; after a panel judges it `shown` at its current digests, it
      passes.
- [ ] R18: appending any line other than a header by hand to
      `test_change_ledger.jsonl` doesn't change the counting check's exit code or output.

### Late commits

- [ ] R19: a run held at `ci_pass_counting` that commits a test-only change
      reaches a re-verifier, and counting there runs again only after the
      re-verifier's judgment is recorded; a `weakens` from it sends the run back
      to `ci_monitor`.
- [ ] R19: a commit at `ci_pass_counting` that edits a test and a production
      file has the test judged and no panel round planned for the production
      file alone.
- [ ] R20: in a two-step plan, a CI fix `/execute` pushes from its monitoring
      state that edits a test is judged by a re-verifier recorded in the step's
      `/work-on` session; `/execute` doesn't mark the step passing while that
      run's counting check exits 1; a `weakens` keeps the step from passing.
- [ ] R20: a CI fix that edits no test passes through `/execute`'s monitoring
      state as it does today.
- [ ] R21: a re-verifier `weakens` on a late test adds one to the panel's
      retry count; once `panel-retry-budget.sh` reports the budget spent, the
      counting check exits 3 and the run ends at `done_blocked`.

### Outside writers

- [ ] R22: the directives for `scrutiny_verdict`, `review_verdict`,
      `qa_verdict` and `light_verdict` each name `koto overrides record` with
      `--by person:<handle>` and `--surface`; `skills/work-on/requires.tsv`
      declares `--by`, `--surface` and `--link`; an override recorded with
      `--surface relay --link <url>` shows the person and the link in
      `koto overrides list`.
- [ ] R23: `/review-plan <plan>` run while `plan-<topic>` is live leaves that
      session's keys unchanged (no `work/review.md`, no
      `work/review_loopback.md`, none removed) and says the `/plan` run owns
      it; run with the session finished, it writes its verdict as before.

### Documents and non-functional

- [ ] R24: `docs/prds/PRD-red-first-fixes.md` and
      `docs/designs/current/DESIGN-red-first-fixes.md` each carry a note naming
      the acceptance seat, the person path, the overrule and the interim
      acceptance rule as superseded by this PRD; `skills/work-on/references/red-first.md`
      names no seat and names the due rule and the re-verifier.
- [ ] R25: the work-on template's state list is identical to `main` before this
      change, and its edges differ only by edges whose source is
      `ci_pass_counting` and whose condition includes
      `counting_status: test_gap`.
- [ ] R26: no file outside `skills/work-on/` writes `test_change_ledger.jsonl`
      or runs a `test-change.sh` subcommand that writes it; a file outside
      `skills/work-on/` that reads the counting check (for R20) only reads.
- [ ] R27: an autonomous run with an edited test finishes counted without any
      directive asking for a person's input (no `AskUserQuestion`, no waiting
      state), and one whose re-verifier says `weakens` loops back
      (to implementation from `pass_counting`, to `ci_monitor` from
      `ci_pass_counting`) without prompting anyone.

## Out of Scope

- A coordinator's land step taking the worker's ledger panel round as the
  review. That's intended: the producer stands behind its own work, and the
  coordinator doesn't redo the worker's checks.
- Widening the freshness rule from tests and observations to every late
  commit. A production commit made during a CI fix still reaches the PR without
  a fresh panel look; that's separate work.
- Recording panel verdicts as typed koto decisions. The panels' verdict record
  already names the seat behind each judgment and is written by the run (see
  Decisions and Trade-offs).
- Changes to koto itself (owner checks, anchors, hooks, or a cross-session
  decision listing).
- Instructions outside shirabe that still describe the seat. Their owners
  update them once this lands.
- The same refusal for `/decision` run directly on a live `/design` session.
  It has the same shape as R19 but isn't part of this work.
- Migrating runs started before this lands beyond R5: a run mid-hold re-runs
  under the new check.
- What a pull request's body says. shirabe already keeps workflow records out
  of PRs, and this work doesn't change that.

## Known Limitations

- A late weakening after the panels spent their retry budget ends the run
  blocked sooner than the old per-path decline limit would have.
- The panels and the re-verifier run inside the producer's own workflow, so
  this work claims producer-side review, not independent certification. A
  repository that wants a check no agent on the host can forge gets it from the
  forge (a required review from a second account, or CODEOWNERS on test paths),
  outside shirabe.
- A person override names its decider as the run is told it, the way koto
  records any person decider; nothing authenticates the handle.

## Decisions and Trade-offs

- **Retire the seat rather than relay it.** The seat could have stayed, with
  the run recording its returned verdict. That keeps a weaker duplicate judge
  (test hunks only, one agent, no test runs) and most of the seat-brief bugs.
  The panels already make the judgment; what they lacked was a freshness rule
  and the two late routes, so this work adds those instead.
- **Drop the person-required path.** No repository declares it, and its
  terminal code and tag only guard against accidents. Keeping it as a person
  decision the run records would keep a claim rather than a check. A forge-side
  required review is the only person check an agent can't forge, and a
  repository can turn that on without shirabe.
- **Drop the coordinator overrule.** It has never been used, nothing reads it
  once a run is done, and keeping it as a reversal in the coordinator's own
  session would need typed decisions to target. Not merging, or reverting, the
  PR does the same job where it belongs.
- **No typed koto decisions for panel verdicts in this work.** The verdict
  record already attributes each judgment to its seat and is written by the
  run. With the overrule gone, nothing would read a typed verdict yet, and
  adding one is a second record for the gate to agree with. A later attribution
  feature can add them without changing the gate.
- **One retry budget.** A re-verifier `weakens` is a blocking finding under the
  panel retry budget, the same as a panel's. A second per-path limit would run
  beside it, and shirabe keeps one cap per step.
- **`/review-plan` refuses on a live `/plan`.** Writing its verdict makes
  `/plan` skip its own review and go to issue filing, and a loop-back removes
  `/plan`'s keys. `/plan` already runs `/review-plan` itself, so refusing, with
  an optional read-only review, loses nothing.
