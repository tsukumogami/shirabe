---
schema: design/v1
status: Current
problem: |
  Five CI jobs on a shirabe pull request run long, independent suite lists one
  after another on one runner, so each takes 35-72 minutes and the round takes
  40-75. Splitting them has to keep every suite running on the same koto
  release and bash version, keep the skill gate the verification map's job of
  record, and get past workflow linters that pin job names and floor calls.
decision: |
  Every long job becomes a fail-fast-off matrix of slices inside its existing
  workflow. One selector, scripts/lib/suite-slice.sh, reads SUITE_SLICE=i/n
  and assigns a list's suites greedily by measured cost; run-tests.sh,
  run-suites.sh, check-skill.sh and check-bash-floor.sh filter through it.
  The skill gate keeps its job of record, which needs new slice jobs and runs
  the once-per-skill checks. An over-long rule-registry suite splits into part
  files, and a static check pins every sliced matrix and the gate's shape.
rationale: |
  An environment variable reaches nested runners and keeps macOS floor calls
  naming their suite literally, which the floor linters require; a flag or
  hand-written lists would not. Cost-balanced greedy slices stay within one
  suite of each other where equal counts would not. Slice jobs the gate needs
  keep the verification map's job name and meaning. Matrices inside existing
  files keep triggers, concurrency and registrations as they are.
upstream: docs/prds/PRD-shirabe-ci-suite-split.md
decision_provenance: inline-resolved
---

# DESIGN: Shorter CI rounds through sliced suite lists

## Status

Current

## Context and Problem Statement

The jobs that set a shirabe pull request's CI round each walk one long list of
test suites on one runner. On pull request runs from 2026-11-23:

- `entry-floor` (`check-koto-entry-floor.yml`, 41-53 minutes) installs the
  oldest supported koto and runs five skills' koto-backed suites in five
  sequential steps. The last step, `skills/coordinate/scripts/run-tests.sh
  --engine`, took 2,633 seconds of it; the other four skills took about 9
  minutes together.
- `test-coordinate-engine` (about 41) and `test-coordinate-scripts
  (ubuntu-latest)` (about 35) in `check-coordinate-scripts.yml` run
  `run-tests.sh --engine` and `run-tests.sh` over 47 engine and 80 offline
  suites, serially. `run-tests.sh` globs `*_test.sh`, runs each under a
  restricted PATH, and fails a suite on a non-zero exit, a `SKIP` line or
  `command not found`.
- `skill-gate` (`check-skill-gate.yml`) runs `scripts/skill-gate.sh`, which
  runs `scripts/check-skill.sh <skill>` in full for each touched skill.
  `check-skill.sh` already runs four suites at once, costliest first by the
  `cost` rows in `skills/<skill>/check-skill.tsv`, but a /coordinate change
  still takes about 42 minutes on Linux and 72 on macOS bash 3.2, reached
  through `scripts/check-bash-floor.sh --backend system skill-gate`.
- `test-rule-registry (macos-latest)` (about 45) spends 43 of them in one
  suite, `scripts/check-rule-registry_test.sh`, so no split of its four-suite
  list helps until that suite is split by its cases.
- `test-work-on-scripts (ubuntu-latest)` (about 20) is roughly 60 separate
  steps; `test-execute-scripts` is 14 on Linux and 19 on macOS.

The requirements (PRD R1-R14) ask for every job under 15 minutes on Linux and
25 on macOS, runner time measured from `started_at` to `completed_at`, on a
ready pull request touching `skills/coordinate/scripts/` and `scripts/lib/`,
with no test dropped, skipped, weakened or retried (R12). Several pieces of
the repository pin the shapes a solution can take:

- `.claude/shirabe-extensions/verification-map.json` names `skill-gate
  (ubuntu-latest)` as the hosted job of record for `check-skill {skill}`.
  `skills/work-on/scripts/verification-hosted-coverage_test.sh` requires that
  job to have an os-only matrix and a Linux step running exactly `bash
  scripts/skill-gate.sh`, and `skills/work-on/scripts/verification-route.sh`
  requires exactly one job of that name to succeed. `scripts/eval-workflows_test.sh`
  pins the same step strings and the `SKILL_GATE_BASE` step (PRD R8a, R14).
