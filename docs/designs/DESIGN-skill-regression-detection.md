---
schema: design/v1
status: Proposed
problem: |
  shirabe wants a maintainer to learn that a change broke a skill, including a
  hand-off from one skill to another, before the release carrying it ships, and
  wants a release to stop on a skill's pass-rate drop. The only mechanism
  today runs graded evals inside `/shirabe:release`, which costs model tokens
  the owner has ruled shirabe doesn't have, so every release since v0.24.0 has
  skipped it and nothing else catches a regression. No hand-off case runs
  without a model, and nothing makes a new skill add one.
decision: |
  No release, pull request check or schedule calls a model. A new
  script-graded case kind in `evals.json` (`grader: script`) checks each
  hand-off with no model, through one shared `scripts/check-handoff.sh`; the
  harness, the free pull request gate and the release all run these cases,
  and the shape check derives a skill's hand-off targets from its koto
  templates so a new skill can't merge without one. Graded runs happen only
  when a maintainer chooses to start one: one run of the changed skill's
  release subset on Sonnet, paid from that person's own Claude plan, committed
  as an add-only record under `evals/records/<skill>/` and bound to a hash of
  the files the skill loads; whether the eval rulings allow such a run is
  waiting on the owner, and the script-graded half stands either way. The
  release reads those records with git, stops
  at exit 5 on an aggregate drop over 0.05 or a newly failing case, asks one
  batched question for changed skills with no current record, and stops
  outright on a failing script case.
rationale: |
  The owner's rulings leave one place a graded run can happen: a person
  choosing to spend their own plan's tokens on the skill they just changed.
  Everything that runs unattended has to be free, so the hand-off coverage
  that must hold for every skill moves to deterministic cases, which the
  existing engine suites already make cheap to build. Committing records
  beside the change makes them reviewable, needs no network at release, and
  survives squash merge through the content hash rather than a commit SHA.
  Splitting drops, unmeasured skills and script failures into separate checks
  keeps a routine confirmation from waving through a real drop. The cost is
  that graded coverage depends on people choosing to measure, which the
  release makes visible on every run instead of hiding.
---

# DESIGN: Skill regression detection without paid release evals

## Status

Proposed

## Context and Problem Statement

shirabe wants a maintainer to learn that a change broke a skill's behaviour,
including a hand-off from one skill to another, before the release that
carries the change reaches users. That has to hold for every skill, including
skills added later. Two observations count as evidence that it does:

1. "A maintainer breaks `/deliver`'s hand-off to `/execute` on a branch, runs
   the eval harness on `/deliver`, and sees its hand-off case fail; doing the
   same to a skill added since this item was written gives the same result."
2. "The same maintainer changes one skill so one of its evals regresses, runs
   `/shirabe:release`, and sees the release stop on that skill's pass-rate
   drop until a person confirms it."

Neither says where graded evals run or how many runs a skill gets. This
design answers both.

Most of the parts exist. Every model-invocable skill has an
`evals/evals.json`, 20 skills in all, and `/deliver` and `/execute` have
hand-off cases. `scripts/run-evals.sh` drives the skill-creator plugin
through one nested `claude -p` session per run, which starts an agent per
case and grades every case with a model. `/shirabe:release` runs the commands
a repository declares under `## Release checks`, with an exit-5
confirm-and-rerun protocol, and shirabe's extension declares
`scripts/release-eval-check.sh`. That check runs the release subset of every
skill changed since the last tag and compares each pass rate, through
`scripts/lib/eval-pass-rates.py merge`, with the newest earlier release's
`eval-pass-rates.json` asset. `docs/designs/current/DESIGN-evals-at-release.md`
describes it. v0.24.0 carries such an asset.

No release since then has one. Every graded case costs model tokens. The
cost spike (`docs/spikes/SPIKE-release-eval-cost.md`) priced a tier-1 case at
about $0.29 plus grading, a tier-2 case at about $3, and the orchestrating
session at $4.34 to $6.27 per skill run, which put a five-skill release at
about $1,200, or about $90 after four cuts. The owner has ruled that shirabe
has no budget for evals at release: "you can skip evals for the release of
shirabe ... fixing these evals is a high priority item though, we cannot
afford to run these many evals, it's prohibitively expensive" (2026-10-15),
and releases never run evals because "we dont have budget for that"
(2026-10-23). So the release check is skipped, and nothing else catches a
regression before it ships:

- `scripts/scheduled-evals.py` has a $50 weekly fallback budget, but nothing
  schedules it and the owner hasn't approved it.
- `.github/workflows/run-evals.yml` is manual-only, bills an API secret, and
  can't grade on branches (shirabe#612).
- The deterministic engine suites for `/deliver` and `/execute` run in CI for
  free, but they use stand-in children, so a change to `/execute`'s outcome
  words passes them, and the harness shows no hand-off case for them.
