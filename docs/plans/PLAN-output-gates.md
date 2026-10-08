---
schema: plan/v1
status: Active
execution_mode: single-pr
tracking_level: none
upstream: docs/designs/DESIGN-output-gates.md
milestone: "Output Gates"
issue_count: 6
---

# PLAN: Output Gates

## Status

Active

Authored at Active: activation files no GitHub issues. Every rule a gate
reads is settled on main, so the build can start from main as it stands.

## Scope Summary

Build the output gates in docs/designs/DESIGN-output-gates.md: the gate
scripts, shirabe's own machine-readable verification map, the bounded
verification runner, /work-on's output and panel gates, and /execute's output
gates, removing every answer value that restated a script's result.

## Decomposition Strategy

**Horizontal decomposition.** The design names components with stable
interfaces between them: gate scripts with a fixed exit convention and finding
format, a runner with an on-disk result, the panels' existing verdict ledger,
and template states that call them. Each script is built and tested on its own
with fixtures before any template routes on it, so the template issues change
routing only and inherit tested commands. A walking skeleton would buy little:
the integration point, koto routing on an exit code, is already exercised by
the gates that ship today.

All six issues land in one pull request. No split trigger fires: the
verification gate reads the map from the default branch, but the build's own
runs use the installed plugin, so the map and the gate can merge together, and
the repository's delivery preference is consolidated.

## Issue Outlines

### Issue 1: feat(work-on): add the commit, wip, docs-visibility and PR gate scripts

**Goal**: Ship `check-branch-output.sh` (`--commits`, `--wip`,
`--docs-visibility`, `--synced`) and `check-pr-output.sh` (`--pr-body`,
`--owned-pr`) with their rule tables, the exit convention 0 pass, 1 violation,
2 could not decide, and `::koto-finding::` lines that carry a stable rule name
as `rule_id` and the source location as `rule_ref`, as the design's Decision
Outcome and rule table specify.

**Acceptance Criteria**:
- [ ] `skills/work-on/scripts/check-branch-output_test.sh` passes and covers: a non-conventional subject in `impl_base..HEAD` below a conventional tip exits 1 with a finding whose `rule_id` is `commit/conventional-subject`; a `Co-Authored-By: Claude` trailer exits 1 with `commit/no-ai-trailer`; a merge commit with git's default subject exits 0; a tree with a `wip/` file exits 1 with `branch/no-wip-files`; in a fixture declaring `Repo Visibility: Public`, a changed `docs/competitive/COMP-x.md` exits 1 with `docs/private-only-type`, a changed VISION with a prohibited section exits 1 with `docs/visibility-vision-sections`, a changed STRATEGY with a prohibited section exits 1 with `docs/visibility-strategy-sections`, a changed PRD missing a required section (a non-visibility code) exits 0, and a changed skill file containing `private/` exits 0; `--synced` on a branch missing `origin/main` exits 1 with `branch/current-with-main`, and with a merge in progress (`MERGE_HEAD` present) exits 1 too; `--base-ref origin/main` selects the same commits as the equivalent `--session` run on a fixture with both set up; a clean fixture exits 0; an unreadable range exits 2.
- [ ] `skills/work-on/scripts/check-pr-output_test.sh` passes and covers, with fake `gh`, `shirabe` and `owned-pr.sh` on `PATH`: validator exit 0, 2, 1, 3 and 4 map to 0, 1, 2, 2 and 2; the four PB messages map to `pr-body/conventional-title`, `pr-body/one-separator`, `pr-body/no-ai-trailer` and `pr-body/no-heading-in-part1`, and an unrecognized message to `pr-body/conformance`; `--pr-body --owned` reads the PR `owned-pr.sh` resolves, not the checked-out branch's; `owned-pr.sh` exit 0 with one URL maps to 0, exit 0 with empty output and exits 3, 4, 5 map to 3, exits 2 and 64 map to 2; `--owned-pr` prints no finding on any exit; the title reaches the validator as one argument when it contains `$(` and a quote.
- [ ] `skills/work-on/scripts/gate-rule-refs_test.sh` passes: every rule table row's excerpt occurs inside its `rule_ref` range at `HEAD`, no two rows share a `rule_id`, and changing a range in a fixture copy makes it fail.
- [ ] Every finding line either script prints parses as koto's finding shape (`jq -e '.rule_id and .level and .message and .rule_ref'` on the text after `::koto-finding::`), checked inside the two test files.
- [ ] `.github/workflows/check-work-on-scripts.yml` runs the three new test files, shown by `grep -c -E 'check-branch-output_test|check-pr-output_test|gate-rule-refs_test' .github/workflows/check-work-on-scripts.yml` printing 3.