- `scripts/check-macos-floor-legs.sh` ignores any floor-call argument holding
  `$`, so a macOS floor call must name its suite literally, and the job's
  `matrix.os` must equal the draft or push-only expression exactly; extra
  matrix keys are allowed. `scripts/check-macos-floor-setup.sh` refuses the
  same floor suite run from two jobs with different setups.
  `scripts/check-bash-floor_test.sh` requires each called suite's list file in
  that workflow's paths.
- `scripts/koto-minimum-consistency_test.sh` greps `check-koto-entry-floor.yml`
  for `assert-koto-floor.sh --print-floor` and `koto@$KOTO_FLOOR_RELEASE`.
- `skills/coordinate/scripts/directive-ceiling_engine_test.sh` needs
  `fetch-depth: 0` for its merge-base read.
- Suites are otherwise independent: each makes its own temporary HOME and its
  own fake S3 server (`skills/coordinate/scripts/testdata/cloud-hosts.sh`),
  so any partition of a list runs the same cases.

Per-skill path filters were ruled out in the PRD's decisions: /deliver's
suites call /execute and /scope scripts, /work-on's read /execute's template,
and /coordinate's read /work-on's template, so a narrower trigger would drop
suites (R10).

## Decision Drivers

- **Same coverage (R12).** Every test file that runs on a draft pull request,
  a ready one, or a push to main, on a given platform and koto release, keeps
  running there. Splitting a suite file into parts is allowed; editing what a
  case asserts is not.
- **Time limits (R8).** 15 minutes per Linux job and 25 per macOS job, runner
  time only. The largest /coordinate suite is 527 CPU-seconds, about 9
  minutes on Linux.
- **The full run stays the default (R6).** Local runs and
  `check-skill.sh --changed` behave exactly as today.
- **Fixed names and shapes.** The verification map's hosted job, the
  required checks `pr-body / pr-body` and `check-skill-requires`, the literal
  floor-call shape, and the koto-minimum greps (R8a, R13, R14).
- **Failures stay legible (R5, R7).** Each job names its list and slice,
  prints its suite counts, names each failing suite, and finishes even when a
  sibling fails.
- **Small surface.** One mechanism used everywhere beats a per-workflow
  arrangement, because every workflow it touches has its own linter.

## Considered Options

### Decision 1: How a job runs one slice of a suite list

Resolved inline.

Four runners walk suite lists: `run-tests.sh` (a glob), `run-suites.sh` (an
argument list), `check-skill.sh` (a glob with cost-ordered launch) and
`check-bash-floor.sh` (a list file). A slice has to be chosen the same way in
each, reach a runner nested under another (`check-bash-floor.sh` runs
`skill-gate.sh`, which runs `check-skill.sh`), and leave macOS floor calls
naming their suite literally.

Key assumptions:

- Suites are independent, so any partition runs the same cases.
- Cost rows measured on Linux rank suites well enough on macOS too.

#### Chosen: One selector driven by `SUITE_SLICE=i/n`

A new library, `scripts/lib/suite-slice.sh`, reads a list of suite paths on
standard input and the environment variable `SUITE_SLICE` (`i/n`, with
`1 <= i <= n <= 16`). It sorts the list by name with `LC_ALL=C` and looks up
each suite's cost by its file's basename in a cost table: either the file
`SUITE_SLICE_COSTS` names, holding `check-skill.tsv`-style rows
(`cost<TAB><basename><TAB><seconds>`), or cost pairs a caller passes on
another descriptor (how `check-bash-floor.sh` hands over a list's `cost:`
lines). A suite with no cost gets the median of the known costs, or 1 when
none is known. Suites are assigned greedily, costliest first, each to the
slice with the lowest running total, ties broken by lower slice number. It
prints the suites of slice `i` in the runner's original order and, on
standard error, `suite-slice: slice i/n: k of N suites`. With `SUITE_SLICE`
unset or empty it prints the list unchanged, which is how R6 holds.