- Nothing obliges a new skill that hands off to another to test the hand-off.

This design settles how a regression becomes visible to the maintainer who
caused it, and how a release stops on a pass-rate drop, without any release
running a paid eval.

## Decision Drivers

- No shirabe release makes a model call to grade a skill, dry runs and
  confirmation re-runs included. This is a requirement.
- No automated gate (pull request CI, a schedule) spends model tokens the
  owner hasn't budgeted.
- A hand-off break in `/deliver` shows up as a failing hand-off case when the
  maintainer runs the eval harness on `/deliver`, and the same holds for a
  skill added later without anyone remembering to add the case.
- A release stops on a skill's pass-rate drop until a person confirms it.
- Every run states its cost driver and who pays it.
- Reuse what exists: the release-check hook and its exit-5 protocol, the
  comparison logic in `eval-pass-rates.py`, `check-skill.sh` and the
  deterministic engine suites.
- Release and worker hosts run macOS's bash 3.2; the graded harness needs
  bash 4.
- Single-run noise on an unchanged skill is up to about five points, and one
  regressed case in `/deliver`'s 33 moves its aggregate by about three.

## Considered Options

### Decision 1: Where graded evals run, how many runs a skill gets, and who pays

Every case in `evals.json` today is graded by a model, so every graded run
costs tokens. The comparison logic in `eval-pass-rates.py` needs no model;
what's missing is a source of graded rates that isn't the release.

Key assumptions:
- The owner's rulings cover releases and automated gates, not a run that a
  person chooses to start on their own plan for a skill they just changed.
  This reading is waiting on the owner's answer; "Waiting on the owner" under
  Decision Outcome says what changes if the answer is no.
- A local run bills the logged-in Claude plan, not the API. `run-evals.sh`
  never reads `ANTHROPIC_API_KEY` itself; only the CI workflow injects one.
- The spike's single-run noise of about five points holds for skills it
  didn't measure. Its cost figures are list price, which is notional under a
  subscription.
- `/deliver`'s hand-off case `auto-merged-no-split` grades on a branch when
  run locally. shirabe#612 breaks grading in CI's isolated checkout; whether it
  touches a local run on this case hasn't been checked, because checking costs
  a paid run.

#### Chosen: a maintainer-started run at change time, one fixed shape, committed for the release to read

Graded runs happen only on a maintainer's own host, when they change a
skill's behaviour, on that skill only. They're opt-in: an agent working for
the maintainer may offer the run and state its estimated cost, and never
starts one by default. The release, pull request CI and any schedule run no
graded eval.

The run has one fixed shape, so any two records of a skill compare:
`EVAL_MODEL=sonnet scripts/run-evals.sh --release-subset --no-baseline --runs 1 <skill>`.
A maintainer chasing one case can run that scenario alone, which prints the
case's verdict whatever the aggregate rate does. Repeats are never required.
A person who wants more certainty after a drop may run three times, but that
measurement is recorded under its own comparison key and never clears a drop.

One run, because cost scales linearly with runs, session overhead included,
and three runs would triple the bill to narrow a noise band that the per-case
signal (Decision 3) and a person's confirmation already cover. A noise flip
will sometimes stop a release; that costs a person's attention, not tokens,
which is the trade the rulings force.

`run-evals.sh` gains two guards. It refuses to start with
`ANTHROPIC_API_KEY` exported unless given an explicit flag, and that API path
also needs an owner-set cap in `scheduled-evals.py`'s ledger, so an exported
key can't silently turn a plan-billed run into API spend. And it checks
`BASH_VERSINFO` up front and names bash 4 as a requirement of the
maintainer's host. `scheduled-evals.py` loses its $50 fallback: without an
owner-set cap it runs nothing. `run-evals.yml` stays dispatch-only, and
`check-run-evals.yml` fails if it gains an automatic trigger.

#### Alternatives Considered

- **Graded runs at release time.** The current check, about $90 per
  five-skill release after the spike's cuts and about $1,200 before. Rejected
  because the owner ruled that releases never run evals.
- **Per-PR CI with an API key.** A workflow runs the changed skill's subset
  on every skill pull request, billing an org secret. Rejected because
  push-triggered spend is the unbudgeted automated gate the rulings rule out,
  fix rounds multiply it, and shirabe#612 stops grading in CI for several
  skills. The deterministic suites already catch hand-off breaks on every pull
  request for free (Decision 2).
- **A budgeted schedule.** Wire `scheduled-evals.py` to cron with a weekly
  cap and three runs per changed skill. Rejected because the owner hasn't
  budgeted recurring spend, its results stay on one host, its three-run,
  with-baseline records don't compare with one-run records, and a skill
  changed after the last pass ships with no fresh rate anyway. It stays the
  documented path for unattended runs if the owner ever funds one.
