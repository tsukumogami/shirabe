---
schema: prd/v1
status: In Progress
problem: |
  A /work-on run spends most of its time in review panels, fixed stops,
  verification and test accounting, and a small share writing code. The
  review level resolves to full on almost every change, a fix round after
  done starts over with a full panel and a branch-wide suite run, the same
  suites run locally and then again in hosted CI, and /execute runs
  independent plan steps one after another.
goals: |
  A small, contained change reaches a ready pull request with review and
  verification sized to it, a fix round redoes only what the fix touched,
  every stop left in the run can change its outcome, and independent plan
  steps progress together. Large and risky changes keep every check that has
  caught a real defect, and each trim is measured against a size-normalized
  baseline so process cost can be told apart from bigger issues.
absorbed:
  - docs/briefs/BRIEF-lighter-work-on-runs.md
---

# PRD: Lighter work-on runs

## Status

In Progress

Absorbed [BRIEF-lighter-work-on-runs](docs/briefs/BRIEF-lighter-work-on-runs.md); carried in Absorbed Brief.

Amended on 2026-11-21, before execution: measurement now rides on koto's
public workflow signals rather than a shirabe report (R1 to R4), each trim is
judged against concurrent opt-out runs, and the experiment defaults (R19,
R20) are withdrawn.

## Absorbed Brief

The feature exists because a /work-on run's cost no longer tracks the
change it carries. Writing the code is a small share of a run; review
panels, fixed stops, repeated verification and test accounting take most
of it, and they cost the same for a two-line test fix as for a
thousand-line step. Plan steps under /execute queue behind each other even
when nothing links them.

The outcome is that the agent running /work-on, and the person waiting on
its pull request, see a small contained change finish with review and
verification sized to it, a fix round cost what the fix costs, and a risky
change keep every check that has caught a real defect. Independent plan
steps progress together, and a maintainer can read why each remaining
check stays.

Five journeys frame it: a small fix, a risky template change, a fix round
after done, a plan with independent steps, and a maintainer deciding
whether a check stays (the User Stories below). The boundary keeps the
multi-session operating model, the milestone Done rule, CI workflow
definitions and the coordinator skill outside, and plans rather than
implements (Out of Scope below).

## Problem Statement

`/work-on` takes one known unit of work to a ready pull request, and
`/execute` drives a plan's units through it. Both have grown heavy in a way
that doesn't track the size or risk of the change.

The work-on koto template went from 28 states and 21 gates (shirabe 0.19.1)
to 52 states and 78 gates on main. The state count isn't what costs: on 567
completed runs recorded between 2026-10-09 and 2026-11-21, median working time stayed between one hour
and an hour and a half while the template grew from 36 to 45 states, then
roughly doubled from the end of October and doubled again in the second week
of November. Transitions and gate evaluations per run grew about 15% over
the same period. The growth sits in what the review, verification,
pass-counting and CI states do on each visit, and in a run now spanning two
or three sessions where it used to span one. On observed runs the three
review panels take about 40% of active time, pre-implementation stops about
a quarter, verification and pass counting about a sixth, and implementation
under a tenth.

Reading the source and history behind those figures gives five mechanisms:

1. **Review does not scale with the change.** The floor rules
   (`skills/work-on/references/review-level-rules.tsv`) put any test path at
   `standard` and any edited test line at `full`. Almost every code change
   ships with a test, so a two-line test fix gets the same seven seats as a
   step of thousands of lines. `light` is reachable only when every changed
   path is documentation, and documentation runs skip the level check.
2. **Work is repeated.** Since PR #1327 a fix after `done` runs as a fresh
   work-on session, up to three per run. A fresh session has no verdict
   history, so its first panel round is a full one, and its verification
   selects suites against the merge-base, so it reruns the whole branch's
   suites for a one-line fix. Edited-test acceptance is checked at
   `pass_counting`, again at `pr_precheck`, and again at `ci_pass_counting`.
   Local verification runs suites that hosted CI then runs again at the same
   head, and `ci_monitor` waits for every check whether or not the changed
   paths reach it.
