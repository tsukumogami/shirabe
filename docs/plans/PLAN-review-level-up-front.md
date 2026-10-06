---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
upstream: docs/designs/DESIGN-review-level-up-front.md
milestone: "Review level up front"
issue_count: 4
---

# PLAN: Review level up front

## Status

Active

Authored at Active: the tracking level is `none` (no `## Tracking Level`
header), so activation files nothing on GitHub. The four items below are
outlines that `/execute` runs in one pull request.

## Scope Summary

Give `/work-on` a review level chosen before implementation, routed on by
koto, raised but never lowered by the facts of the change, bounded by a
coordinator through the brief, and recorded per run in a ledger a script
reads. Absorbs shirabe#521.

## Decomposition Strategy

Horizontal. The level script is a prerequisite for everything else and has a
stable interface (`review-level.sh` subcommands, the ledger key, the rules
file), so it lands first and is tested on its own against a koto stand-in
and a scratch real-koto session. The template wiring then calls it. The
bound plumbing sets variables the template declares, and the brief field
renders flags the plumbing accepts, so each later item depends on the one
before it.

The work lands as one pull request. The repository's Delivery Preference is
the default, `consolidated`, and no split branch fires: no item must reach
the default branch before another can run, and the bound items deliver
nothing a reader can use without the level machinery under them.

## Issue Outlines

### Issue 1: feat(work-on): add review-level.sh, its rules file and the level reference

**Goal**: Ship the one script that chooses, raises, lowers and reports a
run's review level, the rules data file it classifies changes with, and the
reference that defines the three levels, all usable before any template
calls them.

**Acceptance Criteria**:
- [ ] `skills/work-on/references/review-levels.md` defines `light` (one
      `light` panel seat), `standard` (scrutiny 3, review 3) and `full`
      (scrutiny 3, review 3, QA 1), the choose/raise/lower rules, the bound,
      and the ledger events, and points at the rules file.
- [ ] `skills/work-on/references/review-level-rules.tsv` holds the class
      patterns and rules the PRD lists as defaults (the rules file itself in
      the `security` class); the script refuses (exit 64) a file with an
      unknown record type, level or fact.
- [ ] `review-level.sh init <s> <floor> <ceiling>` appends one `bound` line,
      stores `review_level_bound.json`, `review_level_criteria.txt` and
      `review_level_rules.tsv`, and a second run writes nothing.
- [ ] `set` before `init` exits 1 with `refused: no bound recorded yet`.
- [ ] `set` from no level writes `choose` and rebinds `REVIEW_LEVEL` on a
      real koto scratch session built from a minimal template that declares
      the variable with the design's pattern; the variable and the ledger
      agree after every exit.
- [ ] Raise inside the bound with no reason: exit 0, `raise`. Raise above
      the ceiling: exit 1 without a reason, exit 0 with one plus a `breach`
      line. Raise to exactly the facts floor above the ceiling: exit 0 with
      no reason, `floor_raise` and `breach`. `--cause veto:<c>` writes `veto`.
- [ ] Lower without a reason exits 1 and changes nothing; with a reason
      exits 0 and stores it; below the facts floor or the bound floor exits
      1 even with a reason.
- [ ] A first choice outside the bound, and any choice under a bound whose
      floor is above its ceiling, exit 1 with a `refused:` line naming the
      values.
- [ ] A failed rebind exits 66 with no ledger line; a failed ledger write
      after a rebind rebinds back and exits 66 (koto stand-in).
- [ ] A `--reason` has control characters replaced and is cut to 200
      characters.
- [ ] `facts` on fixture commits records lines, files, classes (both sides
      of a rename), tests_changed and criteria_changed matching each fixture,
      with one fixture per class, one rename and one deletion; it uses the
      stored rules copy, so editing the rules file in the diff doesn't change
      the floor.
- [ ] For each threshold, a case at it does not fire and one over does; a
      `standard` and a `full` rule together give `full`; editing one
      threshold in a rules copy changes the floor and nothing else changes.
- [ ] `facts` appends a `check` line only when head, level or floor changed,
      and an `unset` line when the level is empty.
- [ ] `check` exits 0 at or above the floor; 1 with `hold:` naming the rule
      below it, when the level differs from the ledger, when outside the
      bound without a breach, or when the facts head isn't HEAD; 3 for an
      empty level.
- [ ] `slice` prints only counts, class names, booleans, the floor and a
      `level:` line; a test asserts no path, reason or criteria text
      appears.
- [ ] `report` prints a header and one row per session with the PRD's
      columns, for a full ledger, a named session, a session with no ledger
      (`none`) and a corrupt line (`corrupt`, exit 2 after all rows); `final`
      is the last check at or above its floor, `-` with none; tabs, newlines
      and control characters in any field are escaped.
- [ ] Every ledger line the tests write parses as JSON with a UTC ISO-8601
      `ts` and an `event` from the PRD's list.
- [ ] `review-level_test.sh` runs in `check-work-on-scripts.yml` and is
      listed in `scripts/check-bash-floor.sh`.

**Dependencies**: None

**Type**: code
**Files**: `skills/work-on/scripts/review-level.sh`, `skills/work-on/scripts/review-level_test.sh`, `skills/work-on/references/review-levels.md`, `skills/work-on/references/review-level-rules.tsv`

### Issue 2: feat(work-on): choose the review level after analysis and route the panels on it

**Goal**: Wire the level into `work-on.md` so every run records a level
before implementation, every code run passes a level check before its first
panel, and the panels it reaches are the ones its level names.

