---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
upstream: docs/designs/DESIGN-offload-offline-ablation.md
milestone: "Offline ablation for withheld instruction sections"
issue_count: 5
---

# PLAN: offload-offline-ablation

## Status

Active

One pull request carries all five outlines. Nothing is filed on GitHub.

## Scope Summary

Build the ablation mode of the eval harness the DESIGN describes: withhold a
named section in a scratch plugin copy, run `full`, `withheld` and
`without_skill` arms in their own sessions, deliver through a koto wrapper,
grade with scripts, record and summarise against the pinned baseline, and
prove it on `/work-on`'s introspection-evidence section with committed,
regenerable figures.

## Decomposition Strategy

Horizontal. The DESIGN's components have fixed interfaces between them (the
baseline count, the case file, the check contract, the record), and each
later piece reads what an earlier one produces, so each outline builds one
layer fully. A walking skeleton would add little: the prototype already ran
the end-to-end path once, and the risky part, the wrapper and its delivery
paths, is tested with a stub agent inside the second outline.

The repository declares no delivery preference, so the default
`consolidated` applies and no split branch fires: one pull request.

## Issue Outlines

### Issue 1: feat(scripts): count instruction tokens over a directory and add the ablation CI workflow

**Goal**: Let the baseline's token count run over a plugin copy on disk, and stand up the CI workflow with the jobs that guard normal runs, public content and the existing eval runner.

**Acceptance Criteria**:
- [ ] `scripts/offload-baseline.sh count --tree <dir>` prints the same lines as `count <commit>` when `<dir>` is a checkout of that commit, and a test in `scripts/offload-baseline_test.sh` asserts it.
- [ ] `count --tree` over a directory missing a manifest path exits 2 and prints nothing on stdout.
- [ ] `scripts/ablation/check-normal-runs-unchanged.sh <base>` exits 0 when no load-manifest path and no koto template differs from `<base>`, and 1 naming the file when one does; a test covers both.
- [ ] `scripts/ablation/check-public-content.sh` fails, naming the line, on a planted home-directory path, `wip/` path, session or job identifier shape, private repository name, telemetry vendor name and secret shape, reading its denylist from a committed file, and passes on a clean input; a test plants each.
- [ ] `.github/workflows/offload-ablation.yml` runs on `pull_request` with `contents: read` and no secrets, with the jobs `normal-runs-unchanged`, `public-content` (over the diff and the pull request body) and `run-evals-unchanged`, each a separate job.

**Dependencies**: None

**Type**: code
**Files**: `scripts/offload-baseline.sh`, `scripts/offload-baseline_test.sh`, `scripts/ablation/check-normal-runs-unchanged.sh`, `scripts/ablation/check-public-content.sh`, `.github/workflows/offload-ablation.yml`

### Issue 2: feat(ablation): run a case's three arms with a withheld span and deliver through a koto wrapper

**Goal**: Implement the harness core: case validation and selection, span resolution, the per-run root and allowlisted environment, koto setup, the koto wrapper and gh shim, the check contract with the three demonstration checks, audit sampling, the fixture rule, and stub-agent tests with the real koto. It writes each run's raw outputs (the wrapper's call and production log, the stamped transcript, audit outcomes) to the run directory; turning them into records is Issue 3.

**Acceptance Criteria**:
- [ ] `ablation.py validate-case` refuses each malformed field the DESIGN lists, including a check or fixture named by path, and accepts `scripts/ablation/cases/work-on-introspection-evidence.json`.
- [ ] `ablation.py resolve-span` removes exactly the named bytes for a line-range and a heading key, ignores headings inside fenced code, and refuses a malformed key, an unknown commit, a missing file, a span not found and a span found twice, naming the key and reason, before any session starts.
- [ ] In a stub run, only the `withheld` copy lacks the span; the `full` and `withheld` agents get the same prompt and `--plugin-dir` pointing at their own copy, the `without_skill` agent gets no `--plugin-dir`; every agent gets `--setting-sources ""`, `--strict-mcp-config` and `--no-session-persistence`; and each copy holds `skills/`, `references/`, `scripts/` and `.claude-plugin/`. The stub records its argv so the test asserts this.
- [ ] The agent's environment contains only the allowlisted variables (the stub dumps its environment names; a planted `GH_TOKEN` and `SSH_AUTH_SOCK` on the host are absent), and every koto call the harness and wrapper make runs with the run root's `HOME` and `KOTO_SESSIONS_BASE`: nothing under the real home's koto directory changes during a stub run.
- [ ] The wrapper recognises evidence in the `--with-data <json>`, `--with-data=<json>` and `--with-data @<file>` forms, grades only in the target state, passes through without logging when `KOTO_TICK_SESSION` is set, and refuses to start when `ABLATION_REAL_KOTO` is unset or resolves to itself; a test covers each.
- [ ] With the stub agent, the wrapper's log shows: violated then complied (the first refused with koto's `invalid_submission` shape and exit 2, koto never called for it, the second passed through); complied first (no delivery); stop after refusal (no second production).
- [ ] A deployed check exiting 3, printing a reason outside `^[a-z0-9-]{1,40}$`, or exceeding `check_seconds` is logged `not-checkable` with `check-error` or `check-timeout`, and the run continues to its audit checks.
- [ ] The three demonstration checks return their documented reason codes on fixture productions and run directories, including `enum-left-to-koto`, `rationale-missing`, `missing-no-cleanup`, `context-missing` and each `not-checkable` case; `issue_superseded` with no rationale complies.
- [ ] Audit sampling: at rate 1 every pool rule runs on every arm; at a rate below 1 the sample is the rules whose `sha256(case id, repetition, rule)` falls below the rate, identical across a repetition's three arms; an empty pool completes a run.
- [ ] A run whose agent edits the checkout or a file under `scripts/ablation/` is logged `harness-tampered`, and after every run, including one killed by the wall-clock limit, the run root is gone and `git status --porcelain -- skills references` is empty.
- [ ] `ABLATION_AGENT_CMD` is refused unless `ABLATION_TEST=1` is set.
- [ ] `is-fixture-session` classifies by a path component starting with `shirabe-ablation.`, so a header whose directory merely contains that text elsewhere is not a fixture; synthetic headers cover a fixture, a non-fixture, and a non-fixture carrying a pinned template hash.
- [ ] The `greet-repo` fixture's issue and tree make `approach_updated` the correct verdict: the `--name` flag exists in the tree and the README note doesn't.
- [ ] The workflow gains `ablation-tests` (installing koto 0.14.1 from its release, checked by sha256) and `fixture-rule` jobs.
- [ ] One real smoke run and one real repetition complete locally before Issue 3 starts.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `scripts/ablation/ablation.py`, `scripts/ablation/koto-intercept`, `scripts/ablation/is-fixture-session`, `scripts/ablation/checks/`, `scripts/ablation/cases/`, `scripts/ablation/fixtures/`, `scripts/ablation/ablation_test.py`, `.github/workflows/offload-ablation.yml`

