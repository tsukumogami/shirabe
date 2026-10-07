---
schema: prd/v1
status: In Progress
problem: |
  Agents that change a shirabe skill must run its full model-graded eval suite
  at work-on's definition-of-done gate. The suite is slow and noisy, it can't
  run from CI or from bash 3.2 worker hosts today, so each skill pull request
  waives the gate by hand, and the release, where a full pass is worth paying
  for, runs no behavioral check at all.
goals: |
  A skill pull request finishes on deterministic checks any host can run. The
  release session runs the evals of every skill changed since the last tag,
  records pass rates the next release reads, compares them with the last
  recorded ones, and stops when the harness grades nothing.
source_issue: 593
absorbed:
  - docs/briefs/BRIEF-evals-at-release.md
---

# PRD: evals-at-release

## Status

In Progress

Absorbed [BRIEF-evals-at-release](docs/briefs/BRIEF-evals-at-release.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists because the only behavioral test shirabe has for its
skills is asked for at the most expensive point it could be: every pull
request that touches a skill. There it is costly, noisy from one run to the
next, and today impossible to meet from CI or from the bash 3.2 hosts workers
run on, so agents stop on it and waive it by hand, while the release, where a
full pass is worth paying for, checks nothing about skill behavior. This
document's Problem Statement states that in full.

The outcome it asked for is a worker or coordinator who finishes a skill
change on checks it can run anywhere, with no waiver, and a maintainer who
pays for the behavioral signal once, at release, seeing each changed skill's
pass rate beside the last one and a harness that cannot grade stopping the
release instead of passing it. Those are this document's Goals. The brief's
four journeys, a worker finishing a skill change, a maintainer cutting a
release, the harness breaking on release day and an author adding a scenario
on a stronger model, are its User Stories 1 to 4, and its scope boundary is
the Requirements and Out of Scope below.

## Problem Statement

Skill evals are the only behavioral test shirabe has for its skills, and the
repo asks for them on every pull request that touches one. The work-on
extension binds `skills/**` to `scripts/run-evals.sh <skill>` in its
verification map, so the definition-of-done gate won't pass a skill change
until that skill's suite has run and passed. `CLAUDE.md` says the same in its
Skill Evals section.

Three things make that the wrong place. Each run starts a nested `claude -p`
session that spawns two agents per scenario, on the strongest model, and the
larger suites hold dozens of scenarios, so a fix round costs dozens of agent
sessions. One run of a probabilistic scenario says little about whether a
change regressed the skill. And the gate can't be met: `run-evals.yml` fails
before grading on dispatched branches and grades zero evals on its scheduled
run on main (shirabe#612), while the worker hosts coordinators dispatch to
have bash 3.2 and refuse tool installs. Pull requests #609, #619 and #622 each
changed `skills/**` and each recorded a hand-written waiver in its body.

The release, the one point where a full pass over the changed skills is worth
its cost, checks the tree, CI, tags and blocker labels, and nothing about
skill behavior. This matters now because autonomous coordinators open most
pull requests in this repo, and a gate they stop on every time is the
opposite of the cheap, unattended run the repo is working toward.

## Goals

- A worker or coordinator changing a skill finishes work-on's
  definition-of-done gate on deterministic checks that run on any worker host
  without a model call, writes or updates the scenarios that cover the change,
  and records no waiver.
- The maintainer cutting a release sees, before the tag exists, the eval
  results of every skill changed since the last release, with repeated runs
  on the skills coordinators run most and each pass rate set beside the last
  recorded one.
- A harness that cannot grade stops the release and says so; it never reads
  as a pass.

## User Stories

1. As a worker dispatched to change a skill, I want the definition-of-done
   gate to run that skill's validation, template compilation, script tests and
   scenario-shape check on the bash 3.2 host I have, so that I can finish the
   pull request without a waiver.
2. As a maintainer cutting a release, I want the release precondition to run
   the evals of every skill changed since the last tag and show each pass rate
   next to the last recorded one, so that a regression shows up as a number
   that dropped before I tag.
3. As a maintainer on a host where the eval harness can't start, I want the
   release check to fail and name the skill that graded nothing, so that I
   don't ship over a check that measured nothing.
4. As a skill author adding a scenario, I want to set a `model` key on it so
   it runs on a stronger model than the default, while scenarios without the
   key run on Sonnet, so that the release pays for the strong model only where
   a scenario asks for it.
5. As a maintainer of another repo using shirabe's release skill, I want the
   release precondition to run whatever checks my repo declares and to behave
   as before when I declare none, so that the hook costs me nothing until I
   use it.

## Requirements

Identifiers used below: the **last tag** is the output of
`git describe --tags --abbrev=0 --match 'v*'`, the same value `/shirabe:release`
Phase 1 computes. A skill's **pass rate** is assertions passed divided by
assertions graded, summed over every run of that skill in one release check.
The harness's **infrastructure exit codes** are 2 (nothing graded, or a
scenario graded zero assertions), 3 (prerequisites or suite missing) and 4
(nested session did not execute), as `scripts/run-evals.sh` defines them.

### Pull request gate

- **R1.** The `skills/**` entry of `.claude/shirabe-extensions/work-on.md`
  runs one command per changed skill, where a changed skill is a directory
  `skills/<name>/` holding at least one file the issue changed. For that
  skill the command runs: `shirabe validate` over the skill's Markdown files,
  excluding `evals/` and `koto-templates/`; `koto template compile` over each
  file in `koto-templates/` except `*.mermaid.md`; and every `*_test.sh`
  directly under the skill's `scripts/` directory. It does not run
  `scripts/run-evals.sh` or start `claude`.
- **R2.** The same command checks the skill's `evals/evals.json`: it must
  parse as JSON, and every entry under `evals` must have a non-empty `name`, a
  non-empty `prompt`, and at least one of `expectations` or `assertions` as a
  non-empty list. A failure names the file and the offending eval. A skill
  whose `SKILL.md` declares `disable-model-invocation: true` and has no
  `evals/evals.json` passes this check, matching `check-evals-exist.sh`.
- **R3.** The command runs under `/bin/bash` 3.2 and needs only `shirabe`,
  `koto`, `python3` and `git`. When a tool it needs is missing it exits
  non-zero and names the tool, so the gate fails closed as the
  verification-map schema requires.
- **R4.** The `## Skill Evals` section of `CLAUDE.md` says three things: a
  skill change creates or updates its scenarios in `evals/evals.json` without
  running them in the pull request; the evals run in the release precondition;
  and an author who wants a local run uses `scripts/run-evals.sh <skill>`.
- **R5.** `.claude/shirabe-extensions/README.md` describes the `skills/**`
  entry's checks, states that evals run at release, and names
  `.claude/shirabe-extensions/release.md` as where that check is declared.
- **R6.** Every other place in the repository that tells an agent to run
  `scripts/run-evals.sh` as a pull request's definition of done is updated,
  including the work-on eval scenario that asserts the gate runs it.

### Release precondition

- **R7.** `skills/release/SKILL.md` imports
  `@.claude/shirabe-extensions/release.md` and
  `@.claude/shirabe-extensions/release.local.md` directly after its preflight
  line, the same form brief, prd and design use.
- **R8.** An extension declares release checks as a list under a
  `## Release checks` heading, one check per item, each naming the command to
  run. The release skill's precondition phase runs each declared check after
  its built-in checks, in the order listed, from the repository root, with
  `RELEASE_VERSION`, `RELEASE_LAST_TAG` and `RELEASE_DRY_RUN` (`1` or `0`) in
  its environment. A check that exits non-zero stops the release, and the
  report names the check and repeats the last lines of its output.
- **R9.** With no extension file, or one with no `## Release checks` heading,
  the precondition phase runs only its built-in checks, as today.
- **R10.** Declared checks run in `--dry-run` as in a real release. A check
  must not create or modify a GitHub release when `RELEASE_DRY_RUN` is `1`.

### shirabe's release checks

- **R11.** `.claude/shirabe-extensions/release.md` declares one release
  check, the eval check, that runs `scripts/run-evals.sh` over the skills
  changed since the last tag. The critical skills are work-on, scope and
  execute; each of them that is among the changed skills runs with
  `--runs 3`. A critical skill that didn't change doesn't run.
- **R12.** The eval check writes the pass-rate record to a file outside the
  working tree, where no commit can pick it up, and replaces any record an
  earlier run left there. The record holds a `schema` value, the release
  version, the last tag, and per skill: `runs`, `runs_passed`,
  `assertions_passed`, `assertions_graded`, `pass_rate`, the models its
  scenarios ran on, and `measured_at` (the version the numbers were measured
  at). Skills not run in this release are carried forward unchanged from the
  previous record, keeping their original `measured_at`, so every release's
  record holds the latest rate for every skill ever measured.
- **R13.** In a real release, the release skill uploads the record to the
  draft release as the asset `eval-pass-rates.json` after creating the draft,
  replacing an existing asset of that name, and only when the record's
  version and last tag are this release's. Before uploading it sets the
  record's version, and the `measured_at` of the skills measured in this run,
  to the version confirmed in Phase 3. In a dry run nothing is uploaded.
- **R14.** Before notes are drafted, the eval check downloads
  `eval-pass-rates.json` from the release for the last tag and prints, per
  skill run in this release, the current pass rate, the previous one and the
  version it was measured at. A skill is a **drop** when its pass rate is
  strictly lower than the previous one. A previous release with no such
  asset, or an asset that doesn't parse or has an unknown `schema`, gives
  every skill "no baseline", with a warning naming the reason; "no baseline"
  is not a failure.
- **R15.** When any skill dropped, the eval check exits non-zero unless the
  maintainer has confirmed the drop for that release. The release skill asks
  for that confirmation, naming each dropped skill and both rates, and on a
  yes re-runs the comparison, without re-running any eval, with the
  confirmed skills named in `RELEASE_CONFIRMED_DROPS` (comma-separated). A
  drop whose skill isn't in that list still fails, and a value of that
  variable inherited from the environment confirms nothing. A release run
  without a person to ask stops on a drop. A skill whose harness exit was 1
  (assertions failed) is not a failure by itself: its rate is recorded and
  the drop rule decides.
- **R16.** The eval check exits non-zero, naming the skill and the exit code,
  when the harness returns an infrastructure exit code for any selected
  skill, including when one run of a `--runs 3` repetition graded nothing. It
  writes no record that would read as a pass for a skill whose runs graded
  zero assertions.
- **R17.** The comparison and record-merge logic lives in a script that the
  eval check calls and that has its own test suite run in CI, so drop, no
  baseline, malformed baseline and carry-forward are tested without a model.
- **R18.** `release.md` states what the eval check needs on the host:
  `claude` with the skill-creator plugin, `python3`, `git`, `gh`, and bash 4 or
  later. The release session is where that host is assumed; the eval check
  doesn't verify the bash version itself.

### Eval harness

- **R19.** `scripts/run-evals.sh` with no skill name selects the skills that
  have `evals/evals.json` and have any added, modified, renamed or deleted
  file under `skills/<name>/`, its `evals/` directory included, between the
  last tag and `HEAD`. It prints the selected skills before running, and runs
  them with the same failure collection and exit precedence `--all` uses. When
  nothing changed it prints that no skill changed since the tag and exits 0.
  With no `v*` tag it selects every skill with evals and prints that no tag
  was found. A skill name, `--all` and `--list` keep their current meaning,
  and `--runs` applies to whichever selection is made.
- **R20.** The model a scenario runs on is, in order: the scenario's `model`
  key in `evals.json`; else the `EVAL_MODEL` environment variable; else
  `sonnet`. The value takes the form `claude --model` accepts (an alias such
  as `sonnet` or `opus`, or a full model ID). The nested session runs on
  `EVAL_MODEL`, else `sonnet`. The with-skill and baseline agents of a
  scenario both run on the scenario's model, and the model is written into
  the scenario's `eval_metadata.json` as `model`.
- **R21.** `scripts/run-evals.sh --summary-out <file>` writes, for the skills
  it ran, the per-skill counts the pass-rate record needs (R12) and each
  skill's harness exit code, so the eval check never parses the
  human-readable report.
- **R22.** Under `--runs N`, a run that returned an infrastructure exit code
  makes the invocation exit with that code, even when other runs failed
  assertions. Runs that failed assertions, with no run returning an
  infrastructure code, still exit 1.
- **R23.** `scripts/run-evals_test.sh` covers, with its stub `claude`:
  changed-since-tag selection (a changed skill, an unchanged one, an
  `evals/`-only change, no tag, nothing changed); the model default, the
  `EVAL_MODEL` override and a per-scenario `model` key; `--summary-out`; and
  the `--runs` exit code when a run graded nothing.

### CI

- **R24.** `.github/workflows/run-evals.yml` has no `schedule` trigger. It
  stays dispatchable by hand, and a comment at its top says what it needs to
  produce a result: the isolated-checkout fix tracked in shirabe#612, the
  `ANTHROPIC_API_KEY` secret and the skill-creator plugin.
- **R25.** `check-evals.yml` and `scripts/check-evals-exist.sh` are unchanged.
- **R26.** No pull request CI workflow and no verification-map entry runs
  `scripts/run-evals.sh` against a real model. The stubbed
  `scripts/run-evals_test.sh` suite is not affected.

## Acceptance Criteria

Pull request gate:

- [ ] `grep -n 'run-evals.sh' .claude/shirabe-extensions/work-on.md` prints
  nothing, and the `skills/**` entry names one command taking the skill name.
- [ ] Run against `release` (a skill with no `koto-templates/` and no
  `scripts/`) under `/bin/bash` 3.2, the command exits 0, and a `claude` stub
  on `PATH` that records calls is never called.
- [ ] Run against `work-on`, the command compiles each
  `skills/work-on/koto-templates/*.md` except `work-on.mermaid.md` and runs
  each `skills/work-on/scripts/*_test.sh`.
- [ ] In a copy of the repository, each of these makes the command exit
  non-zero and name the file: `evals.json` that is not JSON; an eval with an
  empty `expectations` list and no `assertions`; an eval with no `prompt`; a
  skill Markdown file that `shirabe validate` rejects; a koto template that
  fails `koto template compile`; a `*_test.sh` that exits 1.
- [ ] With `koto` absent from `PATH`, the command run against `work-on` exits
  non-zero and names `koto`.
- [ ] The `## Skill Evals` section of `CLAUDE.md` contains no instruction to
  run `scripts/run-evals.sh` before committing, states that scenarios are
  written without running them in the pull request, states that evals run in
  the release precondition, and names `scripts/run-evals.sh <skill>` as the
  local run.
- [ ] `.claude/shirabe-extensions/README.md` names the `skills/**` checks, says
  evals run at release, and names `.claude/shirabe-extensions/release.md`.
- [ ] Outside `scripts/`, `.github/workflows/`, historical documents under
  `docs/` and `release.md`, no line found by `git grep -n 'run-evals.sh'`
  makes the harness a pull request's definition of done, and the work-on
  scenario that asserted it now asserts the deterministic checks.

Release precondition:

- [ ] `skills/release/SKILL.md` has the two
  `@.claude/shirabe-extensions/release*.md` lines directly after its
  preflight line.
- [ ] Its precondition phase has a step that runs each `## Release checks`
  item with `RELEASE_VERSION`, `RELEASE_LAST_TAG` and `RELEASE_DRY_RUN` set,
  stops on a non-zero exit naming the check, says that a missing extension or
  heading means no declared checks, and says declared checks also run in
  `--dry-run`.
- [ ] A release eval scenario covers each of: a declared check that passes, a
  declared check that fails (the release stops and names it), and no
  extension (the built-in checks only).

shirabe's release checks:

- [ ] `.claude/shirabe-extensions/release.md` exists, passes
  `scripts/check-directive-invocations.sh`, and its `## Release checks` list
  has one item naming the eval check's script. It names work-on, scope and
  execute with `--runs 3`, the asset `eval-pass-rates.json`, and the host
  requirements of R18.
- [ ] The comparison script's test suite runs in CI and passes cases for: a
  drop (exit non-zero, the skill and both rates named); an equal or higher
  rate (exit 0); a previous release with no asset, an unparseable asset and an
  unknown `schema` (each "no baseline" with a warning, exit 0); carry-forward
  of a skill not run this release with its `measured_at` unchanged; a skill
  whose harness exit was 2, 3 or 4 (exit non-zero naming the skill and code,
  and the written record gives that skill no `pass_rate`); a drop with the
  skill in `RELEASE_CONFIRMED_DROPS` (exit 0); and a drop with a different
  skill in that list (exit non-zero).
- [ ] The release skill's precondition step says that on a failing eval check
  caused by a drop it asks the maintainer, names each dropped skill and both
  rates, and re-runs with `RELEASE_CONFIRMED_DROPS`; and that without a person
  to ask the release stops.
- [ ] With `RELEASE_DRY_RUN=1`, the eval check makes no `gh release upload`
  call, verified against a `gh` stub in a test suite run in CI.
- [ ] The release skill's Phase 4 uploads the record as
  `eval-pass-rates.json` with `--clobber` only when the record exists, its
  last tag is this release's, and the run is not a dry run, after setting its
  version to the confirmed one.
- [ ] A record left by an earlier run is gone or replaced once the eval check
  starts, verified in the eval check's test suite.

Eval harness:

- [ ] In a test repository with tag `v0.1.0` and a later commit changing
  `skills/demo/evals/evals.json` only, `scripts/run-evals.sh` with no skill
  name selects `demo` and not `pair`.
- [ ] With no change since the tag it prints that no skill changed and exits
  0; with no `v*` tag it selects every skill with evals and prints that no tag
  was found.
- [ ] A stubbed run of a scenario with no `model` key and no `EVAL_MODEL`
  passes `--model sonnet` to `claude` and writes `"model": "sonnet"` to
  `eval_metadata.json`; with `EVAL_MODEL=opus` both read `opus`; a scenario
  with `"model": "haiku"` writes `haiku` whatever `EVAL_MODEL` says.
- [ ] `--summary-out <file>` writes valid JSON with `runs`, `runs_passed`,
  `assertions_passed`, `assertions_graded` and the exit code per skill run.
- [ ] `scripts/run-evals.sh --runs 3 <skill>` exits 2 when one of the three
  stubbed runs graded nothing and another failed an assertion.
- [ ] `scripts/run-evals_test.sh` passes in `check-run-evals.yml` with a case
  for each item in R23.

CI:

- [ ] `.github/workflows/run-evals.yml` has no `schedule:` key, keeps
  `workflow_dispatch`, and its header comment names shirabe#612,
  `ANTHROPIC_API_KEY` and skill-creator.
- [ ] `git diff` against the base shows no change to `check-evals.yml` or
  `scripts/check-evals-exist.sh`.
- [ ] `grep -rn 'run-evals.sh' .github/workflows/` matches only
  `run-evals.yml` (manual) and `check-run-evals.yml` (the stubbed suite).

## Out of Scope

- Fixing the isolated-checkout failure and the zero-graded scheduled run
  (shirabe#612). This work makes the release check fail loudly when the
  harness can't grade; it doesn't make the harness work.
- Making `scripts/run-evals.sh` run on bash 3.2. The release session assumes
  a bash 4 host.
- Changing review panels: seat models, seat counts or panel routing.
- Writing new scenarios for existing suites, or adding `model` keys to
  existing scenarios. Updating the scenarios that assert the old pull request
  gate (R6) and adding release scenarios for the new precondition step are
  in scope.
- Release checks for repositories other than shirabe; only the generic hook
  and shirabe's declaration ship here.
- Running the eval harness as a definition of done for this work: it is the
  thing being moved, and it can't run on the hosts that build it.
- Cutting a release to exercise the new precondition.

## Decisions and Trade-offs

- **Pass rates live in a release asset.** Alternatives: a committed file, or a
  section of the release notes. A committed file needs a commit on the release
  path, and the release workflow's version-bump step stages the whole tree, so
  a stray record would be swept into it. Notes are user-facing, and the next
  release would have to parse prose. An asset on the draft release is
  machine-readable, travels with the version it measured, and the finalize
  step's asset-count wait already tolerates extra assets. (Closes the brief's
  first open question.)
- **The record carries every skill forward.** Each release runs only the
  skills that changed, so a record holding only those would leave most skills
  without a baseline one release later. Carrying unmeasured skills forward
  with their `measured_at` keeps the latest number for each skill one
  download away.
- **The first release after this lands has no baseline.** Its comparison
  reports "no baseline" for every skill and fails only on infrastructure exit
  codes. (Closes the brief's first open question.)
- **Critical skills are work-on, scope and execute, at three runs each.** They
  are what coordinators run on every unit of work, and three runs is the
  smallest count that separates a flaky scenario from a broken one at a cost
  a release can carry. The extension holds the list, so it changes without
  touching the harness. (Closes the brief's second open question.)
- **A drop needs explicit confirmation rather than failing outright, and any
  decrease counts.** A tolerance would have to be tuned per suite with data
  nobody has yet. A strict comparison plus a confirmation keeps a person in
  the loop for every decrease, and one question costs little in a session that
  already confirms the version. An unattended run stops, because nobody can
  confirm.
- **"Changed" means a file under `skills/<name>/`.** A change to shared
  `scripts/` doesn't select every skill; that would turn every release into
  `--all`.
- **With no `v*` tag, every skill with evals is selected**, since everything
  is new relative to nothing; a refusal would leave the first release with no
  default.
- **The scheduled workflow is made manual-only rather than deleted**, so the
  #612 fix has a place to prove itself.
- **The gate checks scenario shape, not only presence.** Scenarios are now
  written without being run, so a malformed one would otherwise surface only
  at release.

## Known Limitations

- The release check depends on the eval harness, which can't grade from CI
  today (shirabe#612). Until #612 is understood, a release host may hit the
  same failure, and the release check will then fail, loudly, on any release
  that changed a skill. That is the intended behavior: a release that ships
  changed skills without a behavioral check should have to say so.
- The bash 4 requirement is carried from the worker-host reports; no bash 4
  construct was found in `scripts/run-evals.sh`.
- Pass rates compare runs on whatever model each scenario ran on. The record
  stores the models, and a change between releases is visible there, but the
  comparison doesn't adjust for it.
- How long a skill's script tests take is set by the tests, not by this
  work; the gate for `coordinate`, with dozens of suites, takes longer than
  for a skill with none.
