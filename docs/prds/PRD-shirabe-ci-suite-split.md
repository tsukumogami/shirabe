---
schema: prd/v1
status: Accepted
problem: |
  A CI round on a shirabe pull request takes 40-75 minutes, against 2-3
  minutes in September 2026, because a few jobs run long suite lists one
  after another on a single runner. Every fix-and-push round waits for the
  slowest of them, so contributors and agents spend most of a review cycle
  waiting.
goals: |
  Bring every job on a pull request within 15 minutes on Linux and 25 on
  macOS by running independent suites side by side, while every test that
  runs today still runs on the same koto releases, bash versions and
  operating systems, and the checks the rulesets require keep reporting.
absorbed:
  - docs/briefs/BRIEF-shirabe-ci-suite-split.md
---

# PRD: Shorter CI rounds for shirabe pull requests

## Status

Accepted

Absorbed [BRIEF-shirabe-ci-suite-split](docs/briefs/BRIEF-shirabe-ci-suite-split.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so that someone pushing a fix to a shirabe pull request
learns whether it passed in minutes rather than close to an hour. A round
that took 2-3 minutes in September 2026 takes 40-75 by late November, and
the cause is that a few jobs run long, independent suite lists one after
another on one runner, not that the jobs trigger too often. The outcome is a
round bounded by the slowest slice of work, with the same tests on the same
koto releases, bash versions and operating systems, and with every failure
still named.

Four users exercise it: a contributor changing one /coordinate script, a
contributor changing a shared script that many suites call, an author
marking a draft ready (which starts the macOS bash 3.2 legs), and a
maintainer reading a red check. The boundary holds every guarantee the jobs
give today. Nothing is removed, skipped, weakened or retried, no skill prose
or template changes, the macOS legs stay on pull requests, the floor check
keeps its release, and the checks the rulesets require keep their names.

## Problem Statement

A shirabe pull request's CI round is as long as its slowest job, and the
slowest jobs grew from a few minutes in September 2026 to most of an hour by
late November. Each runs a long list of test suites on a single runner.

Measured on pull request runs from 2026-11-23:

| Job | Workflow | Minutes | Where the time goes |
|-----|----------|---------|---------------------|
| `entry-floor` | `check-koto-entry-floor.yml` | 41-53 | about 44 in /coordinate's engine suites; /scope, /execute, /deliver and /work-on together about 9 |
| `test-coordinate-engine` | `check-coordinate-scripts.yml` | about 41 | 47 engine suites, one at a time |
| `test-coordinate-scripts (ubuntu-latest)` | `check-coordinate-scripts.yml` | about 35 | 80 offline suites, one at a time |
| `skill-gate (macos-latest)` | `check-skill-gate.yml` | about 72 | every /coordinate suite on bash 3.2, on a ready pull request that touches /coordinate |
| `skill-gate (ubuntu-latest)` | `check-skill-gate.yml` | about 42 | every /coordinate suite, four at a time |
| `test-rule-registry (macos-latest)` | `check-rule-registry.yml` | about 45 | its suites on bash 3.2 |
| `test-execute-scripts`, `test-work-on-scripts` | their workflows | 14-20 | sequential steps, longer on macOS |

Path filters are not the main cause. entry-floor and the coordinate workflow
already trigger only on the skills and shared scripts they test. The cost is
that suites which are independent of each other run in sequence. The
guarantees these jobs give have to survive: entry-floor proves every
koto-backed skill works on the oldest koto release shirabe supports, the
macOS legs prove the scripts run on bash 3.2 with BSD tools, and a change to
a shared script runs every suite that depends on it.

## Goals

Someone pushing to a shirabe pull request gets every check's result within
the limits R8 sets (15 minutes per Linux job, 25 per macOS job, against
35-72 for the slowest jobs today and a 40-75 minute round). The round is bounded by the slowest slice of a suite list,
and the same tests run on the same koto releases, bash versions and
operating systems as before. A red check names the slice and the suite that
failed, and merging works as it does today.

## User Stories

- As a contributor changing one /coordinate script, I want the floor-koto,
  newest-koto and bash 3.2 runs of coordinate's suites to finish in
  parallel slices, so that no job on my pull request runs past the R8
  limits instead of the 35-53 minutes those runs take today.
- As a contributor changing a shared script such as `scripts/lib/` or
  `scripts/koto-open.sh`, I want every suite that depends on it to keep
  running, so that a faster round never means a narrower one.
- As an author marking a draft ready, I want the macOS bash 3.2 legs to run
  every case they run today and each finish within 25 minutes, instead of
  the 45-72 they take today.
- As a maintainer reading a red check, I want the failing slice and the
  suite inside it named, and a re-run of that job to rerun exactly the
  suites its slice holds.

## Requirements

### Functional

- **R1. Floor jobs per skill.** The floor check runs the koto-backed suites
  of /scope, /execute, /deliver, /work-on and /coordinate in separate
  parallel jobs instead of one. Every job of the floor check installs the
  release `scripts/assert-koto-floor.sh --print-floor` prints and fails
  unless `koto version` reports exactly that release. The template compile,
  the decider check, the suite-runner check and the shared entry and
  preflight suites run in one of those jobs.
- **R2. Coordinate suites in slices.** /coordinate's engine suites and its
  offline suites each run as parallel slices in its own workflow, and its
  engine suites (the only /coordinate list the floor check runs) run as
  parallel slices in the floor check. The number of slices per list is the design's choice, at
  least two, and enough to meet R8.
- **R3. Deterministic, cost-balanced slicing.** The slice selector derives
  the full list the same way the unsliced runner does (the suite files on
  disk), orders it independent of locale and operating system, and assigns
  suites using the per-suite cost rows the skill keeps in its
  `check-skill.tsv`. A suite with no cost row is still assigned to exactly
  one slice, using a default cost. No slice's total cost exceeds the
  lightest slice's by more than the cost of the single largest suite.
- **R4. Slice completeness.** For every sliced list, the union of the slices
  equals the unsliced list and no suite falls in two slices. A slice count
  larger than the list leaves the extra slices empty, and an empty slice
  passes, saying it ran zero suites. A check that runs in CI fails when the
  slices of a list do not cover it exactly.
- **R5. Same failure rules in every slice.** Each slice applies the unsliced
  runner's rules: a non-zero exit fails it, a `SKIP` line in a suite's output
  fails it, and output containing `command not found` fails it. Each slice
  prints its slice number, the slice count, how many suites of the list
  total it ran, and the name of every suite that failed.
- **R6. Full run stays the default.** Every runner given no slice argument
  runs its full list exactly as today, so local runs and
  `scripts/check-skill.sh --changed <skill>` are unchanged.
- **R7. Slices finish independently.** A failing slice does not cancel its
  sibling slices, and every slice reports its own result. Each job's name
  says which list and which slice it runs.
- **R8a. Skill gate within the limits.** On a ready pull request touching
  `skills/coordinate/scripts/`, every skill-gate job meets the R8 limits.
  The skill gate keeps running every check it runs today for each touched
  skill, on Linux and on macOS bash 3.2. The job `skill-gate`, its leg
  `skill-gate (ubuntu-latest)` and that leg's step `bash
  scripts/skill-gate.sh` stay as the repository's verification map declares
  them, and the tests that read that map and the workflow
  (`verification-hosted-coverage_test.sh`, `eval-workflows_test.sh`) pass
  unchanged.
- **R9. Other long jobs.** `test-rule-registry`, `test-execute-scripts` and
  `test-work-on-scripts` meet the R8 limits on a ready pull request that
  triggers them, split by the same slice selector or into separate jobs. A
  suite whose own runtime exceeds a limit is split by its cases, as
  `coordinate_1..4_engine_test.sh` already are, or named in the pull
  request description as an exception to R8 together with its measured
  runtime.
- **R10. Triggers stay at least as wide.** Every split job's pull-request
  and push paths include every path its unsplit job lists today, so a change
  to a shared script (`scripts/lib/**`, `scripts/koto-open.sh`,
  `scripts/skill-preflight.sh`) still starts every dependent suite. No suite
  moves to a narrower trigger.
- **R11. Workflow-level behaviour kept.** Every split workflow keeps its
  concurrency group, its draft and push matrices for macOS, and its place in
  the list `scripts/check-macos-floor-setup.sh --workflows` gives the
  closed-pull-request cancellation workflow.

### Non-functional

- **R8. Time limits.** Per job, from the job's `started_at` to its
  `completed_at` in the Actions API (queue time excluded): every Linux job
  15 minutes or less, every macOS job 25 minutes or less, on a ready pull
  request that touches `skills/coordinate/scripts/` and `scripts/lib/`.
- **R12. No coverage lost.** Every test file that ran on a pull request,
  draft or ready, or on a push to main, on a given platform and koto release
  before the change still runs in that same case after it. No test is
  removed, skipped or edited to assert less, and no retry is added.
- **R13. Required checks unchanged.** The checks the rulesets require
  (`pr-body / pr-body`, `check-skill-requires`) keep their names and
  triggers.
- **R14. Repository checks unchanged.** The workflow linters pass with no
  edit to the rules they enforce: `scripts/check-macos-floor-legs.sh`,
  `scripts/check-macos-floor-setup.sh`, `scripts/check-bash-floor_test.sh`,
  `scripts/koto-minimum-consistency_test.sh`, `scripts/eval-workflows_test.sh`
  and `verification-hosted-coverage_test.sh`. New suite lists or registry
  entries they read are allowed.

## Acceptance Criteria

- [ ] The floor check's run on the pull request shows one job each for
      /scope, /execute, /deliver and /work-on and one per /coordinate engine
      slice, and each job's log shows `koto version` equal to the output of
      `scripts/assert-koto-floor.sh --print-floor`. (R1)
- [ ] A floor job's log shows the template compile, the decider check and
      the shared entry and preflight suites. (R1)
- [ ] /coordinate's engine and offline lists each run as at least two jobs
      in `check-coordinate-scripts.yml`, and the engine list as at least two
      jobs in the floor check. (R2)
- [ ] Running the selector for every slice of one list twice, once under
      `LC_ALL=C` and once under another installed locale, prints identical
      slice contents. (R3)
- [ ] The selector's own test shows, for each sliced list, that the
      heaviest slice's cost minus the lightest's is no more than the largest
      single suite's cost, and that a suite with no cost row lands in
      exactly one slice. (R3)
- [ ] The completeness check passes on the change and, in its own test
      cases, fails for a list with one suite dropped from every slice and
      for one with a suite in two slices. (R4)
- [ ] A test case slicing a two-suite list into three slices shows one slice
      reporting zero suites and passing. (R4)
- [ ] The runner's test cases show a slice failing for a suite that exits
      non-zero, one that prints `SKIP`, and one whose output contains
      `command not found`, and the slice's output names each failing suite.
      (R5)
- [ ] Each slice's log prints its slice number, slice count and suite count,
      and the suite counts across one list's slices add up to the unsliced
      count. (R4, R5)
- [ ] `run-tests.sh`, `run-suites.sh` and `check-skill.sh` given no slice
      argument run the same number of suites as before the change. (R6)
- [ ] Every sliced matrix sets `fail-fast: false`, and each sliced job's
      name contains its list and slice. (R7)
- [ ] On a ready pull request touching `skills/coordinate/scripts/` and
      `scripts/lib/`, the Actions API shows every job of every triggered
      workflow, `test-rule-registry` included, within the R8 limits. (R8,
      R8a, R9)
- [ ] On that pull request exactly one job is named
      `skill-gate (ubuntu-latest)`, it runs `bash scripts/skill-gate.sh`,
      and the skill gate's checks for /coordinate appear in its Linux and
      macOS logs. (R8a)
- [ ] On a ready pull request touching `skills/execute/scripts/` and
      `skills/work-on/scripts/`, the /execute and /work-on jobs are within
      the R8 limits, or the pull request description names each suite
      excepted under R9. (R9)
- [ ] Each changed workflow's `pull_request` and `push` paths are a superset
      of its paths on the base commit, shown by a diff of the two lists.
      (R10)
- [ ] A pull request changing only `scripts/lib/koto-test-guard.sh` starts
      every job of the floor check and of `check-coordinate-scripts.yml`.
      (R10)
- [ ] Each changed workflow keeps its concurrency block, and every workflow
      with a macOS job still appears in the output of
      `scripts/check-macos-floor-setup.sh --workflows`. (R11)
- [ ] A list of the `*_test.sh` files named in the logs of every job on one
      ready pull request, one draft pull request and one push to main, built
      before and after the change by the same script, shows no file missing
      after on any platform and koto release. (R12)
- [ ] `pr-body / pr-body` and `check-skill-requires` report on the pull
      request under those names. (R13)
- [ ] The linters and tests R14 names pass, and the diff touches none of
      their rule code. (R14)

## Out of Scope

- Removing, skipping or weakening any test, or adding retries to hide a
  slow or flaky suite.
- Making individual suites faster by changing what they assert. A suite
  that alone exceeds a limit is split by its cases or named as an
  exception.
- Any change to skill prose, the references skills load, koto templates, or
  /coordinate's behaviour.
- Taking the macOS bash 3.2 legs off pull requests, or changing which koto
  release the floor check installs.
- Removing the repeated runs of /coordinate's suites across the floor
  check, its own workflow and the skill gate. They run on different koto
  releases or bash versions; whether some are redundant is a separate
  decision.
- Narrowing any trigger to per-skill paths. Only /coordinate has a
  mechanically checked dependency map, and the other skills' suites reach
  across skills.

## Known Limitations

- More jobs means more runner start-up: each pays one to two minutes for
  checkout and the tsuku and koto installs, and some pay a cargo build.
  Total runner minutes per pull request go up even as the round goes down.
- R8 measures runner time only. The macOS runner pool is smaller than the
  Linux one, so several macOS slices on one ready pull request can queue
  behind other pull requests and make the round longer than the limits.
- A suite whose own runtime exceeds a limit (the largest is about 9
  CPU-minutes) bounds its slice. Splitting it by cases touches test files
  but not what they assert; one that can't be split is named as an
  exception under R9.

## Decisions and Trade-offs

- **Keep the union trigger on every job.** Per-skill path filters were
  considered for the floor check. They would skip suites that reach across
  skills (/deliver calls /execute and /scope scripts, /work-on's suites read
  /execute's template, /coordinate's read /work-on's template), so every job
  keeps the floor check's current paths and the split only shortens the
  work. This closes the BRIEF's question about narrower triggers: none are
  narrowed.
- **Slice the skill gate rather than drop its repeat runs.** The BRIEF asked
  whether the skill gate should keep re-running a touched skill's full
  suites when that skill's own workflow already runs them. The skill gate's
  macOS leg is the only pull-request-time bash 3.2 run of /coordinate's
  suites, and dropping it would contradict the boundary that keeps macOS
  legs on pull requests, so the gate keeps its checks and is sliced instead.
- **Balance slices by cost, not count.** One /coordinate engine suite is
  about a fifth of the engine list's cost, so equal-count slices would leave
  one slice twice as long as another. The skill's existing cost rows give
  the weights.
- **Slice count is the design's, bounded by R8.** The BRIEF asked how many
  jobs per list. The PRD fixes the time limits and a floor of two; the
  design picks counts that meet the limits given start-up cost.
- **The full run stays the default.** The definition of done for a pull
  request is a local `check-skill.sh --changed` run, so slicing is opt-in
  and only CI passes a slice argument.
- **Existing gaps in the floor check's triggers are not this PRD's.** The
  floor check does not trigger on a few shared scripts its suites call.
  Closing them would widen triggers, which R10 permits; the design may
  include it, and nothing here depends on it.
