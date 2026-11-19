---
schema: design/v1
status: Proposed
problem: |
  A /work-on or /execute run whose map command can't finish inside the 3,600 s
  row maximum ends at done_blocked, because the verification result can't tell
  a stopped run from a failed one, no map row names the hosted jobs that run
  the same suites, and the template's hosted CI route can only be chosen when
  the run starts (shirabe#1876, shirabe#1930).
decision: |
  One route with two triggers and one gate. The supervisor records each
  check's outcome (passed, failed, timed out at its limit, timed out inside
  the command), with check-skill.sh's per-suite lists. A timed-out result with
  no failed check holds verification at a new exit 5, shared with the
  shirabe#1881 rerun, where the agent may submit hosted_of_record with a
  reason when every timed-out row declares its hosted jobs. The route is
  recorded in place, the pull request opens as a draft, and a new
  hosted_record state after ci_monitor reads each declared job's latest
  attempt at the head before the pull request is marked ready, waiting at
  most 120 minutes.
rationale: |
  Hosted CI runs only for a pull request or a push to main, so the hosted
  result can't be read at verification; recording there and reading after
  the draft opens reuses the template's post-PR path without reordering it.
  skill-gate.sh already runs every changed skill's full check-skill.sh, so
  one declared job per row proves coverage by a test. Waiting for one local
  timeout, rather than predicting cost, keeps every run that fits local, and
  sharing #1881's hold keeps one decision point for a timed-out result.
upstream: docs/prds/PRD-verification-cap-route.md
decision_provenance: inline-resolved
---

# DESIGN: Verification cap route

## Status

Proposed

## Context and Problem Statement

The `verification` state in `skills/work-on/koto-templates/work-on.md` runs
the repository's verification map through `run-verification.sh --start`,
which launches a detached supervisor that runs each map command in turn,
and its `verification_verdict` gate polls `check-verification.sh --verdict`
for up to 7,200 s. The supervisor stops a command at its row's
`timeout_secs`, records `timed_out: true`, and the verdict maps that to
exit 4, which routes the run to `done_blocked`. A nonzero exit that isn't a
supervisor stop maps to exit 1 and routes the run back to `implementation`.
A result with both a timed-out and a failed command exits 4 today. The map
loader accepts a `timeout_secs` from 1 to 3,600 and nothing above, and the
whole run has a 7,200 s budget that also caps each command's remaining
deadline.