- **No graded runs at all.** Gate only on checks that call no model. Rejected
  as the whole answer because no graded rate would exist for a release to
  stop on, and a deterministic check can't see a change in SKILL.md wording
  that alters what the agent does. Kept as the only automated gate.

### Decision 2: How a hand-off break fails a free case, for every skill

The `/deliver` to `/execute` hand-off lives in three places. `deliver.md`'s
`execute_run` state carries the `exec_leg` request-leg gate (`leg: execute`,
an `expect` list of five outcomes) and one transition per outcome copying
fields off the leg payload; `deliver-execute-leg.sh` builds the hand-over
arguments; and the state's directive tells the agent to invoke skill
`execute` with `--koto-leg=<req>:execute`. `/execute` has to keep its end: it
accepts `--koto-leg`, keeps its template named `execute.md`, assigns only
outcome words in `/deliver`'s `expect` list, and carries the result keys
`/deliver` copies. `deliver-engine_test.sh` walks the routes on real koto but
with stand-in children, so a rename in `execute.md` fails nothing.

Key assumptions:
- `run-evals.sh` can hand a script-only selection to a runner before any
  bash 4 construct runs. If not, the runner is a separate file and nothing
  else changes.
- koto can attach a real `execute.md` session to a `/deliver` leg without
  running `/execute`'s states. If not, the receiving-side check stays static
  (outcome words, result keys, template name), which still catches drift in
  what the two sides expect.
- A templated leg name, such as `coordinate.md`'s `leg: "{{WAIT_LEG}}"`,
  can't be resolved statically, so that skill names its targets on its cases
  and the shape check refuses an undeclared templated leg.

#### Chosen: a script-graded hand-off case kind, with targets derived from templates and enforced by the free gate

`evals.json` gains an optional per-case grader. A case with
`"grader": "script"` carries a `run` command, where exit 0 passes and anything
else fails with the command's output as the reason, and a `handoff` key
naming the target skill. `run-evals.sh deliver` runs these cases first, with
no nested session and no model, and reports them beside the graded ones;
`run-evals.sh deliver --script-only` runs only them, on bash 3.2.
`check-skill.sh` runs the same cases, so the gate and the harness execute one
definition.

Today `check-skill.sh` runs against real skills only as the work-on
verification-map entry, on the worker's host before a pull request opens; CI
runs only the script's own test suite. That isn't enough to stop a merge, so
`check-skill-gate.yml` gains a job that runs `check-skill.sh` on every skill a
pull request changes (by the tree hash in Decision 3, so an edit to a shared
file selects the skills that load it), on Linux and on the macOS bash 3.2
leg. "The pull request gate" in the rest of this design means that job.

Every hand-off case runs one shared command, `scripts/check-handoff.sh <from>
<to>`, which composes what exists instead of adding a second test suite:

1. the caller's existing hand-off routes, by running its engine, leg and
   structure suites under a selector for the target's routes;
2. a rendered-directive check: the state that waits on the target's leg
   renders a directive naming skill `<to>` and `--koto-leg=<req>:<leg>`;
3. a receiving-side contract check: the target template's file name matches
   what the leg accepts, every outcome word assigned on an edge into the
   target's terminal states is in the caller's `expect` list, the target's
   result map carries every key the caller's transitions copy, and the
   target's SKILL.md declares `--koto-leg`;
4. a real attach: `koto init --koto-leg=<req>:<leg>` of the real target
   template against a fresh request, so a refused attach fails the case.

`/deliver` gets two cases (targets `scope` and `execute`), and `/execute`
gets one for `work-on`, where the leg is the child template reference
`assert-child-template.sh` already checks.

For skills added later, `check-evals-shape.py` derives each skill's hand-off
targets from its koto templates (request-leg `leg:` names, `--koto-leg=` in
directives, child template references) and fails when a target has no
script-graded case with that `handoff`. The pull request gate runs the shape
check on every changed skill, a new skill included, so a new skill that hands
off can't merge without its case. `check-skill.sh` for a skill also runs every other skill's
hand-off case whose target is that skill, so a change to `/execute`'s
outcomes fails `/deliver`'s case in `/execute`'s own pull request.

What the script case doesn't catch is the agent's own behaviour at the
hand-off: skipping or rewording the Skill call despite a correct directive,
running `/execute` inline instead of in an agent, submitting
`child_returned` early, relaying `/execute`'s report instead of `/deliver`'s,
and SKILL.md prose that contradicts the directive. The model-graded hand-off
cases (`/deliver` 1, 2, 18, 20 to 21, 30 to 33; `/execute` 4, 62, 63) keep
those, and they run only when a maintainer chooses (Decision 1).

#### Alternatives Considered

