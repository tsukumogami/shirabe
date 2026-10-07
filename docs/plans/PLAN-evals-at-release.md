---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
upstream: docs/designs/DESIGN-evals-at-release.md
milestone: "Evals at release"
issue_count: 5
---

# PLAN: Evals at release

## Status

Active

## Scope Summary

Move shirabe's skill evals off the work-on pull request gate and into a
release precondition: a deterministic `scripts/check-skill.sh` for
`skills/**`, a generic release-check and release-asset hook in
`/shirabe:release`, shirabe's eval check with a pass-rate record compared
from release to release, and the harness changes that feed it.

## Decomposition Strategy

**Horizontal.** The design's components meet at explicit interfaces (the
harness's `--list-changed` and `--summary-out`, the record script's `merge`
and `stamp`, the release skill's `## Release checks` and `## Release assets`
protocol), so each layer is finished and tested before the next one calls
it. The pull request gate change comes last, so pull requests stop running
evals only once the release runs them. The workflow cleanup is independent.
Everything lands in one pull request: the gate change alone would drop evals
with nothing in their place.

## Issue Outlines

### Issue 1: feat(run-evals): select changed skills, pick models per scenario, write summaries

**Goal**: Give `scripts/run-evals.sh` a changed-since-tag default selection, a per-scenario model, a machine-readable summary and a `--runs` exit that keeps "graded nothing", each covered by its stubbed suite.

**Acceptance Criteria**:
- [ ] With no skill name, the harness selects the skills with `evals/evals.json` that have any added, modified, renamed or deleted file under `skills/<name>/` between `git describe --tags --abbrev=0 --match 'v*'` and `HEAD`, prints the selection, and runs it through the `--all` loop; with nothing changed it prints that no skill changed and exits 0; with no `v*` tag it selects every skill with evals and prints that no tag was found.
- [ ] `--list-changed` prints the same selection, one skill per line, and runs nothing; names are checked against `^[a-z0-9][a-z0-9-]*$`, and the diff uses `-z --no-renames` so a rename selects both the old and the new skill.
- [ ] `RUN_EVALS_REPO_ROOT` overrides the repository root used for git and is documented in the script as test-only.
- [ ] The nested `claude -p` gets `--model` set to `EVAL_MODEL`, else `sonnet`; each scenario's `eval_metadata.json` gets `"model"` set to its `model` key, else `EVAL_MODEL`, else `sonnet`; the per-eval instruction line tells the session to spawn that scenario's with-skill and baseline agents on that model. A value not matching `^[A-Za-z0-9][A-Za-z0-9._:-]*$` is refused.
- [ ] `--summary-out <file>` writes `{"schema": "run-evals-summary/v1", "skills": {...}}` with `runs`, `runs_passed`, `assertions_passed`, `assertions_graded`, `models` and `exit_code` per skill run, including when `--runs` stops early on exit 3 or 4.
- [ ] Under `--runs N`, a run returning 2 makes the invocation exit 2 even when another run failed assertions; runs that only failed assertions still exit 1.
- [ ] The nested session starts with `GH_TOKEN`, `GITHUB_TOKEN` and `SSH_AUTH_SOCK` unset.
- [ ] `scripts/run-evals_test.sh` has passing cases for: a changed skill selected and an unchanged one not, an `evals/`-only change, no tag, nothing changed; `--model sonnet` by default, `EVAL_MODEL=opus`, and a scenario `"model": "haiku"` winning over `EVAL_MODEL`; `--summary-out` contents; `--runs 3` exiting 2 with one nothing-graded run and one failed run; and the stub `claude` seeing no `GH_TOKEN`.
- [ ] `check-run-evals.yml` passes on the branch.

**Dependencies**: None

**Type**: code
**Files**: `scripts/run-evals.sh`, `scripts/run-evals_test.sh`

### Issue 2: feat(release): add the pass-rate record and the shirabe eval check

**Goal**: Add `scripts/lib/eval-pass-rates.py` and `scripts/release-eval-check.sh`, which run the changed skills' evals, validate and merge the previous release's record, decide drops, and hand Phase 4 a record stamped with the released version.

