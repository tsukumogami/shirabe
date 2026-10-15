---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-functional-steps.md
milestone: "functional steps"
issue_count: 7
---

# PLAN: functional steps

## Status

Active

## Scope Summary

Add `plan/v2`, a plan version whose entries are steps (a walking-skeleton
first step, behavioural criteria and a check per detailed step, one-line
outline steps), beside `plan/v1`. The validator, the one outline parser and
`shirabe plan outlines`, task extraction, the `/scope`, `/execute` and
`/work-on` readers, `/plan` authoring and `/review-plan` all accept both
versions, and no `plan/v1` behaviour changes. The default stays `plan/v1`.

## Decomposition Strategy

**Walking skeleton.** The validator, the outline parser and task extraction
are coupled at runtime, so Issue 1 carries a minimal `plan/v2` document
through all three and pins the `plan/v1` regression fixtures. Every later
issue adds one behaviour a person can observe with a command, and leaves
every `plan/v1` path working. The issues are detailed in full because this
PLAN is `plan/v1`; the session that owns it still refines each one before
its work starts, from what the earlier ones taught.

## Issue Outlines

### Issue 1: feat(plan): carry a minimal step plan from validation to tasks

**Complexity**: testable

**Goal**: A minimal plan/v2 document (two detailed steps, one outline step) validates clean with `shirabe validate`, is read by `shirabe plan outlines`, and is turned by `plan-to-tasks.sh` into one `step-<N>` task per step with dependency edges, for single-pr and multi-pr. Validation output for every existing plan/v1 fixture, including a newly added five-layer koto plan, stays byte-identical.

**Acceptance Criteria**:

- [x] `shirabe validate crates/shirabe-validate/tests/fixtures/plan_v2_minimal.md` (frontmatter `schema: plan/v2`, `step_count: 3`, sections Status, Scope Summary, Decomposition Strategy, Steps; steps 1 and 2 detailed, step 3 a one-line outline) exits 0 with no findings.
- [x] A copy of that fixture with `step_count` not matching the number of `### Step N:` headings, and a copy missing the `## Steps` section, each exit non-zero with a message naming the missing or mismatched field.
- [x] `shirabe plan outlines` on the minimal fixture exits 0 and prints three entries in step order; steps 1 and 2 carry `detailed: true` and a `check_declared` value taken from their `**Check**:` line, step 3 carries `detailed: false`; `**Dependencies**: Step 1` resolves to an edge from step 2 to step 1.
- [x] `shirabe plan outlines` on a plan/v1 fixture still prints the same entries it printed before this change (no new fields change existing keys).
- [x] `plan-to-tasks.sh` on the minimal fixture with `execution_mode: single-pr` exits 0 and emits tasks named `step-1`, `step-2`, `step-3` in that order, each with its dependency edges; the same fixture with `execution_mode: multi-pr` and no `tracking_level` (or `none`) emits the same task names and edges.
- [x] `plan-to-tasks.sh` on a plan/v2 file with `tracking_level` other than `none` exits non-zero with a message saying plan/v2 supports only `none`.
- [x] `plan-to-tasks_test.sh` gains plan/v2 cases for single-pr, multi-pr, and the unsupported tracking level; the script runs under bash 3.2 (no associative arrays, no `mapfile`, no `${var,,}`).
- [x] The koto evidence-routing plan is added as `crates/shirabe-validate/tests/fixtures/plan_v1_five_layer.md` (five entries: types, compiler, CLI, tests, plugin templates), with a leading comment naming its source (koto repo, `docs/plans/PLAN-template-evidence-routing.md`) and the commit it was recovered from.
- [x] `shirabe validate` on `plan_v1_five_layer.md` and on every existing plan/v1 fixture produces output identical to the recorded pre-change output (a Rust test pins the five-layer result).
- [x] Every existing plan/v1 test this issue touches (Rust tests in `crates/shirabe-validate`, `crates/shirabe`, and `skills/plan/scripts/plan-to-tasks_test.sh`) still passes unchanged: `cargo test --workspace` is green and no existing assertion is edited.