- **The existing `*_test.sh` suites as they are.** Free and already in CI.
  Rejected because the harness on `/deliver` shows no hand-off case, the
  stand-in children let an outcome rename in `execute.md` pass, and nothing
  obliges a new skill to add one.
- **Model-graded hand-off cases on a cheap model.** Run the existing hand-off
  cases on Haiku in the gate. Rejected because it spends model tokens in an
  automated gate and its results vary between runs.
- **A static check of SKILL.md text.** Grep each SKILL.md for the skills it
  names and the argument text. Rejected because hand-offs are wired in
  templates: a text match passes a broken gate or a renamed outcome, and
  deriving targets from prose picks up every routing mention.

### Decision 3: How the release gets pass rates and stops on a drop without running a paid eval

`eval-pass-rates.py merge` already does the free part: it compares
measurements taken the same way (models, session model, scenario set, run
count), applies the tolerance, and exits 5 with a
`confirm: RELEASE_CONFIRMED_DROPS=...` line. It can't use maintainer records
today: it treats a missing summary as an infrastructure failure, needs
per-case data the summary doesn't carry, and finds its baseline through a
release-asset walk that stops at ten tags, which from v0.39.0 never reaches
v0.24.0, so every skill would read "no baseline, passes". The release skill's
exit-5 protocol allows one confirmation round per check, under any upper-case
variable name. Pull requests squash-merge, and release tags sit on main.

Key assumptions:
- Script-graded cases fall outside the "no evals at release" ruling, because
  the ruling is about budget and these call no model. If the owner reads it
  literally, the release reads script-case results from CI on HEAD's exact
  SHA instead of running them, and nothing else changes.
- The release host has koto (the attach step in `check-handoff.sh` needs it)
  and tags are fetched. Without either, the check exits 1 rather than
  passing.
- A skill's behaviour files can be listed mechanically: `skills/<name>/`
  minus `evals/` and tests, plus the root `references/`, `scripts/` and
  `koto-templates/` files it names through `${CLAUDE_PLUGIN_ROOT}`. A missed
  file neither selects the skill nor marks its record stale, a gap today's
  `--list-changed` already has.
- The second piece of evidence needs a baseline: a record that matches the
  skill at the last tag, or a seed record of the released content that a
  maintainer pays for before changing it.

#### Chosen: committed add-only records bound to skill content, read for free behind three separate checks

**Records.** Each maintainer run under Decision 1 adds one file,
`evals/records/<skill>/<UTC-timestamp>-<tree12>.json`, committed in the same
pull request as the change. The directory sits at the repository root,
outside every skill's hashed files, so a record never changes its own hash
and committing one isn't a skill change. The file is a `run-evals-summary/v1`
skill entry, which merge's summary reader already takes, plus four fields:
`tree`, a hash over the skill's behaviour files, shared root files included;
`cases`, each case's name and verdict; `producer`; and `cost_usd`. No commit
SHA is trusted, because squash merge discards it; the tree hash survives.

**Free pull request check.** `check-evals.yml`, which needs no model, widens
its paths to `evals/records/**` and the shared root paths. It checks that
records are well formed, that no record is edited, and that a record is
deleted only together with its skill. It doesn't require a record: measuring
stays opt-in.

**Selection.** A skill counts as changed when its tree hash at the last tag
differs from its hash at HEAD. Edits to evals, fixtures or tests alone don't
select it; an edit to a shared file it loads does.

**Baseline and current record.** Everything is read with `git ls-tree` and
`git show` in one python3 process, with no `gh` and no network. The baseline
is the newest record at the last tag whose tree matches the skill's tree at
that tag, falling back to the newest record at the tag measured the same way.
Records are never deleted, so the tag's tree holds every earlier record and
the lookup has no depth cap. The current record is the newest record added
since the tag, whether or not its tree matches HEAD.

**Check 1, graded drops (exit 5, `RELEASE_CONFIRMED_DROPS`).** A skill drops
when its aggregate falls more than 0.05 below the baseline's, or when any
case that passed in the baseline fails now. Either signal alone stops the
release; the case signal exists because one regressed case can sit inside
single-run noise. A change of comparison key is reported in the same check. A
drop against a fallback baseline is labelled as such and still blocks. A drop
on a current record that a later edit has made stale still blocks; it clears
only when a newer record taken the same way replaces it.

**Check 2, changed skills with no usable record (exit 5,
`RELEASE_CONFIRMED_UNMEASURED`).** One batched question, under its own
variable, so a quick yes here can never confirm a drop. It lists changed
skills with no record since the tag, with only a stale record, with only a
fallback baseline, or with no baseline at all, and gives each skill's reason.
The output leads with "graded: X of Y changed skills", and the agent copies
that line and the confirmed names into the release notes. merge's "missing
baseline passes" never applies on this path.