**Acceptance Criteria**:
- [ ] `eval-pass-rates.py merge` writes an `eval-pass-rates/v1` record built from an explicit field list: per skill `runs`, `runs_passed`, `assertions_passed`, `assertions_graded`, `pass_rate` (passed over graded, four places, present only for harness exit 0 or 1 with at least one graded assertion), `models`, `measured_at`, and `exit_code` for exits 2, 3 and 4; skills absent from this run's summaries are carried forward unchanged.
- [ ] `merge` exits 0 when clean, 1 when any skill's harness exit was 2, 3 or 4 (naming each skill and code), and 5 when a skill's rate is strictly lower than the previous record's and the skill isn't in `RELEASE_CONFIRMED_DROPS`, ending its output with `confirm: RELEASE_CONFIRMED_DROPS=<a,b>`; an infrastructure failure outranks a drop; a harness exit of 1 with no drop exits 0.
- [ ] A previous record that is missing, over the size cap, unparseable, of another `schema`, or that fails any field check (semver `version` and `measured_at`, tag-shaped `last_tag`, skill-name and model patterns, non-negative integer counts with `runs_passed <= runs` and `assertions_passed <= assertions_graded`, a finite `pass_rate` in [0, 1] agreeing with the counts) gives "no baseline" with a warning naming the field and not its value, and exit 0.
- [ ] `eval-pass-rates.py stamp` sets `version`, and `measured_at` of the skills it is given, to the version passed, leaving carried skills untouched.
- [ ] `release-eval-check.sh --critical work-on,scope,execute --critical-runs 3` validates `RELEASE_LAST_TAG` and `RELEASE_VERSION`, empties `$(git rev-parse --git-dir)/shirabe-release/` and writes a marker naming `HEAD`, the last tag and the skills it measures, runs `scripts/run-evals.sh --runs <N> --summary-out <state>/<i>.json <skill>` per selected skill (3 for a critical skill, 1 otherwise) and continues after a failure, downloads the previous record with `gh release download "$RELEASE_LAST_TAG" --repo <owner/repo> --pattern eval-pass-rates.json` into a `mktemp -d` directory (skipped when the tag is empty), and returns `merge`'s exit code.
- [ ] With `RELEASE_CONFIRMED_DROPS` non-empty and a marker for the same `HEAD` and tag, the check re-merges the saved summaries without calling the harness.
- [ ] With no skill selected, the check still writes a record carrying the previous one forward and exits 0.
- [ ] `release-eval-check.sh --finalize` refuses unless the marker names the current `HEAD` and `RELEASE_LAST_TAG` and a record exists, then stamps the record with `RELEASE_VERSION` and prints `asset: <record path>` as its last line.
- [ ] `scripts/lib/eval-pass-rates_test.py` and `scripts/release-eval-check_test.sh` (stub `gh` and stub `run-evals.sh` on `PATH`) pass cases for: a drop, an equal rate, no asset, an unparseable asset, an unknown schema, an empty last tag, each field-validation failure, carry-forward, infrastructure exits 2, 3 and 4, harness exit 1 without a drop, a confirmed drop, a drop with a different skill confirmed, the confirmation re-run making no harness call, a stale record removed on a fresh run, an empty selection carrying the previous record forward, `--finalize` with a matching marker, a mismatched marker and no record, and no `gh release upload` call anywhere.
- [ ] Both suites run in new jobs of `check-run-evals.yml`, whose path filter includes the new files, and pass on the branch.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `scripts/lib/eval-pass-rates.py`, `scripts/lib/eval-pass-rates_test.py`, `scripts/release-eval-check.sh`, `scripts/release-eval-check_test.sh`, `.github/workflows/check-run-evals.yml`

### Issue 3: feat(release): run repo-declared release checks and attach release assets

**Goal**: Teach `/shirabe:release` to import its extensions, run each `## Release checks` command as a precondition with the exit-5 confirmation protocol, run each `## Release assets` command after the draft exists, and declare shirabe's eval check in `release.md`.

**Acceptance Criteria**:
- [ ] `skills/release/SKILL.md` has `@.claude/shirabe-extensions/release.md` and `@.claude/shirabe-extensions/release.local.md` directly after its preflight line.
- [ ] Phase 2 has a step 7 that prints `git diff --stat <last tag>..HEAD -- scripts/ skills/ .claude/shirabe-extensions/`, then for each `## Release checks` item prints the command and its source file, asks before running a `release.local.md` item, and runs it from the repository root with `RELEASE_VERSION`, `RELEASE_LAST_TAG`, `RELEASE_DRY_RUN` exported and `RELEASE_CONFIRMED_DROPS` empty; exit 0 continues; exit 5 shows the output, asks with `AskUserQuestion`, and on a yes re-runs with the `confirm:` line's variable set; a no, a session that can't ask, or any other non-zero exit stops the release naming the item and the tail of its output.
- [ ] The step says that a missing extension or a missing `## Release checks` heading means no declared checks, and that declared checks run in `--dry-run` too.
- [ ] Phase 4, after the draft exists and only outside a dry run, runs each `## Release assets` item with the confirmed `RELEASE_VERSION`, uploads the path named by an `asset:` last line with `gh release upload v<version> <path> --clobber`, and on a failed command or upload reports it with the retry command without stopping the release.
- [ ] The Error Recovery table gains rows for a failing declared check, an unconfirmed drop and a failed asset upload.
- [ ] `.claude/shirabe-extensions/release.md` exists, lists `scripts/release-eval-check.sh --critical work-on,scope,execute --critical-runs 3` under `## Release checks` and `scripts/release-eval-check.sh --finalize` under `## Release assets`, says unchanged critical skills don't run, names the asset `eval-pass-rates.json`, and states the host requirements: `claude` with the skill-creator plugin, `python3`, `git`, `gh`, bash 4.
- [ ] `scripts/check-directive-invocations.sh` passes with the new extension file.
- [ ] `skills/release/evals/evals.json` gains scenarios for a declared check that passes, one that fails (the release stops and names it), one that exits 5 (the release asks), and no extension (built-in checks only); `scripts/check-evals-exist.sh` still passes.
- [ ] The `run-evals.sh` exemption comment in `scripts/check-bash-floor.sh` says it now runs from the release session on a bash 4 host.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `skills/release/SKILL.md`, `skills/release/evals/evals.json`, `.claude/shirabe-extensions/release.md`, `scripts/check-bash-floor.sh`