It fails closed. An empty full list is an error (exit 1, naming the runner),
since every slice of an empty list would pass having run nothing. An empty
slice is allowed only when the list has fewer suites than `n`. A cost value
that isn't a whole number is an error, not a default.

Greedy longest-first assignment keeps every slice within one largest suite of
the lightest (the PRD's R3 bound), is deterministic for a given list and cost
file, and needs nothing beyond awk and sort, so it runs on bash 3.2.

Each runner filters its list through the selector:

- `run-tests.sh` and `run-suites.sh` before their loop; their closing count
  line reports the slice (`run-tests: 12 of 47 suites (slice 2/4)`), and both
  already name a failing suite.
- `check-skill.sh` in step 4 only, after its own suite selection and before
  the cost-ordered launch, so `--changed` selection and slicing compose. It
  points the selector at `skills/<skill>/check-skill.tsv` itself when that
  file exists, so no workflow names a per-skill cost file.
- `check-bash-floor.sh` over a list's harness lines (the script paths in
  `scripts/bash-floor/<suite>.list`; the `coordinate` list names 54 suite
  files one per line), shrinking the "ran X of Y listed" count to the slice. A list can carry a new directive,
  `slice: pass`, which tells `check-bash-floor.sh` not to slice its harnesses
  and to leave `SUITE_SLICE` set for them; the `skill-gate` list uses it, so
  the slice reaches `check-skill.sh` instead. Without that directive
  `check-bash-floor.sh` slices its harnesses and unsets `SUITE_SLICE` before
  running each, so nothing is sliced twice.

Workflows set `SUITE_SLICE: ${{ matrix.slice }}/<n>` as a job-level
environment variable, so the floor call stays
`scripts/check-bash-floor.sh --backend system <suite>`.

Because the variable is ambient, every test of a runner
(`run-suites_test.sh`, `check-skill_test.sh`, `skill-gate_test.sh`,
`check-bash-floor_test.sh`, and the new `run-tests.sh` cases) unsets
`SUITE_SLICE`, `SUITE_SLICE_COSTS` and `SKILL_GATE_PART` before running a
runner on its fixtures, and each has a case proving a fixture run is
unaffected when the variable is set in its own environment. A developer who
sets the variable in a shell gets a sliced local run, and the runner's count
line says so.

#### Alternatives Considered

**A `--shard i/n` flag on each runner.** Rejected: a macOS floor call carrying
`--shard ${{ matrix.slice }}` is either ignored by `check-macos-floor-legs.sh`
or read as a suite name by `check-bash-floor_test.sh`, and a flag does not
reach a runner nested two scripts deep without each script forwarding it.

**Slice lists written out in workflow YAML.** Rejected: every suite added or
renamed would need a workflow edit, and the lists would drift from the glob
the full run uses.

**Equal-count slices.** Rejected: `driver-check_engine_test.sh` alone is 527 of
2,710 engine CPU-seconds, so count-based slices would leave one slice about
twice as long as another.

### Decision 2: How the skill gate is split

Resolved inline.

The skill gate is the only job here whose name another file depends on. The
verification map declares `skill-gate (ubuntu-latest)` the hosted job of
record for `check-skill {skill}`, and its route requires exactly one job of
that name to succeed. A slice key in its matrix would rename it.

Key assumptions:

- A job-level `needs:` and `env:` on `skill-gate` leave the step strings and
  os-only matrix that `eval-workflows_test.sh` and
  `verification-hosted-coverage_test.sh` check unchanged.
- `check-macos-floor-setup.sh` accepts the `skill-gate` floor suite from two
  jobs when their setup steps are identical.

#### Chosen: Slice jobs the gate job needs