3. **Some stops always get the same answer.** `issue_type_routing` is
   answered `code` on essentially every run. `pre_pr_evidence` is answered
   "nothing found / not applicable", and its four gates repeat ones
   `finalization` already passed. `fix_determination` takes a second tick
   because koto resolves a tick's routes with the variable values the tick
   started with. The up-front review-level choice is overruled by the facts
   floor whenever it differs.
4. **Experiments and telemetry sit in the default path.** The offload canary
   and the rule-distance probe add eight states and their gates to every run,
   enrolled or not. Shadow grading of document criteria waits up to 180
   seconds per jury round and nothing reads its answers.
5. **Plan steps queue.** Since shirabe 0.32.0 `/execute` runs steps strictly
   in PLAN order even when `waits_on` would let two start together, and a
   default plan details only its first two steps, so the owning session must
   rewrite each later step before it can start.

Some of the November rise may be larger issues rather than heavier process.
The run records the size facts needed to tell the two apart, but nobody has
yet compared runs normalized by size.

## Goals

The agent running `/work-on`, and the person waiting on its pull request,
see the run's cost track the change (the outcome in Absorbed Brief). A change
within the light cap and outside the risky path classes gets one reviewer,
one authoritative test run and no constant-answer stops. A change in the
middle band keeps the six-seat `standard` panel. A change over the full
floor, or one with a path in the ci, security, template or engine class,
keeps the full panel. A fix round costs what the fix costs. Independent plan steps run together. Each
trim lands with a before and after figure normalized by diff size, and each
check that remains has a written reason.

## User Stories

- As an agent running `/work-on` on a 12-line change to one script and its
  existing test, I want the run to route itself, review at `light` and run
  the suites once, so that a small fix gets one reviewer seat instead of seven and
  one suite run instead of two.
- As an agent working a 300-line change to a koto template and two gate
  scripts, I want the full panel to stay while constant-answer stops and
  experiment detours go away, so that it keeps all seven seats and loses only the
  stops whose answer never varied.
- As an agent taking a fix round after `done` on a one-line fix, I want the
  round to review only the fix diff and verify only the suites it reaches,
  so that one reviewer's finding doesn't cost a second full run.
- As an agent running `/execute` on a plan whose steps 2 and 3 both wait only
  on step 1, I want both to start once step 1 lands, so that independent work
  doesn't wait in a queue.
- As a maintainer deciding whether a check stays, I want each state added
  since 0.19.1 to carry a recorded keep-or-cut verdict and its evidence, so
  that I can answer from the record instead of reconstructing old pull
  requests.
- As the owner judging whether the trims worked, I want per-visit time
  normalized by diff size before and after each change, so that a faster
  median isn't just smaller issues.

## Requirements

The numbers these requirements use, in one place:

| Term | Value |
|------|-------|
| light cap | at most 200 changed lines and at most 5 changed files |
| full floor (unchanged) | more than 400 lines, more than 12 files, or a ci, security, template or engine path |
| middle band | above the light cap and at or below the full floor, outside the full classes: floors at `standard`, as today |
| fix-round full-round size | more than 200 lines in the fix diff (the retry-lap threshold `panel-scope.sh` already uses) |
| light audit | sessions whose name hashes (SHA-256) to 0 mod 10 |
| audit bound | more than 3 misses in the 30 most recent audited light runs |
| step concurrency | default 2, from 1 (today's serial order) to 6 |

Terms:

- A **gather** is one evaluation of the review-level facts at a head.
- A command's **hosted twin** is a `hosted` entry for that command in the
  verification map, naming a workflow and job.
- The **engine class** is the rules file's class for gate scripts and the
  scripts that open a workflow session; "gate scripts" in this PRD means
  that class.
- A template's **compatibility file** is the `<template>.compat.json` beside
  it, whose gate digest is a hash over the scripts the template's gates
  call.
- A **fix-round base** is the head of the parent run when it reached `done`.
- A **miss** is an audited light run whose full panel blocked at a head the
  light seat passed.
- A **trim** is one requirement below that removes or skips work.

### Measurement

Measurement rides on koto's public workflow signal contract
(`docs/reference/signal-contract.md` in koto), which already carries each
visit's state and duration, each run's result, its configuration version
(template name and hash) and the change it opened. This feature adds no
shirabe-side store, report or dashboard; the numbers are read through
whatever backend the team sends the signals to.

- **R1.** Each run's change size (lines, files and path classes at its last
  review-level gather) and, for a fix round, the run it continues reach the
  workflow signals, recorded by a script or by koto and never typed by an
  agent. Both are additions to the signal contract, proposed to koto, which
  owns it.
