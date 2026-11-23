---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-shirabe-ci-suite-split.md
milestone: "Shorter CI rounds through sliced suite lists"
step_count: 5
---

# PLAN: Shorter CI rounds through sliced suite lists

## Status

Active

## Scope Summary

Every long CI job on a shirabe pull request becomes a fail-fast-off matrix of
cost-balanced slices, chosen by one selector reading `SUITE_SLICE`. The skill
gate keeps its job of record, and the long rule-registry suite splits into
part files. No test is removed, skipped, weakened or retried, and no skill
prose, reference or koto template changes. Everything lands in one pull
request.

## Decomposition Strategy

Walking skeleton. Step 1 crosses the whole path once, on /coordinate's engine
suites (the longest list): a workflow matrix sets `SUITE_SLICE`, `run-tests.sh`
filters its glob through the new selector with /coordinate's cost rows, and the
matrix check guards the matrix. The later steps reuse that path for the floor
check and the offline and macOS floor lists, then the skill gate, then the
rule-registry suites. The last step closes the floor check's trigger gaps and
measures the time limits and the test-file inventory on a real pull request run.

Local checks only ever run targeted pieces (the selector's tests, the runners'
own tests on fixture lists, the workflow linters). The host is shared, so no
full suite list runs locally.

## Steps

### Step 1: /coordinate's engine suites run as four cost-balanced slices on a pull request

**Goal**: On a pull request, the `test-coordinate-engine` job of `check-coordinate-scripts.yml` runs as four parallel jobs, each running one cost-balanced quarter of /coordinate's engine suites, while a run with no slice set still runs every suite. This is the walking skeleton: it crosses workflow matrix, `SUITE_SLICE` environment, `skills/coordinate/scripts/run-tests.sh --engine`, the selector and the matrix check on the one real engine list.

**Acceptance Criteria**:

- [ ] With `SUITE_SLICE` unset or empty, `run-tests.sh --engine` selects the same suites in the same order as before and its closing count line carries no slice; for `i` = 1..4, listing the engine suites with `SUITE_SLICE=i/4` shows every engine suite in exactly one slice, and each slice's stderr says `suite-slice: slice i/4: k of N suites`.
- [ ] With `SUITE_SLICE_COSTS` pointing at /coordinate's `check-skill.tsv`, the heaviest slice's summed cost exceeds the lightest's by no more than the single costliest engine suite, and two runs over the same list print identical slices.
- [ ] Giving the selector an empty suite list exits 1 and names the runner, a malformed `SUITE_SLICE` (`5/4`, `0/4`, `x`, `1/17`) exits 2 naming the value, and a list shorter than `n` gives empty slices that exit 0 with `0 of N suites`.
- [ ] Running the matrix check against a workflow whose sliced job has `matrix.slice` other than `[1, ..., n]` for its `/<n>` (for example `[1, 2, 4]` with `/4`), `fail-fast` not `false`, or a `${{ matrix` inside a `run:` body exits non-zero and names the job; against the real tree it exits 0.
- [ ] On the pull request, four `test-coordinate-engine` jobs appear (slices 1 to 4), each prints a `run-tests: k of N suites (slice i/4)` line, none is skipped, and the four `k` values add up to the engine total.

**Check**: Locally, without running any full suite list (the host is shared and loaded), run `scripts/lib/suite-slice_test.sh` and `scripts/check-suite-slices_test.sh` and expect both to exit 0, then `bash scripts/check-suite-slices.sh` on the tree and expect exit 0. Then list the engine glob with `ls skills/coordinate/scripts/*_engine_test.sh` and, for i in 1 to 4, pipe it through `SUITE_SLICE=$i/4 SUITE_SLICE_COSTS=skills/coordinate/check-skill.tsv bash scripts/lib/suite-slice.sh`; concatenate the four outputs, sort them, and expect the result to equal the sorted full listing with no duplicates. Run the same pipe with `SUITE_SLICE` unset and expect the listing unchanged, and with empty input expect exit 1. On the pull request, open the four `test-coordinate-engine` jobs with `gh run view` and confirm each shows its `run-tests` count line with its slice and that the counts sum to the engine total on the base-commit run.

**Dependencies**: None

**Files**: `scripts/lib/suite-slice.sh`, `scripts/lib/suite-slice_test.sh`, `skills/coordinate/scripts/run-tests.sh`, `scripts/check-suite-slices.sh`, `scripts/check-suite-slices_test.sh`, `.github/workflows/check-coordinate-scripts.yml`, `.github/workflows/check-pr-workflow-content.yml`

### Step 2: the floor check runs one job per skill and four floor-koto /coordinate slices, and the offline and macOS floor lists slice the same way

