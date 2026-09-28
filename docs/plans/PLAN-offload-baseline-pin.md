---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-offload-baseline-pin.md
milestone: "Offload baseline pin"
issue_count: 4
---

# PLAN: offload-baseline-pin

## Status

Active

Single-pr plan with no GitHub issues filed, so it's authored at Active.

## Scope Summary

Build the baseline the design describes: the recount and pin-check script
with its tests, the template pin and load manifest at the pinned commit, the
recorded figures and the README carrying the provisional preloaded-rate
definition, and the CI that keeps them honest. All of it lands in one pull
request against `main`.

## Decomposition Strategy

**Horizontal.** The script is the one piece everything else depends on: the
pin is generated and checked by it, and the figures are its output. So it
comes first, with tests against fixtures that don't depend on shirabe's
history. The pin and manifest follow, then the figures and README, which read
the script's output. CI depends only on the script and its tests, so it can
be written alongside the data.

The work doesn't split. Every piece is needed before a later change can be
measured against the baseline, and none is useful to a reader alone, so it
lands as one pull request under the repository's default consolidated
delivery preference.

## Issue Outlines

### Issue 1: feat(scripts): add offload-baseline verify-pin and count

**Goal**: Add `scripts/offload-baseline.sh` with `verify-pin` and
`count <commit> [--manifest <file>]`, and `scripts/offload-baseline_test.sh`
exercising both against a temporary git repository.

**Acceptance Criteria**:
- [ ] `count` reads every manifest span from git objects (`git cat-file blob <commit>:<path>`),
      supports the `file`, `body` and `state:<name>` selectors, and prints
      raw and weighted tokens per profile, each total divided by 4 and
      rounded once.
- [ ] `count` leaves `git status --porcelain` unchanged, and exits non-zero
      with no stdout for a missing commit, no commit, an argument starting
      with `-`, a missing path, or a missing state, naming the problem.
- [ ] `verify-pin` exits 0 on a correct pin and non-zero, naming each entry,
      for: an altered git blob, two altered entries, a wrong skill, an entry
      the commit lacks, a missing entry, a missing field, a mismatched
      declared name or version, and an unparseable file.
- [ ] `verify-pin` compares `koto_template_hash` only when `koto version`
      matches the pinned `koto_version`, and otherwise reports the comparison
      as skipped without failing; the test covers both paths with a stub
      `koto` on `PATH`.
- [ ] The test suite passes under bash 3.2 and on the runner's bash.

**Dependencies**: None

**Type**: code
**Files**: `scripts/offload-baseline.sh`, `scripts/offload-baseline_test.sh`

### Issue 2: feat(measurement): pin the templates and write the load manifest

**Goal**: Generate `docs/measurement/offload-baseline/template-pin.json` at
the pinned commit and build `load-manifest.tsv` for the five profiles from
what each skill loads there.

**Acceptance Criteria**:
- [ ] The pin names the pinned commit (current `main`, not e592501), koto
      0.14.1, and exactly the five templates under
      `skills/{work-on,execute,scope,deliver}/koto-templates/`.
- [ ] `scripts/offload-baseline.sh verify-pin` exits 0 against it with koto
      0.14.1 installed, including the koto-hash comparison.
- [ ] `load-manifest.tsv` has rows for the `work-on`, `execute-single-pr`,
      `execute-coordinated`, `scope` and `deliver` profiles; every row's
      `note` names its weight's provenance (`resident`, `visits`, `reread`,
      `conditional`, `failure-only`, or `profile-total`).
- [ ] Each profile's rows cover every file its SKILL.md and state directives
      tell the agent to read at the pinned commit, and every file left out on
      purpose (on-demand "see" links, subagent-only files) is listed with the
      reason in the README.
- [ ] `count` succeeds at the pinned commit, and at e592501 with either the
      same manifest or `load-manifest-e592501.tsv` listing that commit's rows.
- [ ] `git diff --name-only <pinned commit> HEAD` on the branch lists no path
      under `skills/` or `references/`: pinning changes no template, and no
      declared `version:` is bumped.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `docs/measurement/offload-baseline/template-pin.json`, `docs/measurement/offload-baseline/load-manifest.tsv`

### Issue 3: docs(measurement): record the token baseline and the provisional definitions

**Goal**: Record the figures at the pinned commit and at e592501 beside the
September census reference, and write the README with the method, the
figures and the provisional preloaded-rate definition.

**Acceptance Criteria**:
- [ ] `token-baseline.tsv` holds raw and weighted figures for all five
      profiles at the pinned commit and at e592501, and the September census
      figures under commit `census-2026-09`.
- [ ] Re-running `count` at both commits reproduces the recorded figures
      exactly.
- [ ] The README states the pinned commit, how to re-run the count and
      verify the pin, every weight that isn't 1, why the recount and the
      census differ, and which manifest rows differ at e592501.
- [ ] The README's preloaded-rate definition has a separately headed part
      for opportunity, violation, observation point, numerator, denominator,
      population, early-ending runs and attribute names, each labelled
      provisional (`provisional-1`) with the alternative it was chosen over.
- [ ] It keys rules by path plus line range or heading at the pinned commit,
      says they're re-keyed to rule-registry ids later, defines no id format,
      and says a later measurement-definitions effort settles the definition
      and may move the baseline.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: docs
**Files**: `docs/measurement/offload-baseline/token-baseline.tsv`, `docs/measurement/offload-baseline/README.md`

### Issue 4: ci: check the offload baseline on every pull request

**Goal**: Add `.github/workflows/check-offload-baseline.yml` and register the
suite in `scripts/check-bash-floor.sh`.

**Acceptance Criteria**:
- [ ] The workflow triggers on `pull_request` for changes to the script, its
      test, the baseline directory or the workflow, with `contents: read`
      permission only.
- [ ] One job runs `scripts/offload-baseline_test.sh`; another checks out
      with full history, runs `verify-pin` and `count` at both recorded
      commits, and fails if the output differs from `token-baseline.tsv`.
- [ ] The suite's public-content check fails on a `tsukumogami/<repo>`
      reference outside the public-repository allowlist, a home-directory
      path, or a session, instance or job identifier, and passes on the
      committed baseline directory.
- [ ] The bash-floor job runs the suite under bash 3.2, and
      `scripts/check-bash-floor_test.sh` and `check-macos-floor-legs.sh`
      still pass.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `.github/workflows/check-offload-baseline.yml`, `scripts/check-bash-floor.sh`

## Implementation Sequence

The critical path is 1, 2, 3. Issue 4 needs only issue 1 and can run
alongside 2 and 3, but its figure-diff job reads `token-baseline.tsv`, so the
pull request's CI goes fully green only once issue 3 lands.