**Dependencies**: None

**Type**: code
**Files**: `skills/work-on/scripts/check-branch-output.sh`, `skills/work-on/scripts/check-branch-output_test.sh`, `skills/work-on/scripts/check-pr-output.sh`, `skills/work-on/scripts/check-pr-output_test.sh`, `skills/work-on/scripts/gate-rules.tsv`, `skills/work-on/scripts/gate-rule-refs_test.sh`, `.github/workflows/check-work-on-scripts.yml`

### Issue 2: docs(work-on): commit shirabe's verification map as JSON

**Goal**: Define the `shirabe-verification-map/v1` schema in
`skills/work-on/references/verification-map.md` and commit shirabe's own map
at `.claude/shirabe-extensions/verification-map.json`, equivalent to the
Markdown map it replaces, with the Markdown section pointing at the file.

**Acceptance Criteria**:
- [ ] `jq -e '.schema == "shirabe-verification-map/v1"' .claude/shirabe-extensions/verification-map.json` exits 0.
- [ ] The map's `default` list names the same three commands the Markdown default names (`cargo test --workspace`, `skills/plan/scripts/plan-to-tasks_test.sh`, `skills/work-on/scripts/run-cascade_test.sh`), and its `skills/**` entry runs `scripts/check-skill.sh` with `each: "skills/*"`, checked by a `jq` query in `skills/work-on/scripts/verification-map-schema_test.sh`.
- [ ] Every command marked `network: true` also sets `unattended` explicitly, checked by the same test.
- [ ] `verification-map.md` documents every field the design lists (`run`, `each`, `timeout_secs`, `network`, `unattended`, `max_procs`, `entries`, `default`) and the merge-base read, shown by the test grepping each field name in it.
- [ ] `.claude/shirabe-extensions/work-on.md` no longer lists commands itself and names `verification-map.json`, shown by `grep -c 'verification-map.json' .claude/shirabe-extensions/work-on.md` printing at least 1 and `grep -c 'cargo test' .claude/shirabe-extensions/work-on.md` printing 0.

**Dependencies**: None

**Type**: docs
**Files**: `.claude/shirabe-extensions/verification-map.json`, `.claude/shirabe-extensions/work-on.md`, `skills/work-on/references/verification-map.md`, `skills/work-on/scripts/verification-map-schema_test.sh`

### Issue 3: feat(work-on): add the bounded verification runner

**Goal**: Ship `run-verification.sh` (`--start`) and `check-verification.sh`
(`--verdict`) as the design's Verification section specifies: the map read at
the merge-base, a detached supervisor that never calls koto, per-command
deadlines, a process-count bound, logs in 0700 directories outside every
repository, an on-disk result keyed by head, and the pending exit 75 a `poll:`
gate waits on.