### Issue 4: feat(work-on): gate skill changes on deterministic checks instead of evals

**Goal**: Add `scripts/check-skill.sh` and the `evals.json` shape check, point the `skills/**` verification-map entry at it, and rewrite CLAUDE.md, the extension README and the work-on scenario that assumed the old gate.

**Acceptance Criteria**:
- [ ] `scripts/check-skill.sh <skill>` runs under `/bin/bash` 3.2 from the repository root; checks `shirabe`, `koto`, `python3` and `git` are on `PATH`, naming a missing one (exit 2); runs `shirabe validate` once over the skill's Markdown outside `evals/` and `koto-templates/`; compiles each `koto-templates/*.md` except `*.mermaid.md`; runs each `scripts/*_test.sh` with `bash`; runs `scripts/lib/check-evals-shape.py` on `evals/evals.json`; reports every failure with its file; and exits 1 if any check failed.
- [ ] `check-evals-shape.py` fails, naming the file and the eval, on invalid JSON, a missing or empty `name` or `prompt`, or an eval with neither a non-empty `expectations` nor a non-empty `assertions` list; a skill with no `evals.json` passes only when `SKILL.md` declares `disable-model-invocation: true`.
- [ ] Skill names are checked against `^[a-z0-9][a-z0-9-]*$`; `CHECK_SKILL_ROOT` is documented in the script as test-only.
- [ ] `scripts/check-skill_test.sh` passes cases for: a clean skill with no templates or scripts (exit 0, a recording `claude` stub never called); each failure kind above, plus a Markdown file `shirabe validate` rejects, a template that fails compilation and a `*_test.sh` exiting 1; `koto` missing from `PATH`; and `*.mermaid.md` skipped.
- [ ] `.github/workflows/check-skill-gate.yml` runs the suite on `pull_request` with `permissions: contents: read`, on ubuntu and on macOS with `/bin/bash`, and passes on the branch.
- [ ] `scripts/check-skill.sh` exits 0 for `release`, `work-on` and `scope` on the branch.
- [ ] `.claude/shirabe-extensions/work-on.md` maps `skills/**` to `scripts/check-skill.sh <skill>` and contains no `run-evals.sh`.
- [ ] `.claude/shirabe-extensions/README.md` describes the entry's checks, says evals run at release, and names `.claude/shirabe-extensions/release.md`.
- [ ] The CLAUDE.md `## Skill Evals` section says a skill change creates or updates its scenarios in `evals/evals.json` without running them in the pull request, that evals run in the release precondition, and that `scripts/run-evals.sh <skill>` is the local run; it no longer says to run the evals before committing.
- [ ] The work-on scenario that asserted `scripts/run-evals.sh` runs at the definition-of-done gate now asserts `scripts/check-skill.sh`, and no other instruction outside `scripts/`, `.github/workflows/`, historical `docs/` and `release.md` makes the harness a pull request's definition of done.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `scripts/check-skill.sh`, `scripts/check-skill_test.sh`, `scripts/lib/check-evals-shape.py`, `.github/workflows/check-skill-gate.yml`, `.claude/shirabe-extensions/work-on.md`, `.claude/shirabe-extensions/README.md`, `CLAUDE.md`, `skills/work-on/evals/evals.json`

### Issue 5: ci(run-evals): make the eval workflow manual-only

**Goal**: Drop the weekly schedule from `run-evals.yml` and say at its top what a run needs.

**Acceptance Criteria**:
- [ ] `.github/workflows/run-evals.yml` has no `schedule:` key and keeps `workflow_dispatch` with its inputs.
- [ ] A header comment names the isolated-checkout fix tracked in shirabe#612, the `ANTHROPIC_API_KEY` secret and the skill-creator plugin as what a run needs.
- [ ] `grep -rn 'run-evals.sh' .github/workflows/` matches only `run-evals.yml` and `check-run-evals.yml`; `check-evals.yml` and `scripts/check-evals-exist.sh` are unchanged.

**Dependencies**: None

**Type**: code
**Files**: `.github/workflows/run-evals.yml`

## Implementation Sequence

**Critical path**: Issue 1 -> Issue 2 -> Issue 3 -> Issue 4. Issue 5 depends on nothing.

**Parallelization**: Issue 5 is independent and can land at any point. Issue 1 is ready now.

**Recommended order**: 1, 5, 2, 3, 4. The gate change goes last so the branch never removes the pull request eval requirement before the release check that replaces it exists.