- **R2.** Until the contract carries them, the same facts stay readable in
  the session: `review_facts.json` keeps every gather instead of the last
  (lines, files, classes, tests changed, tests edited, criteria changed,
  unclassified, floor, rules fired, head), and a fix round records the run
  it continues.
- **R3.** Whether the late-October and mid-November rise is process or
  larger issues is answered by reading visit durations by size band and
  configuration version from the signals, as a measurement reading, not as a
  document this feature commits.
- **R4.** Each trim is judged against concurrent runs that set its opt-out,
  not only against an earlier period, and its pull request carries a
  recorded before-and-after decision on the figure its PLAN issue names.

### Repeated work

- **R5.** A fix round after `done` inherits the parent run's panel verdicts
  and reviews only the fix diff, the same way a retry lap inside one run
  does. A fix diff over the fix-round full-round size plans a full round.
- **R6.** A fix round's verification selects commands from the paths the
  round changed since the fix-round base. A command the parent ran and
  passed that no path
  changed in the round selects reports the parent's result instead of
  running. A command the parent failed or never finished runs again.
- **R7.** Edited-test acceptance is judged once per head. `pr_precheck` and
  `ci_pass_counting` check that the acceptance's head is still the head and
  spawn no acceptance seat when it is; a new commit after the acceptance
  holds as it does today.
- **R8.** When every command the map selects has a hosted twin and no
  changed path is in the template or engine class, the run uses hosted CI
  as its build of record by default, with no typed reason, and the pull
  request body records that choice. A failing hosted twin routes the run
  back to `implementation`. Otherwise local verification runs as today.
- **R9.** `ci_monitor` waits on the hosted twins of the selected commands
  plus the checks the verification map lists as always required. A check
  outside that set doesn't hold the run; when it fails, the run names it in
  a pull request comment. The always-required list is a new key in the
  verification map, empty unless a repository fills it.

### Review sized to the change

- **R10.** A change within the light cap, with no ci, security, template or
  engine path, no acceptance criteria changed and no unclassified path,
  floors at `light`, even when it touches test, executable or instruction
  paths. The middle band floors at `standard`.
- **R11.** An edited test no longer floors the run at `full` on its own. It
  still does when the edited test is a fix's reproducing test whose content
  changed after the revision its red was recorded at.
- **R12.** A koto template's compatibility file leaves the template class
  only together with a test that fails when any script the template's gate
  digest covers is missing from the engine class. With both in place, a
  change to such a script floors at `full` whether or not the
  compatibility file is in the diff.
- **R13.** The light seat's verdict can be `escalate`. An escalation raises
  the level to `standard` and sends the run back through the level check,
  so the next panel at that head is the larger one.
- **R14.** A light run in the light audit also runs the full panel at the
  same head and records whether it was a miss. On a miss the run follows the
  full panel's verdict and takes its fix lap. Whether the run was a miss is
  recorded by `review-round.sh` from the panels' recorded verdicts, as a
  koto decision, so it reaches the signals without the agent reporting it.
  When more than 3 of the 30 most recent audited light runs are misses, or
  any one miss is a security or correctness finding, a maintainer lowers the
  light cap to 40 lines and 3 files by a pull request to the rules file.
- **R15.** The run chooses its review level from the facts. The up-front
  agent choice and its stop are removed. A coordinator's bound still applies:
  a facts floor above the ceiling still raises the level and still logs a
  breach.

### Constant-answer stops

- **R16.** `issue_type_routing` advances with no agent submission when the
  decider answers `code`. `docs` and `task` keep their agent answer.