`check-skill-gate.yml` gains a job `skill-gate-suites`, matrix `os` (the same
draft and push expressions) by `slice: [1, 2, 3, 4]`, `fail-fast: false`,
with the same checkout, tsuku, koto and base-commit steps as `skill-gate`. It
sets `SUITE_SLICE: ${{ matrix.slice }}/4` and `SKILL_GATE_PART: suites`, and
runs the same two step strings as `skill-gate`: `bash scripts/skill-gate.sh`
on Linux and `scripts/check-bash-floor.sh --backend system skill-gate` on
macOS.

`skill-gate` keeps its name, matrix and steps, adds `needs:
skill-gate-suites` and `SKILL_GATE_PART: checks`. Under `SKILL_GATE_PART`,
`skill-gate.sh` passes the part to `check-skill.sh`, which then runs either
only step 4's suites (`suites`) or every step except them (`checks`: the
validator, template compile, eval-shape, script cases, pipe-readers and
mktemp guards). `script-cases --all` runs in the `checks` part. With
`SKILL_GATE_PART` unset, both run, as today (R6).

Because `skill-gate` needs every slice, `skill-gate (ubuntu-latest)` succeeds
only when every Linux and macOS slice succeeded and its own checks passed. A
failed slice leaves it skipped, which the verification route reads as not
passed, so the job of record still means "check-skill passed for every
touched skill". Every check runs on both platforms, split across jobs (R8a).

#### Alternatives Considered

**A slice key in `skill-gate`'s matrix.** Rejected: it renames the job to
`skill-gate (ubuntu-latest, 1)`, breaking the verification map, its coverage
test and the route's one-job rule, all of which R14 keeps unchanged.

**Dropping the gate's repeat of suites other workflows already run.**
Rejected: the gate's macOS leg is the only pull-request-time bash 3.2 run of
/coordinate's suites, and the PRD keeps macOS legs on pull requests.

**More parallel suites inside the one job.** Rejected: hosted runners have
three or four cores, the suites are CPU-bound (cost rows are CPU-seconds), and
`check-skill.sh` already runs four at once.

### Decision 3: Shape of the floor check and the other long jobs

Resolved inline.

Key assumptions:

- The organisation's concurrent-job allowance absorbs roughly 30 more jobs per
  pull request; queueing is outside R8's runner-time measure.
- `scripts/check-rule-registry_test.sh` cases can be partitioned into files
  without sharing state across the cut, as `coordinate_1..4_engine_test.sh`
  were.

#### Chosen: Matrices inside the existing workflow files

Each workflow keeps its file, `paths`, concurrency group and registration, and
its long job becomes a matrix with `fail-fast: false`:

- **Floor check.** `entry-floor` gets `matrix.leg: [shared, scope, execute,
  deliver, work-on]`, and a second job in the same file,
  `entry-floor-coordinate`, gets `matrix.slice: [1, 2, 3, 4]` with
  `SUITE_SLICE: ${{ matrix.slice }}/4`. Every job keeps `fetch-depth: 0`,
  reads the floor with `assert-koto-floor.sh --print-floor`, installs
  `koto@$KOTO_FLOOR_RELEASE`, asserts the exact version and builds shirabe
  (R1). The `shared` leg runs the template compile, the decider check,
  `run-suites_test.sh` and the shared entry and preflight suites; each skill
  leg runs its existing `run-suites.sh` list; `entry-floor-coordinate` runs
  `run-tests.sh --engine` with `SUITE_SLICE_COSTS` set to /coordinate's
  `check-skill.tsv`. A separate job keeps the slice in `matrix.slice`, the
  one form the matrix check reads.
- **Coordinate workflow.** `test-coordinate-engine` gets `slice: [1..4]`.
  `test-coordinate-scripts` keeps its os expression and gains `slice: [1..4]`;
  the Linux step is unchanged apart from the environment, the squash-message
  suite runs in slice 1, and the push-only macOS leg slices the `coordinate`
  floor list the same way. `check-template-compat` is unchanged.
