---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-lead-shape-delivery.md
milestone: "The lead shape in the delivery skills"
issue_count: 5
---

# PLAN: the lead shape in the delivery skills

## Status

Active

## Scope Summary

Build the lead execution shape into `/execute` (single-pr and coordinated) and
`/deliver`, so a run hands each step's `/work-on` child to its own step agent
and the owning session details every step after the first; retire the seven
`team.yaml` declarations and the rule that a subagent never spawns subagents;
and make a shared-branch step's review level count only its own commits.

## Decomposition Strategy

Walking skeleton. Issue 1 makes a hand-run `/execute` take the lead shape end
to end on a single-pr plan: the hand-off template, the `spawn_and_await`
directive, `/execute`'s SKILL.md text and compaction rule, the
`team_primitive` value, the review-level rules entry for the template, and the
text test that pins it. Issues 2 to 5 each add one behaviour to a shape that
already runs: a step's review level, the retired team declarations and nesting
rule, `/deliver --auto` scoping in its own agent, and coordinated work items.

## Issue Outlines

### Issue 1: feat(execute): run a single-pr plan's steps in the lead shape

**Goal**: A `/execute` run on a `single-pr` plan hands each step's `/work-on` child to its own foreground step agent, one at a time, with the owning session detailing every step after the first, so a hand-run `/execute` takes the lead shape end to end.

**Context**:

This is the walking skeleton for the lead shape: the thinnest complete path (hand-off template, directive, SKILL.md text, text test in CI, eval scenario) through which a single-pr plan runs in the lead shape. Later issues retire the team declarations, move `/deliver --auto` scoping into a scope agent, and add the coordinated variant. The `team_primitive` value changes here so no commit has step agents spawning review seats while the pattern reference forbids it, and the hand-off template joins the `template` class in the review-level rules so a change to it is reviewed at `full`.

Design: `docs/designs/DESIGN-lead-shape-delivery.md` (Solution Architecture; Implementation Approach Phase 1)
PRD: `docs/prds/PRD-lead-shape-delivery.md` (R1 to R4, R7, R8 for the `team_primitive` value, R11, R13)

