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

skill-gate-suites runs four slices on Linux and on macOS bash 3.2, skill-gate needs them and runs the checks part, and a skipped job of record reads as not passed.

### Step 4: the rule-registry suites run in four slices with its long suite split into part files

check-rule-registry_test.sh runs as four part files across four slices on Linux and macOS bash 3.2, every case kept and none edited.

### Step 5: every job on a ready /coordinate pull request fits its time limit with no test file lost

/work-on's Linux suites run in two slices, the floor check's trigger gaps close, and Actions API timings and a before-and-after test-file inventory show the limits met and nothing missing.

## Implementation Sequence

The steps run in order. Steps 3 and 4 both need only step 2 and touch
different workflows, so either can go first; step 5 measures after both.
The plan's owner details step 3 after step 2's work reaches its terminal, and
each later step the same way, in a commit that touches only this plan.
