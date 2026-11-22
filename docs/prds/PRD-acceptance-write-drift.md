---
schema: prd/v1
status: Draft
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

Draft

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
  the panels, and re-judged when it changes after a panel seat last looked,
  without minting, waiting on or relaying an acceptance seat.
- A late test edit, whether `/work-on` makes it while counting or `/execute`
  pushes it as a CI fix, reaches a re-verifier before the run counts it.
- A reader of a run's koto session finds only lines the run wrote, with any
  outside input named by its source.
- The PR still stands on its own for a reviewer who never opens koto.

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

## Requirements

### Retiring the seat

- **R1.** `/work-on` no longer mints, commissions or waits on an acceptance
  seat. The `seat`, `accept`, `decline` and `overrule` subcommands of
  `test-change.sh`, the seat brief, and the authority rules in
  `scripts/lib/acceptance-rule.sh` are removed, and no directive, reference or
  eval tells a run to use them.
- **R2.** The person-required path is removed: the `## Test Change Acceptance:`
  declaration is no longer read or documented as a convention, and nothing
  waits at a terminal or checks a terminal code or tag.
- **R3.** The coordinator overrule is removed. Nothing in shirabe writes, or
  tells a coordinator to write, a judgment into another run's session.
- **R4.** The producer-side pieces of red-first stay and behave as before:
  recording the red and the green, the ledger header (`init`), classifying the
  unit's test files, the run's notes on why it edited a test, the record a run
  reads back, and the test classifier.

### Judging tests and observations

- **R5.** Every edited test in the unit's diff is judged `corrects` or
  `weakens` by every real panel seat that runs, as today, and each `weakens` is
  a blocking finding.
- **R6.** The run's note on why it edited a test (R4) reaches the panel seats
  and the re-verifier that judge that test.
- **R7.** A fix's observations (the before and after pair) reach the panels,
  which judge whether the pair shows the reported failure and then its absence.
  A judgment that it doesn't is a blocking finding.
- **R8.** An edited test is **due** when its content at the run's head differs
  from its content at the commit where every panel seat that judged it last
  judged it, or when no panel seat has judged it. An observation is due on the
  same terms against its recorded content.
- **R9.** When the panels plan a round and any edited test or observation is
  due, a re-verifier judges each due item with the same verdicts R5 and R7 use,
  and the run records its judgments in the panels' verdict record alongside the
  seats'. A due item the re-verifier wasn't given can't be recorded as judged.

### Counting

- **R10.** At `pass_counting`, `pr_precheck` and `ci_pass_counting`, the gates
  that read `test-change.sh status` today (`tests_counted` and
  `tests_still_counted`) read a check that holds the unit while any edited test
  or observation is due, or is judged `weakens` (or not shown) at its current
  content and not since re-judged. The gates keep their names.
- **R11.** The check keeps today's other holds: a missing ledger header, and
  uncommitted tracked changes or untracked test files in the work tree.
- **R12.** The check's exit codes keep their meanings for counted (0), held (1)
  and can't decide (2). The design says what exit 3 and the `declined`
  evidence value mean once no seat declines, or shows they are unreachable.
- **R13.** A fix whose red was an observation reaches its green only once its
  observation pair has been judged at its current content and judged to show
  the failure and its absence.
- **R14.** A held unit is never counted by writing a line into the ledger: the
  only way past the hold is a panel or re-verifier judgment recorded by the run,
  or a change to the code or the test that removes the item.

### Late commits

