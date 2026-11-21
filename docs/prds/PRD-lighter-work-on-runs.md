---
schema: prd/v1
status: Draft
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
upstream: docs/briefs/BRIEF-lighter-work-on-runs.md
---

# PRD: Lighter work-on runs

## Status

Draft

## Problem Statement

`/work-on` takes one known unit of work to a ready pull request, and
`/execute` drives a plan's units through it. Both have grown heavy in a way
that doesn't track the size or risk of the change.

The work-on koto template went from 28 states and 21 gates (shirabe 0.19.1)
to 52 states and 78 gates on main. The state count isn't what costs: on a
large sample of completed runs, median working time stayed between one hour
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
see the run's cost track the change (the BRIEF's User Outcome). A small
change outside the risky path classes gets one reviewer, one authoritative
test run and no constant-answer stops. A fix round costs what the fix costs.
A large change, or one that touches CI, security, workflow templates or gate
scripts, keeps the full panel. Independent plan steps run together. Each
trim lands with a before and after figure normalized by diff size, and each
check that remains has a written reason.

## User Stories

- As an agent running `/work-on` on a 12-line change to one script and its
  existing test, I want the run to route itself, review at `light` and run
  the suites once, so that a small fix reaches its pull request in a fraction
  of today's time.
- As an agent working a 300-line change to a koto template and two gate
  scripts, I want the full panel to stay while constant-answer stops and
  experiment detours go away, so that the run's time goes to the review that
  matters.
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

### Measurement

- **R1.** A run keeps the size facts of every gather (lines, files, classes,
  tests edited, the floor and the rules that fired), not only the latest, so
  the size at each review visit can be recovered after the run.
- **R2.** A report built from retained run records gives, per template
  version and per size band (lines changed, files changed, path classes),
  the median time per visit of each review, verification, pass-counting and
  CI state, seats spawned, and sessions per run. It joins a run's fix rounds
  to the run.
- **R3.** Each trim below names the report figure it expects to move and by
  how much, and the plan orders the trims by expected minutes saved per run
  over the risk accepted.

### Repeated work

- **R4.** A fix round after `done` inherits the parent run's panel verdicts
  and reviews only the fix diff, the way a retry lap inside one run already
  does, unless the fix diff alone crosses the size that plans a full round.
- **R5.** A fix round's verification selects suites from the paths the round
  changed, and reuses the parent's per-command results for suites whose
  inputs are unchanged at the new head.
- **R6.** Edited-test acceptance is judged once per head. Later states check
  that the head the acceptance covered is still the head, instead of
  re-deciding it.
- **R7.** For each verification command, the run records whether hosted CI
  runs the same check at the same head. When hosted CI covers every selected
  command, the run treats hosted CI as the build of record by default,
  without a hand-written reason, and a hosted failure routes back to
  implementation the way a local failure does. Local verification stays the
  default when any selected command has no hosted twin, and for changes in
  the template and engine classes.
- **R8.** `ci_monitor` waits on the checks relevant to the changed paths:
  the hosted twins of the selected verification commands plus the checks a
  repository marks as always required. A check outside that set that fails
  is reported on the pull request and doesn't hold the run.

### Review sized to the change

- **R9.** A change of at most 200 changed lines and 5 files, outside the ci,
  security, template and engine classes, with no acceptance criteria
  changed and no unclassified path, floors at `light`, even when it touches
  test, executable or instruction paths.
- **R10.** An edited test no longer floors the run at `full` on its own.
  It still floors at `full` when the edited test is a fix's reproducing test
  changed after its red was recorded.
- **R11.** A koto template's compatibility file stops counting as a template
  path only once every script its gate digest covers is itself in the engine
  class, enforced by a test, so a gate-library change keeps its `full` floor.
- **R12.** The light seat can escalate. An escalation raises the level and
  sends the run back through the level check, so the larger panel runs on
  the same head.
