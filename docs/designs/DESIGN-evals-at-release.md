---
schema: design/v1
status: Planned
problem: |
  shirabe's work-on verification map makes every skill pull request run
  `scripts/run-evals.sh`, which needs a model, a bash 4 host and a harness
  that can't grade from CI today, while `/shirabe:release` has no hook for a
  repo's own checks and the harness can neither pick the skills changed since
  a tag, choose a model per scenario, nor hand a machine-readable pass rate to
  anything that would compare it across releases.
decision: |
  A bash 3.2 script, `scripts/check-skill.sh <skill>`, becomes the `skills/**`
  map entry and runs validation, template compilation, the skill's script
  tests and a scenario-shape check. `/shirabe:release` imports
  `release.md`/`release.local.md` and runs each command listed under their
  `## Release checks` heading as a new precondition step, with the version,
  last tag and dry-run flag in the environment and a generic exit-5
  confirmation protocol; Phase 4 runs each `## Release assets` command and
  uploads the file it names. shirabe's `release.md` lists one check,
  `scripts/release-eval-check.sh`, which runs the harness per changed skill
  (three runs for work-on, scope and execute), keeps the summaries in a state
  directory under the git directory, and hands them to
  `scripts/lib/eval-pass-rates.py`, which validates the previous release's
  record, merges, and decides drops. The harness gains changed-since-tag
  selection as its no-argument default, a scenario > `EVAL_MODEL` > `sonnet`
  model order, `--summary-out`, and exit-2 propagation under `--runs`. The
  scheduled CI eval run becomes manual-only.
rationale: |
  One script per concern keeps each piece testable without a model: the gate
  script and the record logic both get offline suites, and the harness
  changes ride its existing stubbed-claude suite. Putting the generic hook in
  the release skill and the eval specifics in shirabe's extension keeps the
  skill usable by other repos with no checks declared. A release asset holds
  the record because it needs no commit on a release path whose version-bump
  step stages the whole tree, and keeping the working files under the git
  directory means nothing the release writes can be committed by accident.
upstream: docs/prds/PRD-evals-at-release.md
decision_provenance: inline-resolved
---

# DESIGN: Run skill evals at release time

## Status

Planned

## Context and Problem Statement

The PRD asks for three changes in where shirabe's skill evals run, and each
lands on a different piece of code.

**The pull request gate.** `.claude/shirabe-extensions/work-on.md` maps
`skills/**` to `scripts/run-evals.sh <skill>`, so work-on's
definition-of-done gate runs a model-graded suite for every skill change. The
PRD replaces that with deterministic checks (R1-R3): `shirabe validate` over
the skill's Markdown outside `evals/` and `koto-templates/`,
`koto template compile` over each non-mermaid template, every `*_test.sh`
directly under the skill's `scripts/`, and a shape check on `evals.json`
(every eval has a non-empty `name`, `prompt`, and a non-empty `expectations`
or `assertions` list). All of it has to run under `/bin/bash` 3.2 with only
`shirabe`, `koto`, `python3` and `git`, name a missing tool, and never start
`claude`. A probe over today's tree shows `shirabe validate` already passes
every skill's Markdown with zero errors, so the check can be strict from day
one. The `CLAUDE.md` Skill Evals section must then say three things: a skill
change writes or updates scenarios without running them in the pull request,
evals run in the release precondition, and `scripts/run-evals.sh <skill>` is
the local run (R4). The extension README describes the new entry and names
`release.md` (R5), and every other place that makes the harness a pull
request's definition of done changes too, including the work-on eval
scenario that asserts the old gate (R6).

**The release hook.** `skills/release/SKILL.md` imports no extension, unlike
brief, prd, design and seven other skills. The PRD asks it to import
`release.md` and `release.local.md` after its preflight line (R7), to run
every command an extension lists under `## Release checks` after its
built-in precondition checks, from the repo root, with `RELEASE_VERSION`,
`RELEASE_LAST_TAG` and `RELEASE_DRY_RUN` set, stopping on a non-zero exit and
naming the check (R8), to behave as today when nothing is declared (R9), and
to run the checks in `--dry-run` without touching a GitHub release (R10).