- **R15.** A test edited at `ci_pass_counting` reaches a re-verifier before CI
  and counting run again (shirabe#1931).
- **R16.** A CI fix that `/execute` pushes from its monitoring state and that
  edits a test reaches the same judgment as a child run's own edit before the
  plan treats the step as passing (shirabe#1730).
- **R17.** A re-verifier `weakens` sends the run back the way a panel's
  blocking finding does and counts against the panel retry budget. No separate
  per-path decline limit exists.

### Outside writers

- **R18.** A person's override of a panel verdict gate is recorded by the run
  with the person named and the surface named (terminal, forge or relay, with a
  link for relay). The directives spell out that command for every panel verdict
  gate, and the skill's declared koto requirements include the flags it uses.
- **R19.** `/review-plan` run directly on a plan whose `/plan` session is live
  writes nothing into that session and removes nothing from it. It says the
  `/plan` run owns the session and runs its own review, and may review the plan
  read-only, printing its findings without persisting them.

### Documents

- **R20.** The red-first requirements and design are marked as superseded on
  the acceptance seat, the person path, the overrule and the interim rule, with
  a pointer to this PRD. The red-first reference describes what replaces them.

### Non-functional

- **R21.** `/work-on`'s states and edges are unchanged except where the design
  shows a route R15 or R16 needs.
- **R22.** No step in shirabe has a party other than the run write into the
  run's koto session for test-change acceptance.
- **R23.** An autonomous run never stops to wait for a person at a test-change
  hold.

## Acceptance Criteria

### Retiring the seat

- [ ] R1: `grep -rn "test-change.sh seat\|test-change.sh accept\|test-change.sh decline\|test-change.sh overrule" skills/ references/ scripts/`
      finds nothing, `scripts/lib/acceptance-rule.sh` doesn't exist, and
      `test-change.sh seat <session>` exits 64 as an unknown subcommand.
- [ ] R1: no eval in `skills/work-on/evals/evals.json` asserts a seat is
      minted, commissioned or briefed.
- [ ] R2: a repository whose `CLAUDE.md` declares
      `## Test Change Acceptance: person` runs an edited-test fix exactly as one
      without the header: no stop at a hold, no terminal prompt, and the
      convention is absent from `references/fixes/claude-md-conventions.md`.
- [ ] R3: no directive, reference or script in shirabe names an overrule of a
      test-change acceptance.
- [ ] R4: `test-change.sh init`, `classify`, `note`, `record` and the red and
      green recording pass their existing tests unchanged in behaviour, apart
      from the seat, accept, decline, refuse and overrule lines `record` no
      longer has.

### Judging tests and observations

- [ ] R5: a panel round over a diff with one edited test whose real seats omit
      a `corrects`/`weakens` judgment for it is refused, and a `weakens` from any
      seat records a blocking finding.
- [ ] R6: the code packet and the re-verifier packet for a diff with an edited
      test carry the run's note for that test.
- [ ] R7: for a fix whose red was an observation, the panel packet carries both
      observations, and a seat verdict that the pair doesn't show the failure
      records a blocking finding.
- [ ] R8: an edited test judged by every seat at commit A and unchanged at the
      head is not due; the same test changed in a later commit B is due; a test
      first edited after the round is due.
- [ ] R9: with one due test, the next panel round plans a re-verifier whose
      packet lists that test with its hunks; recording the re-verifier's
      `corrects` makes it not due; a round that records no judgment for it
      leaves it due.

### Counting

- [ ] R10: at each of `pass_counting`, `pr_precheck` and `ci_pass_counting`, a
      unit with a due edited test is held (exit 1) and names the test; once a
      re-verifier judges it `corrects` at its current content, the same gate
      exits 0.
- [ ] R10: a unit whose edited test was judged `weakens` at its current content
      is held until a later judgment at new content says `corrects`.
- [ ] R11: the check holds a unit with no ledger header, and one with an
      uncommitted change to a tracked file.
- [ ] R12: the check exits 2 when the work tree is gone or the session can't be
      read.
- [ ] R13: an observation-based fix whose pair no panel judged doesn't pass
      `fix_green`; after a panel judges it shown, it does.
- [ ] R14: appending any line by hand to `test_change_ledger.jsonl` doesn't
      change whether a held unit counts.

### Late commits

- [ ] R15: a run held at `ci_pass_counting` that commits a test-only change
      reaches a re-verifier, and counting at `ci_pass_counting` runs again only
      after that re-verifier records its judgment.
- [ ] R16: in a plan, a CI fix `/execute` pushes from its monitoring state that
      edits a test is judged by a re-verifier before `/execute` treats the step
      as passing; a `weakens` keeps the step from passing.
- [ ] R17: a re-verifier `weakens` routes the run back as a panel blocking
      finding does and adds to the panel's retry count; once that budget is
      spent the run ends blocked, and no third-decline rule exists.

### Outside writers

- [ ] R18: every panel verdict gate's directive names
      `koto overrides record` with `--by person:<handle>` and `--surface`, the
      skill's `requires.tsv` declares those flags, and an override recorded that
      way shows the person as the decider in `koto overrides list`.
- [ ] R19: `/review-plan <plan>` run while `plan-<topic>` is live leaves that
      session's keys unchanged (no `work/review.md`, no
      `work/review_loopback.md`, no key removed) and says the `/plan` run owns
      it.

### Documents and non-functional

- [ ] R20: `docs/prds/PRD-red-first-fixes.md` and
      `docs/designs/current/DESIGN-red-first-fixes.md` carry a note naming the
      superseded parts and this PRD, and `skills/work-on/references/red-first.md`
      names no seat.
- [ ] R21: the work-on template's states and edges match `main` before this
      change, except for edges the design names for R15 or R16.
- [ ] R22: no shirabe script or directive writes into a `/work-on` session
      other than as that run.
- [ ] R23: an autonomous run with an edited test finishes counted with no stop
      for a person.

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
- Migrating runs started before this lands; a run mid-hold re-runs under the
  new check.

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
