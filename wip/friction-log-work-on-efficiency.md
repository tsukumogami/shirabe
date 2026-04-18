# Friction Log: work-on-efficiency Implementation

Running the work-on plan orchestrator against `docs/plans/PLAN-work-on-efficiency.md`
on branch `docs/work-on-koto-unification`, single-pr mode, no new branch.

---

## F1: Input resolution — PLAN doc path not a recognized input type

**Phase**: Input Resolution (work-on skill begin)
**Observed**: The work-on skill's Input Resolution section only recognizes issue
numbers (`71`, `#71`, issue URL) and milestone references (`M3`, `"Milestone Name"`).
A PLAN doc path like `docs/plans/PLAN-work-on-efficiency.md` matches neither pattern.
The skill has a note that "Plan-backed mode uses free-form init" but no formal detection
path for it — the operator must recognize the input type manually and apply the
plan-backed convention.
**Impact**: Low. The plan-backed path works once recognized, but a new user following
the skill mechanically would not know which init mode to use.
**Suggestion**: Add PLAN doc path detection to Input Resolution (matches
`docs/plans/PLAN-*.md`), route to plan-backed free-form mode automatically.

---

## F2: orchestrator_setup — branch creation conflicts with stay-on-branch constraint

**Phase**: orchestrator_setup
**Observed**: The `orchestrator_setup` directive creates `impl/<plan-slug>` as the
shared branch. When the user wants all changes on an existing branch (here,
`docs/work-on-koto-unification`), the only escape valve is the `status: override`
path — which the directive allows when "the current branch is non-main and an open PR
already covers this work."
**Impact**: Medium. The `status: override` path works here (PR #67 exists on this
branch), but the subsequent `spawn_and_await` directive still hardcodes
`impl/$PLAN_SLUG` as the `SHARED_BRANCH` value injected into children. Children would
commit to a non-existent branch.
**Workaround**: Substitute the current branch name for `impl/$PLAN_SLUG` when
building the tasks JSON in `spawn_and_await`.
**Root cause**: The orchestrator_setup / spawn_and_await split assumes branch creation
always succeeds and the branch name is deterministic. There is no mechanism to pass
the actual branch name from `orchestrator_setup` to `spawn_and_await`.
**Suggestion**: Either (a) surface the actual branch name as a context key after
orchestrator_setup so spawn_and_await can read it, or (b) use `{{SESSION_NAME}}` as
part of the branch-name derivation pattern so overrides can be expressed cleanly.

---

## F3: spawn_and_await — `koto next work-on-plan` hardcoded (Issue 1 bug)

**Phase**: spawn_and_await directive (Tick 1 and Tick 2 scripts)
**Observed**: Both tick scripts call `koto next work-on-plan` literally. If the
orchestrator is initialized under any name other than `work-on-plan`, the ticks call
the wrong workflow. This is the exact bug Issue 1 is designed to fix.
**Impact**: High if non-default name used. Zero impact in this run since the workflow
is initialized as `work-on-plan`.
**Note**: This is a known bug — Issue 1 is the fix. Recorded for completeness.

---

## F4: spawn_and_await — `materialize_children` missing `vars_field: vars` (Issue 1 bug)

**Phase**: spawn_and_await state definition
**Observed**: The `materialize_children` block does not include `vars_field: vars`.
koto v0.8.2 can pass each task's `vars` object as `--var` flags when spawning children,
but only if `vars_field` is configured. Without it, children are spawned without
`SHARED_BRANCH`, `ISSUE_SOURCE`, or `ARTIFACT_PREFIX` vars — child templates that
depend on these vars receive empty/default values.
**Impact**: High. Children spawned by the current template do not receive the branch
or source context. This is the root cause of children incorrectly owning their own PR.
**Note**: This is a known bug — Issue 1 is the fix. Recorded for completeness.

---

## F5: spawn_and_await — `CLAUDE_PLUGIN_ROOT` not set in shell environment

**Phase**: spawn_and_await (Tick 1 script)
**Observed**: The tick script uses `${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh`.
`CLAUDE_PLUGIN_ROOT` is not automatically set in the operator's shell environment —
it's an implicit convention. Running the tick script as written fails with
"plan-to-tasks.sh: No such file or directory" unless the operator manually sets
`CLAUDE_PLUGIN_ROOT` first.
**Impact**: Medium. Operator must know the plugin root path to run the script. Using
`shirabe` plugin at version 0.4.1-dev the path is
`/home/dangazineu/.claude/plugins/cache/shirabe/shirabe/0.4.1-dev`.
**Workaround**: Export `CLAUDE_PLUGIN_ROOT` before running tick scripts, or substitute
the absolute path directly.
**Suggestion**: Add a `check-claude-plugin-root.sh` helper that sets the variable, or
document the expected value in SKILL.md. Alternatively, use a relative path from the
template location.

