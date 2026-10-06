---
schema: prd/v1
status: Done
problem: |
  A /work-on run sizes its review from the issue type alone. Every code issue
  runs scrutiny, review and QA, seven seats per round, and any skill or koto
  template edit counts as code, so most of shirabe's own work takes the full
  path whatever its size. A coordinator can't bound a worker's panel, nothing
  checks a choice against the facts of the change, and no run records the
  level it ran at, so nobody can tell whether review spend matched risk.
goals: |
  Each /work-on run commits to a named review level early, the panels it
  spawns follow that level, objective facts about the change can raise the
  level but never lower it, a coordinator can bound it from the brief, and
  every choice, bound and veto lands in a per-run record a script can read.
source_issue: 591
motivating_context: |
  shirabe#595 cut the cost of each seat and shirabe#596 cut the seats a retry
  re-runs. The number of seats a change starts with is what's left, and
  shirabe#521 asked for the coordinator's side of the same lever. Live
  telemetry isn't capturing review spend, so the run's own record is the only
  measurement source the thresholds can be tuned from.
absorbed:
  - docs/briefs/BRIEF-review-level-up-front.md
---

# PRD: review-level-up-front

## Status

Done

R10 and R11 were amended after review of the implementing pull request,
before it merged: the facts diff from the larger of two bases, and the
default path classes and rules below replace the first list.

The completeness and clarity reviewers passed it on a second round, the
testability reviewer on the first.

