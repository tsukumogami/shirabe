---
schema: plan/v1
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Incremental Value. Each issue removes one kind of per-run weight and is
  useful alone: the report measures runs, fix rounds stop repeating review
  and verification, the fixed stops go, acceptance runs once per head,
  experiments leave the default path, hosted CI becomes the build of record
  where it already runs the same check, the CI wait narrows, small diffs
  reach one reviewer, and plan steps stop queueing. Each ships with its own
  opt-out and its own before and after figure, so landing them separately
  is what lets a regression be traced to one change.
tracking_level: none
upstream: docs/designs/DESIGN-lighter-work-on-runs.md
milestone: "Lighter work-on runs"
issue_count: 11
---

# PLAN: Lighter work-on runs

## Status

Active

## Scope Summary

Cut the time a unit of work spends in `/work-on` and `/execute` without
losing a check that has caught a real defect: measure per-visit time by
diff size, stop fix rounds from repeating review and verification, remove
the stops whose answer never varies, take experiments off the default path,
let hosted CI be the build of record where it runs the same check, size
review to the change, and let independent plan steps run together. The
DESIGN is `docs/designs/DESIGN-lighter-work-on-runs.md`; the requirements
(R1 to R25) are in `docs/prds/PRD-lighter-work-on-runs.md`.

## Decomposition Strategy

**Horizontal, one issue per trim.** The trims touch different states and
scripts and share no runtime interface beyond the work-on template, so each
is its own pull request with its own opt-out, ordered by expected minutes
saved per run over the risk it accepts. Issue 1 comes first because every
later issue names the report figure it expects to move. Issues 2 to 5 lower
no review decision; issue 2 narrows what a fix round re-reviews and
re-verifies, the same way a retry lap already does. Issue 6 is a test that must exist
before issue 9 moves the compatibility file. Issues 7 and 8 change what a
run verifies and waits for. Issue 9 lowers review for small diffs and
carries the most risk among the work-on changes. Issues 10 and 11 touch
only `/execute`.

Expected savings are minutes per completed work-on run at the median,
estimated from observed per-state dwell on recent runs (review panels about
58 active minutes per run, verification and pass counting about 27,
`issue_type_routing` about 8, `review_level_choice` about 5,
`pre_pr_evidence` about 4, `ci_pass_counting` about 4) and from runs now
spanning two or three sessions where one used to do. Issue 1's report
replaces each estimate with a measured figure.

**Not trimmed, and why.** The scrutiny, review and QA panels stay at `full`
for ci, security, template and engine paths and for changes over 400 lines
or 12 files; nothing argues for moving those floors, and issue 1's report
will say if something later does. `review_level_check` and its facts floor
stay, since the floor is what keeps risky paths at `full`. `reproduce` and
the red-first rule stay: no recorded catch, but no other state checks that
a fix's test fails without the fix, and issue 1 counts its holds so a later
pass can judge it on data. Acceptance seats still mint at `pass_counting`.
Local verification stays for ci, security, template and engine changes and
wherever a command has no hosted twin. `ci_monitor` still waits for every
relevant check and the always-required list, and no red check reaches a
merge. The DESIGN's keep-or-cut table has the verdict and evidence for each
of the 24 states added since 0.19.1.

**koto dependencies.** None. Every issue is buildable on koto 0.37.
One optional follow-up for `tsukumogami/koto`, not filed by this PLAN and
not blocking anything: let a tick's routes see a variable rebound by the
same state's `default_action`. With it, issue 3's `kind_route` gate could go
and `fix_determination` could route on `UNIT_KIND` again.

## Issue Outlines

### Issue 1: feat(work-on): record gather history and add a size-normalized run report

**Goal**: Keep every review-level gather and print per-visit time by
template version and size band, so each later issue has a measured before
and after figure (R1 to R4).

**Acceptance Criteria**:
- [ ] `review-level.sh facts` appends one JSON line per gather to a
      `review_facts.jsonl` key with lines, files, classes, tests changed,
      tests edited, criteria changed, unclassified, floor, rules fired and
      head; a run with two gathers at different heads holds both.
