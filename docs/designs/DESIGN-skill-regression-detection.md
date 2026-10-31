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
  No eval calls a model: not a release, not CI, not a schedule, and not a
  person running the harness, as the owner settled on 2026-10-31. A new
  script-graded case kind in `evals.json` (`grader: script`) checks each
  hand-off with no model, through one shared `scripts/check-handoff.sh`. The
  harness, a new pull request gate job and the release all run these cases,
  and the shape check derives a skill's hand-off targets from its koto
  templates so a new skill can't merge without one. The release runs every
  skill's script cases, records each skill's script pass rate and per-case
  verdicts in the existing `eval-pass-rates.json` asset, compares them with
  the newest earlier release's record, and stops at exit 5 on any failing
  case, labelled as a drop when it passed before, until a person confirms.
  The model-graded cases stay in `evals.json`, and the harness refuses to run
  them without an owner-set cap.
rationale: |
  With no budget for any graded run, every measurement has to be
  deterministic, and the hand-off wiring is both where the likely breaks are
  and where a script can check without a model, using the engine suites that
  already exist. Running the cases in the pull request gate tells the
  maintainer before merge; running them all again at release catches what a
  shared-file change broke elsewhere and gives a release a pass rate to stop
  on. Reusing the asset record and the exit-5 protocol keeps the release
  change small. The cost is that nothing measures what the agent does when
  the wiring is intact, which the release notes say on every run.
---

# DESIGN: Skill regression detection without paid evals

## Status

Proposed

## Context and Problem Statement