### Issue 3: feat(ablation): derive run records, summarise them and check committed figures

**Goal**: Turn each run's raw outputs into one record on the baseline's attribute names, detect leaks and wrapper bypasses, and summarise and regenerate figures from committed records without a model session.

**Acceptance Criteria**:
- [ ] Each record carries every attribute the DESIGN's record lists, keeps `opportunity.outcome` to the baseline's three values with `point.status` separate, marks a delivered run with no further production `not-produced` at the second point, and holds no path, prompt or free-text reason.
- [ ] `template.fixture` is computed by applying `is-fixture-session` to the run's session header, not set by the harness.
- [ ] A stub transcript that reads one line of the withheld span, or names the span's file outside the arm's copy, before the delivery gives `leak: true` and a `not-checkable` first point; a `koto next` in the transcript missing from the wrapper's log gives `wrapper_bypassed: true`.
- [ ] Session tokens come from the `result` event with `modelUsage`, and a run with no `result` falls back to deduplicated assistant usage marked `partial`; per-state tokens follow the shared clock; static tokens for `withheld` equal `round((B - S) / 4)` and for `without_skill` are 0; observed instruction tokens over a stub transcript that reads a 400-byte file under the copy and one outside it equal 100 plus the skill body's share.
- [ ] Over fixture records with known counts, `summarize` prints the expected per-arm, per-point runs, violations, denominators, not-checkable, not-produced and leak counts, rates and Clopper-Pearson bounds; token deltas and the baseline comparison; audit erosion; both prompts; the detection limit, thresholds row and decision sentence; `n/a` for an arm with no checkable run; and "no audit rules sampled" for an empty pool.
- [ ] `check-figures` passes on committed figures and exits 1 naming the line after one figure is edited.
- [ ] The workflow gains the `ablation-figures` job.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `scripts/ablation/ablation.py`, `scripts/ablation/ablation_test.py`, `.github/workflows/offload-ablation.yml`

### Issue 4: feat(evals): hand ablation runs from run-evals.sh to the harness

**Goal**: Make ablation a mode of the eval runner without changing its path for any other invocation.

**Acceptance Criteria**:
- [ ] `run-evals.sh` execs the harness with its arguments unchanged when `--withhold` appears anywhere in its argument list.
- [ ] Without `--withhold`, `scripts/run-evals_test.sh` passes unchanged, and a test shows the harness is never reached.
- [ ] `--withhold` disagreeing with `--case`'s `withhold.source` refuses; with no `--case`, zero or several matching cases refuse.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `scripts/run-evals.sh`, `scripts/run-evals_test.sh`

### Issue 5: docs(measurement): run the introspection-evidence demonstration and document the ablation method

**Goal**: Run the demonstration case for 5 repetitions, commit its records and summary, and document the method, case format, check contract and fixture rule.

**Acceptance Criteria**:
- [ ] `docs/measurement/offload-ablation/work-on-introspection-evidence/` holds `records.jsonl` with 15 records, every one with `template.fixture: true`, and `summary.txt`, and `ablation.py check-figures` reproduces the summary.
- [ ] `docs/measurement/offload-ablation/README.md` documents running a case, the case format and the external case corpus, the check contract, the fixture rule, and how to read a summary, including what 5 runs can and can't decide.
- [ ] The offload-baseline README's Population section excludes ablation fixtures by the rule.
- [ ] Every CI job is green.

**Dependencies**: Blocked by <<ISSUE:3>>, <<ISSUE:4>>

**Type**: docs
**Files**: `docs/measurement/offload-ablation/`, `docs/measurement/offload-baseline/README.md`

## Dependency Graph

## Implementation Sequence

Issue 1 blocks Issue 2; Issue 2 blocks Issues 3 and 4; Issues 3 and 4 both
block Issue 5. The critical path is 1, 2, 3, 5. Issue 4 can run beside Issue 3 once Issue 2
lands. The demonstration in Issue 5 runs 15 model sessions and is the only
step that costs model time; it runs after every scripted check is in place,
so its records are checked the moment they're committed.