- [ ] `run-report.sh` prints, per template version and size band (light
      cap, middle band, over the full floor), the median minutes per visit
      of `scrutiny`, `review`, `qa_validation`, `light_review`,
      `verification`, `pass_counting` and `ci_monitor`, seats spawned per
      run and sessions per run, with fix rounds joined to their parent.
- [ ] A run with no retained facts is listed as skipped by session count,
      not dropped.
- [ ] It reads only sessions of the repository it runs in, suppresses cells
      under 5 runs, and a test fails on any output field other than a number
      or a fixed label.
- [ ] It prints a seat analysis: for past runs within 200 lines and 5
      files, which seat raised each blocking finding.
- [ ] The first committed report splits the rise after 2026-10-28 and after
      2026-11-09 into a band-shift figure and a within-band figure, in
      minutes per run, summing to the observed rise.
- [ ] Given a ship date, it prints a named figure before and after; with
      fewer than 10 runs after, it prints "insufficient data".

**Dependencies**: None

**Type**: code
**Files**: `skills/work-on/scripts/review-level.sh`, `skills/work-on/scripts/run-report.sh`, `skills/work-on/scripts/run-report_test.sh`

**States and scripts touched**: `review_level_check`'s default action
(`review-level.sh facts`); new `run-report.sh`.
**Expected saving**: none directly; it is the measuring stick for issues 2
to 11.
**Check removed or kept**: none removed.
**Opt-out**: not needed; it only adds a key and a read-only script.

### Issue 2: feat(work-on): let a fix round inherit the parent run's verdicts and verification

**Goal**: A fix round after `done` reviews only its fix diff and verifies
only the commands its paths reach, the way a retry lap does (R5, R6).

**Acceptance Criteria**:
- [ ] `fix-round.sh start` copies the parent's `verdict_ledger.json` and
      its passed `verification_results.json` entries into the round,
      marked `carried_from`, only when the parent's head is an ancestor of
      the fix-round base and the merge-base is unchanged.
- [ ] A 30-line fix round whose parent passed every panel spawns only
      re-verifiers for findings the fix diff touches; a 200-line one still
      does; a 201-line one plans a full round.
- [ ] The round's review floor is the higher of the parent's last floor and
      its own.
- [ ] `run-verification.sh --base` selects commands from paths changed
      since the fix-round base, including the map's `default` commands when a
      round path matches no entry; `check-skill.sh --changed` diffs against
      `SHIRABE_VERIFY_BASE` when it is set.
- [ ] A fix round touching one file in one skill runs only that skill's
      command and reports the parent's result for the rest; a command the
      parent failed runs again; touching a second skill runs its command.
- [ ] `fix-round.sh start --fresh` starts with an empty ledger and full
      selection, as today.