- **R17.** `pre_pr_evidence` is removed. `finalization` already runs its
  four gates, and its two evidence fields move to `finalization`.
- **R18.** When a run enters `fix_determination` with no recorded kind and
  the entry action records one, the same `koto next` call that entered the
  state leaves it: to `reproduce` for a fix, `implementation` for a change.
  The agent's chance to declare a fix moves to `analysis`, which already
  allows it on a return.

### Experiments (unchanged)

- **R19.** Withdrawn. The offload canary and the rule-distance probe already
  do nothing on hosts that aren't enrolled; their defaults belong to the
  work that runs them.
- **R20.** Withdrawn. Shadow grading of document criteria exists to feed
  measurement, so whether it runs by default is the measurement work's call.

### Plan steps

- **R21.** `/execute` starts every plan step whose `waits_on` steps have all
  landed, up to the step concurrency limit, set with a flag on `/execute`.
  A step whose `waits_on` hasn't landed doesn't start.
- **R22.** The agent that finishes a step drafts the PLAN entry of each
  outlined step that waits only on it. The owning session reviews the draft
  and records it as that step's existing step-refine record before the step
  starts, editing it if needed; a step with no recorded review doesn't
  start.

### Keep or cut

- **R23.** The design has one row per work-on state added since 0.19.1,
  with a verdict of keep, trim or cut and its evidence: a pull request or
  issue where the state caught a defect, or "no recorded catch". The list of
  states is the difference between the state names in the 0.19.1 template
  and the current one.

### Non-functional

- **R24.** No change here lowers the floor for a path in the ci, security,
  template or engine class, or for a change over the full floor's size.
- **R25.** Each trim has an opt-out that restores today's behaviour for one
  run, named in its PLAN issue. The opt-out is removed by a later pull
  request once the trim's recorded before-and-after decision (R4) exists. The
  removals in R15 and R17 are exempt: they remove an agent turn whose answer
  never changed the route, and reverting the change restores them.

## Acceptance Criteria

### Measurement

- [ ] A koto issue proposes the change-size and fix-round lineage
      attributes to the signal contract, and the PLAN lists it as a koto
      dependency (R1).
- [ ] A run with two gathers at different heads holds both gathers' facts
      in the session, each with every field R2 lists; a fix round's session
      names the run it continues (R2).
- [ ] Every trim's PLAN issue names the signal figure it expects to move
      (visit duration of named states, seats or sessions per run) and a
      saving in minutes per run (R3, R4).
- [ ] Every trim's pull request carries a recorded before-and-after decision
      comparing runs with and without its opt-out (R4).

### Repeated work

- [ ] A fix round with a 30-line fix diff, whose parent passed every panel,
      spawns only re-verifiers for findings the fix diff touches and no
      first-round seat; a 200-line fix diff still takes re-verifiers only;
      a 201-line fix diff plans a full round (R5).
- [ ] A fix round that changes one file in one skill runs only that skill's
      selected command; the parent's result is reported for every other
      command the parent ran; a fix round that changes a second skill runs
      that skill's command too; a command the parent failed runs again
      (R6).
- [ ] With no new revision after acceptance, `pr_precheck` and
      `ci_pass_counting` pass without spawning an acceptance seat; with one,
      both hold (R7).
- [ ] A change whose selected commands all have hosted twins opens its pull
      request without running them locally and without a typed reason, and
      the body records hosted CI as the build of record; a failing twin sends
      it to `implementation`; a change with one selected command lacking a
      twin, or with a template path, runs local verification (R8).
- [ ] A run whose changed paths select no command for the coordinate skill
      reaches its green edge while a check that only coordinate's paths
      trigger is still pending; a selected command's pending hosted twin
      holds the run; a failing
      check outside the set produces a pull request comment naming it; a
      check the map lists as always required holds the run until it passes
      (R9).

### Review sized to the change

- [ ] Floors for fixtures: 37 lines in one script and its edited test
      gives `light`; 200 lines in 5 files gives `light`; 201 lines gives
      `standard`; 6 files within 200 lines gives `standard`; 37 lines plus
      changed acceptance criteria gives `standard`; 37 lines with an
      unclassified path gives `standard`; 37 lines plus a koto template, a
      ci path, a security path or an engine path each give `full`; 401
      lines gives `full`; 13 files gives `full` (R10, R24).