**Check**: Run `cargo test --workspace` and `bash skills/plan/scripts/plan-to-tasks_test.sh`; both exit 0. Then run `shirabe validate crates/shirabe-validate/tests/fixtures/plan_v2_minimal.md` (exit 0, no findings), `shirabe plan outlines` on it (three entries, two `detailed`), and `bash skills/plan/scripts/plan-to-tasks.sh crates/shirabe-validate/tests/fixtures/plan_v2_minimal.md` (tasks `step-1`, `step-2`, `step-3`).

**Dependencies**: None

**Files**: `crates/shirabe-validate/src/formats.rs`, `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/table.rs`, `crates/shirabe/src/plan_outlines.rs`, `skills/plan/scripts/plan-to-tasks.sh`, `skills/plan/scripts/plan-to-tasks_test.sh`, `crates/shirabe-validate/tests/fixtures/plan_v2_minimal.md`, `crates/shirabe-validate/tests/fixtures/plan_v1_five_layer.md`

---

### Issue 2: feat(validate): refuse malformed step plans naming the step and rule

**Complexity**: testable

**Goal**: `shirabe validate` accepts a well-formed `plan/v2` step plan and refuses each malformed one with an FC22 error naming the step and the rule broken, so an author sees exactly what to fix; plan/v1 output stays byte-identical. Issue 1 already added FC22 with its step-count rule and made a missing `## Steps` an FC04 error; this step adds the remaining step rules to that check and makes FC22 selectable.

**Acceptance Criteria**:

- [x] Every fixture this step adds lives in `crates/shirabe-validate/tests/fixtures/` and is named `PLAN-v2-<rule>.md`: the validator routes by the `PLAN-` filename prefix, so a fixture without it would get prose checks only and prove nothing.
- [x] `shirabe validate` on a valid fixture (`PLAN-v2-valid.md`: steps 1 and 2 detailed, steps 3 and 4 one-line outlines, `**Files**:` on one detailed step and not the other, `step_count: 4`) exits 0 with no finding.
- [x] Each of these fixtures exits non-zero with one FC22 error naming the step (where there is one) and the rule, and no other new finding:
  - `### Issue 2:` heading under `## Steps`; a `### Gate:` heading under `## Steps`
  - `issue_count` present (with or without `step_count`)
  - step 1 an outline
  - a detailed step missing `**Goal**:`, one with no checkbox criterion, one missing `**Check**:`
  - an outline step with two non-blank lines
  - a detailed step after an outline step
  - a dependency on a later step; a dependency on a step that does not exist
  - a `**Dependencies**:` value that is neither `None` nor `Step <N>` references
  - step numbers with a gap; a duplicate number; a number above 999 or with a leading zero
- [x] `execution_mode: coordinated`, `tracking_level: issues` and `tracking_level: issues-and-milestone` each yield an FC22 error whose message names `plan/v1` as the version for that case; `tracking_level: none` and an absent field pass. These match what `plan-to-tasks.sh` already refuses.
- [x] Sections out of order on a v2 fixture yield FC15 naming the section; a v2 fixture missing `step_count` yields FC01 naming `step_count`. The existing step-count and missing-`## Steps` fixtures from Issue 1 keep their findings unchanged.
- [x] FC05-FC09, FC11 and FC12 produce no findings on any `plan/v2` fixture, FC14 emits no table-versus-outline message on one, and FC17 reports an unresolved `Step <N>` dependency the way it reports an unresolved `Issue <N>` on plan/v1.
- [x] Text an FC22 message quotes from the document (a non-step heading, a malformed dependency value) has control characters stripped and is cut to 80 characters, shown on a fixture whose heading carries an ANSI escape and runs past 80 characters.
- [x] `shirabe validate --check FC22 <fixture>` selects FC22 alone. The test that pins the set of known check codes is updated to include FC22; that is the one existing assertion this step changes, and no other existing test or fixture changes.
- [x] Every plan/v1 fixture in the repository produces byte-identical `shirabe validate` output before and after this step, and `crates/shirabe/tests/roadmap_identity.rs` stays green.

**Check**: `cargo test --workspace` passes; `for f in crates/shirabe-validate/tests/fixtures/PLAN-v2-*.md; do cargo run -q -p shirabe -- validate "$f"; echo "exit=$?"; done` shows exit 0 for `PLAN-v2-valid.md` and `PLAN-v2-minimal.md`, and for each invalid fixture a non-zero exit with one `[FC22]` (or the named FC01/FC04/FC15) line naming the step and rule.