- **Rule registry.** `check-rule-registry_test.sh` is split into
  `check-rule-registry_1_test.sh` through `_4_test.sh` by case order, moving
  cases without editing them, and its floor list, the Linux step and the
  workflow `paths` name the four parts. The job gains `slice: [1, 2, 3, 4]`,
  one slice per part, with the three short suites landing on the lightest
  slices; the Linux step becomes one `run-suites.sh` call over the list,
  and the list carries `cost:` directive lines so the selector can balance
  it. The first cost lines come from the 2026-11-23 macOS log, scaled by
  case count per part, and are corrected from the first sliced run in a
  follow-up commit. The two merge-base registry checks run in slice 1.
- **/work-on and /execute.** `test-work-on-scripts` Linux steps that are a
  plain `bash <suite>` move into one `run-suites.sh` call under
  `slice: [1, 2]`; steps with their own environment or setup stay as steps,
  pinned to slice 1. `test-execute-scripts` (14 minutes on Linux, 19 on macOS)
  is within the limits and is left alone unless a measured run says
  otherwise.

Slice counts are set by the limits: four /coordinate engine slices put about
2,710 CPU-seconds into slices of roughly 680 plus start-up; four offline
slices put 3,484 into roughly 870; the skill gate's 72 macOS minutes become
about 18 per slice.

The floor check's existing trigger gaps (`scripts/skill-session.sh`,
`scripts/check-handoff.sh`, `scripts/check-template-compat.sh`,
`scripts/session-role.sh`, `scripts/doc-shadow-check.sh`,
`scripts/review-events.sh`, `references/**`) are closed in the same change,
which only widens triggers (R10).

#### Alternatives Considered

**One workflow file per skill for the floor check.** Rejected: it repeats the
setup and the paths list five times, each new file needs its own
koto-minimum consistency entry, and a later edit to one paths list drifts
from the others.

**Per-skill path filters on floor legs.** Rejected in the PRD: cross-skill
suite calls mean a narrower trigger drops suites.

**Splitting `check-rule-registry_test.sh` with an internal part selector
rather than separate files.** Rejected: separate part files are the existing
precedent, name the failing part in the job log, and need no new environment
contract inside a test.

### Decision 4: How CI proves the slices cover their lists

Resolved inline.

Key assumptions:

- `SUITE_SLICE` is only ever set from a matrix value.

#### Chosen: A static matrix check plus the selector's own tests

`scripts/check-suite-slices.sh` reads every workflow, finds each job that sets
`SUITE_SLICE`, and fails unless the value is exactly
`${{ matrix.slice }}/<n>`, that job's `matrix.slice` is exactly
`[1, ..., n]`, `fail-fast` is `false`, and no `run:` body in the job holds
`${{ matrix`. It also holds the skill gate's shape: `skill-gate` has
`needs: skill-gate-suites`, and neither `skill-gate` nor `skill-gate-suites`
carries a job-level `if:` or `continue-on-error`. Finally it requires each of
the sliced jobs this design creates to exist, by workflow and job name, so
deleting one fails the check rather than shrinking coverage. It runs in
`check-pr-workflow-content.yml`, whose trigger covers `.github/workflows/**`,
and in a new step of the bash-floor registry tests. The selector's own suite,
`scripts/lib/suite-slice_test.sh`, proves the partition: for lists of 0, 1, 2
and 127 suites, with and without cost rows, every suite appears in exactly one
slice for n from 1 to 8, an empty slice reports zero suites and exits 0, the
output is identical under `LC_ALL=C` and `LC_ALL=C.UTF-8`, and the heaviest
slice exceeds the lightest by no more than the largest suite.

Together these make the PRD's coverage requirement (R4) a property of the
code: the selector partitions any list exactly, and the matrix check makes
every list's slices all run.

#### Alternatives Considered

**A run-time manifest comparison.** Each slice uploads the suites it ran and
an aggregation job compares the union with the full list. Rejected for now:
it adds a job per workflow and catches nothing the static check and the
selector tests miss, since every slice derives its list from the same glob.

## Decision Outcome

