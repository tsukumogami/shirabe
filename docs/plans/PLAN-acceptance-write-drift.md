---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-acceptance-write-drift.md
milestone: "Retire the test-change acceptance seat"
step_count: 7
---

# PLAN: acceptance-write-drift

## Status

Active

## Scope Summary

Retire `/work-on`'s test-change acceptance seat and make the review panels own
the judgment it gave. The panels record each judgment of an edited test or an
observation pair keyed by that item's content, the re-verifier judges every
item that changed since a panel last looked, and the counting gates
(`tests_counted`, `tests_still_counted`) read the panels' record through the
same `test-change.sh status` command they run today. The seat, the person path,
the coordinator overrule and the rule library go. Two late routes gain a
re-verifier (`ci_pass_counting`'s `test_gap`, and `/execute`'s test-touching CI
fixes as fix rounds), a person's panel-gate override is recorded by the run
naming the person, and `/review-plan` stops writing into a live `/plan`.

## Decomposition Strategy

Walking skeleton. Step 1 runs one edited test through the whole new path on a
fixture unit: a panel round records its content-keyed judgment, a later commit
changes the test, `--due-items` finds it due, the next round plans the
re-verifier with the test and its note, and the counting gate holds until the
re-verifier's `corrects` is recorded. Step 2 adds observation pairs to the same
path. Step 3 removes the seat machine and its documentation once nothing reads
it, and steps 4 to 7 add the late routes and the outside-writer fixes on top.

## Steps

### Step 1: a test edited after the panels looked is held until a re-verifier judges it

**Goal**: A `/work-on` unit's edited test crosses the whole new path on one
fixture run: a panel round records its judgment keyed by the test's blob, a
later commit changes the test, `panel-scope.sh --due-items` reports it due, the
next non-full round plans the re-verifier with that test and its note in the
packet, and the `tests_counted` gate (`test-change.sh status`) holds until the
re-verifier's `corrects` is recorded, then counts the unit. Covers PRD R6, R7,
R9 to R12 and R14 for edited tests.

**Acceptance Criteria**:

- [ ] On a fixture unit whose edited test every seat judged `corrects` at
  commit A, `panel-scope.sh --due-items <session>` exits 0 and prints nothing;
  after a commit B that changes the test, it exits 1 and prints the test's path
  with `due` and the panel name.
- [ ] With seat 1 judging at A and seat 2 at B and the test unchanged since B,
  `--due-items` exits 0 (one judgment at current content is enough).
- [ ] With the test due and no other change, `panel-scope.sh --plan <panel>`
  writes a scope whose only spawned decision is `reverifier` with reason
  `items-due` and the test in its due list, and `review-packet.sh recheck`
  for it prints a `## Test changes` section holding the test's hunks and the
  run's note, fenced and labeled as the run's claim.
- [ ] `--record` of that round with a re-verifier `test_edits` entry
  `corrects` for the test makes `--due-items` exit 0; a round file whose
  re-verifier entry omits the test, or judges a test not in its due list, is
  refused with exit 65 and leaves the test due.
- [ ] `test-change.sh status <session>` at the fixture's head exits 1 with a
  `held:` line naming the test and `due` while it is due, and exits 0 once the
  re-verifier's `corrects` is recorded; it exits 2 when the work tree is gone
  or the verdict record can't be read.
- [ ] A judgment whose `judged_at` is not an ancestor of HEAD, or whose run no
  round in the record planned, doesn't count.
- [ ] A test whose hunks the packet cut counts as judged only when the judging
  entry's `cited` list includes its path.