- [ ] `skills/work-on/SKILL.md` ("A Fix Round After Done") describes the
      inherited verdicts, the narrowed selection, the floor rule and
      `--fresh`.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/scripts/fix-round.sh`, `skills/work-on/scripts/panel-scope.sh`, `skills/work-on/scripts/run-verification.sh`, `skills/work-on/scripts/check-verification.sh`, `scripts/check-skill.sh`, `skills/work-on/SKILL.md`

**States and scripts touched**: a fix round's `scrutiny`, `review`,
`qa_validation` and `verification` visits; `fix-round.sh`,
`panel-scope.sh`, `run-verification.sh`, `check-skill.sh`.
**Expected saving**: 30 to 50 minutes per run that takes a fix round (one
full panel round and one branch-wide verification), about 20 to 35
averaged over runs. Report figure: sessions per run and panel minutes per
fix round.
**Check removed or kept**: narrowed for fix rounds. Every panel still
reviews the fix diff, but seats that passed the parent's head aren't
respawned and suites the round can't reach aren't rerun.
**Opt-out**: `fix-round.sh start --fresh`.

### Issue 3: feat(work-on): remove the constant-answer stops

**Goal**: Remove or auto-advance the four stops whose answer never changes
the route (R15 to R18).

**Acceptance Criteria**:
- [ ] `review_level_choice` is gone; `review-level.sh init` runs at
      `analysis`'s exit with the merge-base rules copy, and
      `review_level_check` sets the level through `set-from-facts`; with a
      ceiling of `standard` and facts at `full` the run reviews at `full`
      and logs a breach, and with facts at or below the ceiling no breach
      is logged.
- [ ] The agent can still run `review-level.sh raise` from `analysis` on.
- [ ] `issue_type_routing`'s decider answers `code` live, in the template
      and in `scripts/decider-declarations.tsv`; a code run passes with no
      submission and a docs run still stops.
- [ ] `pre_pr_evidence` is gone; `finalization` accepts `cleanup_done` and
      `design_diagram` and routes to `pr_precheck`; a summary failing
      `summary_shape` still holds at `finalization`.
- [ ] `fix_determination` gains a `kind_route` gate (`fix-kind.sh kind
      --exit`) and leaves in the tick that entered it, to `reproduce` for a
      fix and `implementation` for a change; the "declare a fix" directive
      moves to `analysis`.
- [ ] The regenerated decider fixtures route a code run through
      `issue_type_routing` with no submission, and a compiled template has
      no `review_level_choice` or `pre_pr_evidence` state.
- [ ] `skills/work-on/SKILL.md` no longer tells the agent to choose a level
      up front or to answer at `pre_pr_evidence`, and says where to declare
      a fix and how to raise the level.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/scripts/review-level.sh`, `skills/work-on/scripts/fix-kind.sh`, `scripts/decider-declarations.tsv`, `skills/work-on/SKILL.md`

**States and scripts touched**: `review_level_choice` (removed),
`issue_type_routing`, `pre_pr_evidence` (removed), `finalization`,
`fix_determination`, `analysis`; `review-level.sh`, `fix-kind.sh`.
**Expected saving**: 10 to 19 minutes per run (`issue_type_routing` 3 to 8,
`review_level_choice` 2 to 5, `pre_pr_evidence` 4, the second tick at
`fix_determination` 1 to 2). Report figure: agent stops per run and
pre-implementation minutes.
**Check removed or kept**: `pre_pr_evidence`'s four gates removed as exact
copies of `finalization`'s; the facts floor and `kind_unchanged` kept.
**Opt-out**: `ISSUE_TYPE_DECIDER=shadow` for the routing decider; the two
state removals are exempt (R25) and revert with the change.

### Issue 4: feat(work-on): judge edited-test acceptance once per head

**Goal**: Mint acceptance seats only at `pass_counting`, and have later
states confirm the head instead of re-deciding (R7).

**Acceptance Criteria**:
- [ ] `test-change.sh status --confirm` passes when the recorded
      acceptance's head is the current head and holds otherwise, minting no
      seat.
- [ ] `pr_precheck`'s `tests_still_counted` and `ci_pass_counting`'s gate
      use `--confirm`.
- [ ] With no new revision after acceptance, both pass with no acceptance
      seat spawned; with one, both hold.