In shirabe the map's `check-skill` row runs `scripts/check-skill.sh
--changed` once per skill, which selects the suites a diff can affect. The
coordinate skill's `check-skill.tsv` lists 127 suites at about 6,194 CPU
seconds, and a change to any of its six shared scripts, or to a koto
template, selects all of them. Map reads at fe04d94e selected 121 suites
(about 6,163 s) for one example diff, 56 (about 3,051 s) for a change to
`coord-verdict.sh` and 127 (about 6,194 s) for `run-tests.sh`. On an idle
host at four jobs that is under half an hour; on the shared hosts these
runs use, the run for shirabe#1548 finished 10 of 127 suites in 3,601 s,
none failed, and was stopped. So the cap can't be raised to fit
(shirabe#1876), and a rerun at the same head hits the same wall.

Three things are missing in the code, and together they leave such a run
with no way through:

1. **The result can't tell a stopped run from a failed one at suite level.**
   The supervisor's per-command record carries `exit_status`, `timed_out`
   and `duration_secs`, and `check-skill.sh` prints a human line on TERM
   (`stopped with k of m suites done`), but nothing machine-readable says
   which suites finished and passed. A test that fails on its own internal
   timeout under load (a Go test's 10-minute panic, as in shirabe#1930)
   reads as exit 1, the same as an assertion failure.
2. **Hosted CI already runs the same suites at the same commit, but no map
   row says so.** `check-skill-gate.yml`'s `skill-gate` job runs
   `scripts/skill-gate.sh`, which runs `check-skill.sh <skill>` in full once
   for each skill directory the diff touches. Nothing ties a map row to that
   job, and nothing proves the job covers what the row selects.
3. **The template's hosted route is entry-only.** `VERIFICATION=hosted-ci`
   is chosen when the run starts, isn't rebindable, and makes every edge
   that would enter `verification` go to `verification_deferred` instead.
   A run already at `verification` with a timed-out result can submit only
   `blocked`.

Hosted CI here runs only on `pull_request` and on a push to `main`, and a
draft pull request runs only the ubuntu legs of `skill-gate` and
`test-check-skill`. Those two facts decide where the hosted result can be
read.

The change touches the supervisor's result, `check-skill.sh`'s stop output,
the verification map format and its loader, the `verification` state and
the states after it in `work-on.md`, `/execute`'s shared pull request
checks, and the PR-body gate. It sits beside open draft shirabe#1881, which
designs a hold at `verification` for an eligible timed-out result with a
same-head rerun value.

## Decision Drivers

These come from the PRD; each is stated here as the design must meet it.

- **When the route is open (R1).** Only when every check in the map result
  passed or timed out, at least one timed out, and every timed-out check's
  row declares hosted jobs. A failed check, a not-started or runaway
  command, a supervisor error, a dirty tree, or a missing or bad map keeps
  today's handling. Checks that passed locally stay local; the route covers
  only the timed-out checks.
- **Coverage, not stitching (R2, R3, R11).** A timed-out check is covered
  only when its declared hosted jobs, together, ran every suite the check
  can select, at the change's head commit. Local results never fill a gap,
  no subset of the jobs counts, and anything not started, stopped, skipped
  (a path filter, say) or unreadable counts as not run. The selection is
  never narrowed to fit the budget.
- **Timeout is told apart from failure (R4).** Each check's local outcome is
  one of passed, failed, timed out at its limit, or timed out inside the
  command. The last counts only when the row declares how such a timeout
  reads and every reported failure matches the declaration. For
  `check-skill.sh` the result lists finished-passed, finished-failed,
  still-running and not-started suites; a stopped run with a
  finished-failed suite is failed.
- **Declared and tested (R5).** A row declares its hosted jobs and each
  job's suite set in the repository, and a test fails when the declared sets
  don't contain every suite the row can select.
- **Reading hosted results (R6, R7, R15).** The latest attempt of each
  declared job at the head commit decides. Pending, queued or absent is
  waited for, up to 120 minutes from when the route was taken, then the run
  ends at `done_blocked` naming the jobs and commit. Anything other than
  success refuses, naming every refusing job and the commit. A refusal
  leaves the agent its other values (today `blocked`); a failed check goes
  to `implementation` whatever hosted CI says. A new head voids the route.
  The wait starts after the local run ends and isn't charged to the 7,200 s
  budget. Until every job concluded success the run can't reach a ready
  pull request.
- **Chosen, recorded, in place, everywhere (R8, R9, R10).** The agent takes
  the route by submitting a named value with a non-empty reason; no tick
  takes it otherwise. A `VERIFICATION=local` session takes it without being
  re-initialized; a `hosted-ci` session never enters `verification`. The
  koto record names, per covered check, the reason, jobs, head commit and
  each hosted run's id; the PR body carries one line per covered check with
  the check id, head and run links, and the PR-body gate refuses a body
  missing one. `/work-on` and every `/execute` mode get the same route.
- **Beside the rerun (R12).** Where the template also offers the
  shirabe#1881 rerun, both are offered at the same point and neither is a
  precondition for the other.
- **Budgets kept (R13, R14).** The 3,600 s row maximum and the 7,200 s
  run budget stay. A run spends at most one local budget on a check at a
  given head and merge-base before the route is open.
- **Nothing else moves (R16).** In-budget passes, failed checks and
  `hosted-ci` runs behave exactly as today, and their existing tests pass
  unchanged.

Implementation drivers the PRD doesn't name:

- **Reuse the template's existing machinery.** The PR-body gate,
  `ci_monitor` and `/execute`'s shared deferral record already do most of
  the post-PR work for the entry-time hosted route; reusing them keeps one
  meaning for "hosted CI settled this".
- **Testable without a suite run.** Every acceptance criterion is a
  template or script test over fixture results and fixture hosted-job
  responses with the wait clock set by the test. The existing harness,
  `skills/work-on/scripts/output-gates-routing_test.sh`, drives real
  `koto next` over the shipped state blocks with fake gate scripts.
- **One landable step at a time.** Each part should land and be released
  on its own, and none changes a live run before it is installed.

## Considered Options

### Decision 1: Where the hosted result is read

Resolved inline.

A taken route needs the declared jobs' results at the head commit, and
those exist only once a pull request carries the head: both hosted
workflows trigger on `pull_request` (drafts included) and on a push to
`main`. The run reaches `pr_creation` only after `pass_counting`,
`finalization`, `pre_pr_evidence` and `pr_precheck`, and `ci_monitor`'s
`ci_passing` gate already waits for every check on the pull request to be
green, counting `skipping` as green and naming no job.

Key assumptions:

- koto can route on a context-exists gate over the route's record key.
- The 120-minute bound is computed by the read script from the record's
  time; the gate's poll window only paces the reads.

#### Chosen: record at verification, read in a new state after the draft opens

The route is taken and recorded at `verification`, in place. The run then
follows the existing path to `pr_creation`, which opens the pull request as
a draft when the record exists. After `ci_monitor`'s gates pass, a new
`hosted_record` state reads each declared job's latest attempt at the
head. Every job success: the agent marks the pull request ready and the run
returns to `ci_monitor`, which now also waits for the macOS legs that a
draft skips, then goes on to `ci_pass_counting`. Any refusal sends the run
back to `verification`, where the reused timed-out result holds it again
with its values. Still pending past 120 minutes: `done_blocked`, naming the
pending jobs and the commit.

#### Alternatives Considered

**Read hosted CI inside `verification`.** Nothing has run at the head
before a pull request exists, so the read would have to push and open a
pull request from `verification`, ahead of the finalization and PR-precheck
states that exist to come first. Rejected: it reorders the template's
whole tail for one route.

**Reuse `verification_deferred` and `ci_passing` as they are.** The
entry-time deferral already reaches `ci_monitor`. Rejected: `ci_passing`
counts `skipping` as green, checks no job by name and doesn't look at
attempts, so a path-filtered job or a failed latest attempt behind an older
success would pass, against R3 and R6.

**Check only the PR body.** Rejected: a body line proves the claim was
written, not that the jobs passed.

### Decision 2: How a row declares and proves its hosted coverage

Resolved inline.

The `check-skill` row runs once per skill. `scripts/skill-gate.sh`, which
`skill-gate` runs, plans one `check-skill <skill>` line for each skill
directory a changed path falls under and runs `check-skill.sh <skill>` in
full for each; it also has a mode that prints the plan without running it.
The coordinate workflow's two jobs split the coordinate suites by engine
and unit, but trigger on a narrower path list than the row selects from.

Key assumptions:

- `check-skill.sh` can list a skill's full suite set without running it,
  as `--changed --list` lists the selection.

#### Chosen: a `hosted` array on the row, validated by the loader and proven by a test

The row gains an optional `hosted` array; each entry names a workflow file,
the job's name as GitHub reports it, and the plan line the job runs for a
skill. For shirabe the `check-skill` row declares
`skill-gate (ubuntu-latest)` running `check-skill {skill}`. The loader
treats a malformed declaration as `bad-map`. A coverage test checks, over
fixture diffs, that every skill the row runs for is in `skill-gate.sh`'s
plan for the same diff, that the plan line is the full command with no
`--changed`, and that every suite `check-skill.sh --changed --list` prints
is in the skill's full list. Dropping one suite from a declared set fails
it.

#### Alternatives Considered

**Declare the coordinate workflow's two jobs.** Their union is every
coordinate suite. Rejected for v1: the workflow doesn't trigger on
`skills/work-on/**` and other paths that select coordinate suites, so the
jobs would often be absent, and there is no per-suite list to prove
against. A second declaration can add them later.

**A separate mapping file.** Rejected: one row's meaning would be split
across two files the loader has to join.

**Derive coverage from workflow YAML at run time.** Rejected: it parses
YAML in a gate for a fact a test can fix once.

### Decision 3: How the result tells a timeout from a failure

Resolved inline.

The supervisor writes `exit_status`, `timed_out` and `duration_secs` per
command. `check-skill.sh` already traps TERM and prints its stopped line,
and the supervisor gives a stopped command one second before KILL.

Key assumptions:

- `check-skill.sh`'s TERM handler can write its summary inside that
  second; the summary is written as suites finish, so a late write only
  loses the final rename.

#### Chosen: a per-command outcome, a suite summary file, and an optional timeout form

Each command record gains `outcome`: `passed`, `failed`, `timed-out-limit`
or `timed-out-inside`. The supervisor passes `check-skill.sh` a summary
path in its environment; the script writes the finished-passed,
finished-failed, running and not-started suites there as each suite ends
and on TERM, and the supervisor copies it into the record as `suites`. A
stopped command with a finished-failed suite is `failed`. A row may declare
`timeout_form`, a regular expression; a nonzero exit is
`timed-out-inside` only when the row declares one and every failure line
the command's log reports matches it. `check-verification.sh` ranks a
failed check above a timed-out one, so any failed check exits 1.

#### Alternatives Considered

**Parse the human stopped line from the log.** Rejected: brittle text that
carries no per-suite pass or fail.

**Count only limit timeouts.** Rejected: it leaves shirabe#1930's
in-command timeouts as failures, against R4.

**Treat a timeout word anywhere in the output as a timeout.** Rejected: it
hides an assertion failure printed next to it.

### Decision 4: When the route opens and how it sits beside the rerun

Resolved inline.

Re-entering `verification` at the same head and merge-base reuses the
stored result without running anything (`run-verification.sh` keeps any
result for the same pair except a dirty-tree one). shirabe#1881 designs an
exit 5 for an eligible timed-out result: no gate-only edge matches 5, so the
state holds and the agent picks `rerun`, `fix` or `blocked`.

Key assumptions:

- shirabe#1881's exit 5 for a timed-out-plus-failed result is reconciled
  with R7 here by the route's own gate refusing the route for that result.

#### Chosen: open after one local timeout, at one shared hold

A result with a timed-out check and no failed check exits 5, not 4. A
second gate, `verification-route.sh --open`, exits 0 only when R1 holds.
At the hold the agent may submit `hosted_of_record` (which needs the route
gate at 0 and a reason), `fix` or `blocked`; shirabe#1881 adds `rerun`, and
neither value is a precondition for the other. Whichever lands first
introduces the hold; the second adds its value and the test that a
timed-out result accepts either value first. The route opens only after
one local timeout; the reused result offers it again on re-entry without a
second local run.

#### Alternatives Considered

**Open early from recorded cost.** `check-skill.sh --changed --list` gives
the selection's CPU cost. Rejected: 6,194 CPU s at four jobs fits on an
idle host, yet the 1548 run finished 10 of 127 suites in 3,601 s, so a
prediction would skip runs that fit and still miss runs that don't.

**A separate `verification_timed_out` state.** Rejected: two holds for one
condition, and the rerun's self-loop would need copying.

**Take the route on a tick when jobs are declared.** Rejected: R9 forbids a
tick taking the route unless the agent chose it.

## Decision Outcome

The four decisions make one route, opened by either issue's trigger and
closed by one gate. shirabe#1876's case (the check can't finish inside
3,600 s) and shirabe#1930's case (a check that timed out inside its own
command) both end as a timed-out check under the new per-command outcome,
and from there they're the same: the result holds `verification` at exit 5,
the agent chooses `hosted_of_record` with a reason, the record names the
timed-out checks and their declared jobs at the head, and the run goes on to
a draft pull request. The new `hosted_record` state settles the record
against each job's latest attempt at that head before the pull request can
be marked ready. A real failure anywhere still goes to `implementation`,
because a failed check outranks a timeout and closes the route. Beside
shirabe#1881 there is one hold with two optional ways out of a timed-out
result, a same-head rerun and the hosted record, and the design states
which side adds which value depending on which lands first.

## Solution Architecture

### Overview

The route adds a per-command outcome to the verification result, a
declaration to the verification map, a hold and a recording step to
`verification`, and a reading step after `ci_monitor`. The local run, the
3,600 s maximum and the 7,200 s budget are unchanged.

### Components

- **`skills/work-on/scripts/run-verification.sh`** (supervisor). Writes
  `outcome` per command from `exit_status`, `timed_out`, the row's
  `timeout_form` and the copied `suites` summary. Passes
  `SHIRABE_SUITE_SUMMARY=<head dir>/<index>-<name>.suites.json` to each
  command. The map loader's jq accepts the optional `hosted` and
  `timeout_form` fields and refuses a malformed one as `bad-map`.
- **`scripts/check-skill.sh`**. Writes the suite summary when
  `SHIRABE_SUITE_SUMMARY` is set: after each suite ends and in its TERM
  handler, by write-then-rename.
- **`skills/work-on/scripts/check-verification.sh`**. Ranks causes by the
  new outcome: any `failed` exits 1; otherwise a timed-out check exits 5;
  the other exits are unchanged.
- **`skills/work-on/scripts/verification-route.sh`** (new). `--open`
  exits 0 when R1 holds for the current result and map, 1 when it doesn't,
  printing the closing cause; `--record --reason <text>` writes the koto key
  `hosted_of_record`; `--read` reads the hosted jobs (below).
- **`.claude/shirabe-extensions/verification-map.json`**. The
  `check-skill` row gains its `hosted` declaration.
- **`skills/work-on/koto-templates/work-on.md`**. `verification` gains the
  exit-5 hold, the `verification_route` gate and the `hosted_of_record`,
  `fix` and `blocked` edges on 5. A new `verification_hosted` state records
  the route. `pr_creation` requires a draft and the body line when the
  record exists. A new `hosted_record` state sits between `ci_monitor` and
  `ci_pass_counting`.
- **`skills/work-on/scripts/check-pr-output.sh`**. A `--hosted-record` mode
  checks one body line per recorded check.
- **`skills/execute/scripts/shared-deferral-record.sh`** and execute's
  `plan_completion`. Collect children's `hosted_of_record` keys and run the
  same read and body check over the shared or node pull request before it
  is marked ready.
- **Tests.** New cases in `output-gates-routing_test.sh` and
  `run-verification_test.sh`, a new `verification-route_test.sh`, and a
  coverage test beside the map.

### Key Interfaces

Map row declaration:

```json
"check-skill": {
  "run": ["scripts/check-skill.sh", "--changed"], "each": "skills/*",
  "timeout_secs": 3600,
  "hosted": [{"workflow": ".github/workflows/check-skill-gate.yml",
              "job": "skill-gate (ubuntu-latest)",
              "runs": "check-skill {skill}"}]
}
```

An optional `"timeout_form": "<regex>"` sits beside `hosted` on a row whose
command can time out inside itself.

Per-command result record, new fields:

```json
{"id": "check-skill:coordinate", "outcome": "timed-out-limit",
 "suites": {"passed": ["..."], "failed": [], "running": ["..."],
            "not_started": ["..."]}}
```

koto key `hosted_of_record`, written by `--record` and completed by
`--read`:

```json
{"head": "<sha>", "taken_at": "<ISO-8601>", "reason": "<text>",
 "checks": [{"id": "check-skill:coordinate",
             "jobs": [{"workflow": "...", "job": "skill-gate (ubuntu-latest)",
                       "run_id": null, "conclusion": null}]}]}
```

`verification-route.sh --read` exit codes: 0 every job's latest attempt at
`head` concluded success (fills `run_id` and `conclusion`); 1 a job
concluded anything else, or the pull request head is not `head`, or a
result can't be read (names each refusing job and the commit); 75 a job is
pending, queued or absent and fewer than 120 minutes have passed since
`taken_at`; 3 the same past 120 minutes (names the pending jobs and the
commit). It reads `actions/runs?head_sha=<head>` and each run's jobs, taking
the highest `run_attempt` per job.

PR body line, one per recorded check:

```
Hosted of record: check-skill:coordinate at <sha>: <job run URL>
```

### Data Flow

1. `verification` entry runs `--start`. The supervisor runs the map, writes
   outcomes and suite lists, and the gate reads the result.
2. A failed check exits 1 to `implementation`. A timed-out check with no
   failed one exits 5 and the state holds. Re-entry at the same head and
   merge-base reuses the result and holds again.
3. At the hold the agent submits `verification_status: hosted_of_record`
   with `detail` as the reason. The edge needs `verification_verdict` at 5
   and `verification_route` at 0, and goes to `verification_hosted`.
4. `verification_hosted` runs `--record`; its gate checks the key exists,
   names the current head and has a non-empty reason. Pass: on to
   `pass_counting`. Fail: back to `verification`.
5. The run goes through finalization to `pr_creation`, which opens a draft
   and refuses a body without one line per recorded check.
6. `ci_monitor` waits for the draft's checks. With the record present and
   the pull request still a draft, its passing edge goes to `hosted_record`
   instead of `ci_pass_counting`.
7. `hosted_record` polls `--read`. On 0 the agent runs `gh pr ready` and a
   second gate confirms the pull request is no longer a draft; the run goes
   back to `ci_monitor`, which now waits for the non-draft legs too, then to
   `ci_pass_counting`. On 1 the run goes back to `verification`. On 3 it
   ends at `done_blocked` with the names and commit.
8. A new commit changes the head. The record's head no longer matches, so
   `--read` refuses, and the new head enters `verification` afresh.

Under `/execute`, a shared-branch child reaches `pr_status: shared` with
its record. `plan_completion` runs `--read` for each child's record at the
shared pull request's head before `gh pr ready`, measuring the wait from the
later of the record's `taken_at` and the head's push, since no hosted
result can exist before that push. Coordinated node pull requests do the
same in `node-push.sh` before they are marked ready. A `multi-pr` plan runs
`/work-on` and needs nothing more.

## Implementation Approach

### Phase 1: Per-command outcome and suite summary

The result change comes first: everything else reads it, and it changes no
routing on its own, since `check-verification.sh` still maps every timeout
to 4 until Phase 3.

Deliverables:

- `outcome` and `suites` in `run-verification.sh`'s records,
  `SHIRABE_SUITE_SUMMARY` in `check-skill.sh`, `timeout_form` in the loader.
- `run-verification_test.sh` cases for each outcome and for counts that add
  up to the `--changed --list` selection.

### Phase 2: Hosted declaration and coverage test

Independent of Phase 1 except for the loader edit.

Deliverables:

- The `hosted` field in the loader and the schema doc
  (`skills/work-on/references/verification-map.md`), the `check-skill`
  row's declaration, and the coverage test over `skill-gate.sh`'s plan.

### Phase 3: The hold, the route gate and the record

Needs Phases 1 and 2.

Deliverables:

- Exit 5 in `check-verification.sh`, `verification-route.sh --open` and
  `--record`, the `verification` edges and the `verification_hosted` state,
  and routing tests over fixture results.

### Phase 4: The hosted read and the ready step

Needs Phase 3.

Deliverables:

- `verification-route.sh --read`, the draft and body-line checks in
  `pr_creation`, the `hosted_record` state, and fixture tests over hosted
  responses with the clock set by the test.

### Phase 5: /execute parity

Needs Phase 4.

Deliverables:

- `shared-deferral-record.sh` and `plan_completion` reading children's
  records, `node-push.sh`'s ready step, and parity tests for `single-pr`,
  `coordinated` and `multi-pr`.

## Security Considerations

The route reads hosted CI results and lets them stand in for a local run,
so the risk is a pass counted that no run earned.

- **Trust in hosted results.** `--read` takes results only for the
  repository's own workflow file and job name, at the exact head commit,
  from the highest attempt, and accepts only `success`. A result for another
  commit, an older attempt, a skipped job or an unreadable response refuses.
  A pull request from a fork can't add a job the map declares, since the
  declaration is read from the merge-base like the rest of the map.
- **Permissions.** `--read` uses the session's existing `gh` token with read
  access to Actions; it writes only the run's own koto key. `gh pr ready` is
  the one write, the same the run's pull request steps already make.
- **Recorded text.** The reason is agent text that reaches the PR body. It is
  passed with `jq --arg`, stripped of control characters and capped, as the
  existing deferral reason is, and never interpolated into a shell command.
- **Supply chain.** No new dependency; the scripts use `jq` and `gh`, which
  the template already requires.

## Consequences

### Positive

- A run whose selection can't finish inside 3,600 s reaches a verdict that
  still means every selected suite ran at the head and passed.
- A load timeout inside a command stops reading as an assertion failure, and
  the result says which suites passed before the stop.
- shirabe#1876 and shirabe#1930 share one hold with shirabe#1881, so a
  timed-out result has one decision point.

### Negative

- A run taking the route waits for hosted CI, often 40 minutes or more, and
  its pull request stays a draft until then.
- The declared job runs on ubuntu while local runs are on macOS; the macOS
  legs run only once the pull request is ready.
- A result with both a timed-out and a failed check now goes to
  `implementation` instead of `done_blocked`.
- Under `/execute` the shared pull request's head is later than a child's,
  so the read covers the child's check at the head that merges, not at the
  child's own commit.

### Mitigations

- The 120-minute bound ends a stuck wait with the names and commit, and
  `ci_monitor` runs again after the ready step, so the macOS legs must pass
  before `ci_pass_counting`.
- The failed-plus-timed-out change is the PRD's acceptance criterion and is
  tested; a failure the agent can reproduce is better fixed than blocked.
- The skill-gate job runs every touched skill's full suite set at the
  shared head, which contains each child's selection; the record names the
  head that was read.