**Goal**: On a pull request, the floor check shows five per-skill jobs plus four /coordinate engine slices instead of one 41-53 minute job, and every one of them still runs on exactly the floor koto release. The offline /coordinate suites, the macOS floor list, `run-suites.sh` and `check-bash-floor.sh` all honour `SUITE_SLICE=i/n` through the Step 1 selector, so a list's slices together run each suite once.

What Step 1 landed, for this step to build on: the selector is `scripts/lib/suite-slice.sh`. It reads costs only from a file named by `SUITE_SLICE_COSTS`, one row per suite as `cost<TAB><basename><TAB><secs>`. So this step writes a floor list's `cost:` lines out as those TSV rows, to a temp file or a process substitution, and adds no second cost input. `skills/coordinate/scripts/run-tests.sh` already filters through the selector and has `--list`. Locally the 48 engine suites split 13/12/12/11, about 711 cost-seconds per slice. `scripts/check-suite-slices.sh`, run by a Linux job in `check-pr-workflow-content.yml`, checks each sliced matrix's shape (fail-fast off, no exclude or include, no job-level `if:` or `continue-on-error`, `${{ matrix` in the run line) against a REQUIRED list of sliced jobs; every job this step slices goes on that list.

**Acceptance Criteria**:

- [ ] On a pull request, the floor check lists five leg jobs (shared, scope, execute, deliver, work-on) and four `entry-floor-coordinate` jobs (slices 1 to 4), and each job's log prints a koto version equal to the output of `assert-koto-floor.sh --print-floor`.
- [ ] The four `entry-floor-coordinate` logs together show every /coordinate engine suite once, and the four offline `test-coordinate-scripts` slice logs' count lines sum to the offline total, with the squash-message suite appearing only in slice 1.
- [ ] `SUITE_SLICE=2/4 scripts/run-suites.sh <four fixture suites>` runs only that slice's suites and its count line names the slice; with the variable unset it runs all four, as before.
- [ ] `SUITE_SLICE=2/4 scripts/check-bash-floor.sh` on a fixture list slices the list's harness lines and the child suites do not see `SUITE_SLICE`; on a list carrying `slice: pass` it runs every harness line and the children still see the variable. A `cost:` line changes which suite lands in which slice.
- [ ] A fixture run inside `run-suites_test.sh` and `check-bash-floor_test.sh` gives the same result when `SUITE_SLICE` is set to `2/4` in the environment that launches the test, because each test unsets it before running the runner on its fixtures.
- [ ] `koto-minimum-consistency_test.sh`, `check-macos-floor-legs.sh` and `check-macos-floor-setup.sh` pass on the changed workflows, with the push-only macOS leg still calling `scripts/check-bash-floor.sh --backend system coordinate` with a literal suite name.

**Check**: Run `bash scripts/run-suites_test.sh` and `bash scripts/check-bash-floor_test.sh` and see every case pass, including the new slice and ambient-variable cases; then run `SUITE_SLICE=3/4 bash scripts/run-suites_test.sh` and see the same pass result. Run `bash scripts/koto-minimum-consistency_test.sh`, `bash scripts/check-macos-floor-legs.sh` and `bash scripts/check-macos-floor-setup.sh` and see exit 0 from each. Never run the full suite lists locally; the host is shared. On the pull request, open the floor check's run, count five leg jobs and four `entry-floor-coordinate` jobs, compare each log's koto version line with `bash scripts/assert-koto-floor.sh --print-floor`, and add up the offline slices' `N of M suites` lines to confirm they equal the offline total.

**Dependencies**: Step 1

**Files**: `.github/workflows/check-koto-entry-floor.yml`, `.github/workflows/check-coordinate-scripts.yml`, `scripts/run-suites.sh`, `scripts/run-suites_test.sh`, `scripts/check-bash-floor.sh`, `scripts/check-bash-floor_test.sh`

### Step 3: the skill gate's suites run in four slices per platform while skill-gate (ubuntu-latest) stays the job of record