**shirabe's eval check.** shirabe's own `release.md` declares one check that
runs the harness over the skills changed since the last tag, with
`--runs 3` for whichever of work-on, scope and execute changed and not at all
for those that didn't (R11). It writes a record outside the working tree,
replacing any earlier one, holding per skill `runs`, `runs_passed`,
`assertions_passed`, `assertions_graded`, `pass_rate`, the models and
`measured_at`, and carrying forward skills not run this release (R12). The
release uploads it as the asset `eval-pass-rates.json` only when it belongs
to this release, after stamping the version confirmed in Phase 3 (R13).
Before the notes, the check downloads the previous tag's asset and prints
each run skill's rate beside the previous one; a strictly lower rate is a
drop, and a missing, unparseable or unknown-schema asset is "no baseline",
not a failure (R14). A drop fails unless the maintainer confirms it; the
confirmation re-runs the comparison, not the evals, and an inherited
`RELEASE_CONFIRMED_DROPS` confirms nothing. A harness exit of 1 is not a
failure by itself (R15). An infrastructure exit (2, 3 or 4) from any selected
skill, including one run of a repetition, fails the check and leaves that
skill with no `pass_rate` (R16). The record logic has its own CI suite (R17),
and the extension states the host it needs: `claude` with skill-creator,
`python3`, `git`, `gh`, bash 4 (R18).

**The harness.** `scripts/run-evals.sh` (1,515 lines) prints usage and exits
1 when given no skill name. The PRD makes the no-argument form select skills
with evals that have any change under `skills/<name>/` between the last tag
and `HEAD`, print the selection, run it like `--all`, exit 0 with a message
when nothing changed, and select everything with evals when no `v*` tag
exists (R19). Each scenario's model is its `model` key, else `EVAL_MODEL`,
else `sonnet`; the nested session runs on `EVAL_MODEL` or `sonnet`; both
agents of a scenario use the scenario's model, recorded in
`eval_metadata.json` (R20). `--summary-out <file>` writes the per-skill counts
and exit code (R21). Under `--runs N` the repetition loop already stops and
returns on exits 3 and 4, but it counts a run that graded nothing (exit 2) as
an ordinary failure and returns 1; the PRD wants the infrastructure code to
win (R22). The stubbed suite covers all of it (R23).

**CI.** `run-evals.yml` loses its Monday cron and gains a header naming what
it needs, shirabe#612 included (R24). `check-evals.yml` stays (R25), and no
pull request workflow or map entry runs the harness against a model (R26).

## Decision Drivers

- **No model on the pull request path.** Every check the gate runs must be
  deterministic and runnable on a bash 3.2 worker host with the tools it
  already has.
- **Fail closed, and loudly.** A gate or release check that can't run, or a
  harness run that graded nothing, must never read as a pass (PRD R3, R16).
- **Testable without a model.** Each new behavior needs an offline test the
  repo's CI runs, because the harness itself can't be exercised as a
  definition of done here.
- **The release skill stays generic.** It is shipped to other repositories;
  shirabe's eval specifics belong in shirabe's extension.
- **Nothing the release writes can be committed.** `release.yml`'s
  version-bump step runs `git add -A`, and the repository's hygiene rule
  keeps working files out of committed prose, so the record and its inputs
  live under the git directory, not in the tree.
- **The version isn't final until Phase 3.** The release skill confirms the
  version after the precondition phase, so anything stamped earlier may be
  wrong.
- **Existing conventions.** `scripts/check-directive-invocations.sh` scans
  every extension file and requires scripts named by path, executable, with a
  shebang. Helper logic that handles JSON and numbers is standard-library
  Python with offline tests (`scripts/review-shadow/`,
  `scripts/lib/classify-eval-session.py`).
- **Small blast radius in the harness.** `run-evals.sh` is long and its
  stubbed suite is the only safety net; changes should be additive and
  covered case by case.

## Considered Options

### Decision 1: What the `skills/**` map entry runs

The entry needs several checks per changed skill, all on bash 3.2.

Key assumptions:
- The agent running the gate fills `<skill>` with each changed skill's
  directory name and runs the command once per skill, as the extension
  README defines for today's `scripts/run-evals.sh <skill>`; nothing in the
  gate parses the placeholder mechanically.