**Check 3, script-graded cases (exit 1, not confirmable).** The release runs
every skill's `grader: script` cases, not only the changed skills', through a
standalone python3 runner, `scripts/lib/script-cases.py`, that has no code
path to `claude`. `run-evals.sh --script-only` delegates to the same runner,
and a CI test with a failing `claude` stub first on `PATH` proves the release
path never reaches a model. A failure is a deterministic hand-off break this
release would ship, and fixing it costs no tokens.

**Release skill and extension.** `release.md` replaces the paid check with
these three checks and drops the `--finalize` release asset; the
`eval-pass-rates.json` asset is retired, since a record committed at the tag
supersedes it. `claude` and bash 4 come off the release host's required
tools, and koto goes on. `skills/release/SKILL.md` forces every
`RELEASE_CONFIRMED_*` variable empty at the start, not only
`RELEASE_CONFIRMED_DROPS`, so nothing in the environment can confirm in
advance. All three checks run the same way in a dry run, because they're
free.

#### Alternatives Considered

- **One overwritten summary file per skill, with the release-asset walk as
  baseline.** Rejected because the walk finds no asset newer than v0.24.0, so
  every skill passes with no baseline. Reading the baseline through `git show`
  at the tag instead leaves the asset adding a network dependency and no
  information, and overwriting loses a seed record committed in the same pull
  request.
- **Git notes, or pull request comments.** Records kept out of the tree under
  a notes ref, or posted as comments the release finds through `gh`. Rejected
  because notes are invisible in review, aren't fetched or pushed by default,
  and can be force-pushed, and comments are editable free text found through
  merged-PR search, which returns work a release doesn't contain.
- **The release computes a free signal itself and treats graded records as
  advisory.** Script cases block; changed skills with no graded record are
  only listed. Rejected as the whole answer because script cases don't
  measure what SKILL.md wording does to the agent, and when listing is the
  only consequence, not measuring becomes the easy path. Its two other pieces
  were kept: script cases at release for every skill, and a runner with no
  path to the graded harness.
- **Script-case results read from CI instead of run at release.**
  `check-evals.yml` runs every script case on push to main, and the release
  requires that run's success on HEAD's exact SHA. Not chosen for now: it
  needs new CI plumbing, and running the cases locally checks exactly what
  ships. It's the swap if the owner reads the ruling literally or koto on
  release hosts proves a burden.

## Decision Outcome

The three decisions split detection by what it costs. Everything that runs
unattended is free: script-graded hand-off cases in the pull request gate and
at release, record-shape checks in CI, and the release's reading and
comparing of records. Everything that costs tokens is started by a person, on
one skill, on their own plan, and leaves a committed record of what it found
and what it cost. The release turns those records into a stop: a drop, or a
case that newly fails, waits for a person's yes; a changed skill nobody
measured waits for a separate, batched yes that lands in the release notes;
and a failing hand-off case stops the release until it's fixed.

That answers the two questions the evidence leaves open. Graded evals run
neither in CI nor at release time: they run on a maintainer's host at change
time. A skill gets one run of its release subset per measurement, and the
per-case signal and a person's confirmation stand in for repeat runs.

### How each piece of evidence is met

| Evidence | What meets it | Cost of showing it |
|---|---|---|
| 1. A maintainer breaks `/deliver`'s hand-off to `/execute`, runs the harness on `/deliver`, and sees its hand-off case fail | `run-evals.sh deliver` runs the `grader: script` case with `handoff: execute` first; `check-handoff.sh deliver execute` fails on a broken gate, directive, leg script, outcome word, result key, template name or attach (Decision 2). A break only in the agent's behaviour fails the model-graded hand-off case when the maintainer runs it (Decision 1). | $0 for the script case; about $3 for the single graded case, from the maintainer's plan |
| 1, for a skill added later | `check-evals-shape.py` derives the new skill's targets from its templates and refuses it in the free gate until each has a script-graded case, so the harness on that skill has a hand-off case to fail (Decision 2). | $0 |
| 2. A maintainer regresses one eval, runs `/shirabe:release`, and the release stops on that skill's drop until a person confirms | If the regressed eval is graded: the maintainer's committed record shows the aggregate down more than 0.05 or the case newly failing, and Check 1 exits 5 until `RELEASE_CONFIRMED_DROPS` names the skill. If no record was taken, Check 2 exits 5 naming the skill as unmeasured. If the regressed eval is script-graded: Check 3 stops the release (Decision 3). | $0 at release; the graded record costs the release-subset run on the maintainer's plan |

For the second piece of evidence to show a pass-rate drop rather than an
unmeasured skill, the skill needs a baseline: a record matching it at the
last tag, or a seed record of the released content taken before the change.

### Waiting on the owner