**Check**: On a fixture unit built by a new end-to-end case in
`skills/work-on/scripts/test-change-routes_test.sh` (a session, a work tree, an
edited test and its note), walk the path with the real scripts: record a panel
round with `panel-scope.sh --record`, change the test in a new commit, run
`test-change.sh status` and see exit 1 with `held: <test> due`, run
`panel-scope.sh --plan` and see a `reverifier` decision with reason
`items-due`, record the re-verifier's `corrects`, and run `test-change.sh
status` again to see exit 0. The case prints each step's exit code; the
existing cases in `panel-scope_test.sh` and `test-change_test.sh` still pass.

**Dependencies**: None

**Files**: `skills/work-on/scripts/panel-scope.sh`, `skills/work-on/scripts/panel-scope_test.sh`, `scripts/review-packet.sh`, `skills/work-on/scripts/test-change.sh`, `skills/work-on/scripts/test-change-routes_test.sh`

### Step 2: an observation pair is judged by the panels and counted from their record

**Goal**: A fix whose red was an observation gets its before and after
observations in front of every panel seat, each seat judges the pair `shown`
or `not shown`, a change to the pair makes it due for the re-verifier, and
`fix_green` and the counting gates count the pair from the panels' record
instead of from a seat acceptance. It builds on step 1: the pair is one more
item in `.judgments[<panel>]`, keyed by its two digests, `--due-items` reports
it as `observation`, and `test-change.sh status` and `covered` answer it from
there once a panel has recorded. Covers PRD R8, R10 and R17 and the
observation cases of R9 and R12.

**Acceptance Criteria**:

- [ ] For a fixture fix with a recorded observation pair, `review-packet.sh
  code` prints an `## Observations` section holding both observation texts
  and the report passage, fenced, labeled as the run's claim and capped at
  4 KiB each; a note or observation containing a line `## Diff` stays inside
  its fence.
- [ ] A panel round where a seat omits the pair's judgment is refused (exit
  65); a seat's `not_shown` records a blocking finding under rule
  `review/observation-not-shown`.
- [ ] After the pair is judged `shown` and the after-observation is then
  re-recorded, `panel-scope.sh --due-items` reports `observation` due, and a
  re-verifier `shown` clears it.
- [ ] `red-first.sh check-green <session>` (the `fix_green` gate) exits 1 for
  an observation-based fix whose pair no panel judged, naming the panels, and
  exits 0 once a panel has judged it `shown` at its current digests; no seat
  acceptance is involved.
- [ ] `test-change.sh status` holds a unit whose pair is due or carries an
  open `not shown` finding, with a `held:` line naming `observation`.

**Check**: Extend the end-to-end case from step 1 with an observation-based
fix: record the pair, record a panel round judging it `shown`, run
`red-first.sh check-green` and `test-change.sh status` and see both exit 0;
re-record the after-observation and see both exit 1 naming `observation`; record
a re-verifier `shown` and see both exit 0 again. `panel-scope_test.sh`,
`red-first_test.sh` and `test-change_test.sh` still pass.

**Dependencies**: Step 1

**Files**: `skills/work-on/scripts/panel-scope.sh`, `scripts/review-packet.sh`, `skills/work-on/scripts/red-first.sh`, `skills/work-on/scripts/test-change.sh`, `skills/work-on/scripts/test-change-routes_test.sh`, `references/rule-registry.json`

### Step 3: no acceptance line, seat, person or overrule can count or hold a unit

**Goal**: The counting gates and `fix_green` answer only from the panels'
record. The acceptance fallback steps 1 and 2 left (used while no panel had
recorded) goes, so an edited test or observation pair no panel has judged is
held as due rather than sent to a seat; `test-change.sh seat`, `accept`,
`decline` and `overrule`, the person-required path and its key and tag, the
seat brief and `scripts/lib/acceptance-rule.sh` are deleted; old acceptance
lines in a ledger are ignored; exit 3 means the panel retry budget is spent;
and every directive, reference, eval and document that described the seat
says what replaced it. Covers PRD R1 to R5, R13 to R15, R18, R24, R26 and R27.

**Acceptance Criteria**:

- [ ] `grep -rnE "test-change\.sh (seat|accept|decline|overrule)" skills/ references/ scripts/`
  finds nothing, `scripts/lib/acceptance-rule.sh` and its test don't exist,
  and `test-change.sh seat <session>` exits 64 naming an unknown subcommand.
- [ ] On a fixture unit with an edited test and no panel round recorded,
  `test-change.sh status` exits 1 with a `held:` line naming the test as due,
  and no line in its output tells the run to mint or commission a seat.
- [ ] A ledger holding hand-written `seat`, `accept`, `decline` and `overrule`
  lines for an edited test gives the same `status` exit code and output as the
  same ledger without them; `test-change.sh record` lists them as legacy
  history.
- [ ] With an edited test held as due and `panel-retry-budget.sh --remaining`
  reporting no retry left, `status` exits 3; with retries left it exits 1.
- [ ] A fixture repository whose `CLAUDE.md` declares
  `## Test Change Acceptance: person` gets the same `status` output as one
  without the header, and `grep -rn "Test Change Acceptance" references/ scripts/ skills/`
  finds nothing.