**Acceptance Criteria**:
- [ ] `work-on.md` declares `REVIEW_LEVEL` (rebind), `REVIEW_FLOOR` and
      `REVIEW_CEILING`, each optional with pattern
      `^(light|standard|full)?$`; `koto template compile` succeeds on koto
      0.15.0 and the repository's template checks pass.
- [ ] `analysis`'s `plan_ready` targets `review_level_choice`; a real-koto
      test submits `plan_ready` with no level and the run doesn't reach
      `implementation`; after `review-level.sh set <s> light --reason x` the
      next tick does.
- [ ] `issue_type_routing`'s code route targets `review_level_check`, whose
      action, `level_floor` gate, `level_fits_facts` decider check (one
      `veto` criterion, read by no route) and routes match the design.
- [ ] Real-koto tests with facts under every threshold: `light` enters
      `light_review` then `verification` and never `scrutiny`, `review` or
      `qa_validation`; `standard` reaches `verification` from `review`
      without `qa_validation`; `full` enters all three panels.
- [ ] A code run whose changed paths are only `.md` under `skills/`, at
      `standard`, never enters `qa_validation`.
- [ ] A `docs` run and a `task` run record a level and reach
      `verification` by today's routes.
- [ ] A `light` run below a `standard` floor holds before any panel with a
      message naming the rule; after a raise the next tick enters
      `scrutiny`, and the ledger holds `floor_raise` then a `check` at
      `standard`.
- [ ] After a blocking retry whose fix pushes changed lines past 40, the
      next level check holds a `light` run until it is raised.
- [ ] A hand rebind that leaves the variable differing from the ledger
      holds the level check, naming both levels.
- [ ] A session with the level unset at the check enters `scrutiny`,
      `review` and `qa_validation` and its ledger has an `unset` line.
- [ ] `panel-scope.sh` accepts the `light` panel with seat `reviewer`;
      `light_review` mirrors `review` with `has_commits` on its evidence
      `passed` route; a blocking `light` round returns to `implementation`
      and its seat is in the verdict ledger.
- [ ] Every retry clearing loop that removes the three panel results also
      removes `light_results.json`, and no clearing site names
      `review_level.jsonl` (both asserted by test).
- [ ] `phase-4d-light.md` holds the seat's commissioning line (Sonnet, a
      call budget, the `review-packet.sh code` packet) and prompt; the
      seat-commissioning check accepts it.
- [ ] `SKILL.md`, `review-panel-orchestration.md` and the review directive
      describe the levels; the lines shirabe#588 rewrites are not edited, and
      `git merge-tree` against that pull request's head reports no conflict.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/scripts/panel-scope.sh`, `skills/work-on/SKILL.md`, `skills/work-on/references/review-panel-orchestration.md`, `skills/work-on/references/phases/phase-4d-light.md`

### Issue 3: feat(execute, deliver): carry a review-level bound to every work-on run

**Goal**: Let `/work-on`, `/execute` and `/deliver` take
`--review-floor=<level>` and `--review-ceiling=<level>` and hand them down to
every `/work-on` run a unit starts.

**Acceptance Criteria**:
- [ ] `/work-on`'s direct init and `work-on-open.sh` pass the two flags as
      `REVIEW_FLOOR`/`REVIEW_CEILING`; a run started with
      `--review-floor=standard` has a `bound` line with that floor before its
      first `choose`; a value outside the three names is refused at init.
- [ ] `execute-open.sh` maps the flags; `execute.md` and
      `execute-coordinated.md` declare the variables; the spawn `jq` sets
      them on every child task's `vars` only when non-empty, shown by a test
      of the tasks it builds.
- [ ] `deliver-open.sh` maps the flags; `deliver.md` declares them and its
      `execute_run` directive appends them when non-empty, shown by a test of
      the rendered directive.
- [ ] Runs without the flags initialise exactly the variables they did
      before; `check-init-site-vars.sh` and the execute and deliver suites
      pass.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `skills/execute/scripts/execute-open.sh`, `skills/execute/koto-templates/execute.md`, `skills/execute/koto-templates/execute-coordinated.md`, `skills/deliver/scripts/deliver-open.sh`, `skills/deliver/koto-templates/deliver.md`, `skills/work-on/scripts/work-on-open.sh`

### Issue 4: feat(coordinate): a brief can bound the worker's review level

**Goal**: Give the coordinate brief an optional `review_level` field that
`render-brief.sh` checks and renders into the worker's brief and its
invocation, closing shirabe#521.

**Acceptance Criteria**:
- [ ] `render-brief.sh` with `review_level: {"ceiling": "standard"}` renders
      a line naming the ceiling in Acceptance criteria and
      `--review-ceiling=standard` in the invocation.
- [ ] Without `review_level`, its output is byte-identical to the output
      before this change for the same input.
- [ ] `{"floor": "full", "ceiling": "light"}`, a value outside the three
      names, or the field on an entry point that doesn't take the flags each
      exits 1 and writes nothing.
- [ ] `entry-points.tsv` admits `--review-floor=*` and `--review-ceiling=*`
      for `deliver`, `execute` and `work-on`; `brief-template.md` shows the
      line; `render-brief_test.sh` keeps the template and the rendered
      headings in step.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `skills/coordinate/scripts/render-brief.sh`, `skills/coordinate/references/brief-template.md`, `skills/coordinate/references/entry-points.tsv`

## Implementation Sequence

The critical path is all four items in order, I1 → I2 → I3 → I4. There is no
parallel work: each item uses an interface the one before it adds. I1 and I2
carry most of the risk (the rebind, the routes, the floor) and most of the
tests; I3 and I4 are plumbing with existing test harnesses to extend.