- **R13.** A fixed fraction of light runs, about one in ten, chosen
  deterministically from the session name, also runs the full panel. The
  run records whether the full panel blocked where the light seat passed.
  If that miss rate goes over the bound the design sets, the size caps in
  R9 go back down.
- **R14.** The run chooses its review level from the facts. The up-front
  agent choice and its stop are removed; a coordinator's bound still applies
  and still logs a breach.

### Constant-answer stops

- **R15.** `issue_type_routing` advances without an agent answer when the
  type is `code`, through the decider it already declares. `docs` and `task`
  keep their agent answer.
- **R16.** `pre_pr_evidence`'s checks fold into `finalization`, which
  already runs them. The state is removed, or reduced to a pass-through with
  no agent stop.
- **R17.** A fresh fix determination routes in the tick that made it. If
  that needs koto to route on a value written during the same tick, the
  requirement is filed against koto and listed as a dependency, and the
  shirabe side waits for it.

### Experiments off the default path

- **R18.** The offload canary and the rule-distance probe are off by
  default. A run without an opt-in neither enters their states nor runs
  their gates, and a host or run that opts in gets today's behaviour.
- **R19.** Shadow grading of document criteria runs only when opted in. A
  run without the opt-in makes no grading call and waits on nothing.

### Plan steps

- **R20.** `/execute` starts every plan step whose `waits_on` steps have
  landed, up to a concurrency limit the run states, instead of strictly in
  PLAN order.
- **R21.** The agent that finishes a step details the next outlined step
  that waits on it, so the owning session no longer rewrites each step
  before it can start. The owner still reviews the detail before that step
  starts.

### Keep or cut

- **R22.** Every work-on state added since 0.19.1 carries a keep, trim or
  cut verdict in the design, with the evidence used and, for a keep, the
  defect class it catches.

### Non-functional

- **R23.** No change in this PRD lowers the review floor for a path in the
  ci, security, template or engine class, or for a change over 400 lines or
  12 files.
- **R24.** Every trim keeps a way to get today's behaviour back for one run
  (a flag or a variable) until its report figure has been read after it
  ships.

## Acceptance Criteria

- [ ] A completed run's records hold the size facts of each gather, and a
      run with two gathers at different heads shows both (R1).
- [ ] The report prints, for at least two template versions, per size band,
      median minutes per visit of `scrutiny`, `review`, `qa_validation`,
      `verification`, `pass_counting` and `ci_monitor`, seats spawned and
      sessions per run, with fix rounds joined to their run (R2).
- [ ] Each issue in the PLAN names the report figure it expects to move and
      its expected saving in minutes per run (R3).
- [ ] A fix round whose fix diff is under the full-round size spawns only the
      re-verifiers the fix diff needs, not a full first round (R4).
- [ ] A fix round that changes one file in one skill runs only that skill's
      selected suites, and a suite whose inputs are unchanged reports the
      parent's result instead of running (R5).
- [ ] With no commit after acceptance, `pr_precheck` and `ci_pass_counting`
      pass without spawning an acceptance seat; with a commit after it, they
      hold (R6).
- [ ] A run whose selected commands all have hosted twins opens its pull
      request without running them locally and without a typed reason; a
      failing hosted twin sends it back to `implementation` (R7).
- [ ] A run whose changed paths reach no coordinate suite reaches its green
      edge while a coordinate-only check is still pending or failing, and
      the pull request body names that check (R8).
- [ ] A 37-line change to one script and its existing test lands at `light`;
      the same change plus a koto template edit lands at `full` (R9, R23).
- [ ] An edited test alone in a small diff doesn't raise the floor to
      `full`; an edit to a fix's reproducing test after its red does (R10).
- [ ] A change to a gate-library script that a template's gate digest
      covers floors at `full` with or without the compatibility file in the
      diff (R11).
- [ ] A light seat that escalates sends the run to the level check, and the
      next panel at that head is the larger one (R12).
- [ ] For a fixed set of session names, the audited one-in-ten light runs are
      the same on every evaluation, and each records whether the full panel
      blocked (R13).