- [ ] An edited existing test in a 37-line change floors at `light`; the
      same edit to a fix's reproducing test, made after the revision its red
      was recorded at, floors at `full` (R11).
- [ ] The digest-coverage test fails when a script the gate digest covers
      is removed from the engine class; a change to that script without the
      compatibility file floors at `full` (R12).
- [ ] A light seat that returns `escalate` sends the run to the level check,
      and the next panel at that head is `standard` (R13).
- [ ] Over 1,000 generated session names, between 8% and 12% are in the
      light audit, and the same names are chosen on every evaluation; an
      audited light run spawns the full panel and records a miss or not; on
      a miss the run takes a fix lap and `review-round.sh` records a miss
      decision; a run whose full panel passed records a no-miss decision
      (R14).
- [ ] A run with no coordinator bound reaches its first panel with no agent
      stop for a review-level choice; with a ceiling of `standard` and facts
      at `full`, the run reviews at `full` and logs a breach; with facts at
      or below the ceiling, no breach is logged (R15).

### Constant-answer stops

- [ ] A code run passes `issue_type_routing` with no agent submission; a
      docs run still stops there for an answer (R16).
- [ ] The template has no `pre_pr_evidence` state; a run whose
      finalization gates all pass reaches `pr_precheck` with no agent stop in
      between; a run whose summary fails `summary_shape` still holds at
      `finalization` (R17).
- [ ] A run whose fix kind is decided on entry leaves `fix_determination`
      in that same tick, to `implementation` for a change and `reproduce`
      for a fix (R18).

### Plan steps

- [ ] On a plan where steps 2 and 3 wait only on step 1, both steps' start
      events come after step 1's landing and before either's completion;
      with the limit at 1 they run in PLAN order; a step 4 waiting on step 2
      doesn't start before step 2 lands; with three ready steps and the
      limit at 2, two start (R21).
- [ ] When step 1 finishes, step 2's PLAN entry holds a draft by step 1's
      agent, and step 2 starts only after its step-refine record exists; with
      no record, step 2 doesn't start; an owner edit to the draft before
      recording is what step 2 runs against (R22).

### Keep or cut and opt-outs

- [ ] The design has a row for each of the 24 states added since 0.19.1,
      each with a verdict and either a link or "no recorded catch" (R23).
- [ ] Each trim's PLAN issue names its opt-out and a fixture where a run
      with the opt-out set spawns the same seats, runs the same commands and
      enters the same states as the pre-change template for that trim's
      behaviour (R25).

## Out of Scope

- The multi-session operating model: coordinators, merge seats, grant rules
  and session succession (see Absorbed Brief). They add their own waiting,
  but they live outside these two skills.
- When a roadmap milestone counts as Done.
- CI workflow definitions and suite duration. R9 changes what a run waits
  for, not which jobs exist or how long they take.
- The coordinator skill and its workflows.
- The rest of the planning skills' review wiring (review events, document
  checks), and the defaults of the offload canary, the rule-distance probe
  and shadow grading of document criteria (R19 and R20 withdrawn).
- A shirabe-side measurement store, report or dashboard. The numbers come
  from koto's public signals, read in the team's own backend.
- Coarse suite selection inside `check-skill.sh --changed`, which PRs #1875
  and #1940 already narrowed.
- The hosted-of-record route for a timed-out local check (the
  verification-cap-route work in flight). R8 builds on the same map
  declaration and must not conflict with it.
- A koto engine change for the workflow itself. Every trim can be built in
  shirabe on koto 0.37; the only koto work is R1's proposal to the signal
  contract, and one optional engine change the design names for R18.

## Known Limitations

- The light seat doesn't run code. A small change whose defect only shows
  at runtime and isn't covered by its tests can pass `light` where the QA
  seat would have caught it. R14's audit measures how often that happens;
  it doesn't prevent it.
- Size caps are a proxy for risk. A 150-line change to an instruction file
  can change agent behaviour widely. Keeping instruction paths eligible for
  `light` is the most debatable part of R10.