- `shirabe validate` stays clean on every skill's Markdown, as the probe on
  today's tree showed.

#### Chosen: one script, `scripts/check-skill.sh <skill>`

A bash 3.2 script, run from the repository root, that for `skills/<skill>/`:

1. checks `shirabe`, `koto`, `python3` and `git` are on `PATH`, naming any
   that isn't (exit 2);
2. runs `shirabe validate` once, over all of the skill's Markdown outside
   `evals/` and `koto-templates/`;
3. runs `koto template compile` on each `koto-templates/*.md` that isn't
   `*.mermaid.md`;
4. runs each `scripts/*_test.sh` with `bash`, from the repository root, the
   way the CI workflows invoke them;
5. runs `scripts/lib/check-evals-shape.py` on `evals/evals.json`. A skill
   with no `evals.json` passes only when its `SKILL.md` frontmatter carries
   `disable-model-invocation: true`, read the same way
   `check-evals-exist.sh` reads it; otherwise the missing file fails.

It runs every check, reports each failure with the file it concerns, and
exits 1 if any failed. The map entry becomes
`skills/** -> scripts/check-skill.sh <skill>`.

#### Alternatives Considered

- **Several map lines, one per check.** The schema allows several commands
  per entry. Rejected: the commands would have to be shell loops over globs,
  which `check-directive-invocations.sh` forbids in extension files and which
  no test could cover; one script is testable and reads as one line.
- **Reuse `scripts/check-bash-floor.sh <suite>` for the tests.** Each CI
  suite there lists a skill's tests and runs them on a real 3.2 floor.
  Rejected: suites exist for only some skills, the docker backend needs a
  daemon a worker host may not have, and the gate's job is to run the tests,
  not to prove portability, which CI's floor jobs already do.

### Decision 2: How the release skill declares and runs repo checks

#### Chosen: a `## Release checks` list, run as Phase 2 step 7, with an exit-5 confirmation protocol

`release.md` holds a heading `## Release checks` and a bullet list, one
check per item, each item a command in backticks starting with a repository
path. Phase 2 gains a seventh step after the six built-in checks:

1. Print `git diff --stat <last tag>..HEAD -- scripts/ skills/
   .claude/shirabe-extensions/`, so the maintainer sees the code the checks
   will run.
2. For each item, in order, print the command and the file it came from
   (checks from `release.local.md` are labelled local and run only after the
   maintainer says yes, since that file is untracked), then run it from the
   repository root with `RELEASE_VERSION` (the version Phase 1 recommends or
   the one given), `RELEASE_LAST_TAG` (Phase 1's value, empty on a first
   release) and `RELEASE_DRY_RUN` exported, and `RELEASE_CONFIRMED_DROPS` set
   to the empty string.
3. Exit 0 continues. Exit 5 means the check needs a person to confirm
   something: its last output line reads `confirm: <NAME>=<value>`. The
   skill shows the check's output and asks with `AskUserQuestion`. On a yes it
   re-runs the same command with `<NAME>=<value>` set, without asking again
   about a local check it already approved. On a no, or when nobody can
   answer (the session runs with `--auto`, or the question can't be put to a
   person), the release stops. Any other exit stops the release, naming the
   item and repeating the tail of its output.

No heading, or no extension, means the step prints nothing and does nothing.
The step runs in `--dry-run` because dry-run already runs Phase 2.

Phase 4 gains a second, matching hook. An extension may list commands under
`## Release assets`. After the draft is created, and only when this isn't a
dry run, the skill runs each one from the repository root with
`RELEASE_VERSION` set to the version confirmed in Phase 3 and
`RELEASE_LAST_TAG` set as before. A command that exits 0 with a last output
line `asset: <path>` names a file to attach, and the skill runs
`gh release upload v<version> <path> --clobber`. Exit 0 without that line
means nothing to attach. A non-zero exit, or a failed upload, doesn't stop
the release, since the draft already exists. The skill reports it with the
command to retry, and for shirabe's record it adds that the next release
will otherwise have no baseline. The generic skill knows nothing about pass
rates; shirabe's `release.md` lists
`scripts/release-eval-check.sh --finalize` under the heading.

#### Alternatives Considered