**Acceptance Criteria**:
- [ ] `skills/work-on/scripts/run-verification_test.sh` passes and shows the verdict exit for each case: no result yet gives 75; a result for an older head only gives 75; all commands pass gives 0; a failing command gives 1; a command that forks past `max_procs` gives 4 and leaves no process of its group alive; a command past its `timeout_secs` gives 4; a command whose `run[0]` doesn't exist gives 4 with `verification/not-started`; no map at the merge-base gives 3; a map that doesn't parse gives 3 with `verification/bad-map`; a map that selects nothing gives 3; a map edited only on the branch is not used; a dirty tracked file gives 4; an `unattended: false` command gives 4 and is never started; an unreadable result file gives 2.
- [ ] The same test shows selection, by recording each started command's argv: a change matching two entries runs both entries' commands; an `each: "skills/*"` command changed under `skills/a/` and `skills/b/` runs twice, with `a` and `b` as the last argument; the `default` list runs when a changed path matches no entry, and not when every changed path matches one.
- [ ] Each violation exit prints a finding whose `rule_id` is the matching `verification/` name from the design's table, checked in the test.
- [ ] `--start` returns in under two seconds in every case above, measured in the test.
- [ ] A stale lock whose process is gone does not block a new start, shown in the test.
- [ ] One test case runs the launcher as a `default_action` and `--verdict` as a `poll:` gate under a real `koto next` against a fixture template, and reaches the state the verdict routes to, shown by the session's current state name.
- [ ] Log directories are created with mode 0700 and only the last ten heads per session are kept, shown by `stat` in the test.
- [ ] Neither script uses `setsid` or GNU `timeout`, shown by `grep -c -E '\bsetsid\b|\btimeout ' skills/work-on/scripts/run-verification.sh skills/work-on/scripts/check-verification.sh` printing 0 for each file, and both pass `scripts/check-bash-floor.sh`.
- [ ] `.github/workflows/check-work-on-scripts.yml` runs `run-verification_test.sh` and `verification-map-schema_test.sh`, shown by `grep -c -E 'run-verification_test|verification-map-schema_test' .github/workflows/check-work-on-scripts.yml` printing 2.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `skills/work-on/scripts/run-verification.sh`, `skills/work-on/scripts/check-verification.sh`, `skills/work-on/scripts/run-verification_test.sh`, `.github/workflows/check-work-on-scripts.yml`

### Issue 4: feat(work-on): gate commits, wip, docs, the PR body, CI role, staleness and verification

**Goal**: Wire gates 1 to 5, 7 and 8 of the design into
`skills/work-on/koto-templates/work-on.md`, turn `verification` into a state
koto runs (launcher action plus `verification_verdict` polling gate), and
remove the evidence values the design's before-and-after table removes from
`staleness_check`, `verification` and `ci_monitor`.

**Acceptance Criteria**:
- [ ] `koto template compile skills/work-on/koto-templates/work-on.md` succeeds, and `scripts/validate-template-mermaid.sh` and `scripts/check-template-interpolation.sh` pass on it.
- [ ] No transition in `staleness_check` names `staleness_signal: fresh`, `stale_requires_introspection` or `unavailable`, no state accepts `commands_run` or `verification_outcome`, and `ci_monitor` accepts no `session_role` and no `ci_outcome: passing`, each shown by a `grep -c` printing 0 in `skills/work-on/scripts/output-gates-routing_test.sh`.
- [ ] `output-gates-routing_test.sh` drives each new route with fake gate results and passes: staleness exits 0, 1, 3 and -1 reach `analysis`, `introspection`, `analysis`, `analysis` with no evidence; `verification_verdict` exits 0, 1, 3, 4 reach `finalization`, `implementation`, `done_blocked`, `done_blocked`, 75 leaves the state waiting, and 2 holds; `is_root` 0 and 1 with green CI reach `cascade_entry` and `done`; a failing `commit_convention` holds at `finalization` and at `deferral_approval`'s approved edge, and ends at `done_blocked` at `pre_pr_evidence`; failing `branch_wip_clean` or `branch_docs_visibility` holds at `pr_precheck` unless `SHARED_BRANCH` is set; failing `pr_body_conformant` holds at `pr_creation`.
- [ ] The same test shows every retained value still routes: `staleness_signal: override` reaches `analysis` and `blocked` reaches `done_blocked`; `verification_status: blocked` reaches `done_blocked`; `ci_outcome: failing_fixed` returns to `ci_monitor` and `failing_unresolvable` reaches `done_blocked`.
- [ ] No routing gate prints a finding: with each of `is_root` and `staleness_fresh` failing, the fake gate run's stdout holds no `::koto-finding::` line, checked in the routing test.
- [ ] `.github/workflows/check-work-on-scripts.yml` runs `output-gates-routing_test.sh`, shown by `grep -c 'output-gates-routing_test' .github/workflows/check-work-on-scripts.yml` printing at least 1.
- [ ] The existing suites `pre-pr-evidence_test.sh`, `finalization-shape_test.sh` and `ci-monitor-role_test.sh` pass, updated for the new gate commands.
- [ ] `skills/work-on/references/finishing-obligations.md` lists each new gate in its gated table and no longer lists `session_role` as carried evidence, shown by `grep -c 'session_role' skills/work-on/references/finishing-obligations.md` printing 0.
- [ ] No directive is removed: every directive line in `work-on.md` at the build's base that mentions verification commands, the PR body rule, or the commit convention is still present, shown by a `diff` of those lines in the routing test.
- [ ] `scripts/check-skill.sh work-on` passes.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:3>>