- [ ] `skills/work-on/references/red-first.md` documents the once-per-head
      rule and `TEST_ACCEPTANCE_RECHECK=full`.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/scripts/test-change.sh`, `skills/work-on/koto-templates/work-on.md`

**States and scripts touched**: `pass_counting`, `pr_precheck`,
`ci_pass_counting`; `test-change.sh`.
**Expected saving**: 3 to 5 minutes per run that edits a test. Report
figure: `pass_counting` plus `ci_pass_counting` minutes.
**Check removed or kept**: kept; the acceptance itself is unchanged and a
later commit still holds.
**Opt-out**: `TEST_ACCEPTANCE_RECHECK=full` restores the full re-check at
both states.

### Issue 5: feat(work-on): take the experiments and shadow grading off the default path

**Goal**: A run joins the offload canary, the rule-distance probe or
document-criteria grading only when its host opts in (R19, R20).

**Acceptance Criteria**:
- [ ] `OFFLOAD_CANARY` and `PROBE` default to `off`; `work-on-open.sh` binds
      either to `on` when `shirabe/offload-canary` or `shirabe/probe` under
      the user config directory has first line exactly `on`.
- [ ] With no opt-in file, a run enters none of the eight canary and probe
      states and runs no `probe_value_absent` gate; with the file at `on` it
      does; with `off`, `On` or an empty file it doesn't.
- [ ] `doc-criteria.sh grade` returns at once with no call unless
      `shirabe/doc-criteria` has first line `on`; with it, grading runs as
      today.
- [ ] `docs/guides/offload-live-canary.md`, `docs/guides/probe.md` and
      `docs/guides/review-shadow.md` say the default is off and show the
      opt-in file.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/scripts/work-on-open.sh`, `scripts/doc-criteria.sh`, `docs/guides/offload-live-canary.md`, `docs/guides/probe.md`, `docs/guides/review-shadow.md`

**States and scripts touched**: `offload_canary`, `offload_arm_withheld`,
`offload_arm_preloaded`, `probe_draw`, `probe_arm_near`, `probe_arm_far`,
`probe_arm_far_redeliver`, `probe_near`, and the `probe_value_absent` gates
on `pr_precheck`, `pr_creation` and `ci_monitor`; `work-on-open.sh`,
`doc-criteria.sh`.
**Expected saving**: seconds per work-on run on hosts not enrolled (state
passes and gate forks); up to 3 minutes per jury round in `/brief`, `/prd`,
`/design`, `/strategy` and `/roadmap`. Report figure: transitions per run.
**Check removed or kept**: no defect check removed; telemetry and
experiment arms now need an opt-in.
**Opt-out**: the opt-in files themselves.

### Issue 6: test(work-on): require every gate-digest script to be in the engine class

**Goal**: A test that fails when any script a template's gate digest
covers, or a library it sources or a script it runs, is missing from the
engine class (R12, first half).

**Acceptance Criteria**:
- [ ] `review-level-rules_engine_test.sh` reads each template's
      `gate_scripts` digest inputs, follows sourced libraries and executed
      script paths, and fails naming any path no `engine` row matches.
- [ ] Removing a covered script's `engine` row makes the test fail.
- [ ] Engine rows are added for every script the test finds missing
      (for coordinate today, `state-holding.sh`, `state-write-core.sh`,
      `state-common.sh`, `reconcile-check.sh`, `coord-log.sh`).
- [ ] The test's header states that run-time paths and data files are
      outside a static scan.

**Dependencies**: None

**Type**: code
**Files**: `skills/work-on/references/review-level-rules.tsv`, `skills/work-on/scripts/review-level-rules_engine_test.sh`

**States and scripts touched**: none at run time; the rules file and a new
test.
**Expected saving**: none; prerequisite for issue 9.
**Check removed or kept**: adds a check. Gate-library changes that only the
compatibility file kept at `full` now floor at `full` on their own.
**Opt-out**: not needed; it raises floors only.

### Issue 7: feat(work-on): use hosted CI as the build of record where every command has a twin

**Goal**: Run verification once per round: hosted CI when it runs every
selected command, local otherwise (R8).

**Acceptance Criteria**:
- [ ] `VERIFICATION` gains `auto`, the new default; `run-verification.sh
      plan` resolves it to `hosted-ci` when every selected command has a
      `hosted` twin in the merge-base map and no changed path is in the ci,
      security, template or engine class, and to `local` otherwise.
- [ ] A hosted resolution writes its own deferral reason, and the pull
      request body records hosted CI as the build of record.
- [ ] A failing hosted twin sends the run to `implementation`; a twin
      missing from the current default branch's map at `ci_monitor` sends it
      to local verification.
- [ ] A change with one selected command lacking a twin, or with a template
      path, runs local verification.
- [ ] A map test checks that each `hosted` entry names a job that runs on
      pull requests and runs the same command.