Every long job becomes a matrix of slices inside its existing workflow, and
every slice is chosen by one selector reading `SUITE_SLICE`. The selector
balances by the cost rows /coordinate already keeps and by new `cost:` lines
in the floor lists that need them. The skill gate keeps its job of record and
waits for its slice jobs, so the hosted-of-record contract still means every
check passed. Suites too long for any slice are split into part files, as
/coordinate's engine suite was before. Nothing narrows a trigger; the floor
check's trigger gaps close. The full run stays the default everywhere.

The pieces fit because the environment variable is the only new contract:
workflows set it, the selector reads it, the runners filter through the
selector, and `check-bash-floor.sh` decides per list whether to slice or pass
it on. Coverage holds because the selector partitions exactly and the matrix
check makes every slice run.

## Solution Architecture

### Overview

```
workflow matrix (slice: [1..n], fail-fast: false)
  env SUITE_SLICE=i/n, SUITE_SLICE_COSTS=<cost rows>
    -> runner (run-tests.sh | run-suites.sh | check-skill.sh step 4 |
               check-bash-floor.sh harness list)
         -> scripts/lib/suite-slice.sh  (full list in, slice i out)
         -> runs slice i under the runner's existing failure rules
```

### Components

- **`scripts/lib/suite-slice.sh`** (new): the selector. Bash 3.2, awk and
  sort only. Refuses a malformed `SUITE_SLICE` (not `i/n`, `i > n`, `n > 16`)
  with exit 2 and a message naming the value.
- **`scripts/lib/suite-slice_test.sh`** (new): the partition, balance,
  locale, empty-slice and refusal cases.
- **`skills/coordinate/scripts/run-tests.sh`**, **`scripts/run-suites.sh`**:
  filter through the selector; print the slice in the count line.
- **`scripts/check-skill.sh`**: filter step 4's suites through the selector;
  honour `SKILL_GATE_PART=suites|checks`.
- **`scripts/skill-gate.sh`**: pass `SKILL_GATE_PART` through; run
  `script-cases --all` only when the part is unset or `checks`.
- **`scripts/check-bash-floor.sh`**: slice harness lines unless the list says
  `slice: pass`; read `cost:` lines; unset `SUITE_SLICE` for children of a
  sliced list.
- **`scripts/check-suite-slices.sh`** (new) and its test: the matrix check
  and the skill gate's shape.
- **`skills/work-on/scripts/verification-route.sh`'s test**: a new case for a
  skipped job of record.
- **Workflows**: `check-koto-entry-floor.yml`, `check-coordinate-scripts.yml`,
  `check-skill-gate.yml`, `check-rule-registry.yml`,
  `check-work-on-scripts.yml`, plus a step in
  `check-pr-workflow-content.yml`.
- **Floor lists**: `skill-gate.list` gains `slice: pass`;
  `rule-registry.list` names the four part files and their `cost:` lines.
- **`scripts/check-rule-registry_{1..4}_test.sh`**: the split suite.

### Key Interfaces

- `SUITE_SLICE=i/n`: unset or empty means the full list.
- `SUITE_SLICE_COSTS=<file>`: rows `cost<TAB><suite basename><TAB><seconds>`;
  floor lists use `cost: <suite path> <seconds>` directive lines instead, and
  both are matched on the suite's basename. `check-skill.sh` sets it to its
  skill's `check-skill.tsv` when unset.
- `SKILL_GATE_PART=suites|checks`: unset means both. `skill-gate.sh` and
  `check-skill.sh` refuse any other value with exit 2.
- `suite-slice.sh` standard output: one suite path per line, the slice's
  suites in the runner's original order; standard error: the count line.

### Data Flow

A pull request event starts each workflow once, as today. Each matrix job
checks out, installs its tools and runs its runner with its slice. The runner
asks the selector for its slice of the same list the full run would use and
runs those suites under its usual rules. GitHub reports each job separately;
`skill-gate` reports after its slice jobs.

## Implementation Approach

### Phase 1: Selector and runners