**Goal**: On a ready pull request, the skill gate's suite run (`check-skill.sh` step 4, about 42 minutes on Linux and 72 on macOS bash 3.2) is spread over four slice jobs per platform. The job `skill-gate`, its leg `skill-gate (ubuntu-latest)` and that leg's step `bash scripts/skill-gate.sh` keep the names, matrix and step strings the verification map declares, so the hosted job of record still means "check-skill passed for every touched skill". `check-skill-gate.yml` gains a job `skill-gate-suites`: matrix `os` (the same draft and push expressions as `skill-gate`) by `slice: [1, 2, 3, 4]`, `fail-fast: false`, the same checkout, tsuku, koto and base-commit steps as `skill-gate`, `SUITE_SLICE: ${{ matrix.slice }}/4` and `SKILL_GATE_PART: suites`, and the same two step strings (`bash scripts/skill-gate.sh` on Linux, `scripts/check-bash-floor.sh --backend system skill-gate` on macOS). `skill-gate` adds `needs: skill-gate-suites` and `SKILL_GATE_PART: checks`, and gains no `if: always()` or `continue-on-error`, so a failed slice leaves it skipped, which the verification route reads as not passed. `check-skill.sh` filters its step 4 suites through the selector and honours `SKILL_GATE_PART=suites|checks` (`suites`: only step 4's suites; `checks`: every other step, `script-cases --all` included), refusing any other value with exit 2. Unset, it runs both, as today. `skill-gate.sh` passes the part through. `check-skill.sh` sets `SUITE_SLICE_COSTS` to its skill's `check-skill.tsv` when it's unset.

What Steps 1 and 2 landed, for this step to build on: the selector is `scripts/lib/suite-slice.sh` (`SUITE_SLICE=i/n`, unset or empty means the full list; costs from `SUITE_SLICE_COSTS`, rows `cost<TAB><basename><TAB><secs>`; suite paths on stdout in the runner's order, the count line on stderr). `run-suites.sh` and `check-bash-floor.sh` already slice through it. Floor lists already accept `cost:` and `slice: pass` lines, and `skill-gate.list` can take `slice: pass` as is, so the macOS skill-gate leg's children keep `SUITE_SLICE` set and slice inside `check-skill.sh`. `scripts/check-suite-slices.sh` checks every sliced job named in its REQUIRED list; `skill-gate-suites` goes on that list, and the script also gains the skill gate's shape rules (`skill-gate` has `needs: skill-gate-suites`, and neither job has a job-level `if:` or `continue-on-error`). `check-macos-floor-setup.sh` was already edited in Step 2 so the slice variables don't fail its env comparison; it must also accept the `skill-gate` floor suite from two jobs whose setup steps are identical.

**Acceptance Criteria**:

- [ ] On a ready pull request touching `skills/coordinate/scripts/`, `check-skill-gate.yml` shows four `skill-gate-suites` jobs per platform and exactly one job named `skill-gate (ubuntu-latest)`, which runs `bash scripts/skill-gate.sh` and starts only after every slice finished
- [ ] The four Linux slice logs' count lines add up to the number of step 4 suites an unsliced `check-skill.sh` runs for the touched skill, with no suite in two slices; the same holds for the macOS slices
- [ ] `SKILL_GATE_PART=checks bash scripts/check-skill.sh <skill>` runs every step except step 4's suites, and `SKILL_GATE_PART=suites` runs only those suites; unset, both run; any other value exits 2 from both `check-skill.sh` and `skill-gate.sh`
- [ ] `verification-hosted-coverage_test.sh` and `eval-workflows_test.sh` pass with no edit, and `.claude/shirabe-extensions/verification-map.json` is unchanged
- [ ] A new case in `skills/work-on/scripts/verification-route.sh`'s test shows a skipped `skill-gate (ubuntu-latest)` does not count as passed
- [ ] `check-suite-slices.sh` lists `skill-gate-suites` and fails a fixture workflow where `skill-gate` lacks `needs: skill-gate-suites` or has a job-level `if:` or `continue-on-error`
- [ ] `check-macos-floor-legs.sh` and `check-macos-floor-setup.sh` pass on the changed workflow
- [ ] No test is removed, skipped or edited to assert less, and no retry is added

**Check**: Run `bash scripts/check-skill_test.sh`, `bash scripts/skill-gate_test.sh`, `bash scripts/check-suite-slices_test.sh`, the verification-route test, `bash scripts/verification-hosted-coverage_test.sh`, `bash scripts/eval-workflows_test.sh`, `bash scripts/check-macos-floor-legs.sh` and `bash scripts/check-macos-floor-setup.sh`, and see each pass. Confirm `git diff main... -- .claude/shirabe-extensions/verification-map.json` prints nothing. Don't run full suite lists locally; the host is shared. On the pull request, open the skill-gate run, count four slice jobs per platform and one `skill-gate (ubuntu-latest)`, and add up the slice count lines.

**Dependencies**: Step 2

**Files**: `.github/workflows/check-skill-gate.yml`, `scripts/check-skill.sh`, `scripts/check-skill_test.sh`, `scripts/skill-gate.sh`, `scripts/skill-gate_test.sh`, `scripts/check-suite-slices.sh`, `scripts/check-suite-slices_test.sh`, `scripts/bash-floor/skill-gate.list`, `scripts/check-macos-floor-setup.sh`, `skills/work-on/scripts/verification-route_test.sh`

### Step 4: the rule-registry suites run in four slices with its long suite split into part files

**Goal**: `test-rule-registry` stops being a 45-minute macOS job. Almost all of that time is one suite, `scripts/check-rule-registry_test.sh` (893 lines, about 43 minutes on bash 3.2). It's split into `scripts/check-rule-registry_1_test.sh` through `_4_test.sh` by case order: cases move without being edited, and each part file carries the setup its cases need. The job in `check-rule-registry.yml` gains `slice: [1, 2, 3, 4]` with `fail-fast: false` and `SUITE_SLICE: ${{ matrix.slice }}/4`, keeping its os expression, `paths`, concurrency group and step names. The Linux step, today four `bash scripts/<suite>` lines, becomes one `scripts/run-suites.sh` call over the suites in `scripts/bash-floor/rule-registry.list`. The macOS step keeps `scripts/check-bash-floor.sh --backend system rule-registry`, which slices the list's harness lines. The list names the four part files in place of the old suite, and carries `cost:` lines (first estimates, from the old suite's measured time over four plus the three short suites' times) so the selector puts one part file in each slice and the three short suites on the lightest ones. The workflow's `paths` name the four part files in place of the old suite. `check-rule-registry_test.sh` is removed only once all of its cases live in the parts.

What Steps 1 to 3 landed, for this step to build on: the selector is `scripts/lib/suite-slice.sh` (`SUITE_SLICE=i/n`; unset or empty means the full list; it fails closed on a malformed value or an empty slice). `scripts/run-suites.sh` and `scripts/check-bash-floor.sh` already slice through it and print the slice in their count lines. Floor lists accept `cost: <suite path> <seconds>` lines, matched on the suite's basename, and `check-bash-floor.sh` unsets `SUITE_SLICE` for the children of a sliced list. `scripts/check-suite-slices.sh` checks each sliced job on its REQUIRED list, and the sliced `test-rule-registry` job goes on that list. `check-macos-floor-legs.sh` and `check-macos-floor-setup.sh` check the macOS floor legs.

**Acceptance Criteria**:

- [ ] `scripts/check-rule-registry_1_test.sh` through `_4_test.sh` together hold every case `scripts/check-rule-registry_test.sh` held on main, each unedited, and the old file is gone. The sorted case names across the four parts equal the sorted case names in main's file, and the parts' pass counts add up to its pass count
- [ ] Each part file passes on its own (`bash scripts/check-rule-registry_<n>_test.sh`), with no state shared across the cut
- [ ] `scripts/bash-floor/rule-registry.list` names the four part files and has a `cost:` line for each of its suites; `SUITE_SLICE=<i>/4 scripts/run-suites.sh <list's suites>` puts each part file in a different slice, and the four slices' count lines add up to the list's suite count
- [ ] `check-rule-registry.yml`'s `pull_request` and `push` `paths` are a superset of main's with the old suite replaced by the four part files, and the job keeps its name, os expression and concurrency group
- [ ] `check-suite-slices.sh` lists the sliced rule-registry job and passes on the changed workflow; `check-macos-floor-legs.sh`, `check-macos-floor-setup.sh` and `check-bash-floor_test.sh` pass
- [ ] No case is removed, skipped or edited to assert less, and no retry is added

**Check**: Extract the case names from main's `scripts/check-rule-registry_test.sh` (`git show main:scripts/check-rule-registry_test.sh`) and from the four part files, sort both, and `diff` them; it prints nothing. Run each part file once and confirm the pass counts sum to the old suite's count from a main run's log (don't rerun the old 43-minute suite locally; the host is shared). Run `SUITE_SLICE=1/4` to `4/4` against the list's suites with `scripts/lib/suite-slice.sh` directly (not the full run) and confirm one part per slice. Run `bash scripts/check-suite-slices_test.sh`, `bash scripts/check-suite-slices.sh`, `bash scripts/check-macos-floor-legs.sh`, `bash scripts/check-macos-floor-setup.sh` and `bash scripts/check-bash-floor_test.sh`. On the pull request, the four `test-rule-registry` jobs per platform each finish in their limit.

**Dependencies**: Step 3

**Files**: `scripts/check-rule-registry_test.sh` (removed), `scripts/check-rule-registry_1_test.sh` to `_4_test.sh`, `scripts/bash-floor/rule-registry.list`, `.github/workflows/check-rule-registry.yml`, `scripts/check-suite-slices.sh`

### Step 5: every job on a ready /coordinate pull request fits its time limit with no test file lost

/work-on's Linux suites run in two slices, the floor check's trigger gaps close, and Actions API timings and a before-and-after test-file inventory show the limits met and nothing missing.

## Implementation Sequence

The steps run in order. Steps 3 and 4 both need only step 2 and touch
different workflows, so either can go first; step 5 measures after both.
The plan's owner details step 3 after step 2's work reaches its terminal, and
each later step the same way, in a commit that touches only this plan.