- [ ] The change fits the hosted-of-record route already in flight for
      timed-out checks and doesn't change its behaviour.
- [ ] In a fix round, "selected" means the commands issue 2's selection
      runs at the round's head; a carried result is not a selected command,
      so a round whose only selected command has a twin resolves to
      `hosted-ci` and its carried results stay as recorded.
- [ ] `skills/work-on/SKILL.md` ("Deferring Verification to Hosted CI") and
      `skills/work-on/references/verification-map.md` document `auto`, its
      resolution rule and `--verification=local`.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>

**Type**: code
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/scripts/run-verification.sh`, `skills/work-on/scripts/check-verification.sh`, `skills/work-on/references/verification-map.md`, `.claude/shirabe-extensions/verification-map.json`, `skills/work-on/SKILL.md`

**States and scripts touched**: `verification`, `verification_deferred`,
`pr_creation`'s deferral gate, `ci_monitor`; `run-verification.sh`,
`check-verification.sh`.
**Expected saving**: 15 to 25 minutes per qualifying run (the local
verification visit). Report figure: `verification` minutes per run.
**Check removed or kept**: kept as one run instead of two; local stays for
risky classes and untwinned commands.
**Opt-out**: `--verification=local`.

### Issue 8: feat(work-on): wait only on the checks the change can reach

**Goal**: `ci_monitor` waits on the selected commands' hosted twins and an
always-required list, not on every check (R9).

**Acceptance Criteria**:
- [ ] `pr-checks.sh --relevant <file>` filters by workflow and job; the run
      writes `relevant_checks.txt` from the merge-base map's twins and
      `always_required`, and re-reads both from the current default branch
      before the green edge.
- [ ] The filter is off in a repository whose map has no `always_required`
      key; shirabe's map ships one seeded with its security and lint checks.
- [ ] A run whose paths select no coordinate command reaches its green edge
      while a coordinate-only check is pending; a selected twin still
      pending holds it; an always-required check holds it until it passes.
- [ ] A failing check outside the set produces one pull request comment
      with only its name and URL, mentions and markup neutralised, and the
      run's final status names it; merge readiness still needs every check
      green.
- [ ] A skipped twin counts as not passed, and the relevant set is the union
      of the merge-base and current default-branch reads.
- [ ] `skills/work-on/references/verification-map.md` documents
      `always_required` and `CI_WAIT=all`.

**Dependencies**: Blocked by <<ISSUE:7>>

**Type**: code
**Files**: `skills/work-on/scripts/pr-checks.sh`, `skills/work-on/koto-templates/work-on.md`, `.claude/shirabe-extensions/verification-map.json`, `skills/work-on/references/verification-map.md`

**States and scripts touched**: `ci_monitor` (`ci_passing`); `pr-checks.sh`.
**Expected saving**: 10 to 25 minutes on runs whose paths don't reach a
slow suite (the coordinate suites take about 40 minutes). Report figure:
`ci_monitor` minutes per run.
**Check removed or kept**: kept for merging; an unrelated check stops
holding the run's own green edge.
**Opt-out**: `CI_WAIT=all`.

### Issue 9: feat(work-on): let small diffs reach the light review level

**Goal**: A small change outside the risky classes takes one reviewer, with
an escalate verdict and an audit that can reverse the cap (R10, R11, R12
second half, R13, R14).

**Acceptance Criteria**:
- [ ] A `cap` rule kind lowers a `standard` floor to `light` when no `full`
      rule fired, neither `criteria_changed` nor `unclassified` fired, and
      every path is in the row's classes; it never lowers `full`, and a
      `manifest` path keeps `standard`.
- [ ] First step: `cap light lines<=200 files<=5 classes=docs,test`. Second
      step: the classes widen to `docs,test,executable,instruction` only
      after issue 1's seat analysis shows under 10% of blocking findings
      within the cap came from seats the light panel lacks.
- [ ] After the second step: 37 lines in one script and its edited test
      gives `light`; 200 lines and 5 files gives `light`; 201 lines or 6
      files gives `standard`; changed criteria or an unclassified path gives
      `standard`; adding a template, ci, security or engine path gives
      `full`; 401 lines or 13 files gives `full`.
- [ ] Binary files, renames, mode changes and submodule bumps count as
      `unclassified`.
- [ ] `rule full red_test_edited` replaces `rule full tests_edited`; an
      edit to a fix's reproducing test after its red's revision floors at
      `full`, an ordinary edited test does not.
- [ ] With `*.compat.json` moved from the template class to `manifest`, a
      44-line change to three coordinate gate-library scripts plus the
      compatibility file floors at `full` through the engine class, and a
      change to the compatibility file alone floors at `standard`. A
      compatibility-file change in issue 7's class test resolves to `local`
      whenever the scripts it hashes changed, since those are engine paths.
- [ ] The light seat can return `escalate`, which records a raise and sends
      the run back to `review_level_check`; the next panel is `standard`.
- [ ] `review-level.sh audit` selects sessions whose name hashes to 0 mod
      10 (8% to 12% of 1,000 generated names, the same on every
      evaluation); an audited run goes on to `scrutiny`, `review` and
      `qa_validation`.
- [ ] `run-report.sh` derives misses from the verdict ledger, prints the
      over-bound line at 4 misses in 30 audited runs and not at 3, and
      trips at once on any security or correctness miss.
- [ ] A branch that edits `review-level-rules.tsv` to widen the cap is
      classified by the merge-base copy and floors at `full`; the regenerated
      decider fixtures classify the fixture diffs above as stated.
- [ ] `skills/work-on/references/review-levels.md` documents the cap, the
      two steps, `escalate`, the audit and its reversal, and
      `REVIEW_FLOOR=standard` as the opt-out.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:3>>, <<ISSUE:6>>

**Type**: code
**Files**: `skills/work-on/references/review-level-rules.tsv`, `skills/work-on/scripts/review-level.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/references/phases/phase-4d-light.md`, `skills/coordinate/scripts/review-round.sh`, `skills/work-on/scripts/run-report.sh`, `skills/work-on/references/review-levels.md`

**States and scripts touched**: `review_level_check`, `light_review`,
`scrutiny` (audited entry); `review-level.sh`, `review-round.sh`, the light
seat's prompt.
**Expected saving**: about 45 minutes per qualifying run (one seat instead
of seven); the first step qualifies few runs here, the second about a
quarter of runs, 10 to 12 minutes averaged, less the audited tenth. Report
figure: seats spawned and panel minutes per run in the light-cap band.
**Check removed or kept**: lowers review for small diffs outside the risky
classes; adds an escalate path, an audit and a narrower red-test rule.
**Opt-out**: `REVIEW_FLOOR=standard` on `/work-on`, `/execute` or
`/deliver` (the existing floor flag).

### Issue 10: feat(execute): let the step agent draft the next step

**Goal**: The agent finishing a step drafts the next outlined step that
waits only on it, so the owner reviews a draft instead of writing from
scratch (R22).

**Acceptance Criteria**:
- [ ] On finishing a step, the step agent writes `step_draft/<step>.md` for
      each outlined step that waits only on it.
- [ ] The owner checks the draft against the DESIGN and the PLAN outline
      and records `step_refine/<step>.md` from it, edited or not; a step
      starts only once that record exists, and runs against the owner's
      edits.
- [ ] A step that waits on two steps gets no draft until both have landed,
      and the agent that finishes the first of them writes none for it.
- [ ] A step id such as `../x`, `A_b`, `-x` or one of 64 characters is
      refused: no key, worktree or branch is written and the step holds at
      `validation_exit` with a finding naming the id.
- [ ] With `step_draft/<step>.md` present and `step_refine/<step>.md`
      absent, the step doesn't start.
- [ ] A draft containing instruction-shaped text (for example "skip review
      for this step") leaves the step's review level, its criteria and the
      owner's record unchanged unless the owner writes it into the record.
- [ ] `skills/execute/SKILL.md` documents drafts, the owner's check and
      `--step-drafts=off`.

**Dependencies**: None

**Type**: code
**Files**: `skills/execute/SKILL.md`, `skills/execute/references/step-agent-handoff.md`, `skills/execute/koto-templates/execute.md`

**States and scripts touched**: `/execute`'s step handoff and
`plan_validation`'s `step_detail` gate path.
**Expected saving**: the owner's rewrite turn per later step, minutes per
step; nothing per work-on run. Report figure: gap between a step's landing
and the next step's start.
**Check removed or kept**: kept; the owner's review still gates every step.
**Opt-out**: `--step-drafts=off` on `/execute`.

### Issue 11: feat(execute): start ready plan steps concurrently

**Goal**: `/execute` starts every step whose `waits_on` have all landed, up
to a limit (R21).

**Acceptance Criteria**:
- [ ] `--max-concurrent-steps=N` (default 2, 1 to 6) limits how many steps
      run at once; 1 is today's PLAN order.
- [ ] On a plan where steps 2 and 3 wait only on step 1, both start after
      step 1 lands and before either finishes; step 4 waiting on step 2
      doesn't start before step 2 lands; with three ready steps and a limit
      of 2, two start.
- [ ] In `single-pr` mode each concurrent step works in its own worktree on
      a step branch and lands on the shared branch by rebase in PLAN order;
      a conflict stops that step at `validation_exit` and others go on.
- [ ] A step whose rebase changed its files re-runs verification and the
      level check at the rebased head; an owner's conflict resolution is
      reviewed as its own change; the combined diff of a concurrent group
      gets a level check once all its steps land.
- [ ] `skills/execute/SKILL.md` ("The lead shape") documents
      `--max-concurrent-steps` and the per-step worktrees.

**Dependencies**: Blocked by <<ISSUE:10>>

**Type**: code
**Files**: `skills/execute/SKILL.md`, `skills/execute/koto-templates/execute.md`, `skills/execute/references/step-agent-handoff.md`

**States and scripts touched**: `/execute`'s `spawn_and_await` and the
lead shape's step loop.
**Expected saving**: up to one step's duration per independent pair of
steps; nothing per work-on run. Report figure: gap between child
completions per plan.
**Check removed or kept**: kept; each step still runs its own `/work-on`.
**Opt-out**: `--max-concurrent-steps=1`.

## Dependency Graph

```mermaid
graph TD
    I1["#1: run report"]
    I2["#2: fix-round inheritance"]
    I3["#3: constant-answer stops"]
    I4["#4: acceptance once per head"]
    I5["#5: experiments opt-in"]
    I6["#6: engine-class test"]
    I7["#7: hosted build of record"]
    I8["#8: relevant CI wait"]
    I9["#9: light cap"]
    I10["#10: step drafts"]
    I11["#11: concurrent steps"]
    I1 --> I2
    I1 --> I3
    I1 --> I4
    I1 --> I5
    I1 --> I7
    I2 --> I7
    I7 --> I8
    I3 --> I9
    I1 --> I9
    I6 --> I9
    I10 --> I11
```

## Implementation Sequence

**Critical path:** issue 1, then issue 9 (after issue 6), then issue 9's
second step once the report's seat analysis clears its bar.

**Order by saving over risk:** 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11. Issues 2
to 5 carry the least risk and deliver an estimated 35 to 60 minutes per run
between them, so most of the saving lands before review on small diffs is
lowered. Issues 4 and 5 save less than 7 and 8 but come first because they
accept no risk at all; 7 and 8 move defect discovery later.

**Parallel work:** issues 6 and 10 depend on nothing and can start at once,
alongside issue 1. After issue 1, issues 2, 3, 4 and 5 can run in
parallel; issues 3, 4, 5, 7, 8 and 9 all edit `work-on.md`, so they land one
at a time and rebase on each other. Issue 7 follows 1 and 2, issue 8 follows
7, issue 9 follows 1, 3 and 6, and issue 11 follows 10.