The design has two halves, and only one depends on an open question.

The script-graded half stands whatever the answer: script-graded hand-off
cases, target derivation in the shape check, Check 3 at release, and the
record-reading release with no model call. None of it spends a token.

The graded half, maintainer-chosen runs and the records they write, rests on
reading the eval rulings as covering releases and automated gates but not a
run a maintainer chooses to start on their own plan. That reading has gone
to the owner and isn't settled. If the owner rules maintainer-chosen runs out
too, the edit is small: Decision 1's chosen option becomes "no graded runs at
all", `run-evals.sh` refuses graded cases unless an owner-set cap exists,
Check 1 has no records to read and stays dormant, Check 2 lists every changed
skill as unmeasured, and the second piece of evidence holds only for an eval
that is script-graded, through Check 3. Nothing else in the architecture
moves.

## Solution Architecture

### Overview

Three paths meet at the release. The pull request gate runs script-graded
cases and checks record files, for free. A maintainer may run graded evals on
a changed skill and commit the record. The release selects changed skills by
content hash, reads their records from the tree, runs every script case, and
stops on what it finds.

### Components

| Component | Change | Runs on | Calls a model |
|---|---|---|---|
| `skills/*/evals/evals.json` | Optional `grader`, `run`, `handoff` per case | (data) | no |
| `scripts/check-handoff.sh <from> <to>` | New: routes, rendered directive, receiving-side contract, real attach | PR gate, harness, release | no |
| `scripts/lib/script-cases.py` | New: runs a skill's (or every skill's) `grader: script` cases; no path to `claude` | PR gate, harness, release | no |
| `scripts/lib/check-evals-shape.py` | Derives hand-off targets from templates; requires a script case per target | PR gate | no |
| `scripts/check-skill.sh` | Runs the skill's script cases, and other skills' cases that target it | PR gate, work-on map | no |
| `.github/workflows/check-skill-gate.yml` | New job: `check-skill.sh` on every skill the pull request changes, Linux and macOS bash 3.2 | CI | no |
| `scripts/lib/skill-tree.py` | New: lists a skill's behaviour files and hashes them | harness, CI, release | no |
| `scripts/run-evals.sh` | Script cases first; `--script-only`; writes a record with `tree`, `cases`, `producer`, `cost_usd`; API-key and bash 4 guards | maintainer host | yes, when graded |
| `evals/records/<skill>/*.json` | New add-only record files | (data) | no |
| `.github/workflows/check-evals.yml` | Record shape, add-only and deletion rules | CI | no |
| `scripts/lib/eval-pass-rates.py` | Baseline adapter, per-case comparison, stale/unbaselined/nobaseline/rekeyed outcomes | release | no |
| `scripts/release-eval-check.sh` | Loses the paid loop, asset walk, state marker and `--finalize`; runs the three checks | release | no |
| `.claude/shirabe-extensions/release.md` | Declares the three checks; drops the release asset; host needs koto, not `claude` or bash 4 | release | no |
| `skills/release/SKILL.md` | Forces every `RELEASE_CONFIRMED_*` empty at start | release | no |
| `scripts/scheduled-evals.py` | No $50 fallback; runs nothing without an owner-set cap; same run shape | (off) | only if funded |

### Key Interfaces

**Script-graded case** in `evals.json`:

```json
{
  "id": 34,
  "name": "handoff-execute-contract",
  "grader": "script",
  "handoff": "execute",
  "run": "scripts/check-handoff.sh deliver execute"
}
```

`run` is split into words on spaces and executed directly, never through a
shell. Its first word must resolve, after `realpath`, to a tracked regular
file under `scripts/` that isn't a symlink, and every argument must match
`[A-Za-z0-9._-]+`; the shape check refuses anything else, and the runner
checks again before executing. Each case gets a timeout (300 seconds by
default). A `grader: script` case has no `prompt` or `expectations`.

**Record file** `evals/records/<skill>/<UTC>-<tree12>.json`: a
`run-evals-summary/v1` skill entry (`runs`, `runs_passed`, `assertions`,
`pass_rate`, `models`, `session_model`, `scenario_set`, `measured_at`) plus:

```json
{
  "tree": "sha256:<hex over the sorted behaviour files and their blob ids>",
  "cases": [{"name": "auto-merged-no-split", "verdict": "pass"}],
  "producer": "local",
  "cost_usd": 13.84
}
```

**Release checks** in `release.md`, each a separate entry so each gets its own
confirmation round:

- `scripts/release-eval-check.sh --drops --tolerance 0.05` (exit 5 with
  `RELEASE_CONFIRMED_DROPS`)
- `scripts/release-eval-check.sh --unmeasured` (exit 5 with
  `RELEASE_CONFIRMED_UNMEASURED`)