---

## F6: pr_finalization — `koto context get work-on-plan batch_final_view` hardcoded

**Phase**: pr_finalization directive
**Observed**: The directive calls `koto context get work-on-plan batch_final_view`
literally. Same hardcoded-name bug as F3. Issue 1 fixes this.
**Note**: Recorded for completeness.

---

## F7: Single-pr mode — work-on-plan.md orchestrator designed for multi-pr

**Phase**: Overall architecture
**Observed**: The `work-on-plan.md` orchestrator creates its own branch/PR and expects
children to commit to it. In single-pr mode, the PLAN is already inside an existing
PR (all issues go in one commit set, one review). The orchestrator's branch-creation
and PR-creation logic does not map cleanly to the "stay on existing branch, update
existing PR" constraint.
**Impact**: Medium-high. The `status: override` path partially handles this, but the
PR finalization step (`pr_finalization`) would update the existing PR #67's description
with per-child outcomes — which may or may not be the desired behavior for a single-pr
implementation.
**Suggestion**: Consider a `single_pr: true` mode in orchestrator_setup that skips
branch/PR creation entirely and assumes the caller owns the PR lifecycle. This maps
directly to the single-pr PLAN execution mode.

---

## F8: plan-to-tasks.sh — all 7 task names truncated at 64-char koto limit