shirabe wants a maintainer to learn that a change broke a skill's behaviour,
including a hand-off from one skill to another, before the release that
carries the change reaches users. That has to hold for every skill, including
skills added later. The project's roadmap, not this design, sets the
acceptance evidence for that goal, as two observations. They're quoted here
so the design can show which of its parts makes each one reachable (see "How
each piece of evidence is met"); this document adds no requirements of its
own:

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

- No eval makes a model call: not a release (dry runs and confirmation
  re-runs included), not pull request CI, not a schedule, and not a person
  running the harness. This is a requirement, from the owner's rulings and
  the settlement quoted in Decision 1.
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

## Considered Options

### Decision 1: Where graded evals run, how many runs a skill gets, and who pays

Every case in `evals.json` today is graded by a model, so every graded run
costs tokens. The owner's earlier rulings ruled out graded runs at release
and in automated gates. A run a maintainer chooses to start on their own
plan was left open, and the owner settled it on 2026-10-31: "do not run any
evals, no budget for that". No paid eval runs, whoever starts it.

Key assumptions:
- The settlement holds until the owner funds graded runs. When that happens,
  the dormant graded path described below is the place to switch them on,
  and nothing else in this design has to move.
- A deterministic case is not an eval in the sense the rulings use: it calls
  no model and costs nothing but CPU, so the rulings don't reach it.

#### Chosen: no graded runs anywhere; deterministic cases are the only measurement

Graded evals run nowhere: not at release, not in CI, not on a schedule, and
not on a maintainer's host. A skill gets zero graded runs and one run of its
script-graded cases (Decision 2) wherever those run, since a deterministic
case gives the same answer every time and a repeat measures nothing.

The model-graded cases stay in `evals.json`. They still describe the
behaviour each skill promises, and they're what a funded run would grade.
But the harness won't run them under this design:

- `run-evals.sh` runs script-graded cases by default and refuses to start a
  graded case unless an owner-set cap exists in `scheduled-evals.py`'s
  ledger. No such cap exists, so the refusal is the default for everyone,
  the CI workflow included.
- It also refuses to start a graded case with any variable set that could
  bill an API or cloud account (the list is in Security Considerations),
  cap or no cap, unless explicitly flagged.
- `scheduled-evals.py` loses its $50 weekly fallback; without an owner-set
  cap it runs nothing.
- `run-evals.yml` stays dispatch-only, and `check-run-evals.yml` fails if it
  gains an automatic trigger. A manual dispatch reaches the same refusal.

#### Alternatives Considered

- **Graded runs at release time.** The current check, about $90 per
  five-skill release after the spike's cuts and about $1,200 before. Rejected:
  the owner ruled that releases never run evals.
- **Per-PR CI with an API key.** A workflow runs the changed skill's subset
  on every skill pull request, billing an org secret. Rejected: unbudgeted
  automated spend, multiplied by fix rounds, and shirabe#612 stops grading in
  CI for several skills.
- **A budgeted schedule.** Wire `scheduled-evals.py` to cron with a weekly
  cap. Rejected: the owner hasn't budgeted recurring spend. It stays the
  documented path if the owner ever funds one.
- **A maintainer-started run at change time.** One run of the changed skill's
  release subset on the maintainer's own plan, committed as a record the
  release reads. This was the recommendation until the owner settled the
  question; rejected by the settlement, "do not run any evals, no budget for
  that".

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
`check-skill-gate.yml` gains a job that runs `check-skill.sh` on every skill
with changed files under `skills/<name>/`, and `script-cases.py --all` when
a shared path (`scripts/`, `references/`, `koto-templates/`) changes, on
Linux and on the macOS bash 3.2 leg. "The pull request gate" in the rest of this design means that job.

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
cases (`/deliver` 1, 2, 18, 20 to 21, 30 to 33; `/execute` 4, 62, 63) cover
those, and under the owner's settlement nobody runs them (Decision 1), so
these breaks go unmeasured.

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

With no graded runs, the only pass rates that can exist are script-graded
ones. `eval-pass-rates.py merge` already compares a skill's measurement with
the newest earlier release that measured it the same way (models, session
model, scenario set, run count), and exits 5 with a
`confirm: RELEASE_CONFIRMED_DROPS=...` line. `release-eval-check.sh` already
walks up to ten earlier releases for their `eval-pass-rates.json` assets, and
its `--finalize` step names this release's record for upload. The paid part
is the loop that calls the graded harness for each changed skill.

Key assumptions:
- The release host has koto (the attach step in `check-handoff.sh` needs it)
  and `gh` access to earlier releases. Without either the check exits 1
  rather than passing.
- `eval-pass-rates.py` can accept a script measurement: `models:
  ["script"]`, no session model, one run, a scenario set hashed over the
  script cases' ids and commands, and a per-case `cases` list.
- No release since v0.24.0 has an asset, so the first release after this
  lands has no baseline for any skill. That release still stops on any
  failing case; it just can't call the failure a drop.

#### Chosen: the release runs every script case, records script pass rates, and stops on any failing case until a person confirms

`release-eval-check.sh` loses its graded loop and its call to
`run-evals.sh`. In its place it runs every skill's `grader: script` cases
through `scripts/lib/script-cases.py`, a standalone python3 runner with no
code path to `claude`, and writes one summary per skill: cases run, cases
passed, the pass rate and each case's verdict. All skills run, not only the
changed ones, because the cases are cheap and a change to a shared file or to
a hand-off target can break a skill whose own files didn't change.

It hands those summaries to `eval-pass-rates.py merge` with the earlier
releases' records as baselines, as today. The stop rule is any failing script
case, in any skill. The output names each failing case and labels it:

- **regressed**: the case passed in the skill's baseline, or the skill's rate
  fell below its baseline rate. This is the pass-rate drop.
- **failing, no baseline**: the case is new, or no earlier release measured
  the skill this way.

Either label exits 5, and the release asks the person running it. Re-running
with `RELEASE_CONFIRMED_DROPS` naming every skill with a failing case lets
the release continue; the confirmed names and the "script cases: P of N
passed" line go into the release notes. A runner that can't start, missing
koto or a failed download, exits 1 with a retry message.

Per-case comparison matters because adding one passing case and breaking
another in the same release changes the scenario set, which `merge` treats
as a new reference rather than a drop. Comparing case by case catches the
break anyway, and "any failing case stops" catches it even with no baseline.

The release also prints, for the notes, "model-graded cases: not run, per
the owner's ruling of 2026-10-31", so every release says what it didn't
measure.

`--finalize` stays: it stamps the record with the confirmed version and
Phase 4 uploads it as `eval-pass-rates.json`, so the next release has a
baseline. `release.md` declares the check with no model or session-model
options, and the release host's required tools lose `claude` and bash 4 and
gain koto. `skills/release/SKILL.md` empties every `RELEASE_CONFIRMED_*`
variable before the first check runs, so nothing set in advance can confirm.

#### Alternatives Considered

- **A failing script case stops the release outright (exit 1).** Rejected:
  the evidence asks for a stop "until a person confirms it", and a release
  that must ship with a known, accepted failure (a fix in flight, a case
  that's wrong rather than the skill) would have no way through except
  editing the case.
- **Baseline by re-running the last tag's script cases in a temporary
  worktree.** No stored record at all, and always a baseline. Rejected: the
  old cases run against today's koto and today's shared scripts, so an
  environment change reads as a skill change, and the release would do
  twice the work to learn what a stored record already says.
- **Committed records under `evals/records/`.** Records reviewed with the
  change and read with `git show` at the tag. Rejected: designed to carry
  graded runs, which no longer exist. For deterministic results the release
  can produce itself, a committed copy adds files and an add-only rule with
  nothing to protect.
- **Read script-case results from CI on HEAD's exact SHA.** Takes koto off
  the release host. Not chosen for now: it needs new CI plumbing, and the
  release skill's current "CI green on HEAD" check passes on a missing
  status. It's the swap if koto on release hosts proves a burden.

## Decision Outcome

Nothing in this design makes a model call: not a release, not CI, not a
schedule, and not a person running the harness. Detection rests entirely on
script-graded cases, which check each hand-off with no model. The pull
request gate runs them on every change, so the maintainer who breaks a
hand-off learns it before merging, and a new skill can't merge without its
hand-off cases. The release runs all of them again, records each skill's
script pass rate, and stops on any failing case, labelled as a drop when it
passed before, until a person confirms.

That answers the two questions the evidence leaves open. Graded evals run
nowhere until the owner funds them. A skill gets no graded runs and one run
of its script cases in each place they run.

### How each piece of evidence is met

| Evidence | What meets it | Cost of showing it |
|---|---|---|
| 1. A maintainer breaks `/deliver`'s hand-off to `/execute`, runs the harness on `/deliver`, and sees its hand-off case fail | `run-evals.sh deliver` runs the `grader: script` case with `handoff: execute`; `check-handoff.sh deliver execute` fails on a broken gate, directive, leg script, outcome word, result key, template name or attach (Decision 2). | $0 |
| 1, for a skill added later | `check-evals-shape.py` derives the new skill's targets from its templates and refuses it in the pull request gate until each has a script-graded case, so the harness on that skill has a hand-off case to fail (Decision 2). | $0 |
| 2. A maintainer regresses one eval, runs `/shirabe:release`, and the release stops on that skill's drop until a person confirms | For a script-graded eval: the release's check sees the case fail where the baseline had it passing, labels it regressed with the skill's rate against its baseline rate, and exits 5 until `RELEASE_CONFIRMED_DROPS` names the skill (Decision 3). | $0 |

The second piece of evidence holds for script-graded evals only. A regression
in a model-graded eval, such as a SKILL.md wording change that alters what
the agent does at a hand-off while the wiring stays intact, isn't measured by
anything under the owner's settlement, and the release says so in its notes.
The first release after this lands has no baseline, so it reports a broken
case as failing rather than regressed; from the second release on, the drop
shows as a drop.

## Solution Architecture

### Overview

Two paths, both free. The pull request gate runs the shape check and the
script cases on every change. The release runs every script case, compares
the results with the newest earlier release's record, stops on any failure,
and uploads a new record.

### Components

| Component | Change | Runs on | Calls a model |
|---|---|---|---|
| `skills/*/evals/evals.json` | Optional `grader`, `run`, `handoff` per case | (data) | no |
| `scripts/check-handoff.sh <from> <to>` | New: routes, rendered directive, receiving-side contract, real attach | PR gate, harness, release | no |
| `scripts/lib/script-cases.py` | New: runs one skill's or every skill's `grader: script` cases; writes a per-skill summary with per-case verdicts; no path to `claude` | PR gate, harness, release | no |
| `scripts/lib/check-evals-shape.py` | Accepts the new keys; derives hand-off targets from templates; requires a script case per target | PR gate | no |
| `scripts/check-skill.sh` | Runs the skill's script cases, and other skills' cases that target it | PR gate, work-on map | no |
| `.github/workflows/check-skill-gate.yml` | New job: `check-skill.sh` on each skill with changed files, and `script-cases.py --all` when shared paths change | CI | no |
| `scripts/run-evals.sh` | Script cases by default; `--script-only`; refuses graded cases without an owner-set cap, and with any billing variable set | anyone's host | no, under this design |
| `scripts/lib/eval-pass-rates.py` | Accepts script measurements and `cases`; compares case by case; labels regressed and failing-no-baseline | release | no |
| `scripts/release-eval-check.sh` | Graded loop and `run-evals.sh` call replaced by `script-cases.py --all`; any failing case exits 5 | release | no |
| `.claude/shirabe-extensions/release.md` | Check declared without model options; host needs koto, not `claude` or bash 4 | release | no |
| `skills/release/SKILL.md` | Empties every `RELEASE_CONFIRMED_*` before the first check | release | no |
| `scripts/scheduled-evals.py` | No $50 fallback; runs nothing without an owner-set cap | (off) | only if funded |

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
`[A-Za-z0-9][A-Za-z0-9._-]*`, with an argument in a skill position naming a
directory under `skills/`; the shape check refuses anything else, and the
runner checks again before executing. Each case gets a timeout (300 seconds
by default) and the limits in Security Considerations. A `grader: script`
case has no `prompt` or `expectations`.

**Script measurement** in the `eval-pass-rates/v1` record, per skill:

```json
{
  "runs": 1,
  "runs_passed": 1,
  "assertions": {"passed": 2, "graded": 2},
  "pass_rate": 1.0,
  "models": ["script"],
  "scenario_set": "sha256:<hex over the script cases' ids and run commands>",
  "cases": [{"name": "handoff-execute-contract", "verdict": "pass"}],
  "measured_at": "0.40.0"
}
```

**Release check** in `release.md`: `scripts/release-eval-check.sh` (exit 5
with `RELEASE_CONFIRMED_DROPS` on any failing case; exit 1 on an
infrastructure failure), and `scripts/release-eval-check.sh --finalize`
under `## Release assets`, as today.

### Data Flow

1. A maintainer changes `skills/deliver/`. The pull request gate runs
   `check-skill.sh deliver`: validation, template compile, script tests, the
   shape check (targets derived, a case each) and the script cases,
   `/deliver`'s own and any other skill's that target it. A change to a
   shared path also runs `script-cases.py --all`.
2. The maintainer can run `run-evals.sh deliver` on any host, bash 3.2
   included, to see the same cases; graded cases are refused.
3. At release, `release-eval-check.sh` runs `script-cases.py --all`,
   downloads the newest earlier records, and hands both to
   `eval-pass-rates.py merge`, which labels every failing case.
4. Any failing case exits 5; the release asks the person, re-runs the check
   with the confirmed names, and copies the "script cases: P of N passed"
   line, the confirmed names and the "model-graded cases: not run" line into
   the notes. `--finalize` stamps the record and Phase 4 uploads it.

### Cost of every run

| Run | Cost driver | Who pays | Tokens |
|---|---|---|---|
| PR gate: shape check, script cases | CPU, scaling with the changed skills' cases and the cases targeting them, or every case on a shared-path change | GitHub Actions minutes, free on a public repository | 0 |
| Harness on a maintainer's host | CPU, scaling with the skill's script cases | The maintainer's machine time | 0 |
| Release: script cases | CPU and wall time, seconds to minutes, scaling with every skill's script cases | The release host's machine time | 0 |
| Release: record download and compare | Up to ten small `gh` downloads and a python3 merge | The release host's machine time and network | 0 |
| Release: confirmation | A person's attention, at most one question per release | The person releasing | 0 |
| Graded cases, scheduled runs | Not run; would be scenario count times runs | Only with an owner-set cap | 0 under this design |

## Implementation Approach

### Phase 1: Script-graded cases and the hand-off check

The free layer comes first because both pieces of evidence lean on it.

Deliverables:
- `scripts/check-handoff.sh` and its test suite, with route selectors on the
  `/deliver` and `/execute` engine suites.
- `scripts/lib/script-cases.py`, `run-evals.sh --script-only` delegating to
  it, and the failing-`claude`-stub test.
- `grader`, `run`, `handoff` in `check-evals-shape.py`, with target
  derivation from templates; `check-skill.sh` running script cases.
- Script-graded hand-off cases in `/deliver` (scope, execute), `/execute`
  (work-on) and every other skill the derivation names.

### Phase 2: The pull request gate and the harness guards

Depends on Phase 1's runner and shape check.

Deliverables:
- The `check-skill-gate.yml` job, on `pull_request` with read-only
  permissions, and its trigger test.
- `run-evals.sh`: script cases by default, the graded refusal without an
  owner-set cap, the billing-variable refusal.
- `scheduled-evals.py` without its fallback budget; the dispatch-only test
  for `run-evals.yml`.

### Phase 3: The release runs script cases

Depends on Phase 1's runner and summary format.

Deliverables:
- `eval-pass-rates.py`: script measurements, `cases`, case-by-case
  comparison, the regressed and failing-no-baseline labels; offline tests.
- `release-eval-check.sh` with the graded loop replaced by `script-cases.py
  --all` and the any-failing-case stop.
- `release.md`, `skills/release/SKILL.md`, CLAUDE.md, AGENTS.md and the
  extension README describing the new split; the release half of
  `DESIGN-evals-at-release.md` marked as replaced by this design.

## Security Considerations

**Script cases run commands from `evals.json`.** The pull request gate and
the release host execute each case's `run` field, so a careless or hostile
case is code execution. The runner never hands `run` to a shell: it splits it
into words and executes the first directly, after checking that it resolves
through `realpath` to a tracked regular file under `scripts/` that isn't a
symlink. Every argument must start with a letter or digit and match
`[A-Za-z0-9][A-Za-z0-9._-]*`, which rules out `.`, `..` and anything that
reads as an option, and an argument in a skill position must name a
directory under `skills/`. That rules out traversal, symlinks pointing
outside the tree, untracked files and shell metacharacters. The scripts a
case names go through review like any other code.

The release host is a maintainer's machine and holds credentials, so running
these cases there is a trust boundary, not a free action. Each case runs:

- with an allowlisted environment (`PATH`, `LANG`, `TMPDIR` and the
  variables the case's script documents), not the caller's, so no token or
  `ANTHROPIC_*` variable reaches it;
- with `HOME` set to a fresh temporary directory, so `~/.ssh`,
  `~/.config/gh` and other stored credentials aren't on the paths a script
  would look in; a determined script can still reach the real home by
  absolute path, which is why review of `scripts/` stays the control;
- with a temporary koto state directory, so `koto init` and the engine
  suites never touch the maintainer's real sessions;
- in its own process group, killed as a group when its timeout runs out;
- from the tree at the commit being tagged, not from whatever else is in the
  working copy.

A case that needs a credential is a defect in the case. Dry runs execute the
cases the same way, under the same limits.

**CI runs with no secrets and read-only permissions.** `check-evals.yml` and
`check-skill-gate.yml` trigger on `pull_request`, never
`pull_request_target`, and declare `permissions: contents: read`, so a pull
request from a fork runs its script cases with no token that can write and
no repository secret. Both use GitHub-hosted runners, the macOS bash 3.2 leg
included, never a self-hosted one. `check-run-evals.yml` gains a test for
these properties, next to the one that keeps `run-evals.yml` dispatch-only.

**No model call is reachable.** `script-cases.py` has no code path to
`claude`, `release-eval-check.sh` no longer calls `run-evals.sh`, and a CI
test with a failing `claude` stub first on `PATH` proves the release path
never reaches a model. The nested eval session's access to stored
credentials, an accepted risk in the release-time design, no longer applies
anywhere, since no nested session starts.

**Accidental spend.** Several variables can turn a run into API or cloud
billing: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`,
and the switches that route Claude Code through Bedrock or Vertex
(`CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`). `run-evals.sh`
refuses graded cases without an owner-set cap, and refuses them with any of
those variables set unless explicitly flagged. `run-evals.yml` can't gain an
automatic trigger without failing a CI test.

**Release records.** The baseline comes from earlier releases'
`eval-pass-rates.json` assets, which anyone with release write access can
replace. `eval-pass-rates.py` already validates every field and skips an
unusable record; a tampered record can at worst make a failing case read
"failing, no baseline" instead of "regressed", and either label stops the
release. Asset write access stays limited to the repository's maintainers.

**Pre-set confirmations.** A `RELEASE_CONFIRMED_*` variable left in the
environment could pass the check without anyone answering. The release skill
empties all of them before the first check runs.

**Output an agent reads.** The release prints skill names, case names and
the output of failing script cases, and an agent reads all of it, so crafted
text could carry terminal escape sequences or words meant to steer the
agent. The record reader refuses names outside `[A-Za-z0-9._-]`, the runner
strips control characters from script output and truncates each case's
output to its last 200 lines, and the release treats all of it as data,
never as instructions.

## Consequences

### Positive

- No release, pull request, schedule or person spends a model token, on any
  path, dry runs and confirmation re-runs included.
- A hand-off break in templates, leg scripts, directives or the target's
  outcome words fails a named case in the harness, the pull request gate and
  the release, including the receiving-side drift the engine suites'
  stand-in children let through today.
- A new skill that hands off to another can't merge without a hand-off case.
- Every release records a script pass rate per skill again, the first since
  v0.24.0, and says in its notes what it didn't measure.
- The harness runs on bash 3.2 for everything it's allowed to run.

### Negative

- Nothing measures the agent's behaviour: a SKILL.md change that alters what
  the agent does at a hand-off, or anywhere else, while the wiring stays
  intact, ships unmeasured.
- The second piece of evidence holds for script-graded evals only.
- The first release after this lands has no baseline, so it can't label a
  failure as a drop.
- The release host needs koto, which it didn't before.
- The model-graded cases stop being exercised, so they can rot against
  skills that keep changing.

### Mitigations

- The release notes' "model-graded cases: not run" line keeps the gap in
  view, and the dormant graded path (an owner-set cap) is the one switch to
  turn graded runs back on if the owner funds them.
- Hand-off wiring is where the most likely breaks live, and it's now covered
  for every skill; turning more behaviour into deterministic cases, where a
  check can stand in for a model, narrows the gap further at no token cost.
- From the second release on, every failure that passed before shows as a
  drop; the first release still stops on any failure.
- The CI swap for script-case results (Decision 3) takes koto off the release
  host if it proves a burden.
- `check-evals-shape.py` keeps checking the shape of the model-graded cases
  on every change, so at least their structure stays valid until they run
  again.