- [ ] The work-on template names no seat, person acceptance, overrule or
  decline limit in any directive, description or `failure_reason`, its
  `tests_counted` command is byte-identical at `pass_counting` and
  `ci_pass_counting`, and `scripts/validate-template-mermaid.sh` passes.
- [ ] `skills/work-on/references/red-first.md` names no seat and describes the
  due rule and the re-verifier; `docs/prds/PRD-red-first-fixes.md` and
  `docs/designs/current/DESIGN-red-first-fixes.md` each carry a note naming the
  acceptance seat, the person path, the overrule and the interim acceptance
  rule as superseded by `docs/prds/PRD-acceptance-write-drift.md`.
- [ ] No eval in `skills/work-on/evals/evals.json` asserts a seat is minted,
  commissioned or briefed, and `test-change/held` in
  `references/rule-registry.json` has fixtures that pass for the new holds.

**Check**: Run the work-on suites the CI workflow `check-work-on-scripts.yml`
runs, including `test-change_test.sh`, `test-change-routes_test.sh`,
`red-first_test.sh`, `output-gates-routing_test.sh` and
`scripts/rule-registry_test.sh`, and see them pass with the seat cases removed;
then run the greps in the criteria above and see each find nothing.

**Dependencies**: Step 2

**Files**: `skills/work-on/scripts/test-change.sh`, `scripts/lib/acceptance-rule.sh`, `skills/work-on/scripts/panel-retry-budget.sh`, `skills/work-on/scripts/red-first.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/SKILL.md`, `skills/work-on/references/red-first.md`, `references/rule-registry.json`, `skills/work-on/evals/evals.json`, `docs/prds/PRD-red-first-fixes.md`, `docs/designs/current/DESIGN-red-first-fixes.md`

### Step 4: a test fixed at ci_pass_counting goes back through the panels

**Goal**: A run held at `ci_pass_counting` on a due or adverse edited test (or
one that has found a gap in its own tests after CI) submits
`counting_status: test_gap` and returns to implementation, the route
`pass_counting` already has, so the next panel round's re-verifier judges the
changed test before verification, counting and CI run again on the open PR.
`declined` keeps its route to `ci_monitor` for a hold answered with a non-test
fix. This closes the unbounded loop step 3 left at `ci_pass_counting`
(shirabe#1931). Covers PRD R19, R21 and R25.

**Acceptance Criteria**:

- [ ] `ci_pass_counting` accepts `counting_status: test_gap`, with an edge to
  `implementation` when `tests_counted` exits 0 and one when it exits 1, and
  these are the only edges the template gains: its state list is unchanged and
  every new edge leaves `ci_pass_counting` on `test_gap`.
- [ ] A route test holds a fixture run at `ci_pass_counting` on a due test,
  submits `test_gap`, commits a test-only change, and sees the run pass a panel
  round whose only spawned decision is the re-verifier with that test in its
  due list, then reach `ci_pass_counting` again with `tests_counted` exiting 0
  once the re-verifier's `corrects` is recorded.
- [ ] The same route with the re-verifier's `weakens` adds one to the panel's
  retry count and sends the run back to implementation; once the budget is
  spent the counting check exits 3 and the run ends at `done_blocked`.
- [ ] The `ci_pass_counting` directive says when to submit `test_gap` and when
  `declined`, and the run reuses its open pull request on the way back through
  `pr_creation`.

**Check**: Run `bash skills/work-on/scripts/test-change-routes_test.sh` and see
the new `ci_pass_counting` `test_gap` case reach the re-verifier and count
again, and the `weakens` case end at `done_blocked` once the budget is spent;
`scripts/validate-template-mermaid.sh` passes on the template.

**Dependencies**: Step 3

**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/scripts/test-change-routes_test.sh`

### Step 5: a test-touching CI fix in /execute goes through a fix round

A CI fix /execute makes that edits a test is held by the ci_fix_tests_judged gate until a fix round of the step's own run has judged it.

### Step 6: a person's panel-gate override is recorded by the run naming the person

The four panel verdict gates' directives spell out koto overrides record with --by person and --surface, and the koto floor is 0.37.0.

### Step 7: /review-plan refuses to write into a live /plan session

Run directly while the plan session is live, /review-plan writes and removes no key and offers a read-only review.

## Implementation Sequence

The steps run in order in one pull request. Steps 6 and 7 depend only on the
skeleton and can run beside steps 2 to 5. Step 4 lands with step 3: without it,
a unit held at `ci_pass_counting` has no route to a re-verifier once the seat
is gone.