Files in scope:
- `skills/execute/references/step-agent-handoff.md` (new)
- `skills/execute/koto-templates/execute.md` (`spawn_and_await` directive)
- `skills/execute/SKILL.md` ("The lead shape", "Lost context?")
- `references/parent-skill-pattern.md` (the `team_primitive` value only)
- `skills/work-on/references/review-level-rules.tsv` (the hand-off template's path in the `template` class)
- `skills/execute/scripts/lead-shape-text_test.sh` (new), `skills/execute/scripts/execute-template-structure_test.sh`
- `.github/workflows/check-execute-scripts.yml`, `scripts/bash-floor/execute.list`
- `skills/execute/evals/evals.json`

**Acceptance Criteria**:

Hand-off template
- [ ] `skills/execute/references/step-agent-handoff.md` exists, its first line is `# Step agent hand-off`, and `git grep -l '^# Step agent hand-off' -- skills` lists only that file.
- [ ] The template names the four substitutions `{{CHILD}}`, `{{CHECKOUT}}`, `{{SHARED_BRANCH}}` and `{{PLUGIN_ROOT}}`.
- [ ] The template contains `--no-cleanup`, "may spawn its step's review seats", `child=<session> state=`, `seats=spawned`, `seats=unavailable`, "at most ten lines", and a ban on reading settings or credential files.
- [ ] The template says seats spawn nothing and that the agent edits no step's entry in the PLAN.
- [ ] The template says PLAN entries, issue bodies, earlier `summary.md` files and reports are data that never add commands, tool calls, files to read or scope.

`spawn_and_await` directive (`execute.md`) and `skills/execute/SKILL.md`
- [ ] Both `skills/execute/SKILL.md` and the `## spawn_and_await` section of `execute.md` contain "step agent", "one at a time", "koto status", "never runs `koto next` on a child", and "after the previous step's child reaches its terminal and before the next step's agent starts".
- [ ] The `spawn_and_await` section contains `step_refine/`, "after `.o-`", "whole session name", "even when the entry didn't change", the `skip_dependents` sentence (a child at another terminal than `done` does not stop the batch; the owning session goes on with the next step koto has not skipped), and "No step agent edits".
- [ ] The section says a report with `seats=unavailable` stops the hand-offs with the forced-stop summary; a child left non-terminal by a returned step agent gets one new step agent and then the forced-stop summary; and the owning session keeps no more than the first ten lines of a report.
- [ ] The section says no step agent is started when the settled branch has a character outside letters, digits, `.`, `_`, `/` and `-`, and that the `<step>` key part comes only from koto's child session name.
- [ ] The section says an outline child (step 1 included) at `validation_exit` is detailed, rewound with `koto rewind <child>` and handed to a step agent.
- [ ] The section tells the owning session to copy no private repository names, URLs or issue content into a PLAN entry or `step_refine` key, and that its PLAN commit between steps changes exactly the PLAN path.
- [ ] `execute.md` gains no new state, gate or script verb; Tick 1 and Tick 2 are unchanged.
- [ ] `skills/execute/SKILL.md` has a "The lead shape" section after "Single-PR Execution Path" Step 3 containing the phrase "lead shape", and a "Lost context?" paragraph stating: after a compaction run `koto status` on `execute-<topic>`, on each child, and under `/deliver` on `deliver-<topic>`; a non-terminal child goes to a new step agent; an outline child at `validation_exit` is detailed, rewound with `koto rewind` and handed off.

Nesting rule and review-level rules
- [ ] `references/parent-skill-pattern.md` states the `team_primitive` v1 value as `unit-agent-spawns-own-reviewers`, contains "may spawn" and "spawn nothing", and `git grep -n 'single-team-per-leader-no-nested' -- references skills` prints nothing. Other team-declaration passages in that file are left for the retirement issue.
- [ ] `skills/work-on/references/review-level-rules.tsv` classifies `skills/execute/references/step-agent-handoff.md` in the `template` class, and the `skills/work-on/` script tests that read this file still pass.

Tests, CI and evals
- [ ] `skills/execute/scripts/lead-shape-text_test.sh` runs under `/bin/bash` 3.2, checks each phrase above with `grep -F`, and on a missing phrase exits non-zero naming it.
- [ ] `skills/execute/scripts/execute-template-structure_test.sh` passes, with its mutation of the summaries sentence following the new wording (the owning session reads a child's `summary.md` itself when it details the next step, once per child).
- [ ] `.github/workflows/check-execute-scripts.yml` runs the new test in "Check execute scripts", and `scripts/bash-floor/execute.list` lists it.
- [ ] `skills/execute/evals/evals.json` has a scenario for a three-step `plan/v1` plan whose expectations name a step agent per step, a `step_refine/` key for steps two and three, and no `koto next` on a child by the owning session; it passes `scripts/check-skill.sh --changed execute`.
- [ ] E2E flow still works (do not break the skeleton): a `multi-pr` plan, a direct `/work-on`, and `skills/deliver/`, `skills/scope/`, `skills/charter/` and `skills/coordinate/` are untouched (`git diff --name-only` lists no file under them), and the CI workflows "Check execute scripts", "Check work-on scripts" and "Check bash floor" pass.

**Dependencies**: None

### Issue 2: feat(work-on): floor a shared-branch step's review level on its own commits

**Goal**: Make `review-level.sh facts` measure only a step's own `impl_base` diff when it runs on a shared branch, so a late step of a plan no longer floors at `full` because of earlier steps' commits.

**Context**:

Under the lead shape every plan-backed child commits to one shared branch. `facts` today keeps the larger of the `impl_base` diff and the merge-base diff, and on a shared branch the merge-base diff holds every earlier step's commits, so a late step crosses the 400-line or 12-file threshold or inherits an earlier step's template or engine path. `record-changed-paths.sh` already uses `impl_base` alone on a shared branch. This issue gives `facts` the same rule (PRD requirement R10, Design Decision 5, Implementation Approach Phase 2).

This is a refinement of the skeleton (Issue 1): it changes how one skeleton step is measured and does not touch the skeleton's flow.

Design: `docs/designs/DESIGN-lead-shape-delivery.md`

Relevant code: `skills/work-on/scripts/review-level.sh` (`facts`, around lines 600-640) and the `review_level_check` default action in `skills/work-on/koto-templates/work-on.md` (around line 915).

What Issue 1 landed that this issue builds on: `skills/execute/references/step-agent-handoff.md` (the step agent's hand-off, which the `/work-on` paragraph below should name), the `unit-agent-spawns-own-reviewers` value in `references/parent-skill-pattern.md`, and a `template`-class entry for the hand-off file in `skills/work-on/references/review-level-rules.tsv`, which this issue leaves in place. `review-level_test.sh` passed 258 cases after Issue 1. `/work-on`'s verification gate runs `scripts/check-skill.sh` for any `skills/**` change, which the host this plan runs on must not run: record the koto decision that hosted CI is the build of record for it before the tick that enters verification.

**Acceptance Criteria**:

- [ ] The skeleton still holds: `/bin/bash skills/execute/scripts/lead-shape-text_test.sh` passes unchanged.
- [ ] `review-level.sh facts <session> <level> [--shared-branch <branch>]` accepts the option after the two positionals, `<level>` may be empty, and `usage()` names the option.
- [ ] A `--shared-branch` value that fails `git check-ref-format --branch`, or that starts with `-`, makes `facts` exit 64.
- [ ] With a non-empty `--shared-branch`, `facts` skips `default_merge_base`, measures the `impl_base` diff only, and writes `base_source: impl_base` and `shared_branch` (the branch string) to `review_facts.json`.
- [ ] With a non-empty `--shared-branch` and no stored `impl_base`, `facts` exits 64 with the message `no base resolves on a shared branch: impl_base is unset`, and does not fall back to the merge-base.
- [ ] With an empty or absent `--shared-branch`, behaviour is unchanged: the larger-diff rule applies, and `shared_branch` is an empty string in `review_facts.json`. The 40-line, 400-line and 12-file thresholds are unchanged.
- [ ] `grep -F 'review-level.sh facts "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}" --shared-branch "{{SHARED_BRANCH}}"' skills/work-on/koto-templates/work-on.md` prints the `review_level_check` default action's command, and the template-consistency and `review-level_test.sh` checks that read the template's commands still pass.
- [ ] `skills/work-on/scripts/review-level_test.sh` has a case where, on a shared branch, an earlier sibling committed a `koto-templates/` file and 500 lines and the step's own `impl_base` diff is a 20-line `SKILL.md` change: `facts` records `base_source: impl_base` and floor `standard`.
- [ ] `review-level_test.sh` has a case off a shared branch with the same commits and an `impl_base` recorded after them: `facts` records `base_source: merge_base` and floor `full`, as today.
- [ ] `review-level_test.sh` has a case on a shared branch with no `impl_base`: `facts` exits 64 and the output names `impl_base`.
- [ ] `review-level_test.sh` has a case where `--shared-branch` is given a value that fails `git check-ref-format --branch`: `facts` exits 64.
- [ ] The existing base-choice cases in `review-level_test.sh` pass unchanged.
- [ ] `skills/work-on/references/review-levels.md`: "The facts floor" bullet on bases says the merge-base candidate is skipped on a shared branch, and a new section "A step's level under the lead shape" names `impl_base` as the only base on a shared branch, says the step's own `/work-on` chooses its level inside the bound and its own commits floor it, lists `ci`, `security`, `template` and `engine` as the classes that floor a step at `full`, and says a step touching none of them within 400 lines and 12 files floors no higher than `standard`.
- [ ] `skills/work-on/SKILL.md` Plan-Backed Child Mode has a paragraph that contains "lead shape" and "may spawn its step's review seats", names `skills/execute/references/step-agent-handoff.md`, and says the seats spawn nothing and a step agent never edits a step's entry.
- [ ] `skills/work-on/evals/evals.json` has a scenario in which a shared-branch child's facts record `base_source: impl_base`, with its `behaviour` field set per the repo's eval shape rules (checked locally by reading the shape rules; `scripts/check-skill.sh` is left to hosted CI on this host).
- [ ] Hosted CI's "Check work-on scripts", "Check skill gate" and "Check skill evals exist" pass on the pushed head.
- [ ] Bash 3.2 compatible (no associative arrays, no `mapfile`); no change to koto or niwa.
- [ ] No private repository names or URLs in any changed file (public repo).

**Dependencies**: Issue 1

### Issue 3: refactor(skills): retire the team declarations and the no-nesting rule

**Goal**: Retire the seven `team.yaml` declarations and the no-nesting rule, so no file describes a team that nothing builds and a unit's agent may spawn its own reviewers, jurors and researchers (PRD R8, R9).

**Context**:

The seven `skills/*/team.yaml` files have no reader (no script, validator check, test or eval), yet `references/parent-skill-pattern.md` presents them as a dispatch contract, and its `team_primitive` v1 value forbids the sub-agent spawning that step agents and scope agents need. Issue 1 changes the `team_primitive` value itself; this issue removes everything else that depends on the old premise and rewrites each skill's Team Shape section as prose.

Design: `docs/designs/DESIGN-lead-shape-delivery.md` (Decision 4; Solution Architecture, "Team declarations and the nesting rule"; Implementation Approach Phase 3). PRD: `docs/prds/PRD-lead-shape-delivery.md` (R8, R9).

Work items:

- Delete `skills/{brief,prd,design,plan,vision,strategy,roadmap}/team.yaml`.
- Rewrite the `## Team Shape` section in the nine `skills/*/SKILL.md` files (the seven plus `charter` and `scope`): say in prose which agents the skill spawns, at which phase, and that they spawn nothing. No section points at a file. Drop `/plan`'s line that its dispatcher "is therefore not declared in team.yaml".
- `references/parent-skill-pattern.md`: remove the Team-Shape Declarator section, the Dispatch Contract's Child Team-Shape Declaration element and the `skills/<name>/team.yaml` glob-marker list item; rewrite the binding notes near lines 980-990 and every other passage that cites them; rewrite the `team_primitive` consequences to match the value Issue 1 set (`unit-agent-spawns-own-reviewers`). Do not re-edit the value itself.
- `references/fixes/sub-agent-dispatch.md` and `skills/design/references/phases/phase-6-final-review.md` (around lines 95-98): the serial-self-jury fallback stays, but its premise becomes "when the harness can't spawn subagents".
- `references/worktree-discipline.md` (team-lead-spawned rows, around lines 181-190): the rows describe the parent itself, not a nested-team substrate.
- `docs/designs/current/DESIGN-shirabe-child-dispatch-contract.md` and `docs/designs/current/DESIGN-shirabe-progression-authoring.md`: add a dated "Retired" note saying the declaration was retired and `DESIGN-lead-shape-delivery.md` records why. Other designs that only cite the old choice as precedent stay untouched.

Write prose without emojis, and do not cite any `wip/` path from committed text.

**Acceptance Criteria**:

- [ ] No team declaration file remains: `git ls-files 'skills/*/team.yaml'` prints nothing.
- [ ] No live skill or reference points at a declaration file: `git grep -n 'team\.yaml' -- skills references scripts .github` prints nothing.
- [ ] None of the nine Team Shape sections link to a file: `git grep -n -A12 '^## Team Shape' -- skills/brief/SKILL.md skills/prd/SKILL.md skills/design/SKILL.md skills/plan/SKILL.md skills/vision/SKILL.md skills/strategy/SKILL.md skills/roadmap/SKILL.md skills/charter/SKILL.md skills/scope/SKILL.md | grep -c 'team\.yaml\|declarator'` prints `0`, and each of the nine files still has a `## Team Shape` heading (`git grep -c '^## Team Shape' -- <the nine files>` shows `1` per file).
- [ ] The pattern reference drops the declaration contract: `git grep -n 'Team-Shape Declarator\|Child Team-Shape Declaration\|skills/\*/team\.yaml\|skills/<name>/team\.yaml' -- references/parent-skill-pattern.md` prints nothing.
- [ ] The old nesting value is gone from the pattern reference and the live skills: `git grep -n 'single-team-per-leader-no-nested' -- references skills` prints nothing, and `git grep -c 'unit-agent-spawns-own-reviewers' -- references/parent-skill-pattern.md` prints a count of 1 or more (the value comes from Issue 1; this criterion also confirms the consequences are rewritten to use it).
- [ ] The pattern reference's `team_primitive` consequences say a unit's agent may spawn that unit's reviewers, jurors and researchers and that those spawn nothing: `git grep -n 'spawn nothing' -- references/parent-skill-pattern.md` prints at least one line.
- [ ] The serial-self-jury fallback stays with its new premise: `git grep -n "can't spawn" -- references/fixes/sub-agent-dispatch.md skills/design/references/phases/phase-6-final-review.md` prints at least one line from each file, and `git grep -c 'serial' -- references/fixes/sub-agent-dispatch.md skills/design/references/phases/phase-6-final-review.md` shows the fallback still present in both.
- [ ] The worktree-discipline rows no longer cite the old substrate: `git grep -n 'no-nested' -- references/worktree-discipline.md` prints nothing.
- [ ] Both current designs carry a dated retirement note naming this design: `git grep -n 'DESIGN-lead-shape-delivery' -- docs/designs/current/DESIGN-shirabe-child-dispatch-contract.md docs/designs/current/DESIGN-shirabe-progression-authoring.md` prints at least one line from each file, and each of those lines sits within a note containing a `2026-` date (`git grep -n -B3 -A3 'DESIGN-lead-shape-delivery' -- <the two files> | grep -c '2026-'` prints 2 or more).
- [ ] Designs that only cite the old choice as precedent are unchanged: `git diff --name-only <base>... -- docs/designs/current` lists only the two files above and the files other issues of this plan touch.
- [ ] No `wip/` reference or emoji was added by this step: `git diff <this step's impl_base>..HEAD | grep -n '^+.*wip/'` prints nothing.
- [ ] Nothing reads the retired files: before the deletion commit, `git grep -n -e 'team\.yaml' -e parent_layer -e child_layer -e upper_bound -e 'cardinality:' -- scripts crates .github hooks .claude-plugin 'skills/*/scripts' 'skills/*/evals' 'skills/*/koto-templates'` prints nothing (it printed nothing when this step was detailed), and the step's report says so.
- [ ] The skeleton still holds: `/bin/bash skills/execute/scripts/lead-shape-text_test.sh` exits 0, including its check that the old `team_primitive` value appears nowhere under `references/` or `skills/`.
- [ ] Hosted CI's "Check skill gate", "Check skill evals exist", "Check scope scripts", "Check plan scripts" and "Check execute scripts" pass on the pushed head; `scripts/check-skill.sh` for the nine touched skills is left to that CI on the host this plan runs on.

Notes from the steps already landed: Issue 1 set the `team_primitive` value to `unit-agent-spawns-own-reviewers` and renamed the old value's one mention in `references/worktree-discipline.md`; this step rewrites the value's consequences and the team-lead rows, not the value. `/work-on`'s verification gate starts `scripts/check-skill.sh` for any `skills/**` change: record the koto decision that hosted CI is the build of record for it first, and move to `verification` and past it with directed transitions so its action never runs on this host. `setup_plan_backed`'s `skip_if` did not fire on the last child although `SHARED_BRANCH` was set; pass it with `status: override` if it stops there.

**Dependencies**: Issue 1

### Issue 4: feat(deliver): scope in its own agent under --auto

**Goal**: Refine the skeleton so an `--auto` `/deliver` run hands `/scope` to one foreground scope agent, while an interactive run still calls `/scope` in the owning session.

**Context**:

Scoping in the same `/deliver` invocation used about half the context window before step one. Decision 3 of the design delegates `/scope` only under `MODE=auto`, because an interactive `/scope` asks the author questions a subagent cannot reach. This issue implements PRD requirement R6 and Phase 4 of the design.

Design: `docs/designs/DESIGN-lead-shape-delivery.md`

Changes land in:
- the `scope_run` directive in `skills/deliver/koto-templates/deliver.md` (near line 1033): the "Invoke the Skill tool" sentence becomes conditional on `{{MODE}}`
- `skills/deliver/SKILL.md`, Running the Workflow step 3
- new `skills/deliver/scripts/lead-shape-text_test.sh` (bash 3.2, `grep -F` per phrase, failing with the missing phrase)
- `.github/workflows/check-deliver-scripts.yml` and `scripts/bash-floor/deliver.list`
- `skills/deliver/evals/evals.json`

No change under `skills/scope/koto-templates/` or `skills/charter/koto-templates/`, and no koto or niwa change.

**Acceptance Criteria**:

- [ ] Under `auto`, the `scope_run` directive tells the owning session to hand the `/scope` Skill call, with exactly the arguments the directive builds, to one scope agent started in the foreground in the same checkout.
- [ ] The directive says the scope agent runs `/scope` to its terminal and returns at most ten lines, none of which the run uses; the owning session ticks `deliver-<topic>` to read the leg and reads the PLAN and documents from disk.
- [ ] Under `interactive`, the directive still invokes the Skill tool directly in the owning session.
- [ ] The `child_returned: yes` path to `deliver:child-absent` is unchanged and still covers a scope agent that returns with the leg open.
- [ ] `skills/deliver/SKILL.md` Running the Workflow step 3 states the same split and contains the phrase "lead shape".
- [ ] `skills/deliver/scripts/lead-shape-text_test.sh` asserts, per phrase with `grep -F`, that the `scope_run` directive hands the `/scope` call to one scope agent under `auto`, calls it directly under `interactive`, and keeps `child_returned: yes`; it exits non-zero naming the missing phrase.
- [ ] The test runs on bash 3.2: it is listed in `scripts/bash-floor/deliver.list` and wired into "Check deliver scripts" in `.github/workflows/check-deliver-scripts.yml`.
- [ ] Mutating the directive (removing the scope-agent phrase) makes the test fail.
- [ ] `skills/deliver/evals/evals.json` has an `--auto` scenario whose expectations name a scope agent.
- [ ] The directive's instruction to the scope agent says it must not read settings or credential files, and that the agents `/scope`'s children start (juries, researchers, issue-body agents) spawn nothing further except where `references/parent-skill-pattern.md` names an exception.
- [ ] `references/parent-skill-pattern.md`'s `team_primitive` value no longer says flatly that "Spawn depth stops at two": the sentence names the exception its consequence 2 already describes (`/design`'s critical-tier deciders follow `/decision`, whose phases start their own agents, which under a scope agent is a third level), so the value and its consequences agree; `/bin/bash skills/execute/scripts/lead-shape-text_test.sh` still passes.
- [ ] The CI workflows "Check deliver scripts", "Check skill gate", "Check skill evals exist" and "Check bash floor" pass on the pull request's head; `scripts/check-skill.sh --changed deliver` is left to that CI on the host this plan runs on.
- [ ] The skeleton still holds: `/bin/bash skills/execute/scripts/lead-shape-text_test.sh` exits 0, and nothing under `skills/execute/` or `skills/work-on/` changes in this step.

Notes from the steps already landed: Issue 3 rewrote the nine Team Shape sections and the pattern reference to say that the agent running `/scope` (for example a scope agent) spawns the children's juries; build on that wording rather than restating it. Step 1's text test pins phrases in `skills/execute/` and the pattern reference; this step adds its own test under `skills/deliver/scripts/`. `/work-on`'s verification gate starts `scripts/check-skill.sh` for any `skills/**` change, and the last panel's pass enters verification by itself: record the koto decision that hosted CI is the build of record before ticking past the last panel, then move with directed transitions. `setup_plan_backed` may need `status: override` although `SHARED_BRANCH` is set.

**Dependencies**: Issue 1

### Issue 5: feat(execute): hand coordinated work items to step agents

**Goal**: Make the coordinated path's `dispatch:<node>` action hand each work item to its own step agent, one at a time in the node's worktree, while the owning session keeps every run-record and remote write.

**Context**:

On a `coordinated` PLAN the `dispatch:<node>` action in `skills/execute/koto-templates/execute-coordinated.md` tells the session to dispatch each work item "as a `/work-on` plan-backed child" and drive it itself, so a multi-repository plan keeps the inline-context problem the single-pr path is leaving behind. This issue refines the skeleton (Issue 1) for the coordinated path (PRD R5): only the child loop moves to step agents. `repo-visibility.sh`, `node-cut.sh`, `node-push.sh`, their exit handling and every remote or run-record write stay with the owning session. Nothing under `skills/coordinate/` changes.

The refine commit stays local on the coordination branch: children read the PLAN through `plan_abs` in the coordination checkout, and `node-push.sh coordination` pushes that branch with the cascade, as it does today.

Design: `docs/designs/DESIGN-lead-shape-delivery.md` (Solution Architecture, the `dispatch:<node>` action and hand-off components; Implementation Approach Phase 5). Requirements: `docs/prds/PRD-lead-shape-delivery.md` (R5 and its coordinated acceptance criterion).

**Acceptance Criteria**:

- [ ] The skeleton still holds: `/bin/bash skills/execute/scripts/lead-shape-text_test.sh` passes with the new coordinated assertions added, and `/bin/bash skills/deliver/scripts/lead-shape-text_test.sh` still passes.
- [ ] The `dispatch:<node>` action in `skills/execute/koto-templates/execute-coordinated.md` hands each work item, one at a time in `ISSUES` order, to a step agent from the coordinated variant of the hand-off template in `skills/execute/references/step-agent-handoff.md`, started in the node's worktree, with the variables the action already lists (`ISSUE_SOURCE`, `SHARED_BRANCH=impl/{{PLAN_SLUG}}-<node>`, `ISSUE_NUMBER`, `PLAN_DOC` set to `plan_abs`, `REVIEW_FLOOR`, `REVIEW_CEILING`).
- [ ] The action has the owning session confirm each work item's child with `koto status work-on-<plan-slug>-<node>-<item>` before the next work item starts.
- [ ] The action has the owning session, before every work item after the run's first, rewrite that item's outline in the PLAN at `plan_abs`, commit it on the coordination branch in the coordination checkout, and record `step_refine/work-on-<plan-slug>-<node>-<item>.md`, with the same data-not-commands rule the single-pr directive states.
- [ ] `repo-visibility.sh`, `node-cut.sh`, `node-push.sh` and their exit-code handling in the action are unchanged in wording and still run by the owning session; the action states the refine commit stays local until `node-push.sh coordination` pushes the branch.
- [ ] The coordinated variant in `step-agent-handoff.md` names the session the step agent opens (`work-on-<plan-slug>-<node>-<item>`), lists the dispatch variables, and tells the agent it makes no push and no `gh` write.
- [ ] `skills/execute/scripts/lead-shape-text_test.sh` asserts, with `grep -F` and failing with the missing phrase, that the `dispatch:<node>` action names the hand-off template, "one at a time", the node's worktree, `koto status`, `step_refine/` and `plan_abs`, and that `node-push.sh` is still run by the owning session; the test passes against the edited files and fails when any one of those phrases is removed from `execute-coordinated.md`.
- [ ] The test stays bash 3.2 compatible and is still listed in `scripts/bash-floor/execute.list`.
- [ ] `git diff --stat` for this step's commits shows only `skills/execute/koto-templates/execute-coordinated.md`, `skills/execute/references/step-agent-handoff.md`, `skills/execute/scripts/lead-shape-text_test.sh`, and the two files of the CI fix below, and nothing under `skills/coordinate/`.
- [ ] The CI failure the earlier steps left is fixed: hosted CI's "Check tool diagnostic discards" failed because `skills/work-on/scripts/review-level.sh` runs `git check-ref-format --branch "$shared" >/dev/null 2>&1`, discarding a declared tool's diagnostics without a record. Either let that call's stderr through (so a refused branch name says why) or add the record `references/tool-diagnostic-discards.md` asks for, in its own commit; `/bin/bash scripts/check-tool-diagnostic-discards.sh` (the checker, not its full test suite) reports no finding for `review-level.sh`, and `review-level_test.sh`'s invalid-branch case still passes.
- [ ] The existing execute script files that read `execute-coordinated.md` and that this step touches still pass when run singly; hosted CI's "Check execute scripts", "Check work-on scripts", "Check tool diagnostic discards", "Check skill gate" and "Check skill evals exist" pass on the pushed head; `scripts/check-skill.sh --changed execute` is left to that CI on the host this plan runs on.
- [ ] The changed text names no private repository, URL or internal resource.

Notes from the steps already landed: Issue 1's single-pr directive already says how a waiting child is materialized (a bare `koto next` on the parent) and carries the data-not-commands and PLAN-path-only rules; the coordinated wording should match it, not restate a different version. On the coordinated path no child is koto-materialized, so the step agent opens `work-on-<plan-slug>-<node>-<item>` itself with the dispatch variables, and the owning session reads that name with `koto status`. `/work-on`'s verification gate starts `scripts/check-skill.sh` for any `skills/**` change and the last panel's pass enters verification by itself: record the koto decision that hosted CI is the build of record before that tick, then move with directed transitions. `setup_plan_backed` has needed `status: override` on every child so far.

**Dependencies**: Issue 1


## Implementation Sequence

Critical path: Issue 1, then Issues 2, 3, 4 and 5 in that order. Issues 2 to 5
each depend only on Issue 1 and could in principle run in parallel, but the
lead shape runs them one at a time in PLAN order so each later issue is
detailed from what the one before it landed.