Absorbed [BRIEF-review-level-up-front](docs/briefs/BRIEF-review-level-up-front.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists because review spend in `/work-on` follows the issue type
rather than the change: a one-line template fix gets the seven seats an
engine change gets, a coordinator who judges a unit low-risk has no way to say
so, and no run records the level it meant to run at. This document's Problem
Statement states that, with the three gaps behind it.

The outcome it asked for is a worker who spends a small review on a small
change, decided once and early; a light choice that the facts overrule before
any panel; a coordinator whose bound reaches the run; and a maintainer who can
tune thresholds from the record. Those are this document's Goals, and its four
journeys (the one-line fix, the overruled choice, the bounded unit, the
threshold tuning) are its User Stories, with the raise and the reasoned lower
split out as their own.

Its boundary kept the decider to raising only, added no koto primitive, left
seat models, packets, sticky verdicts and the retry cap as they are, kept
coordinate changes to the brief field, and left planned levels from `/plan`
and live telemetry to later work. Those are this document's Out of Scope.

## Problem Statement

`/work-on` decides how much review a change gets at one point: the
`issue_type_routing` state, where the agent answers code, docs or task. Code
runs all three panels (three scrutiny seats, three review seats, one QA
tester) on every round. The code answer's own description includes "a skill
or koto template that drives a workflow, even when every changed path ends in
.md", so in shirabe, where most changes are skills and templates, a one-line
directive fix gets the same seven seats as a rewrite of panel routing.

Three things are missing around that one question:

1. **No level.** Nothing between "skip the panels" (docs, task) and "run all
   seven seats" (code) exists, and nothing lets the run say which it intends
   before the panels start.
2. **No check on the choice.** The facts that say how risky a change is (its
   size, which paths it touched, whether it changed tests or acceptance
   criteria) are available after implementation, but no step reads them. A
   lighter path would need something that stops a light choice on a risky
   change.
3. **No coordinator lever and no record.** The coordinate brief has no field
   that bounds a worker's review, so a coordinator under a usage directive
   can't act on its own risk judgment (shirabe#521). And a run records
   spawns per round and granted retries, but not what level it meant to run
   at or why, so a threshold for "small enough to review lightly" can't be
   checked against outcomes.

## Goals

- A worker spends review in proportion to the change, decided once and
  early, not discovered through seven seats and their retries.
- A light choice on a risky change can't reach the panels unraised.
- A coordinator's risk judgment reaches the worker's run as a bound the run
  honours.
- Every run leaves a record of its level, bound and vetoes that a script can
  read across retained sessions, so the thresholds are tuned from data.

## User Stories

- As a worker running `/work-on` on a one-line directive fix, I want to
  record a light level with a reason before implementing, so that the change
  is reviewed by one bounded seat instead of seven.
- As a worker who picked a light level that the change outgrew, I want the
  run to stop me before the panels and tell me which rule requires more, so
  that I raise the level instead of shipping an under-reviewed change.
- As a worker who realises mid-run that the change is riskier than planned, I
  want to raise the level at any point inside my bound without justifying
  it, so that more review is never the expensive path.
- As a worker who planned too high, I want to lower the level only with a
  stated reason that the run keeps, so that a lowered level is always
  explainable afterwards.
- As a coordinator dispatching a low-risk documentation-and-scripts unit, I
  want to set a ceiling in the brief, and for a gate rewrite a floor, so that
  the worker's level lands where I judged it should, and I want to see in
  the record when the facts or the worker went above my ceiling.
- As a maintainer tuning the thresholds, I want one command that lists, per
  retained run, the level chosen, the level the panels last ran at, the
  bound, the raises, lowers and vetoes, and the seats spawned, so that I can
  see where the thresholds are wrong.

## Requirements

### Levels

- **R1. Named levels.** `/work-on` defines exactly three review levels, in
  increasing order: `light`, `standard`, `full`. One reference file defines
  each level by the panels it runs and the seat count of each:
  - `light`: one panel, `light`, of one seat. The seat gets the same
    script-assembled code packet the review panels get today
    (`scripts/review-packet.sh code`: the acceptance criteria, design
    context, changed paths and diff from `impl_base`), judges the
    change against the acceptance criteria, and returns the same verdict
    shape and the same definition of a blocking finding as a review-panel
    seat. No scrutiny, review or QA panel runs.
  - `standard`: the scrutiny panel (three seats), then the review panel
    (three seats). No QA.
  - `full`: scrutiny (three), review (three), then QA (one), as today.
- **R2. Level as a template variable.** The run's level is held in a
  `/work-on` template variable, and every route that differs by level is a
  koto `when` route on that variable's value. No new koto engine primitive
  is used.
- **R3. Chosen before implementation.** Every `/work-on` run, whatever its
  issue type, records a level before implementation: the run does not reach
  `implementation` until the level variable is set, and the
  directive asks for a level and a one-line reason. A `docs` or `task` run
  records one too; its route skips the panels as today, so the level only
  appears in its ledger.
- **R4. Panels follow the level.** A code-typed issue reaches exactly the
  panels its level names, in this order: `light` runs the `light` panel and
  then verification; `standard` runs scrutiny, then review, then
  verification; `full` runs scrutiny, review, QA, then verification. A
  blocking result from any panel, the `light` panel included, retries
  through implementation as today, under the same retry cap and with the
  same sticky-verdict and per-seat scoping (the `light` seat's verdict goes
  in the existing verdict ledger like any other seat's).
- **R5. Type no longer forces the full panel.** Being classified `code`
  because the changed paths are skills or koto templates no longer, by
  itself, sends a change through all three panels: a code issue's panels
  are decided by its level. The `docs` and `task` routes are unchanged.

### Recording a level

- **R6. One entry point.** A level is set, raised or lowered only through
  one script, `skills/work-on/scripts/review-level.sh`, which updates the
  level variable on the live session and appends to the ledger (R17) in
  the same call. Its result is observable: exit 0 when the change is
  recorded; exit 1 with a line starting `refused:` and naming the rule when
  it refuses, leaving the variable and the ledger unchanged; exit 64 on a
  usage error; exit 66 when the variable or the ledger write fails, after
  which neither has changed. The grammar is
  `review-level.sh set <session> <level> [--reason <text>] [--cause veto:<criterion>]`
  and `review-level.sh report [<session>...]` (R18). Because a variable can
  also be changed by hand with `koto init`, the level check (R12) holds
  whenever the variable differs from the last level the ledger records,
  naming both; a `set` to the level the run should be at clears it.
- **R7. Raising is free inside the bound.** A raise to a level at or below
  the coordinator ceiling (or with no ceiling) is accepted at any point with
  no reason. A raise above the ceiling is accepted only with a reason, and
  is recorded as a ceiling breach, unless it is a floor raise: a raise to
  exactly the current facts' floor (R12), which needs no reason anywhere.
- **R8. Lowering needs a reason.** Once a level is recorded, a lower level
  is accepted only with a non-empty reason, which the ledger keeps. A lower
  below the current facts' floor (R10) or below a coordinator floor is
  refused, with or without a reason.
- **R9. Coordinator bound.** A run can be given a floor, a ceiling, or both,
  each one of the three level names. The first choice must fall inside the
  bound, or it is refused. A bound whose floor is above its ceiling is
  refused at the first choice with a `refused:` line naming both values, and
  at brief input (R15).

### Facts and the veto

- **R10. Facts and the floor.** After implementation and before the first
  panel of a code-typed issue, on every lap, a script records the change's facts in the run's
  context and derives a minimum level, the floor, from them:
  - the diff is the larger of `impl_base..HEAD`, the commits the run made,
    and the diff from the merge-base with the default branch, so an
    `impl_base` recorded late can't shrink it; uncommitted work is not
    counted; a rename counts as one file plus its changed lines; a deletion
    counts its deleted lines;
  - changed lines (added plus deleted) and changed files;
  - which path classes the changed paths fall in, and whether any path
    falls in none;
  - whether a test file changed;
  - whether acceptance criteria changed: true when the diff touches a file
    under `docs/plans/` or `docs/prds/`, or when the acceptance-criteria
    text the review packet would carry differs from the copy `set` stored
    in the run's context at the first level choice. A run with no
    criteria text at either point compares as unchanged.
- **R11. Rules in one data file.** The path-class patterns and the
  thresholds live in one versioned data file in the repository; changing a
  threshold or a pattern is a change to that file and nothing else. The
  floor is the highest level any matching rule yields. The shipped defaults
  are:
  - path classes: `ci` is `.github/workflows/**` and `.github/actions/**`;
    `security` is `install.sh`, the rules data file itself, `**/hooks/**`,
    `.claude/**`, `**/settings*.json`, any path containing `credential`,
    `secret`, `token` or `password`, `.env`, `.env.*` and `*.pem`;
    `template` is `**/koto-templates/**`; `engine` is every script a koto
    template names in a gate's or a `default_action`'s command, plus every
    `*-open.sh`; `instruction` is `SKILL.md`, any path under a `references`
    directory, `CLAUDE.md` and `AGENTS.md`; `executable` is `**/scripts/**`,
    `scripts/**` and `crates/**`; `test` is `test/**`, `tests/**`, `spec/**`,
    `*.spec.*`, `*_test.*`, `test_*.*` and `**/evals/**`; `manifest` is
    `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`,
    `Cargo.toml`, `Cargo.lock`, `go.mod`, `go.sum`, `requirements*.txt`,
    `pyproject.toml`, `poetry.lock`, `Gemfile` and `Gemfile.lock`; `docs` is
    `*.md`, `docs/**`, `*.txt` and `LICENSE`;
  - `full` when any path is `ci`, `security`, `template` or `engine`, or
    changed lines exceed 400, or changed files exceed 12;
  - `standard` when any path is `instruction`, `executable`, `test` or
    `manifest`, or any path is in no class, or acceptance criteria changed,
    or changed lines exceed 40;
  - `light` otherwise: every changed path is documentation (`docs`, which
    no rule names) and no other rule fired.
- **R12. The floor only raises.** When the level is below the floor, the
  run doesn't reach any panel: the level check holds with a message naming
  the rule and the floor, until the level is raised to at least the floor.
  A level at or above the floor passes unchanged. No outcome lowers a level.
  A raise made to meet the floor is recorded as a floor raise naming the
  rule, and this applies above a coordinator ceiling too: the facts win, and
  the breach is recorded. The hold is a koto command gate, so koto's
  override record is the only way past it without a raise, and the reader
  (R18) reports each override.
- **R13. Veto-only decider check.** The level check state also declares a
  koto `decider-check` gate with one criterion in `veto` mode. Its command
  prints the recorded facts and the current level and nothing else. Its
  question asks whether the level is too light for the facts under the
  level definitions. No `when` clause or context assignment reads it. When
  koto reports it blocking, the directive tells the agent to raise the level
  through R6 naming the criterion, which the ledger records as a veto, or to
  record a koto override. Whether it runs, and with what effect, is koto's
  behaviour: it acts only for a user whose decider mode is `auto`, and in
  shadow or not at all otherwise. R12 applies either way.
- **R14. Re-checked on every lap.** A retry that returns through
  implementation re-records the facts and re-applies R12 and R13 before the
  next panel, so a fix that grows the change raises the level before more
  review runs, and the next round runs the raised level's panels.

### The coordinator bound

- **R15. Brief field and rendering.** The coordinate brief input accepts an
  optional `review_level` object with `floor`, `ceiling` or both, each one
  of the three level names. `render-brief.sh` refuses (exit 1) a value that
  isn't a level name or a floor above the ceiling. A brief with the field
  carries a line naming the bound, and the invocation it shows carries
  `--review-floor=<level>` and `--review-ceiling=<level>` for the values
  given. A brief without the field renders byte-identically to today.
- **R16. Flags carried to every run.** `/work-on`, `/execute` and
  `/deliver` accept `--review-floor=<level>` and `--review-ceiling=<level>`.
  `/deliver` passes them to `/execute`; `/execute` passes them to every
  `/work-on` child it starts; `/work-on` records the bound as template
  variables and in its ledger. koto refuses a value that isn't a level name
  at init.

### The ledger

- **R17. Per-run ledger.** Each `/work-on` run appends to a ledger in the
  koto context key `review_level.jsonl`, next to the existing verdict ledger
  and retry record. Each line is one JSON object with `ts` (UTC, ISO-8601),
  `event`, and the fields the event needs: `from`, `to`, `reason`, `rule`,
  `floor`, `ceiling`, `level`, `head`. The events are `bound` (the bound in force,
  or none), `choose`, `raise`, `lower`, `floor_raise`, `veto`, `breach`,
  `check` (the level and the facts' floor each time the level check runs,
  once per distinct head, level and floor) and `unset` (a level check reached with no level). Each level
  change writes exactly one of `choose`, `raise`, `lower`, `floor_raise`
  or `veto`, plus a `breach` line when it goes above the ceiling. Lines are
  only appended. No retry clearing step removes the key.
- **R18. A script reads it.** `review-level.sh report [<session>...]` prints
  one tab-separated line per `/work-on` session, after a header line, with
  the columns `session`, `chosen`, `final`, `floor`, `ceiling`, `raises`,
  `lowers`, `floor_raises`, `vetoes`, `breaches`, `overrides`, `seats`.
  `chosen` is the first `choose`; `final` is the level of the last `check` whose level is at or above its floor (the level the panels ran at),
  `-` when there is none (a docs or task run); each count column counts
  its own event only;
  `floor` and `ceiling` are the bound, `-` when absent; `seats` is the sum
  of the spawn counts in the verdict ledger's history; `overrides` counts
  koto overrides recorded on the level check's gates. With no session
  named it lists every session `koto workflows` reports from the work-on
  template. A session with no ledger is printed with `none` in `chosen`; a
  ledger line that isn't valid JSON makes that session's row read
  `corrupt` in `chosen` and the script exit 2 after printing every row.

### Compatibility

- **R19. Unset level means today's route.** If the level check is reached
  with the level variable unset (an override past R3, or a session started
  from an earlier template), a code issue goes through scrutiny, review and
  QA as today, and the ledger records `unset`.
- **R20. Existing panel machinery is kept.** Seat models, call budgets and
  packets (shirabe#595), sticky verdicts and per-seat scoping (shirabe#596),
  and the retry cap are used as they are. The only changes to the existing
  scrutiny, review and QA states and their phase files are the review
  panel's passed route (which now depends on the level) and the line that
  names the next state. Lines the progress-based retry cap (shirabe#588)
  rewrites are not edited.
- **R21. Tests and CI.** Every new or changed script has a `_test.sh`
  harness listed in the repository's script-check workflow and in the
  bash 3.2 floor list, and the template passes the existing template
  checks.

## Acceptance Criteria

Levels and routing

- [ ] The level reference defines `light`, `standard` and `full`, each with
      its panels and seat counts exactly as R1 states.
- [ ] `work-on.md` declares the level variable, the routes out of the level
      check and the review panel's passed routes are `when` clauses on its
      value, and `koto template compile` succeeds on koto 0.15.0.
- [ ] A real-koto test submits `plan_ready` at `analysis` with no level
      recorded and the session does not reach `implementation`; after
      `review-level.sh set <session> light --reason x` the next tick
      reaches `implementation`.
- [ ] Real-koto tests, one per level, with facts under every threshold:
      `light` enters `light` and then `verification` and never enters
      `scrutiny`, `review` or `qa_validation`; `standard` enters `scrutiny`
      and `review` and reaches `verification` without entering
      `qa_validation`; `full` enters all three.
- [ ] A run classified `code` whose changed paths are only `.md` files
      under `skills/`, at level `standard`, reaches `verification` without
      entering `qa_validation`.
- [ ] A run classified `docs` and one classified `task` reach
      `verification` by the same route as before this change, with a level
      recorded.
- [ ] A `light` round with a blocking verdict routes to `implementation`,
      records the seat in the verdict ledger, and on the next lap the seat
      is re-checked as the existing scoping rules say.
- [ ] A session whose level variable is unset at the level check enters
      `scrutiny`, `review` and `qa_validation`, and its ledger has an
      `unset` line.

Recording

- [ ] `set` from no level to any level with a reason exits 0; the variable
      reads the new level and the ledger ends with a `choose` line.
- [ ] A raise inside the bound with no reason exits 0 and adds a `raise`
      line; a raise above the ceiling with no reason exits 1 with a
      `refused:` line; with a reason it exits 0 and adds `raise` and
      `breach` lines.
- [ ] A lower with no reason exits 1 with a `refused:` line and the variable
      and ledger are unchanged; a lower with a reason exits 0 and the ledger
      line carries the reason.
- [ ] A lower below the facts' floor, and one below a coordinator floor,
      each exit 1 even with a reason.
- [ ] A first choice outside the bound exits 1; a bound of floor `full`,
      ceiling `light` makes the first choice exit 1 with a `refused:` line
      naming both.
- [ ] A level variable changed by hand with `koto init --attach-live`, so
      it differs from the ledger's last level, holds the level check with a
      message naming both levels.
- [ ] When the koto write of the variable or the ledger fails (a koto
      stand-in that fails it), the script exits 66 and a read-back shows
      neither changed.

Facts and floor

- [ ] Against fixture commits, the facts script records changed lines,
      changed files, each path class, tests-changed and criteria-changed
      matching the fixture, with one fixture per path class, one rename and
      one deletion.
- [ ] For each threshold in R11, a case at the threshold does not trigger
      its rule and a case one over does; a case matching a `standard` rule
      and a `full` rule yields `full`.
- [ ] Changing one threshold in the rules data file, and no other file,
      changes the floor a test case yields.
- [ ] A run at `light` whose floor is `standard` holds before any panel with
      a message naming the rule; after a raise to `standard` it proceeds;
      the ledger has a `floor_raise` line naming the rule, `light` and
      `standard`.
- [ ] With a ceiling of `light` and a floor of `full`, the raise to `full`
      exits 0 without a reason and the ledger has `floor_raise` and
      `breach` lines.
- [ ] Across every floor and level-check test case, no case leaves the level
      lower than it was before the check.
- [ ] After a blocking retry whose fix pushes changed lines past 40, the next
      level check holds a `light` run until it is raised to `standard`, and
      the next round enters `scrutiny`.
- [ ] The level check declares a `decider-check` gate with one criterion in
      `veto` mode; no `when` clause or context assignment names it; its
      command, run against a fixture session, prints exactly the facts
      record and the level line.
- [ ] `set` with `--cause veto:<criterion>` on a raise adds a `veto` line
      naming the criterion.

Bound plumbing

- [ ] `render-brief.sh` with `review_level: {"ceiling": "standard"}` renders
      a line naming the ceiling and `--review-ceiling=standard` in the
      invocation; with no `review_level`, its output is byte-identical to
      the output before this change for the same input; with
      `{"floor": "full", "ceiling": "light"}` or a level name outside the
      three, it exits 1 and writes nothing.
- [ ] `/deliver` opened with `--review-ceiling=light` passes it to the
      `/execute` invocation its directive shows; `/execute` opened with it
      initialises every `/work-on` child with the ceiling variable, shown by
      a test of the variables each child task carries.
- [ ] `/work-on` initialised with `--review-floor=standard` records a
      `bound` line with that floor before the first `choose`; a value that
      isn't a level name is refused at init.

Ledger and reader

- [ ] No retry clearing site in the shipped template or phase files names
      `review_level.jsonl` (a test greps every one).
- [ ] Every ledger line written by the tests above parses as JSON with a
      `ts` in UTC ISO-8601 and an `event` from R17.
- [ ] `report` prints a header and one row per session with the R18
      columns, for: a session with a full ledger, a named session, a session
      with no ledger (`none`), and a session with a corrupt line (`corrupt`,
      exit 2 after all rows).
- [ ] A session whose last passing check was at `standard` reports
      `final` as `standard` and `seats` equal to the verdict ledger's summed
      spawn counts.

Compatibility and CI

- [ ] `git merge-tree` of this work's final head against the head of
      shirabe#588 at the time the pull request is marked ready reports no
      conflict in any file.
- [ ] Every new script has a `_test.sh` listed in `check-work-on-scripts.yml`
      (or the coordinate equivalent) and in `scripts/check-bash-floor.sh`.
- [ ] Every CI job on each pull request concludes `success`.

## Out of Scope

- Moving any review seat, or the level choice itself, to the koto decider;
  the decider check only raises. Closed-criteria checks on the decider are
  shirabe#592.
- Testing the decider's own answers. Whether a `fail` blocks, and how an
  override clears it, are koto's guarantees and are tested in koto; this
  work tests its declaration and the slice it sends.
- Changing which model a seat runs on, its call budget, or what its packet
  holds.
- Any new koto engine feature, including routing on context keys or
  captures.
- The retry cap's rule and its record, which shirabe#588 governs.
- Choosing levels at planning time: `/plan` writing a level per issue and
  `/execute` passing it per child. The bound passes through `/execute`
  unchanged for every child; a per-issue planned level is later work.
- Coordinate changes beyond the brief field and its rendering, such as a
  coordinator reading ledgers to choose bounds.
- Live telemetry of the ledger; the retained sessions and the reader are
  the measurement source.
- Tuning the default thresholds from data; this work ships the defaults and
  the means to tune them.

## Decisions and Trade-offs

- **Three levels, not two or four.** `light` and `full` alone would leave the
  most common shirabe change, a template or script edit of moderate size,
  choosing between one seat and seven. A fourth level splitting QA from
  review would add a route without a case that needs it.
- **The facts' floor is deterministic; the decider check is extra.** koto
  runs a veto-mode check only for users whose decider mode is `auto`, so a
  guarantee that a risky change can't stay light can't rest on it. The
  script floor applies to every run; the decider check adds a judgment the
  rules can't express and, like the floor, can only raise.
- **Facts beat a coordinator ceiling; a worker can pass it with a reason.**
  A ceiling expresses a cost judgment made before the change existed. The
  floor expresses evidence about the change, and a worker who sees more
  risk than the coordinator did shouldn't be stopped from reviewing it.
  Both are recorded as breaches so the coordinator sees them.
- **Every issue type records a level.** Scoping the choice to code issues
  would need the type before implementation, and the type is asked after
  it. One line of choice on a docs run is cheaper than a second question.
- **The level lives in a rebindable template variable.** koto routes on a
  variable's value and lets a live session's rebindable variable change
  through `koto init --attach-live`, root or child (checked on koto 0.15.0
  with a scratch template); a capture or a context key can't be routed on
  without a new primitive.
- **Planned levels from `/plan` are out.** It would need a PLAN format field
  and per-issue `/execute` plumbing; the bound already gives a coordinator
  the per-unit lever shirabe#521 asked for.

## Known Limitations

- The decider check is inert for users who aren't opted in to `auto`
  decider mode; only the script floor protects them.
- The thresholds and path classes are starting values chosen from reading,
  not from data; the ledger exists to correct them.
- A `light` round is one seat, so it catches less than three; the floor
  rules keep it to small changes outside the risky path classes.
- A level change goes through a re-attach of the session, so a level can
  also be changed by hand with `koto init`. R6's comparison makes a hand
  change hold the run rather than pass silently, but it can't stop the
  change being made.