**Dependencies**: Blocked by <<ISSUE:1>>

**Files**: `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/table.rs`, `crates/shirabe-validate/src/validate.rs`, `crates/shirabe-validate/tests/`, `crates/shirabe-validate/tests/fixtures/PLAN-v2-*.md`

---

### Issue 3: feat(plan): write a step plan when plan/v2 is selected

**Complexity**: testable

**Goal**: `/plan` writes a `plan/v2` step plan when v2 is selected by `--plan-version=v2` or a `## Plan Version: v2` header in the repository's CLAUDE.md, and still writes `plan/v1` by default. The format reference states the horizon, owner and report rules a reader needs to work from a step plan.

**Acceptance Criteria**:

- [x] `skills/plan/scripts/resolve-plan-version.sh --plan-version=v2` prints `v2` and exits 0; `--plan-version=v1` prints `v1`, even when the CLAUDE.md header says `v2` (flag wins over header).
- [x] With no flag, a CLAUDE.md containing the whole line `## Plan Version: v2` resolves to `v2`; the same line inside a fenced code block is ignored and resolution falls through to the default.
- [x] With no flag and no header, the script prints the value of `DEFAULT_PLAN_VERSION`, which is `v1` and is assigned on exactly one line of the script.
- [x] `--plan-version=v3`, an empty value, and a CLAUDE.md with a header value other than `v1` or `v2` each exit non-zero with a message naming `v1` and `v2`, and write nothing.
- [x] A CLAUDE.md with two `## Plan Version:` headers outside fenced code exits non-zero naming the duplicate, before anything is written.
- [x] In `resolve-plan-version_test.sh`, a case copies the script to a temp dir, flips `DEFAULT_PLAN_VERSION` to `v2` with a one-line substitution, and shows a no-flag, no-header run now resolves to `v2` with nothing else edited.
- [x] `resolve-plan-version_test.sh` runs under bash 3.2 and passes; the fixtures it adds are the CLAUDE.md variants under `skills/plan/scripts/` test data (flag-only, header-only, fenced header, duplicate header, bad value).
- [x] `/plan` Phase 1 runs the resolver and records the version in `work/analysis.md`; Phases 3, 4 and 7 and the new `references/templates/step.md` branch on it. With `v2`, Phase 3 decomposes into steps (step 1 a walking skeleton whose check runs it end to end, criteria that describe observable behaviour, not files), Phase 4 details steps 1 and 2 only (every step when there are two or fewer), and Phase 7 writes `schema: plan/v2`, `step_count`, `## Steps` with `### Step N:` headings and files no issue. A v1 run reads exactly as it does today.
- [x] The plan `/plan` writes under `v2` passes FC22 as step 2 built it: each outline step is its heading plus exactly one non-blank line with no `**Field**:` line; each detailed step has `**Goal**:`, at least one checkbox criterion, `**Check**:` and `**Dependencies**:` (`None` or `Step <N>` references to earlier steps); numbering runs 1..n with no leading zero; `tracking_level` is `none` or absent. The step example in `plan-doc-examples.md`, saved as a `PLAN-` file, validates clean, checked by a case in the plan scripts suite.
- [x] Under `v2`, a split that resolves to `coordinated` stops before anything is written, with a message saying coordinated plans use `--plan-version=v1`; a CLAUDE.md `## Tracking Level:` that asks for issues is not applied, and the run says it wrote `tracking_level: none` because step plans file no issues.
- [x] `references/plan-format.md` gains a `plan/v2` section covering the format and the FC22 rules above, the horizon (steps 1 and 2 detailed at authoring), the owner rule (the plan's owner details step N+1 after step N's work reaches its terminal and before step N+1's starts, in one commit touching only the plan; workers never edit steps), and the report rule, which contains the exact phrase "the behaviour this step added" plus the check and its result, and states that reviewers read every Check like code. The `/plan` SKILL.md names the flag, the header and the default.
- [x] `plan-doc-structure.md` and `plan-doc-examples.md` carry a step example; `evals/evals.json` has scenarios for flag selection, header selection, default v1, a refused value, and planning koto's template evidence-routing design under `v2` (its design text copied into `skills/plan/evals/fixtures/` with its source named) expecting a skeleton-first step plan; `scripts/check-skill.sh plan` passes.
- [x] Every existing plan/v1 test this issue touches (`resolve-split-mode_test.sh`, `plan-to-tasks_test.sh`, `create-issues-batch_test.sh`) passes unchanged.

**Check**: Run `bash skills/plan/scripts/resolve-plan-version_test.sh`: all cases pass, including the flipped-default case. Run `git grep -n "the behaviour this step added" skills/plan/references/plan-format.md` and `git grep -n "DEFAULT_PLAN_VERSION=v1" skills/plan/scripts/`: each matches once. Run `scripts/check-skill.sh plan`: exits 0.

**Dependencies**: Blocked by <<ISSUE:2>>

**Files**: `skills/plan/scripts/resolve-plan-version.sh`, `skills/plan/scripts/resolve-plan-version_test.sh`, `skills/plan/SKILL.md`, `skills/plan/references/plan-format.md`, `skills/plan/references/quality/plan-doc-structure.md`, `skills/plan/references/quality/plan-doc-examples.md`, `skills/plan/references/phases/phase-1-analysis.md`, `skills/plan/references/phases/phase-3-decomposition.md`, `skills/plan/references/phases/phase-4-agent-generation.md`, `skills/plan/references/phases/phase-7-creation.md`, `skills/plan/references/templates/step.md`, `skills/plan/evals/evals.json`

---

### Issue 4: feat(work-on): stop an outline step's work until it is detailed

**Complexity**: testable

**Goal**: A `/work-on` child for a plan/v2 step that is still a one-line outline stops before any implementation, with a message naming the step and saying the plan's owner details it first; once the owner commits the detail, rerunning the same child builds from the detailed text. Step plans also run in order until detailed, so no outline step's child becomes startable ahead of the step before it.

**Acceptance Criteria**:

- [x] `skills/work-on/scripts/step-detail-check.sh <plan> <step>` exits 0 for a detailed step and non-zero for an outline step, printing `step <N> is an outline; the plan's owner details it before its work starts`. It decides through `shirabe plan outlines` (the `detailed` field, which needs goal, criteria and check together), so it never disagrees with what step 2's FC22 accepts on a valid plan; its suite shows this on FC22-valid fixtures named `PLAN-v2-*.md` in `skills/work-on/scripts/testdata/`, in single-pr and multi-pr.
- [x] A step argument not matching `^[1-9][0-9]{0,2}$` (`0`, `01`, `1000`, `a`, empty, `1;ls`) is refused, naming the rule, before the plan is read; a plan path that is missing, not a regular file, or resolves outside the repository (absolute path elsewhere, `..`, a symlink out) is refused with a clear message; a plan that is not plan/v1 or plan/v2, or a missing `shirabe` binary, is refused saying so.
- [x] A hostile-title plan/v2 fixture (`$(touch PWNED)`, backticks, a leading `--`, an ANSI escape in step titles) run through `step-detail-check.sh` exits as its step's shape dictates, creates no `PWNED` file, and prints no step text unescaped.
- [x] `skills/work-on/koto-templates/work-on.md`: `plan_context_injection` extracts a `### Step N:` block as the context for a plan/v2 task, and `plan_validation` runs `step-detail-check.sh` and submits `verdict: exit` carrying the refusal message when the step is an outline. A template-level case (the work-on template suite or a decider fixture) drives `plan_validation` on an outline step and shows the exit with the message, and on the same step after detailing shows `verdict: proceed`; `koto template compile` on the template succeeds.
- [x] `plan-to-tasks.sh` gives each outline step a dependency edge on the step before it, so a fresh plan/v2 runs in step order; a detailed step keeps exactly the edges its `**Dependencies**:` line declares. Existing plan/v2 cases in `plan-to-tasks_test.sh` are updated only where they asserted no edges on outline steps, and the plan/v1 cases are unchanged.
- [x] `skills/work-on/scripts/work-on-open.sh` treats a file declaring `schema: plan/v2` as a plan, as it does `schema: plan/v1`, shown on a fixture whose name does not start with `PLAN-`.
- [x] `skills/work-on/SKILL.md` plan-mode detection names both versions, and its instructions for a plan step's report say the report names "the behaviour this step added" and the check that shows it, with the check's result. `skills/execute/SKILL.md` says it drives plan/v1 and plan/v2 and that an outline step's child stops until the plan's owner details it.
- [x] Every existing plan/v1 case in `work-on-open_test.sh`, the work-on template suites and `run-cascade_test.sh` passes unchanged; new scripts run under /bin/bash 3.2.

**Check**: `bash skills/work-on/scripts/step-detail-check_test.sh` passes; `skills/work-on/scripts/step-detail-check.sh skills/work-on/scripts/testdata/PLAN-v2-single-pr.md 3` prints the outline refusal and exits non-zero, and the same call with step `1` exits 0; `bash skills/plan/scripts/plan-to-tasks_test.sh` passes and shows the outline steps' edges; `koto template compile skills/work-on/koto-templates/work-on.md` exits 0.

**Dependencies**: Blocked by <<ISSUE:1>>

**Files**: `skills/work-on/scripts/step-detail-check.sh`, `skills/work-on/scripts/step-detail-check_test.sh`, `skills/work-on/scripts/testdata/`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/scripts/work-on-open.sh`, `skills/work-on/SKILL.md`, `skills/execute/SKILL.md`, `skills/plan/scripts/plan-to-tasks.sh`, `skills/plan/scripts/plan-to-tasks_test.sh`

---

### Issue 5: feat(scope): report step titles and goals in the scope and execute readers

**Complexity**: testable

**Goal**: The scope and execute shell readers understand a `plan/v2` step plan: the scope hop check accepts it, and the startable list, the scoping PR body and the drift facts show step titles, goals and Files instead of coming out empty. Hostile step text passes through them as inert data. The step also closes four small gaps step 4's reviewers left in the outline gate's text.

**Acceptance Criteria**:

- [x] New fixtures are named `PLAN-v2-*.md` and pass `shirabe validate` (FC22) with the branch's build: outline steps are a heading plus one line with no `**Dependencies**:` line, detailed steps carry Goal, a checkbox criterion, Check and Dependencies.
- [x] Every reader that goes through `shirabe plan outlines` takes the binary from `SHIRABE_BIN` when set, as `plan-to-tasks.sh` does, and its suite builds and points at the branch's binary, because the installed shirabe 0.25.0 refuses plan/v2.
- [x] `hop-complete.sh` reports the plan hop complete for a `plan/v2` fixture (`skills/scope/scripts/testdata/PLAN-v2-steps.md`) and for a `plan/v1` PLAN; an unknown schema value still leaves the hop incomplete.
- [x] `startable-issues.sh` on the v2 fixture lists step 1 (the only step with no unfinished predecessor) with its `### Step N:` title, and lists no step with an empty title.
- [x] `publish-scoping-pr.sh` on the v2 fixture (existing gh shim, `--body-file` capture) writes a PR body listing every `### Step N: <title>`, none blank.
- [x] `drift-facts.sh` on the v2 fixture records each step's goal, or its outline line for an outline step, in `plan_intent.md`, and its `**Files**:` paths among the referenced paths; no step shows a missing goal.
- [x] `node-push.sh` is left unchanged: it serves only coordinated plans, which plan/v2 does not support (FC22 refuses them); a comment at `work_item_goal` says so.
- [x] A hostile-title fixture `skills/execute/scripts/testdata/PLAN-v2-hostile.md` (step titles carrying `$(touch PWNED)`, backticks, a leading `--`, an ANSI escape, `Fixes #1`, an `@mention`) runs through `plan-to-tasks.sh`, `publish-scoping-pr.sh` and `drift-facts.sh`: each exits 0, no `PWNED` file appears, and the title text is present as data in each output.
- [x] Step 4's leftovers: the multi-pr dispatcher text in `skills/work-on/SKILL.md` says what exit 2 (refused) from `step-detail-check.sh` means, beside exit 1; the script's header states the truncation it actually applies (240 characters for shirabe's error line); `skills/work-on/koto-templates/work-on.mermaid.md` shows the gate on the `plan_validation` to `setup_plan_backed` edge; and a comment in `plan-to-tasks.sh` says why a missing `detailed` field is read as true there while the check refuses it.
- [x] Every existing plan/v1 case in `hop-complete_test.sh`, `startable-issues_test.sh`, `publish-scoping-pr_test.sh`, `drift-facts_test.sh`, `plan-to-tasks_test.sh` and `step-detail-check_test.sh` passes with its assertions unchanged, under /bin/bash 3.2.

**Check**: With `SHIRABE_BIN` pointing at the branch's build, run `bash skills/scope/scripts/hop-complete_test.sh`, `bash skills/scope/scripts/startable-issues_test.sh`, `bash skills/scope/scripts/publish-scoping-pr_test.sh`, `bash skills/execute/scripts/drift-facts_test.sh` and `bash skills/plan/scripts/plan-to-tasks_test.sh`; each exits 0 with the new plan/v2 and hostile-title cases passing beside the unchanged plan/v1 cases.

**Dependencies**: Blocked by <<ISSUE:1>>

**Files**: `skills/scope/scripts/hop-complete.sh`, `skills/scope/scripts/startable-issues.sh`, `skills/scope/scripts/publish-scoping-pr.sh`, `skills/scope/scripts/testdata/PLAN-v2-steps.md`, `skills/execute/scripts/drift-facts.sh`, `skills/execute/scripts/node-push.sh`, `skills/execute/scripts/testdata/PLAN-v2-hostile.md`, `skills/work-on/SKILL.md`, `skills/work-on/scripts/step-detail-check.sh`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/plan/scripts/plan-to-tasks.sh`, and the matching `_test.sh` files

---

### Issue 6: feat(review-plan): flag plans cut into layers and file-shaped criteria

**Complexity**: testable

**Goal**: `/review-plan` gains category E (Functional Shape). It flags a plan cut into layers, a first entry that is not a walking skeleton, each file-shaped criterion, and, at authoring, a `plan/v2` plan with more than two detailed steps. Findings loop back under `plan/v2` and are advisory under `plan/v1`.

**Acceptance Criteria**:

- [ ] A fresh-session `/review-plan` run on the koto five-layer `plan/v1` fixture (added by issue 1) reports it as layer-shaped, names the entries and their components (types, compiler, CLI, tests, plugin templates), and lists each file-shaped criterion by entry and text (for example "Add `Transition` struct with `target: String`"). The findings are advisory and the verdict does not loop back.
- [ ] A run on the behavioural `plan/v2` fixture `skills/review-plan/evals/fixtures/plan-v2-behavioural.md`, which carries `**Files**:` lines, reports no layer-shaped finding and no file-shaped finding. No `**Files**:` line is ever listed as a file-shaped criterion.
- [ ] A run on `skills/review-plan/evals/fixtures/plan-v2-types-only-step1.md` (step 1 adds types only) reports that step 1 is not a walking skeleton, because its check is a build or unit test of one component and not observed end to end. The finding is a loop-back finding.
- [ ] A run on `skills/review-plan/evals/fixtures/plan-v2-three-detailed.md` (three detailed steps) invoked inside `/plan` at authoring flags the horizon. The same fixture run standalone does not.
- [ ] The category E finding is recorded in the `review_result` schema with category `E`. `references/templates/review-result-schema.md` documents it, and `phase-5-verdict.md` loops back on a layer-shaped plan or non-skeleton first step under `plan/v2` and treats the same findings as advisory under `plan/v1`.
- [ ] `phase-0-setup.md` reads `step_count` and `## Steps` for `plan/v2`, so a `plan/v2` plan is reviewed without an issue-table error.
- [ ] `SKILL.md` lists category E in its category table and counts five categories in the adversarial-mode spawn count (15 validator agents, not 12).
- [ ] `skills/review-plan/evals/evals.json` has a scenario per fixture above, each stating the expected findings, and passes the shape check.
- [ ] Every existing plan/v1 review-plan eval scenario and test the issue touches still passes unchanged.

**Check**: From a fresh session, run `/review-plan` on each of the four fixtures and compare the findings with the criteria above. Then run `scripts/check-skill.sh review-plan`. Passing shows the expected findings per fixture, no finding on the behavioural fixture, and exit 0 from the check.

**Dependencies**: Blocked by <<ISSUE:1>>

**Files**: `skills/review-plan/SKILL.md`, `skills/review-plan/references/phases/phase-4b-functional-shape.md`, `skills/review-plan/references/phases/phase-0-setup.md`, `skills/review-plan/references/phases/phase-5-verdict.md`, `skills/review-plan/references/templates/review-result-schema.md`, `skills/review-plan/evals/evals.json`, `skills/review-plan/evals/fixtures/`

---

### Issue 7: feat(validate): stop completion while outline steps remain

**Complexity**: testable

**Goal**: Completing a chain that holds a `plan/v2` plan with a one-line outline step stops with a lifecycle error naming that step, and the cascade proceeds once the step is detailed and its criteria are ticked.

**Acceptance Criteria**:

- [ ] `shirabe validate --lifecycle-chain` on the fixture `crates/shirabe-validate/tests/fixtures/plan-v2/lifecycle-outline-step/` (a `plan/v2` single-pr PLAN with steps 1 and 2 detailed and step 3 a one-line outline) exits non-zero and prints exactly one `L10` error naming `Step 3`.
- [ ] The fixture `lifecycle-two-outline-steps/` (steps 3 and 4 outlines) produces two `L10` errors, one per outline step, each naming its step number.
- [ ] The fixture `lifecycle-all-detailed/` (every step detailed, every criterion ticked) produces no `L10` and no `L06` finding under `--lifecycle-chain`.
- [ ] The fixture `lifecycle-unticked-detailed-step/` (a detailed step with an unticked criterion) produces an `L06` error naming that step and no `L10`.
- [ ] A `plan/v2` PLAN at the expected posture raises no `L01` finding that a `plan/v1` outline-shaped PLAN at the same posture would not; a `plan/v2` Draft single-pr PLAN fails `L01` the way the `plan/v1` one does.
- [ ] `L10` is emitted only by the `--lifecycle-chain` run: a plain `--lifecycle` run on the outline-step fixture prints no `L10`.
- [ ] `skills/work-on/scripts/run-cascade_test.sh` gains a `plan/v2` case: with the outline-step fixture the cascade stops, its output names the `L10` finding and the step, and the plan is not deleted; after the step is detailed and its criteria ticked, the same cascade proceeds.
- [ ] `skills/explore/references/phases/phase-5-produce-execute.md` and `skills/scope/references/phases/phase-3-exit-finalization.md` each mention `plan/v2` where they describe the plan format, and say completion waits until no outline step remains.
- [ ] Every existing `plan/v1` lifecycle test in `crates/shirabe-validate` and every existing case in `run-cascade_test.sh` still passes unchanged; `run-cascade_test.sh` runs on bash 3.2.

**Check**: Run `cargo test -p shirabe-validate lifecycle`, then `shirabe validate --lifecycle-chain` on each fixture above and confirm `lifecycle-outline-step` exits non-zero with an `L10` naming `Step 3` while `lifecycle-all-detailed` exits 0. Then run `bash skills/work-on/scripts/run-cascade_test.sh` and confirm every case, including the `plan/v2` one, reports a pass.

**Dependencies**: Blocked by <<ISSUE:1>>

**Files**: `crates/shirabe-validate/src/lifecycle.rs`, `crates/shirabe-validate/src/validate.rs`, `crates/shirabe-validate/tests/fixtures/plan-v2/`, `skills/work-on/scripts/run-cascade_test.sh`, `skills/explore/references/phases/phase-5-produce-execute.md`, `skills/scope/references/phases/phase-3-exit-finalization.md`

## Implementation Sequence

Serial, one issue at a time in a single pull request: 1, 2, 3, 4, 5, 6, 7.
Issue 1 is the skeleton every other issue reads through; Issue 3 waits on
Issue 2's rules so `/plan` writes plans the validator already checks. Issues
4 to 7 depend only on Issue 1 and could run in any order; they run in
number order so each step's detail can use what the previous one taught.
