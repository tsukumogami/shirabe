---
schema: brief/v1
status: Accepted
problem: |
  Every pull request that changes a skill has to run that skill's full
  model-graded eval suite before work-on will let it finish. The suite is slow,
  noisy from run to run, and can't run from CI or from worker hosts today, so
  agents stop on a gate they can't meet and record waivers by hand, while the
  release, where a full behavioral pass is worth paying for, checks nothing.
outcome: |
  A worker or coordinator changing a skill finishes its pull request on cheap
  checks it can run anywhere, with no waiver. The maintainer cutting a release
  gets the behavioral signal instead: the changed skills' evals run before the
  tag, their pass rates sit next to the last release's, and a harness that
  grades nothing stops the release rather than passing it.
motivating_context: |
  shirabe#593 proposed the move. Three pull requests that landed on 2026-10-06
  (#609, #619, #622) each changed skills/** and each had to waive the eval line
  of the work-on verification map in its body, because the eval harness can't
  set up on dispatched branches and grades zero scenarios on main (shirabe#612).
---

# BRIEF: evals-at-release

## Status

Accepted

This brief frames moving skill evals from the pull request gate to the release.
It doesn't fix the harness failure tracked in shirabe#612; it changes where the
harness is asked to run and makes the release check fail loudly when the harness
can't grade.

## Problem Statement

shirabe's skills are prose that a model follows, so the only test that tells you
whether a skill still behaves is to run it through a model and grade what it
did. That is what the eval suites under `skills/<name>/evals/` do, and today the
repo asks for them at the most expensive point it could: every pull request that
touches a skill. The work-on extension binds `skills/**` to
`scripts/run-evals.sh <skill>` in its verification map, and `CLAUDE.md` tells the
agent to run the suite and fix any failure before committing.

That gate costs more than it returns. Each run starts a nested `claude -p`
session that spawns a with-skill and a baseline agent per scenario, and the large
suites hold dozens of scenarios, so one fix round on a skill like work-on means
dozens of agent sessions, all on the strongest model whether the scenario tests
judgment or only checks that a command was routed correctly. The result of a
single run says little: these scenarios are probabilistic, and one pass or one
failure is within the noise.

Worse, the gate can't be met right now. The CI workflow fails before grading
anything on any dispatched branch and grades zero evals on its weekly run on
main. The script needs bash 4, and the worker hosts coordinators dispatch to run
bash 3.2 with installs refused. So every skill change hits a wall, and the three
that landed most recently each waived the eval line by hand in their pull request
body. A waiver written per pull request is a gate nobody is held to, and the
coordinators this repo is trying to make cheap to run stop on it every time.

Meanwhile the release, which is the one moment a full pass across the changed
skills is worth its cost, runs no behavioral check at all. `/shirabe:release`
checks the working tree, CI, tags and blocker labels, and nothing about whether
the skills it ships still do what they did in the last release.

## User Outcome

A worker or coordinator that changes a skill reaches work-on's
definition-of-done gate and gets checks that run in seconds on any host: the
skill validates, its koto templates compile, and its own script tests pass. It
writes or updates the scenarios that cover its change, and nobody asks it to run
them or to explain in the pull request body why it couldn't.

The maintainer cutting a release is the one who pays for the behavioral signal,
once, where it matters. Before the tag exists they see the evals of every skill
that changed since the last release, with repeated runs on the skills that matter
most and each pass rate set beside the previous release's, so a skill that got
worse shows up as a number that dropped. When the harness can't produce a grade,
the release stops and says so, rather than reporting a pass nobody measured.

## User Journeys

### A worker finishes a skill change

A worker dispatched by a coordinator runs `/work-on` on an issue that edits
`skills/execute/SKILL.md` and a script under `skills/execute/scripts/`. At the
definition-of-done gate the verification map runs `shirabe validate` on the
skill, compiles its koto templates and runs its script tests on the bash 3.2
host it has. All three pass, the issue finalizes, and the pull request body says
nothing about evals beyond the scenarios it added.

### A maintainer cuts a release

A maintainer runs `/shirabe:release 0.24.0`. Before notes are drafted, the
precondition phase reads the release checks shirabe declares and runs them: the
eval suites of the seven skills changed since `v0.23.0`, with work-on and scope
run several times each. The maintainer sees each skill's pass rate next to the
rate recorded at `v0.23.0`, notices scope fell from 0.9 to 0.6, and holds the
release to look.

### The harness breaks on release day

A maintainer runs `/shirabe:release` on a host where the nested session can't
start. The eval check reports that no scenario was graded, names the skill, and
the precondition fails. The release stops there instead of drafting notes over a
check that measured nothing.

### An author adds a scenario

An author fixing a routing bug in `/scope` adds a scenario to
`skills/scope/evals/evals.json` that reproduces it and marks it as needing the
stronger model, because it tests judgment rather than routing. The pull request
carries the scenario unrun. The next release runs it, on the model the scenario
asked for, alongside the rest of scope's suite.

## Scope Boundary

**IN:**

- The `skills/**` entry of shirabe's work-on verification map, changed to
  deterministic checks, and the `CLAUDE.md` Skill Evals section and the
  extension README rewritten to describe the split.
- `/shirabe:release` loading repo extensions the way brief, prd and design do,
  and running whatever release checks the repo declares as a precondition.
- shirabe's own release extension declaring the eval check, the skills it runs
  repeatedly, and where pass rates are recorded and compared.
- `scripts/run-evals.sh` selecting the skills changed since the last tag by
  default, and a cheaper default model that a scenario can override.
- The scheduled CI eval workflow removed or made manual-only; the CI check that
  eval files exist stays.

**OUT:**

- Fixing the isolated-checkout failure and the zero-graded run (shirabe#612).
  This work stops asking pull requests to run evals and makes the release check
  fail loudly; it doesn't make the harness work.
- Making `run-evals.sh` run on bash 3.2. The release session is where a bash 4
  host is assumed.
- Changing review panels: which model review seats use, how many there are, or
  how a panel is routed.
- Writing new eval scenarios for existing skills, or rebalancing existing suites.
- Release checks for any repository other than shirabe. The extension hook is
  generic, but only shirabe's declaration ships here.
- Cutting a release to exercise the new precondition.