- `scripts/release-eval-check.sh --script-cases` (exit 1 on any failure)

### Data Flow

1. A maintainer changes `skills/deliver/`. `check-skill.sh deliver` runs in
   the PR gate: validation, template compile, script tests, the shape check
   (targets derived, a case each) and the script cases, `/deliver`'s own and
   any other skill's that target it.
2. Optionally the maintainer runs `run-evals.sh deliver` on their host. Script
   cases print first; graded cases run on their plan; the run writes
   `evals/records/deliver/<UTC>-<tree12>.json`, which they commit.
3. CI's `check-evals.yml` checks the record is well formed and that no older
   record changed.
4. At release, `release-eval-check.sh` computes each skill's tree at the last
   tag and at HEAD, selects the changed skills, reads the baseline and current
   records from git, and hands them to `eval-pass-rates.py`, which decides
   drops and unmeasured skills. It then runs every script case through
   `script-cases.py`.
5. A drop or an unmeasured list exits 5; the release asks the person, re-runs
   the check with the confirmed names, and copies the "graded: X of Y" line
   into the notes. A failing script case exits 1 and the release stops.

### Cost of every run

| Run | Cost driver | Who pays | Tokens |
|---|---|---|---|
| PR gate: shape check, script cases | CPU, scaling with the changed skill's script cases and the cases targeting it | GitHub Actions minutes, free on a public repository | 0 |
| CI record check | CPU, scaling with record files changed | GitHub Actions minutes | 0 |
| Maintainer graded run | The skill's release-subset scenario count times the per-scenario rate, plus about $2.50 of session overhead: about $3 for one case, $14 for `/deliver`'s subset, $39 for `/execute`'s, at list price | The Claude plan of the person who starts it; refused with an exported API key unless flagged and under an owner-set cap | yes |
| Release: selection and hashing | CPU, scaling with skills and their behaviour files | The release host's machine time | 0 |
| Release: reading and comparing records | CPU, milliseconds, scaling with changed skills and their records | The release host's machine time | 0 |
| Release: script cases | CPU and wall time, seconds to minutes, scaling with every skill's script cases | The release host's machine time | 0 |
| Release: confirmations | A person's attention, at most one question per check | The person releasing | 0 |
| Scheduled runs | Off; would be scenario count times runs, billed to that host's account | Only with an owner-set cap | only if funded |

## Implementation Approach

### Phase 1: Script-graded cases and the hand-off check

The free layer comes first because both pieces of evidence lean on it and it
needs nothing else.

Deliverables:
- `scripts/check-handoff.sh` and its test suite, with route selectors on the
  `/deliver` and `/execute` engine suites.
- `scripts/lib/script-cases.py`, `run-evals.sh --script-only` delegating to
  it, and the failing-`claude`-stub test.
- `grader`, `run`, `handoff` in `check-evals-shape.py`, with target
  derivation from templates; `check-skill.sh` running script cases; the
  `check-skill-gate.yml` job running `check-skill.sh` on every changed skill,
  with `pull_request`, read-only permissions and its trigger test.
- Script-graded hand-off cases in `/deliver` (scope, execute), `/execute`
  (work-on) and every other skill the derivation names.

### Phase 2: Records and the harness guards

Depends on nothing in Phase 1 but lands after it, so the first records carry
the new case kind.

Deliverables:
- `scripts/lib/skill-tree.py` and its tests.
- Record writing in `run-evals.sh` (`tree`, `cases`, `producer`,
  `cost_usd`), the API-key guard and the `BASH_VERSINFO` guard.
- `check-evals.yml` record checks; the dispatch-only test for
  `run-evals.yml`; `scheduled-evals.py` without its fallback budget.

### Phase 3: The release reads records

Depends on Phase 2's record format and Phase 1's runner.

Deliverables:
- `eval-pass-rates.py`: baseline adapter, per-case comparison, the new
  outcomes, no "missing baseline passes" on this path; offline tests.
- `release-eval-check.sh` with `--drops`, `--unmeasured`, `--script-cases`,
  and the paid loop, asset walk and `--finalize` removed.
- `release.md`, `skills/release/SKILL.md`, CLAUDE.md, AGENTS.md and the
  extension README describing the new split; the release half of
  `DESIGN-evals-at-release.md` marked as replaced by this design.

## Security Considerations

**A record is an assertion, not a proof.** A pull request author can commit a
record with any numbers. The release checks it only structurally: the tree
hash matches content, the scenario set and run shape match, and older
records are unchanged. Records arrive through the same review as the code
they measure, add-only enforcement keeps an author from rewriting a baseline,
and a forged good record hides a regression no better than not measuring,
which Check 2 already surfaces. shirabe's maintainers are trusted to the same
degree as the code they merge; this design doesn't change that. Add-only
enforcement is a CI check, so it holds only as far as branch protection and
review do: a maintainer who can merge past a red check, or rewrite a record
inside a squashed pull request that review misses, can still change a
baseline. The release can't detect that, and the design doesn't try to.