**Type**: code
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/references/finishing-obligations.md`, `skills/work-on/scripts/output-gates-routing_test.sh`, `skills/work-on/scripts/pre-pr-evidence_test.sh`, `skills/work-on/scripts/finalization-shape_test.sh`, `skills/work-on/scripts/ci-monitor-role_test.sh`, `.github/workflows/check-work-on-scripts.yml`

### Issue 5: feat(work-on): recompute panel verdicts from finding severity

**Goal**: Extend `panel-scope.sh` so `--record` derives each seat's blocking
status from its findings' `severity` and ignores `blocking_count`, add the
`--verdict` mode, and wire it as the `<panel>_verdict` gate on `scrutiny`,
`review`, `qa_validation` and `light_review`, replacing the agent's
`*_outcome: passed` and the `*_results.json` existence gate.

**Acceptance Criteria**:
- [ ] `skills/work-on/scripts/panel-scope_test.sh` passes with new cases: a round whose only finding is `severity: blocking` and whose `blocking_count` is 0 records the seat as blocking; a round with `blocking_count: 2` and only advisory findings records it as passing; a finding with no `severity`, or with a severity other than `blocking` or `advisory`, makes `--record` refuse the round with a non-zero exit; `--verdict` exits 0 when every seat of the panel is recorded and none is blocking, 1 with one `panel/blocking-finding` finding per blocking finding, non-zero when a seat the round's scope spawned has no verdict recorded since the scope, and 2 when the ledger is unreadable.
- [ ] No panel state accepts `scrutiny_outcome: passed`, `review_outcome: passed`, `qa_outcome: passed` or `light_outcome: passed`, and no panel state has a `<panel>_results` `context-exists` gate, shown by `grep -c` printing 0 in `output-gates-routing_test.sh`.
- [ ] `output-gates-routing_test.sh` shows each panel's `<panel>_verdict` at 0 advancing with no evidence, at 1 routing `blocking_retry` to `implementation` and `blocking_escalate` to `done_blocked`, at 0 refusing both of those values, and at 2 holding, with the existing `<panel>_carried` route unchanged.
- [ ] The panel phase files describe the round file with a `severity` on every finding, shown by `grep -c 'severity'` printing at least 1 in each of `phase-4a-scrutiny.md`, `phase-4b-review.md` and `phase-4c-qa.md`.
- [ ] Each panel state keeps an `override_default`, shown by the routing test.
- [ ] `retry-clearing_test.sh` and `scripts/check-skill.sh work-on` pass.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: code
**Files**: `skills/work-on/scripts/panel-scope.sh`, `skills/work-on/scripts/panel-scope_test.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/references/phases/phase-4a-scrutiny.md`, `skills/work-on/references/phases/phase-4b-review.md`, `skills/work-on/references/phases/phase-4c-qa.md`, `skills/work-on/scripts/retry-clearing_test.sh`

### Issue 6: feat(execute): gate the owned PR, its output, the pause and the cascade verdict

**Goal**: Wire gates 9 to 19 of the design into
`skills/execute/koto-templates/execute.md`, route `pr_finalization`'s pause on
`vars.PAUSE_BEFORE_FINALIZE`, have `run-cascade.sh --session` record its
verdict as `cascade_result.json`, and remove the evidence values the
before-and-after table removes from `orchestrator_setup`, `pr_finalization`,
`plan_completion` and `ci_monitor`.

**Acceptance Criteria**:
- [ ] `koto template compile skills/execute/koto-templates/execute.md` succeeds, and `scripts/validate-template-mermaid.sh` and `scripts/check-template-interpolation.sh` pass on it.
- [ ] No state accepts `pr_adopt` or `status_read` as an evidence value, `pr_finalization` accepts no `pause_decision`, `plan_completion` accepts no `cascade_status`, and `ci_monitor` accepts no `dirty_merge_state` and no `passing`, shown by `grep -c` printing 0 in `execute-output-gates-routing_test.sh`.
- [ ] `execute-output-gates-routing_test.sh` drives each new route with fake gate results and passes, naming the target of every route:

  | State | Gate result | Target |
  |---|---|---|
  | `orchestrator_setup` | `setup_owned_pr` 0, 3, 2 | `settled_branch_record`; `done_blocked` with step `execute:pr-adopt`; `done_blocked` with step `execute:status-read` |
  | `pr_finalization` | `final_owned_pr` 3, 2 | `done_blocked` with `execute:pr-adopt`; with `execute:status-read` |
  | `pr_finalization` | output gates pass, `PAUSE_BEFORE_FINALIZE` `true` / `false` | `paused_for_review`; `plan_completion` |
  | `pr_finalization` | any of the PR-body, commit, wip or docs-visibility gates failing | holds |
  | `plan_completion` | `cascade_result.json` `completed`, `skipped`, `partial` | `ci_monitor`; `ci_monitor`; holds |
  | `plan_completion` | `ready_owned_pr` 3, 2 | `done_blocked` with `execute:pr-adopt`; with `execute:status-read` |
  | `ci_monitor` | both CI gates green, `monitor_owned_pr` 0, no evidence | `merge_readiness` |
  | `ci_monitor` | `owned_ci_passing` 1, no evidence | holds |
  | `ci_monitor` | `owned_merge_state_clean` 1, no evidence | `escalate_dirty_merge_state` |
  | `ci_monitor` | `monitor_owned_pr` 3, 2 | `done_blocked` with `execute:pr-adopt`; with `execute:status-read` |
- [ ] The same test shows every retained value still routes: `orchestrator_setup` `status: override` reaches `settled_branch_record` and `blocked` reaches `done_blocked`; `finalization_status: update_failed` reaches `done_blocked`; `plan_completion` accepts `cascade_detail`; `ci_outcome` `failing_fixed` and `pending` reach `merge_readiness` and `failing_unresolvable` reaches `done_blocked`.
- [ ] No routing gate prints a finding: with each of `setup_owned_pr`, `final_owned_pr`, `ready_owned_pr`, `monitor_owned_pr` and the three cascade gates failing, stdout holds no `::koto-finding::` line, checked in the routing test.
- [ ] `worktree_sync`'s `current_with_main` gate calls `check-branch-output.sh --synced`, shown by `grep -c 'check-branch-output.sh" --synced' skills/execute/koto-templates/execute.md` printing 1, and its routing is unchanged, shown by the existing `worktree_sync` cases in `execute-template-structure_test.sh` passing.
- [ ] `.github/workflows/check-execute-scripts.yml` runs `execute-output-gates-routing_test.sh`, shown by `grep -c 'execute-output-gates-routing_test' .github/workflows/check-execute-scripts.yml` printing at least 1.
- [ ] `run-cascade_test.sh` passes and shows `--session` recording `cascade_result.json` whose `cascade_status` equals the verdict the script prints.
- [ ] `execute-template-structure_test.sh`, `owned-pr-callers_test.sh` and `settled-branch-record_test.sh` pass, and `scripts/check-skill.sh execute` passes.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/execute/koto-templates/execute.md`, `skills/execute/SKILL.md`, `skills/work-on/scripts/run-cascade.sh`, `skills/work-on/scripts/run-cascade_test.sh`, `skills/execute/scripts/execute-output-gates-routing_test.sh`, `.github/workflows/check-execute-scripts.yml`

## Implementation Sequence

**Critical path:** Issue 2, Issue 3, Issue 4, Issue 5.

**Parallel start:** Issues 1 and 2 have no dependencies. Issue 6 needs only
Issue 1 and can run beside Issues 3 to 5, since it touches /execute's files
and `run-cascade.sh`, none of which the /work-on issues write.

**Rules the gates read:** all settled on main by the contradiction-settlement
work (the design's last table lists where). The build re-reads
`work-on.md`, `execute.md` and `panel-scope.sh` at its own base before
editing them.