`suite-slice.sh` and its test; slicing in `run-tests.sh`, `run-suites.sh`,
`check-skill.sh`, `skill-gate.sh` and `check-bash-floor.sh`, each with test
cases for the full-run default and a sliced run; `check-suite-slices.sh` and
its test. Checked locally only on targeted suites (the selector's, the
runners' own tests on a small fixture list), never the full lists.

### Phase 2: Long single suites

Split `check-rule-registry_test.sh` into four part files by case order,
moving cases without editing them, and update its floor list, Linux step and
workflow `paths` to name the parts, with first-estimate `cost:` lines.

### Phase 3: Workflows

The matrix changes in the five workflows, the `slice: pass` directive, the
floor check's widened paths, and the matrix check's step. Checked by the
repository's workflow linters and by one pull request run. If that run shows
another suite over a limit, split it as in Phase 2 or name it, with its
measured runtime, in the pull request description (PRD R9); corrected
`cost:` lines land in a follow-up commit.

### Phase 4: Measure

On the pull request, read every job's `started_at` and `completed_at` from the
Actions API, confirm the R8 limits, and compare a per-test-file inventory of
the job logs against the same inventory from a run on the base commit, for a
draft run, a ready run and the push to main (R12).

## Security Considerations

No new permissions, secrets or triggers. New jobs inherit the workflow-level
`permissions: contents: read`, add no job-level `permissions`, and use the
same `GITHUB_TOKEN` the job they split from uses; no `pull_request_target`
trigger is added, and `eval-workflows_test.sh` keeps guarding that for every
job. Matrix values are static YAML literals and reach shell steps only through
`env:`, never through `${{ }}` inside a `run:` body.

The selector and the matrix check read only files in the checked-out tree and
environment values the workflow sets, never pull request text. `SUITE_SLICE`
and `SKILL_GATE_PART` are validated against fixed patterns before use, and
cost files and `cost:` lines are parsed as data by awk with numeric checks,
never sourced or evaluated.

`skill-gate` must not gain `if: always()` or `continue-on-error`: a failed or
skipped slice has to leave the job of record unpassed, which is what keeps the
verification route honest. `check-suite-slices.sh` enforces that, and a new
case in `verification-route.sh`'s test proves a skipped `skill-gate
(ubuntu-latest)` does not count as passed. GitHub treats a skipped job as
passing for a required status check, so `skill-gate` must not become a
required check without an always-run aggregate job in front of it; today it
isn't one.

The variable that selects a slice could also shrink coverage silently. The
selector fails on an empty full list, runner tests unset it before fixture
runs, and the matrix check pins every sliced job's slice set, so no path
leaves a job green with fewer suites than its slice holds. Every new job that installs tools sets
`TSUKU_TELEMETRY=0` and uses the same actions as its parent job, the
SHA-pinned ones at the same SHAs and `actions/checkout` at the same tag as
today. More jobs per pull request means more checkouts of untrusted pull
request code and more downloads of koto, tsuku and apt packages, but no more
trust placed in any of them: each runs with the read-only token the unsplit
job had.

## Consequences

### Positive

- Every job on a ready /coordinate pull request fits in 15 minutes on Linux
  and 25 on macOS, so a fix-and-push round costs minutes.
- One mechanism serves every runner; a suite added later lands in a slice
  without a workflow edit.
- The floor check's trigger gaps close.

### Negative

- About 30 more jobs per pull request, each paying one to two minutes of
  setup and some a cargo build, so total runner minutes rise.
- macOS slices compete for a smaller runner pool and can queue.
- The skill gate's job of record now finishes after its slices, so its own
  start waits on the slowest slice.
- Cost rows go stale as suites change; a stale row skews balance, never
  coverage.

### Mitigations

- `scripts/check-cost-rows.sh` already requires a cost row for every
  /coordinate suite, which keeps that table current.
- Slice counts are matrix values, so a slice count can rise in a one-line
  change when a list grows.
- The matrix check and the selector tests keep coverage a property of the
  code rather than of review.