- **A machine-readable file (`release-checks.tsv`) instead of Markdown.**
  Rejected: every other repo-specific setting in this mechanism lives in the
  `@`-imported Markdown the skill already reads, and a second file format
  for one list adds a parser to a skill that has none.
- **Run the checks in Phase 1, before preconditions.** Rejected: an eval run
  is the most expensive thing a release does, and the built-in checks (dirty
  tree, existing tag, blockers) are cheap reasons to stop first.
- **Confirm the version before the checks run.** Rejected: it would reorder
  the release skill's phases so that the notes, which inform the version
  choice, come after a long eval run. Stamping at Phase 4 changes one field
  instead.
- **Treat any drop as a hard failure with no confirmation.** Rejected in the
  PRD: probabilistic scenarios would block releases on noise.
- **Let the check upload the asset itself.** Rejected: the draft doesn't
  exist until Phase 4, after the precondition phase, and keeping checks free
  of release writes is what makes the dry-run promise (R10) hold by
  construction.

### Decision 3: The shape of shirabe's eval check

#### Chosen: a bash orchestrator plus a Python record script, sharing a state directory

The state directory is `$(git rev-parse --git-dir)/shirabe-release/`: inside
the repository's git directory, so it survives between the release skill's
separate shell calls, is per worktree, and can never be committed.

`scripts/release-eval-check.sh --critical work-on,scope,execute
--critical-runs 3` (the arguments are what `release.md` lists, so the list
lives in the extension):

1. Validates `RELEASE_LAST_TAG` (empty, or `^v[0-9]+\.[0-9]+\.[0-9]+$`) and
   `RELEASE_VERSION`.
2. If `RELEASE_CONFIRMED_DROPS` is non-empty and the state directory holds
   summaries for this `HEAD` and last tag, skips straight to step 6: a
   confirmation re-compares the numbers the maintainer saw, it doesn't
   re-measure them.
3. Otherwise empties the state directory, removing any record or summaries
   an earlier run left, and writes a marker naming `HEAD` and the last tag.
4. Asks the harness for the selection with `scripts/run-evals.sh
   --list-changed` (one skill per line).
5. Runs `scripts/run-evals.sh --runs <N> --summary-out <state>/<i>.json
   <skill>` per selected skill, N being 3 for a critical skill and 1
   otherwise, and keeps going after a failure so every skill is reported.
6. With a non-empty `RELEASE_LAST_TAG`, downloads the previous record with
   `gh release download "$RELEASE_LAST_TAG" --repo <owner/repo> --pattern
   eval-pass-rates.json` into a `mktemp -d` directory; an empty tag or a
   failed download means no baseline, with the reason passed on.
7. Calls `scripts/lib/eval-pass-rates.py merge` with the previous record (or
   none), the summaries, the version and the last tag. It writes
   `<state>/eval-pass-rates.json`, prints the comparison table, and exits:
   0 when clean; 1 when any skill's harness exit was 2, 3 or 4, naming each;
   5 when there are drops not listed in `RELEASE_CONFIRMED_DROPS`, ending
   with `confirm: RELEASE_CONFIRMED_DROPS=<a,b>`. An infrastructure failure
   outranks a drop.

A harness exit of 1 (assertions failed) is not a failure here: the skill's
rate is recorded and the drop rule decides, as the PRD settles. Calling the
harness once per skill is also what keeps `--all`'s precedence, where an
exit 1 outranks an infrastructure exit, from hiding a 2, 3 or 4. A skill
whose summary carries exit 2, 3 or 4 gets `exit_code` and no `pass_rate`, so
no consumer can read it as a pass.

`scripts/release-eval-check.sh --finalize` is the Phase 4 half. It refuses,
exiting non-zero, unless the state directory's marker names the current
`HEAD` and `RELEASE_LAST_TAG` and holds a record. Then it calls
`eval-pass-rates.py stamp`, which sets the record's `version`, and the
`measured_at` of the skills listed in the marker as measured by this run, to
`RELEASE_VERSION`. Its last line is `asset: <record path>`. A run that
selected no skill still writes a record, carrying the previous one forward
under the new version, so every release has a baseline to hand on.

#### Alternatives Considered

- **Do it all inside `run-evals.sh`.** Rejected: the harness would grow a
  release concept, a `gh` dependency and JSON merging in an already long
  script whose only safety net is its stubbed suite.