**Script cases run commands from `evals.json`.** The PR gate and the release
host execute each case's `run` field, so a careless or hostile case is code
execution. The runner never hands `run` to a shell: it splits it into words
and executes the first directly, after checking that it resolves through
`realpath` to a tracked regular file under `scripts/` that isn't a symlink,
and that every argument matches `[A-Za-z0-9._-]+`. That rules out `..`
traversal, symlinks pointing outside the tree, untracked files and shell
metacharacters. Each case has a timeout, so a hung case stops the check
rather than the host. The scripts a case names go through review like any
other code.

The release host is a maintainer's machine and holds credentials, so running
these cases there is a trust boundary, not a free action. The runner unsets
`GH_TOKEN`, `GITHUB_TOKEN` and `SSH_AUTH_SOCK` for each case, the same
variables the nested eval session already drops, and the release runs the
cases from the tree at the commit being tagged, not from whatever else is in
the working copy. A case that needs a credential is a defect in the case.

**CI runs with no secrets and read-only permissions.** `check-evals.yml` and
`check-skill-gate.yml` trigger on `pull_request`, never
`pull_request_target`, and declare `permissions: contents: read`, so a pull
request from a fork runs its script cases with no token that can write and
no repository secret. `check-run-evals.yml` gains a test for both properties,
next to the one that keeps `run-evals.yml` dispatch-only.

**No model call is reachable from the release.** `script-cases.py` has no code
path to `claude`, `release-eval-check.sh` no longer calls `run-evals.sh`, and
a CI test with a failing `claude` stub first on `PATH` proves it. The nested
eval session's access to stored credentials, an accepted risk in the
release-time design, no longer applies to release hosts; it applies only on a
maintainer's host when they choose to run graded evals, and `run-evals.sh`
keeps printing that fact before it runs.

**Accidental API spend.** An exported `ANTHROPIC_API_KEY` could turn a
plan-billed run into API billing. `run-evals.sh` refuses to start with one
unless explicitly flagged and under an owner-set cap, and `run-evals.yml`
can't gain an automatic trigger without failing a CI test.

**Pre-set confirmations.** A `RELEASE_CONFIRMED_*` variable left in the
environment could pass a check without anyone answering. The release skill
empties all of them before the first check runs.

**Record contents.** A record holds case names, verdicts, models and a cost
figure, no transcripts, prompts or paths from the maintainer's host.
`cost_usd` reveals what a run cost at list price, which the spike already
publishes. The release prints skill names, case names and `producer` from
records, and an agent reads that output, so a crafted name could carry
terminal escape sequences or text meant to steer the agent. The CI record
check and the release's reader both refuse any of those fields outside
`[A-Za-z0-9._-]`, and the release treats record contents as data, never as
instructions.

## Consequences

### Positive

- No release, pull request or schedule spends a model token, on any path,
  dry runs and confirmation re-runs included.
- A hand-off break in templates, leg scripts, directives or the target's
  outcome words now fails a named case in the harness, the PR gate and the
  release, for free, including the receiving-side drift the engine suites'
  stand-in children let through today.
- A new skill that hands off to another can't merge without a hand-off case.
- Every release states how many changed skills were graded, against what
  baseline, and what each measurement cost.
- The baseline lookup reads the tag's tree, so it has no depth cap and no
  network dependency, and squash merge doesn't break it.

### Negative

- Graded coverage depends on people choosing to measure; a release can ship
  a skill whose wording change nobody graded, with only a confirmation in its
  way.
- Shared root files are loaded by many skills, so most releases will raise
  the unmeasured question for several skills at once.
- Single-run noise will sometimes stop a release on a case that flipped by
  chance.
- A record written on a laptop can be checked only for shape, not
  re-verified.
- The second piece of evidence can show a drop only once a skill has a
  baseline, which for most skills means one paid seed run.
- The release host needs koto, which it didn't before.

### Mitigations

- The "graded: X of Y" line in every release's notes shows how much is
  unmeasured, which is the evidence for asking the owner to fund more
  measurement, through the documented schedule path.
- The unmeasured question is one batched confirmation under its own
  variable, so it costs one answer and can't confirm a drop.
- A noise flip costs a person's attention and an optional re-run on their
  plan, never an automatic spend; the per-case output names the case so the
  person can judge it.
- Add-only records and review keep a forged baseline out; a forged current
  record is no worse than not measuring, which Check 2 surfaces.
- Seed runs can be taken one skill at a time, when a maintainer next works on
  that skill.
- The CI swap for script-case results (Decision 3) takes koto off the release
  host if it proves a burden.
