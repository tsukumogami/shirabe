---
schema: prd/v1
status: In Progress
problem: |
  A /work-on or /execute run whose change selects more check-skill suites than
  one local command can finish in 3,600 s, the per-row budget and the map
  format's maximum, can't get through its verification state. A timed-out
  command ends the run at done_blocked, a rerun hits the same wall, and when the
  only local failures are load timeouts the run can't take the green hosted CI
  run of the same checks at the same head instead (shirabe#1876, shirabe#1930).
goals: |
  Such a run reaches a verification verdict by a route the workflow template
  provides and records, covering every selected suite with a run at the change's
  head, counting nothing as passed that no run executed, and still sending a
  real failure back to implementation.
upstream: docs/briefs/BRIEF-verification-cap-route.md
source_issue: 1876
---

# PRD: Verification cap route

## Status

In Progress

Accepted under `/scope`'s non-interactive mode after three jury rounds. Each round
failed on precision, and each set of findings was fixed in place; the third
round's were edge cases (the wait-end case, hosted job conclusions, a wrong
cross-reference) rather than missing requirements. Where the hosted results
are read, before or after the draft pull request opens, is left to the design.

## Problem Statement

`/work-on` and `/execute` end each issue's implementation in a `verification`
state. Its entry action runs the repository's verification map on the local host
under a detached supervisor, and its gate reads the result. In shirabe, the map's
`check-skill` row runs `scripts/check-skill.sh --changed`, which selects the
skill suites a diff can affect, with a `timeout_secs` of 3,600. That value is
also the largest the map format accepts, so the budget can't be raised to fit
(shirabe#1876).

The selected suites regularly cost more than that. `skills/coordinate/check-skill.tsv`
records 127 coordinate suites at about 6,194 CPU seconds in all, and a change to
any of its six shared scripts, or to a koto template, selects all of them. Map
reads at fe04d94e selected 121 suites (about 6,163 s) for one example diff, 56
(about 3,051 s) for a change to `coord-verdict.sh` and 127 (about 6,194 s) for
`run-tests.sh`. At four parallel jobs on an idle host that is under half an hour,
but the hosts these runs share are rarely idle: the run for shirabe#1548 finished
10 of 127 suites in 3,601 s with none failed, and the read for shirabe#1196
selected all 127.

When the supervisor stops a command at its limit, the gate reads it as exit 4 and
the run goes to `done_blocked`, a terminal. Nothing in the result says the
command was stopped while its finished suites all passed. A test that fails on
its own internal timeout under load reads as an ordinary failure and sends the
run back to `implementation` (shirabe#1930). Meanwhile hosted CI has often run
every coordinate suite at the same commit and passed. The template has a hosted
CI route, but only one chosen when the run starts; a run already at
`verification` can't take it.

So a change that touches a shared script or a template has no way through
verification, and three changes close to landing (shirabe#1196, shirabe#1166,
shirabe#1548) wait on this.

## Goals

- A run whose selected checks cost more than one local command may take still
  reaches a verdict, without an operator editing the run by hand.
- The verdict means what a local pass means today: every selected suite ran at
  the change's head and passed.
- A reader of the run's record can see where each check ran, at which commit, and whether a local failure was a timeout.

## User Stories

- As an agent running `/work-on` on a change to a shared coordinate script, I
  want verification to finish with a verdict on every suite the change selects,
  so that I can open the pull request instead of ending at `done_blocked`.
- As an agent whose local map command was stopped or failed only on load
  timeouts while hosted CI passed the same checks at the same head, I want a
  named route that uses the hosted result, so that I neither rerun the same
  hour nor go back to implementation for nothing.
- As an agent whose local run found a real assertion failure, I want to be sent
  back to implementation as today, so that a hosted pass never hides a failure I
  can reproduce.
- As a coordinator or reviewer, I want the run's record and its pull request to
  say which checks ran locally, which were settled by hosted CI and at which
  commit, and which local failures were timeouts, so that I can trust the
  verdict without rerunning it.
- As an agent running `/execute`, I want each issue's verification to have the
  same route, so that a plan whose issues touch shared scripts can finish.

## Requirements

The requirements name one route, called here the hosted-of-record route: a
named step in the `verification` state by which a run counts hosted CI results
as the record for a map check that couldn't be settled locally. How the step is
built is the design's to decide; what it must do is below.

Terms used throughout. A check is one map command (a map row run for one
skill, for `check-skill`). Each check's local outcome is one of those R4 lists.
A check *failed* when R4 records it as failed; that is what "assertion failure"
means here. A check is *timed out* when R4 records either timeout outcome.

### Functional

- **R1. When the route is open.** The route is open for a run at `verification`
  when every check in its map result passed or timed out, at least one timed
  out, and every timed-out check's map row declares hosted jobs (R5). Any other
  result (a failed check, a not-started command, or a command the supervisor flagged as runaway, a
  supervisor error, a dirty tree, a missing or bad map) keeps today's handling,
  and the route is closed. Checks that passed locally stay passed locally; the
  route covers only the timed-out checks, each on its own declared jobs.
- **R2. Hosted coverage, not stitching.** A timed-out check is covered only
  when the hosted jobs declared for its row, taken together, executed every
  suite that check can select, at the change's head commit. Local results never
  fill a gap in hosted coverage, and no subset of the declared jobs counts. The
  selection's merge-base doesn't enter the hosted match; only the head commit
  does.
- **R3. Nothing passes unrun.** A suite or job that was not started, was stopped
  before it finished, was skipped (for example by a workflow's path filter), or
  whose result can't be read counts as not run, and no route counts it as
  passed.
- **R4. Timeout is told apart from failure.** The verification result records,
  for each check, one of: passed; failed; timed out at its limit (the
  supervisor stopped it); or timed out inside the command, which counts only
  when the map row declares how such a timeout reads in its output and every
  failure the output reports matches that declaration. A row with no
  declaration can time out only at its limit. For `check-skill.sh` the result
  also lists the suites that finished and passed, finished and failed, were
  still running, and never started; a stopped run with a finished-failed suite
  is recorded as failed.
- **R5. Declared hosted jobs.** A map row may declare the hosted CI jobs whose
  success covers it, each with the set of suites the job runs (for `check-skill`, the suites; for
  any other row, the row's command itself). The declaration
  is part of the repository, and a test checks that the declared jobs' suite
  sets together contain every suite the row can select.
- **R6. Reading hosted results.** For each declared job of a covered check, the
  run reads the job's latest attempt at the head commit. A job that is pending, queued or has no attempt yet at that commit is waited
  for (R15). A job whose latest attempt concluded anything other than success
  (cancelled, failure, skipped, timed_out, neutral, action_required, stale) or
  whose result can't be read refuses the check. A refusal names every
  refusing job and the commit.
- **R7. Refusal and failure.** A refused route leaves the run at
  `verification`, where the agent may submit another value the state offers
  (today `blocked`). A failed check routes the run to `implementation` as
  today, whatever hosted CI says.
- **R8. In place.** A run started with `VERIFICATION=local` can take the route
  at `verification` without its session being re-initialized. A run started
  with `VERIFICATION=hosted-ci` never enters `verification` and is unaffected.
- **R9. Chosen and recorded.** The agent takes the route by submitting a named
  value with a reason; no tick takes it unless that value was submitted, and a
  submission without a reason is refused. The run's koto record names, for each
  covered check, the reason, the declared jobs, the head commit and each hosted
  run's identifier. The pull request body carries one line per covered check
  with the check's id, the head commit and the hosted run links, and the
  PR-body gate refuses a body that lacks a line for a check the record names.
- **R10. Every entry point.** `/work-on` and every issue run `/execute` launches,
  in each of its PLAN modes, get the same route under the same conditions.
- **R11. Full selection stays full.** No route samples, skips or narrows a
  check's selection to fit the budget.
- **R12. A same-head rerun stays a separate choice.** Where the template also
  offers a rerun of a timed-out result at the same head (the design in
  shirabe#1881), both are offered at the same point and neither is a
  precondition for the other.

### Non-functional

- **R13. Cap kept.** The 3,600 s maximum per map command and the 7,200 s
  whole-run budget stay as they are.
- **R14. One local budget at most.** A run spends at most one local budget on a
  check at a given head and merge-base before the route is open to it.
- **R15. Bounded waiting.** A covered check counts as passed only once every
  declared job has concluded success at the head commit. Until then the run
  can't reach a ready pull request. The wait is measured from the time the
  record says the route was taken; if any declared job is still pending or has no attempt more than
  120 minutes after it, the run ends at `done_blocked` with a reason naming the
  pending jobs and the commit. The wait starts after the local run has ended
  and doesn't count against the 7,200 s whole-run budget. A new head commit
  voids the route: hosted results for an earlier commit never count for a later
  one, and the new head enters `verification` afresh.
- **R16. Unrelated outcomes unchanged.** Runs whose checks finish inside the
  budget, runs with a failed check, and runs started with hosted CI
  verification behave exactly as today.

## Acceptance Criteria

Each criterion is a template or script test over a fixture verification result
and fixture hosted-job results, with the wait clock set by the test; none needs
a real suite run.

- [ ] `check-skill` timed out at its limit, every finished suite passed, both
      declared jobs' latest attempts at head concluded success: the route is
      taken with a reason, the run reaches `pass_counting`, and the record names
      the reason, jobs, commit and run ids. (R1, R6, R9)
- [ ] The same, with one declared job concluded cancelled, failed or skipped,
      or unreadable: the route is refused, the run stays at `verification`, and
      the refusal names that job and the commit; with two such jobs it names
      both. (R3, R6, R7)
- [ ] A job whose first attempt failed and whose latest attempt at head
      succeeded is accepted; the reverse is refused. (R6)
- [ ] One check timed out and another failed: the run reaches
      `implementation` and the route value is refused. A stopped `check-skill`
      run with one finished-failed suite is recorded as failed and does the
      same. (R1, R4, R7)
- [ ] One check passed locally and another timed out with its jobs green: the
      run reaches `pass_counting` and the record shows the first as local and
      the second as hosted. Two timed-out checks need both covered; one covered
      and one refused is refused. (R1, R2)
- [ ] A timed-out check whose row declares no hosted jobs, and a result with a
      not-started command, a supervisor error or a dirty tree: the route is
      refused and today's outcome follows. (R1, R16)
- [ ] A command that exited non-zero with output matching only its row's
      declared timeout form is recorded as timed out inside the command; the
      same output plus one other failure is recorded as failed; the same output
      from a row with no declaration is recorded as failed. (R4)
- [ ] The result written for a stopped `check-skill.sh` lists finished-passed,
      finished-failed, running and not-started suites, and their counts add up
      to the selection. (R4)
- [ ] The coverage test fails when a declared job's suite set drops one suite
      the row can select, and passes for the real declaration covering every
      coordinate suite on disk at the time it runs. (R2, R5, R11)
- [ ] A command recorded as timed out inside the command (and no failed check)
      opens the route the same way a limit timeout does. (R1, R4)
- [ ] Two fixtures with the same head and different merge-bases, and the same
      green hosted jobs, both reach `pass_counting`. (R2)
- [ ] A declared job with no attempt at head when the wait ends refuses the
      route, naming the job and the commit; after any refusal the run still
      accepts `blocked`. (R6, R7)
- [ ] While a declared job is pending, the step that marks the pull request
      ready refuses; once it concludes success, that step goes through. (R15)
- [ ] A route taken at one head, followed by a new commit, records no pass for
      the new head from the earlier hosted runs. (R15)
- [ ] The PR-body line for a covered check carries the check id, the head
      commit and one link per declared job; a line missing any of them is
      refused. (R9)
- [ ] The selection recorded for a check taken by the route equals the
      selection `check-skill.sh --changed --list` prints for the same diff.
      (R11)
- [ ] A session started with `VERIFICATION=local` takes the route without being
      re-initialized. (R8)
- [ ] A timed-out result with no route value submitted is never moved past
      `verification` by a tick; a route value with an empty reason is refused.
      (R9)
- [ ] An issue run launched by `/execute` in `single-pr`, `coordinated` and
      `multi-pr` modes reaches the same next state and writes the same record
      fields as `/work-on` on the same fixtures. (R10)
- [ ] The map loader still rejects a `timeout_secs` above 3,600, and the
      whole-run budget is still 7,200 s. (R13)
- [ ] After one local timeout of a check at a head and merge-base, the next
      entry into `verification` at the same pair offers the route without
      starting that check locally. (R14)
- [ ] A declared job pending at 119 minutes after the route was taken leaves the
      run waiting; once more than 120 minutes have passed the run ends at `done_blocked` with a reason
      naming the job and commit. (R15)
- [ ] Hosted success at a commit older than the head is refused. (R15)
- [ ] A PR body missing the line for a check the record names is refused by the
      PR-body gate; with the line it passes. (R9)
- [ ] Whichever of this route and the shirabe#1881 rerun lands second carries a
      test that a timed-out result accepts either value first. (R12)
- [ ] The existing verification-state tests for in-budget passes, failures and
      the hosted CI entry route pass unchanged. (R16)

## Out of Scope

- Narrowing which suites `check-skill.sh --changed` selects for a shared-script
  change (shirabe#1934). It makes the cap bite less often; these requirements
  hold for any selection.
- Raising or removing the 3,600 s maximum or the 7,200 s whole-run budget.
- A general override for a real failure that isn't the change's fault
  (shirabe#1098). Only timeouts qualify here.
- The rerun itself (shirabe#1855, designed in shirabe#1881). R12 is the only
  requirement about it.
- Holding verification entry for a shared test slot (shirabe#1477).
- Runs already in flight, which pick up the route only once it is released and
  installed.

## Known Limitations

- Hosted CI runs only for a pushed commit, and shirabe's coordinate workflows
  run on pull requests. A run taking the route may therefore have its hosted
  results read after its pull request opens as a draft. R15 keeps that pull
  request from being ready until they are read; where in the template the read
  happens is the design's call.
- The coordinate workflows run every suite, not the selection, so they satisfy
  R2 by containing it. A check whose suites no hosted job runs can't use the
  route.
- The 120-minute wait in R15 sits above the slowest hosted job seen so far (the
  macOS skill gate at about 66 minutes); a slower job would need the value
  revisited.