- **jq instead of Python for the record.** Rejected: the merge needs float
  division, field validation and per-skill carry-forward with clear errors;
  the repo's precedent for that is standard-library Python with unit tests,
  and the release host already needs `python3` for the harness.
- **One harness call over all changed skills with a single `--runs`.**
  Rejected: it can't give the critical skills three runs and the rest one,
  and it would collapse per-skill exit codes into one.
- **Keep the record in `wip/`, like the release skill's other files.**
  Rejected: `wip/` files are swept by hygiene and by `git add`; the git
  directory is never committed and survives as long as the release session
  needs it.

### Decision 4: Harness changes

#### Chosen: additive options, the model plumbed through metadata and prompt

- **Selection.** A function computes the changed skills: the last tag from
  `git describe --tags --abbrev=0 --match 'v*'`, then
  `git diff --name-only -z <tag> HEAD -- skills/`, mapped to directory names,
  checked against `^[a-z0-9][a-z0-9-]*$`, and filtered to those with
  `evals/evals.json`; no tag selects every skill with evals. The no-argument
  branch and `--list-changed` both use it, and the no-argument branch runs
  the `--all` loop over the list. `RUN_EVALS_REPO_ROOT` overrides the repo
  root for git, documented as test-only, so the suite can point it at a
  temporary repository.
- **Model.** `EVAL_MODEL` (default `sonnet`) goes to the nested
  `claude -p` as `--model`. Prep writes each scenario's resolved model
  (`model` key, else `EVAL_MODEL`, else `sonnet`) into its
  `eval_metadata.json`, and the per-eval instruction line tells the session
  to spawn that scenario's with-skill and baseline agents on that model.
  Values must match `^[A-Za-z0-9][A-Za-z0-9._:-]*$`; the harness refuses a
  run or scenario that doesn't.