- [ ] A run with no coordinator bound reaches its first panel without an
      agent stop at a review-level choice (R14).
- [ ] A code-typed run passes `issue_type_routing` with no agent submission;
      a docs-typed run still stops there (R15).
- [ ] A run with clean finalization output reaches `pr_precheck` with no
      agent stop between them (R16).
- [ ] A run whose fix kind is decided on entry routes to `implementation` or
      `reproduce` in that same tick, or the PLAN lists the koto issue this
      waits on (R17).
- [ ] On a host with no opt-in, a run enters none of the canary or probe
      states; with the opt-in file present, it does (R18).
- [ ] A jury round with no opt-in makes no grading call; with it, the
      grading runs as today (R19).
- [ ] On a plan with steps 2 and 3 both waiting only on step 1, both start
      before either finishes (R20).
- [ ] When step 1 finishes, step 2's PLAN entry is detailed by step 1's agent
      and the owner's review is recorded before step 2 starts (R21).
- [ ] The design has a row for each state added since 0.19.1 with a verdict
      and its evidence (R22).
- [ ] Each trim's opt-out restores today's behaviour for one run (R24).

## Out of Scope

- The multi-session operating model: coordinators, merge seats, grant rules
  and session succession (the BRIEF's out-list). They add their own waiting,
  but they live outside these two skills.
- When a roadmap milestone counts as Done.
- CI workflow definitions and suite duration. R8 changes what a run waits
  for, not which jobs exist or how long they take.
- The coordinator skill and its workflows.
- The rest of the planning skills' review wiring (review events, document
  checks). R19 takes only shadow grading off the default path.
- Coarse suite selection inside `check-skill.sh --changed`, which PRs #1875
  and #1940 already narrowed.
- The hosted-of-record route for a timed-out local check (the
  verification-cap-route work in flight). R7 builds on the same map
  declaration and must not conflict with it.

## Known Limitations

- The light seat doesn't run code. A small change whose defect only shows
  at runtime and isn't covered by its tests can pass `light` where the QA
  seat would have caught it. R13's audit measures how often that happens;
  it doesn't prevent it.
- Size caps are a proxy for risk. A 150-line change to an instruction file
  can change agent behaviour widely. Keeping instruction paths eligible for
  `light` is the most debatable part of R9.
- Deferring to hosted CI moves defect discovery after the pull request
  opens. A hosted failure costs a CI round where a local failure cost a
  local run.
- Concurrent plan steps share a branch in a `single-pr` plan, so two steps
  that touch the same files conflict. R20 helps only where steps really are
  independent.
- The report in R2 can only read runs whose records were retained.

## Decisions and Trade-offs

- **Repetition before rules.** The research found that a fix round re-runs a
  full panel and the branch's whole suite set, and that this matches the
  rise in sessions per run better than any template change. R4 to R6 come
  before the review-level rules because they remove work without lowering
  any check. Alternative: lead with the review level, which frees about a
  quarter of runs but lowers review for them.
- **The 11-09 template change is not a cause.** It adds one telemetry call
  per review round. The step at that date is more plausibly the koto floor
  bump it carried, the hosted skill-gate run added days later, and the
  operating-model changes of the same week, or a measurement break in the
  review telemetry it introduced. Reverting it would recover nothing; R2
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
  the BRIEF's open question about whether one seat is enough: the answer is
  measured after shipping, with a bound that reverses R9.
- **Hosted as build of record only where twins exist.** The verification
  map already declares hosted twins for some commands. Requiring a twin for
  every selected command keeps local verification wherever hosted CI
  wouldn't run the same check.
- **Remove the up-front review-level choice.** Every recent choice that
  differed from the facts floor was overruled by it, so the stop adds an
  agent turn and decides nothing.
- **Experiments default off, not removed.** Their designs may still want
  data. Off by default keeps the code and moves the cost to runs that opt
  in.