**Phase**: spawn_and_await (Tick 1)
**Observed**: plan-to-tasks.sh constructs names as `outline-<slugified-title>`. Every
issue title in this plan produces names over 64 chars (koto's hard limit). All 7 names
were truncated with a warning. The truncated names are opaque — comparing
`outline-feat-work-on-add-pr-status-shared-for-plan-backed-childr` to the original
title requires cross-referencing the PLAN doc.
**Impact**: Medium. koto truncates gracefully with a warning; no crash. But tracking
which child corresponds to which issue becomes harder, especially in `koto status`
output.
**Suggestion**: plan-to-tasks.sh could use the issue number as part of the name
(e.g., `outline-1-fix-session-name`) to stay under the limit and remain readable.
Or the naming strategy could be issue-number-only (e.g., `issue-1`, `issue-2`) for
single-pr mode, since the full title is in the PLAN doc.

---

## F9: PLAN_DOC variable not propagated to children

**Phase**: plan_context_injection (child workflows)
**Observed**: The `plan_context_injection` directive says "the PLAN doc is already
available via the PLAN_DOC variable." But `PLAN_DOC` is set on the parent
(`work-on-plan`) template, not on the child (`work-on.md`) template. Without
`vars_field: vars`, children receive no vars from the parent (Issue 1 bug). Even after
Issue 1 is fixed (which adds `vars_field: vars` to pass task vars), the task vars from
plan-to-tasks.sh don't include `PLAN_DOC` — only `ISSUE_SOURCE`, `ARTIFACT_PREFIX`,
`SHARED_BRANCH`, and optionally `ISSUE_TYPE`.
**Impact**: Medium. The `plan_context_injection` directive's instruction to use
`{{PLAN_DOC}}` to extract issue context is dead letter in practice. Operators must
write context.md manually (or the gate's override_default masks the gap).
**Suggestion**: plan-to-tasks.sh should emit `PLAN_DOC` in each task's `vars` object,
and the orchestrator template's tick script should ensure it's included. Or the
gate's `override_default: {exists: true}` should be documented as the intentional
fallback.

---

## F10: Issue 1 (simple fix) runs full scrutiny/review/QA panel

**Phase**: implementation → scrutiny → review → qa_validation
**Observed**: Issue 1 is a simple template find-and-replace (complexity: simple). It
went through three consecutive panel states (scrutiny, review, qa_validation) with no
benefit — the changes are mechanical and already captured in the ACs. Each panel
requires writing a gate artifact to context and submitting evidence.
**Impact**: Medium. This is the exact inefficiency Issue 3 (issue_type routing) is
designed to fix. Running the plan before Issue 3 is implemented means the first
round of children can't use the fast path.
**Mitigation**: Once Issue 3 is implemented and Issue 4 adds pr_status: shared, future
plan runs will skip panels for docs/simple issues. The current run takes the hit.
**Suggestion**: Implementation order within a single-pr plan matters. Consider
implementing Issues 2 and 3 (routing) before other children to allow subsequent
children to benefit from the fast path. The dependency graph doesn't capture this
"improves the tooling mid-flight" pattern.

---

## F11: Plan-backed child submits pr_status: created instead of shared

**Phase**: pr_creation (child workflows)
**Observed**: Issue 1 child submitted `pr_status: created` with PR #67's URL, since
`pr_status: shared` doesn't exist yet (Issue 4 adds it). This goes through ci_monitor
which then checks CI for the PR. The child is semantically doing the wrong thing —
it doesn't own the PR.
**Impact**: Low in practice (ci_monitor has a fallback transition to done), but the
wrong semantic is captured in the koto event log.
**Note**: This is the known bug Issue 4 fixes. Recorded for completeness.

---

## F12: context_artifact gate override_default unclear

**Phase**: plan_context_injection
**Observed**: The gate has `override_default: {exists: true}` which should make it
auto-pass without a context.md. However, when submitting evidence on the first call
(without context.md written), Issues 2/5/7 stayed at `plan_context_injection` instead
of advancing. Writing context.md manually was required. The override_default appeared
not to fire on the initial evidence submission.
**Impact**: Low. Writing context.md is easy. But the override_default semantics are
unclear — it may only apply when no evidence has been submitted yet, or there may be a
timing issue.
**Suggestion**: Document the exact semantics of override_default in the koto template
authoring guide. Consider renaming it to `gate_default` to make the scope clearer.

---

---

## F13: koto mutual exclusivity check requires issue_type in all implementation transitions

**Phase**: implementation state transitions
**Observed**: When adding `docs → finalization` and `task → finalization` transitions
alongside the existing default `→ scrutiny` transition, koto rejected the template with
"transitions to 'finalization' and 'scrutiny' are not mutually exclusive: all shared
fields have identical values." The `docs` transition had `issue_type: docs` + two gate
conditions. The default `scrutiny` had no `issue_type` + the same two gate conditions.
koto's check: if ALL fields present in BOTH transitions share identical values, they're
ambiguous — even though one has an additional discriminating `issue_type: docs` that the
other lacks.
**Root cause**: koto's mutual exclusivity check only passes if the shared field values
include at least one difference. An optional discriminating field on one side isn't
enough — the field must be present on BOTH transitions with different values.
**Fix**: Declare `issue_type` explicitly (code/docs/task) on ALL three transitions. All
three then share `issue_type` as a common field, but with distinct values → unambiguous.
**Suggestion**: koto could improve the error message to show which transitions are
ambiguous and why, listing which shared fields were identical. Current message omits the
specific field names.

---

## F14: vars_field removed from materialize_children in koto 0.8.2

**Phase**: spawn_and_await (template compilation)
**Observed**: The `vars_field: vars` field added in Issue 1 caused "failed to parse
front-matter" in koto 0.8.2. The field doesn't appear in the koto-skills batch-coordinator
example or in koto source code. koto 0.8.2 became strict about unrecognized YAML keys.
**Impact**: High. After reinitializing the orchestrator, koto template compilation failed
until `vars_field: vars` was removed. This blocked all work for one investigation cycle.
**Root cause**: Issue 1 added `vars_field: vars` based on reading the feature requirements,
but the field was never in koto's schema. koto 0.8.1 silently ignored unknown fields;
0.8.2 fails hard.
**Fix**: Removed `vars_field: vars` from `materialize_children`. The task vars are already
passed via each task's `vars` object in the tasks array — no extra field needed.
**Suggestion**: koto template schema should be versioned and documented. A linting command
(`koto template lint`) that catches unrecognized fields before `koto init` would surface
this earlier.

---

## F15: Orchestrator auto-advanced to done_blocked via default escalate fallback

**Phase**: spawn_and_await (between Tick 1 and Tick 2)
**Observed**: When Issue 4's child was retried after the template fix, all 7 children
eventually completed. But the orchestrator's default fallback transition `- target: escalate`
(without a `when:` guard) fired before Tick 2 could submit `batch_outcome: all_success`.
The orchestrator reached `escalate → done_blocked` (terminal, failure). After reaching a
terminal state, koto cleans it up — `koto workflows` returned `[]` and subsequent
`koto next work-on-plan` returned "workflow not found."
**Impact**: High. Required full orchestrator re-initialization and re-driving all 7
children through `done_already_complete`.
**Root cause**: The default fallback fires when the `batch_done` gate becomes true but
no matching evidence transition exists yet. The agent must submit Tick 2 faster than
the gate fires, or the default transition must be removed.
**Suggestion**: Remove the default `- target: escalate` fallback from `spawn_and_await`.
The two explicit transitions (`all_success → pr_finalization`, `needs_attention → escalate`)
are sufficient. An unconditional default exit from a long-running state is dangerous.

---

## Implementation Progress

| Issue | Status | Notes |
|-------|--------|-------|
| 1: fix SESSION_NAME + vars_field | done | |
| 2: done_already_complete | done | |
| 3: issue_type routing | done | |
| 4: pr_status: shared | done | |
| 5: Type + Files in spec | done | |
| 6: plan-to-tasks.sh parsing | done | |
| 7: CI validation script | done | |

All 7 issues implemented. PR #67 updated. CI pending.