- **Summary.** `--summary-out <file>` writes
  `{"schema": "run-evals-summary/v1", "skills": {<name>: {...}}}` with, per
  skill run, `runs` (attempted, so an early stop shows), `runs_passed`,
  `assertions_passed`, `assertions_graded` (summed from each run's
  `validation_summary.json`), `models` (the distinct values from that
  skill's `eval_metadata.json` files) and `exit_code`. When the loop stops
  early on 3 or 4, the file is still written, with the runs attempted so far
  and that exit code.
- **`--runs` exit.** The repetition loop already returns at once on 3 and
  4. It now also remembers a run that returned 2 and returns 2 at the end,
  ahead of 1.
- **Credentials.** The nested session starts with `GH_TOKEN`,
  `GITHUB_TOKEN` and `SSH_AUTH_SOCK` unset (see Security Considerations).

#### Alternatives Considered

- **Only `--model` on the nested session.** Rejected: the agents the session
  spawns choose their own model unless told, so a session flag alone doesn't
  reach the with-skill and baseline agents, and a per-scenario override would
  have nowhere to go.
- **A separate selection script outside the harness.** Rejected: the
  no-argument default has to live in the harness per the PRD, and two copies
  of "changed since tag" would drift.

### Decision 5: The scheduled CI workflow

#### Chosen: drop the `schedule` trigger, keep `workflow_dispatch`, add a header

The header says what a run needs: the isolated-checkout fix tracked in
shirabe#612, the `ANTHROPIC_API_KEY` secret, and the skill-creator plugin.

#### Alternatives Considered

- **Delete the workflow.** Rejected: whoever fixes #612 needs a way to show
  a dispatched run grading scenarios, and this is it.

## Decision Outcome

A skill change now finishes on `scripts/check-skill.sh`, which runs on any
worker host and fails on anything malformed, including scenarios nobody ran.
The model-graded signal moves to `/shirabe:release`, which learns to run
whatever a repository declares and to ask a person when a check says it needs
one. shirabe declares one check that runs the changed skills' suites on the
cheaper default model, three times for the skills coordinators lean on, and
compares them with the last recorded rate for each skill. The record travels
with each release as an asset, stamped with the version actually released,
so the history accumulates one release at a time with no commit. Every way
the harness can fail to measure ends the release with the skill named. A drop
stops it until a person confirms that drop, against the numbers they were
shown.

## Solution Architecture

```
work-on DoD gate ──> .claude/shirabe-extensions/work-on.md
                       skills/** -> scripts/check-skill.sh <skill>
                                     ├─ shirabe validate (skill *.md)
                                     ├─ koto template compile (templates)
                                     ├─ bash skills/<skill>/scripts/*_test.sh
                                     └─ python3 scripts/lib/check-evals-shape.py

/shirabe:release
  Phase 1  LAST_TAG, release range
  Phase 2  built-in checks 1-6
           step 7: diff --stat; each `## Release checks` item
             └─ scripts/release-eval-check.sh --critical ... --critical-runs 3
                  ├─ scripts/run-evals.sh --list-changed
                  ├─ scripts/run-evals.sh --runs N --summary-out <state>/<i>.json <skill>
                  ├─ gh release download $RELEASE_LAST_TAG --repo ... eval-pass-rates.json
                  └─ scripts/lib/eval-pass-rates.py merge
                        -> <state>/eval-pass-rates.json, table, exit 0|1|5
           exit 5 -> AskUserQuestion -> re-run with confirm: NAME=value
  Phase 3  notes, version confirmed
  Phase 4  gh release create --draft
           each `## Release assets` item (RELEASE_VERSION = confirmed)
             └─ scripts/release-eval-check.sh --finalize
                  └─ eval-pass-rates.py stamp -> "asset: <state>/eval-pass-rates.json"
           gh release upload v<version> <path> --clobber

<state> = $(git rev-parse --git-dir)/shirabe-release/
```

**Components and interfaces:**

| Component | Interface | Exit codes |
|---|---|---|
| `scripts/check-skill.sh` | `<skill>` | 0 passed; 1 a check failed; 2 usage or missing tool |
| `scripts/lib/check-evals-shape.py` | `<evals.json> <SKILL.md>` | 0 sound; 1 malformed, file and eval named; 2 usage |
| `scripts/release-eval-check.sh` | `--critical <a,b> --critical-runs <N>`, or `--finalize`; env `RELEASE_*` | check: 0; 1 infrastructure failure; 5 unconfirmed drops; 2 usage. finalize: 0 with an `asset:` line; 1 when the marker doesn't match |
| `scripts/lib/eval-pass-rates.py` | `merge --previous <file or -> --summary <file>... --version <v> --last-tag <t> --out <file>`; `stamp --record <file> --version <v> --measured <skill>...` | merge 0, 1, 5; stamp 0, or 1 on an invalid record |
| `scripts/run-evals.sh` | adds no-arg default, `--list-changed`, `--summary-out <file>`, `EVAL_MODEL`, `RUN_EVALS_REPO_ROOT` | unchanged codes; `--runs` now returns 2 |

**Record (`eval-pass-rates/v1`):**

```json
{
  "schema": "eval-pass-rates/v1",
  "version": "0.24.0",
  "last_tag": "v0.23.0",
  "skills": {
    "scope": {"runs": 3, "runs_passed": 2, "assertions_passed": 140,
              "assertions_graded": 150, "pass_rate": 0.9333,
              "models": ["sonnet"], "measured_at": "0.24.0"},
    "brief": {"runs": 1, "runs_passed": 0, "assertions_passed": 0,
              "assertions_graded": 0, "exit_code": 2,
              "models": ["sonnet"], "measured_at": "0.24.0"}
  }
}
```

`pass_rate` is `assertions_passed / assertions_graded`, rounded to four
places, present only when the harness exit was 0 or 1 and at least one
assertion was graded. A skill absent from this release's summaries is copied
from the previous record unchanged. Drops are decided on the rounded values.

**Tests.** `scripts/check-skill_test.sh` builds throwaway skills in a temp
tree, through a test-only `CHECK_SKILL_ROOT` override, and covers each
failure the PRD lists, a missing tool, and `claude` never being called. It
runs in a new `check-skill-gate.yml` workflow on ubuntu and on macOS's
`/bin/bash` 3.2. `scripts/lib/eval-pass-rates_test.py` (unittest) and
`scripts/release-eval-check_test.sh`, with stub `gh` and stub `run-evals.sh`
on `PATH`, cover these cases:

- a drop, an equal rate, and no baseline from a missing asset, an
  unparseable one, an unknown schema or an empty last tag;
- every field-validation failure, and carry-forward;
- infrastructure exits, harness exit 1 with no drop, and confirmed and
  unconfirmed drops;
- the confirmation re-run making no harness call, and a stale record being
  removed;
- `--finalize` with a matching marker (an `asset:` line, the version and the
  measured skills' `measured_at` rewritten, carried skills untouched), with a
  marker from another `HEAD` or tag (refused), and no `gh release upload`
  call anywhere in the check.

Both run as new jobs in `check-run-evals.yml`, whose path filter gains the
new files. `scripts/run-evals_test.sh` gains the harness cases, including
that the stub `claude` sees no `GH_TOKEN`.

## Implementation Approach

1. **Harness.** Selection function, no-argument default, `--list-changed`,
   `RUN_EVALS_REPO_ROOT`, `EVAL_MODEL` and the per-scenario model in metadata
   and prompt, `--summary-out`, exit 2 under `--runs`, credential unsetting,
   and the new cases in `run-evals_test.sh`. Independent of everything else.
2. **Pass-rate record and eval check.** `scripts/lib/eval-pass-rates.py`,
   `scripts/release-eval-check.sh`, their suites, and the CI jobs. Depends on
   step 1 for `--list-changed` and `--summary-out`.
3. **Release hook and shirabe's declaration.** In `skills/release/SKILL.md`:
   the import lines after the preflight line, Phase 2 step 7 with the diff,
   the local-check confirmation and the exit-5 protocol, and the Phase 4
   `## Release assets` hook. `.claude/shirabe-extensions/release.md` lists the
   eval check under `## Release checks` with work-on, scope and execute at
   three runs and `--finalize` under `## Release assets`, notes that
   unchanged critical skills don't run, names the asset, and
   lists the host it needs: `claude` with the skill-creator plugin,
   `python3`, `git`, `gh` and bash 4. Release eval scenarios cover a passing
   check, a failing check, a check needing confirmation and no extension. The
   bash-floor exemption comment for `run-evals.sh` changes to say it now runs
   from the release session. Depends on step 2.
4. **Pull request gate.** `scripts/check-skill.sh`,
   `scripts/lib/check-evals-shape.py`, `check-skill_test.sh` and
   `check-skill-gate.yml`. The `work-on.md` entry and the README change. The
   CLAUDE.md Skill Evals section gets its three statements. Every
   instruction outside `scripts/`, `.github/workflows/`, historical `docs/`
   and `release.md` that makes the harness a pull request's definition of
   done changes, including the work-on scenario that asserted the old gate.
   Independent of steps 1-3 in code, but it lands last, so pull requests stop
   running evals only once the release runs them.
5. **CI cleanup.** Drop the cron from `run-evals.yml` and add its header.
   Independent.

## Security Considerations

**The downloaded baseline is untrusted input.** The record isn't signed:
anyone who can replace a release asset can already alter the release itself.
But a forged baseline is not harmless. Rates set to zero would hide a
regression in every skill at once for that release, and rates set to one
would force a confirmation on every skill. So `eval-pass-rates.py` treats the
file as hostile. It's downloaded by exact asset name, with `--repo` pinned,
into a `mktemp -d` directory outside the repository, after
`RELEASE_LAST_TAG` is checked against the tag pattern. The Python side
reads it under a size cap and accepts it only if every field passes these
checks:

- `schema` is `eval-pass-rates/v1`;
- `version` and every `measured_at` match a bare semver;
- `last_tag` matches the tag pattern;
- every skill name matches `^[a-z0-9][a-z0-9-]*$`;
- every model matches `^[A-Za-z0-9][A-Za-z0-9._:-]*$`;
- counts are non-negative integers with `runs_passed <= runs` and
  `assertions_passed <= assertions_graded`;
- `pass_rate` is a finite number in [0, 1] that agrees with the counts.

A record that fails any check, or that raises any parsing error, is "no
baseline" with a warning, not a crash. The warning names the failing field
and never prints its value. Carried-forward entries pass the same checks, and
the new record is built from an explicit list of fields, so an unknown key
never propagates into the next release.

**Only this run's record is published.** The eval check empties its state
directory before measuring, so a stale or dry-run record can't survive into a
real release. `--finalize` refuses unless the state marker names the current
`HEAD` and this release's last tag, and the upload happens only after it
succeeds.

**Names and values reaching a shell.** Skill names from `git diff` and the
gate's `<skill>` argument are checked against the skill-name pattern before
use and always quoted; temporary summary files are named by index, not by
skill. A scenario's `model` and `EVAL_MODEL` must match the model pattern,
which can't start with `-`, before either reaches `--model` or the per-eval
instruction line. `RUN_EVALS_REPO_ROOT` and `CHECK_SKILL_ROOT` are
documented as test-only in their scripts and appear in no extension file.

**What runs on the release host.** The release skill's `allowed-tools`
isn't widened; each declared check runs under the session's normal
permission handling, and the skill prints the code diff and each command
with the file it came from before running it. Commands start with a
repository script path and contain no shell operators, which
`check-directive-invocations.sh` already enforces for tracked extension
files. `release.local.md` is untracked and unreviewed, so its checks are
labelled local and run only after the maintainer says yes.

**The nested eval session, and the risk this design accepts.** The harness's
nested `claude -p` session keeps `--permission-mode acceptEdits
--allowedTools Bash`. Scenario prompts and the skill content they load run
shell without prompting, on the maintainer's host, driven by content pull
requests in the release range authored. The harness unsets `GH_TOKEN`,
`GITHUB_TOKEN` and `SSH_AUTH_SOCK` for the session. That narrows the
exposure but doesn't close it: stored `gh` logins, git credential helpers and
SSH keys on disk stay reachable. The eval check says so in its own output:
before running any eval it prints the host it runs on and that the nested
sessions can reach that host's stored credentials, so the release log
records the exposure, not only this document.

This exposure isn't new. Today `CLAUDE.md` tells every agent that changes a
skill to run the same harness, in the same mode, on whatever host it works
on. The design moves those runs into one session per release, run by a
maintainer who has just been shown the diff of what will execute. Sandboxing
the session, or moving release evals into CI under a protected environment,
would close the gap. Both need the isolated-checkout fix tracked in
shirabe#612 first, so they are left as follow-up proposals rather than done
here.

**Drop confirmation.** The release step sets `RELEASE_CONFIRMED_DROPS` to the
empty string on the first run, so a value inherited from the environment
can't pre-confirm a drop. The confirmation is an `AskUserQuestion` answered
by a person, and only the re-run after that answer carries a list. A session
with nobody to ask stops.

**What is published.** The release asset holds skill names, counts, rates,
model names, the version and the last tag, all from an allow-listed set of
fields. It holds no prompts, transcripts or command output.

**CI.** `check-skill-gate.yml` triggers on `pull_request` with
`permissions: contents: read` and no secrets, since it runs shell from the
pull request's own skill directories, as the existing script-suite workflows
already do.

## Consequences

### Positive

- A skill pull request needs no model, no bash 4 and no waiver; workers on
  3.2 hosts can meet the gate.
- Scenario files are checked for shape on every change, so a malformed
  scenario fails in its pull request rather than at release.
- Each release carries a pass rate for every skill it measured, stamped with
  the version that shipped, and regressions surface as numbers with a person
  deciding.
- Release checks become available to any repository using the release skill.

### Negative

- Behavioral regressions are caught later, at release, after several pull
  requests may have stacked on the one that caused them.
- A release that changed a skill can't complete while the harness can't
  grade on the release host (#612); the release check says so, but the
  maintainer has to fix the harness or stop.
- Release time and cost grow with the number of changed skills, and three
  runs each for work-on, scope and execute is the bulk of it.
- The generic release skill learns a small protocol (exit 5 with a
  `confirm:` line, and asset commands ending in an `asset:` line) that other
  repositories only meet if they use it.

### Mitigations

- Authors can still run `scripts/run-evals.sh <skill>` locally on a bash 4
  host before merging a risky change; CLAUDE.md says how.
- The critical list and run count live in `release.md`, so trimming cost is
  a one-line change with no code involved.
- The record names the version each rate was measured at, so a late-caught
  regression narrows to the releases between two measurements.