- Deferring to hosted CI moves defect discovery after the pull request
  opens. A hosted failure costs a CI round where a local failure cost a
  local run.
- Concurrent plan steps share a branch in a `single-pr` plan, so two steps
  that touch the same files conflict. R21 helps only where steps really are
  independent.
- Before-and-after comparisons on one change are noisy at the fleet's
  volume; an earlier hand-run comparison of a template change didn't
  reproduce. Comparing against concurrent opt-out runs narrows that but
  doesn't remove it.

## Decisions and Trade-offs

- **Repetition before rules.** The research found that a fix round re-runs a
  full panel and the branch's whole suite set, and that this matches the
  rise in sessions per run better than any template change. R5 to R7 come
  before the review-level rules because they remove work without lowering
  any check. Alternative: lead with the review level, which frees about a
  quarter of runs but lowers review for them.
- **The 11-09 template change is not a cause.** It adds one telemetry call
  per review round. The step at that date is more plausibly the koto floor
  bump it carried, the hosted skill-gate run added days later, and the
  operating-model changes of the same week, or a measurement break in the
  review telemetry it introduced. Reverting it would recover nothing; R3
  is how to confirm.
- **200 lines and 5 files for `light`.** The thresholds 40, 400 and 12 were
  chosen from reading and never tuned. 200 lines is the size under which a
  retry lap already takes a single re-verifier, so the workflow already
  treats it as small. On a sample of 23 recent runs this frees 5 to 8 runs.
  Alternative: a pure size rule ignoring path classes, which would let small
  template and gate-script edits through with one reviewer.
- **Keep `tests_edited -> full` only for a reproducing test.** Edited tests
  already hold at `pass_counting` until an acceptance seat accepts them, and
  the light seat judges each edited test. Rewriting a fix's own red test is
  the case where weakening is most likely, so it keeps the full floor.
- **Audit by sampling, not by blocking.** A one-in-ten full panel on light
  runs costs about a tenth of the saving and gives a miss rate. This closes
  the framing's open question about whether one seat is enough: the answer is
  measured after shipping, with a bound (more than 3 misses in 30) that
  sends the cap back to 40 lines and 3 files.
- **Hosted as build of record only where twins exist.** The verification
  map already declares hosted twins for some commands. Requiring a twin for
  every selected command keeps local verification wherever hosted CI
  wouldn't run the same check, and template and engine changes keep local
  verification because a broken gate script can stall the run before CI
  ever reports.
- **Remove the up-front review-level choice.** Every recent choice that
  differed from the facts floor was overruled by it, so the stop adds an
  agent turn and decides nothing.
- **Remove `pre_pr_evidence` rather than keep a pass-through.** Its gates
  are byte-identical copies of `finalization`'s, kept as a backstop after
  the copy onto `finalization` was made. A pass-through would keep a state
  whose only effect is a second evaluation of the same scripts.
- **No koto dependency.** `fix_determination`'s second tick exists because
  routes read the variable value the tick started with. A command gate runs
  after the state's default action in the same tick, so routing on that gate
  needs no engine change. Making same-tick rebinds visible to routes would
  be cleaner and is listed as optional follow-up.
- **Step concurrency defaults to 2.** One is today's behaviour. Two captures
  most of the gain on plans with a fork after step 1 while keeping branch
  conflicts and host load bounded; six matches the most workers a host has
  been seen to run.
- **Measure through the public signals, not a shirabe report.** The first
  draft added a shirabe report script and a committed report. koto's signal
  contract is the one home for workflow telemetry and already carries visit
  durations and configuration versions; a second channel would hide data
  from the team's own backend. The trims therefore propose the two missing
  facts to the contract and keep them in the session meanwhile.
- **Concurrent comparison over before-and-after.** A single before-and-after
  comparison of a template change has failed to reproduce here. Each trim's
  opt-out gives a control arm running in the same weeks.
- **Experiments left alone.** Turning the canary, the probe and shadow
  grading off by default saves seconds per run and takes data from the work
  that owns them, so R19 and R20 are withdrawn.
