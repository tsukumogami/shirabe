# Lead

Inventory every value-adding capability of `/work-on`'s CURRENT multi-issue PLAN execution, so the `/execute` PRD can require parity-or-better as explicit acceptance criteria. The author's hard guardrail: `/execute` (absorbing /work-on's PLAN-level multi-issue execution) MUST deliver parity-or-better with the VALUE /work-on's multi-issue execution provides today. Source of truth is the merged worktree post-#196 at `/home/dgazineu/dev/worktrees/shirabe-execute-skill/skills/work-on/`.

The plan orchestrator is the koto state machine in `koto-templates/work-on-plan.md`. It drives one shared branch + one draft PR through: `orchestrator_setup → worktree_discipline_check → spawn_and_await → pr_finalization → plan_completion → ci_monitor → done`, with escalation branches at each risky step. Each issue is a materialized child running the full `koto-templates/work-on.md` per-issue machine.

# Value Inventory

## 1. Drift-prevention gate (`worktree_discipline_check`)
- **What**: A dedicated koto state that runs ONCE between `orchestrator_setup` and `spawn_and_await`. It does `git fetch origin` + `git rebase origin/main`, then classifies upstream impact into `none | informational | intent-changing`, writes `wip/work-on_${PLAN_SLUG}_impact.json` (the `impact_classified` command gate checks file presence), and submits the class as evidence. `none`/`informational` route forward; `intent-changing` routes to `escalate_upstream_drift → done_blocked` carrying an actionable rationale. (`work-on-plan.md:38-77, 249-261`; `references/phases/phase-2.5-worktree-discipline.md:1-100`)
- **Why valuable**: Catches the case where main moved under a long-running shared-branch PR and silently invalidated the PLAN's foundation (deleted referenced files, changed contracts, restructured substrate). The phase doc names the catastrophic failure it prevents: SE11 / PR-141 in the v0.7.0 friction record, where drift was discovered only at PR finalization when recovery cost was maximal. Moves detection to the cheapest-recovery point. Classification is about INTENT (does the PLAN's foundation still hold), not mechanical rebase cleanliness — a clean rebase can still land a contract change.
- **Plan-level or per-issue**: **PLAN-LEVEL.** This is the single most important plan-orchestrator-only capability; single-issue `work-on.md` invocations explicitly do NOT run it (phase-2.5 doc:11-13). Must move to `/execute`.

## 2. Inter-issue learning / carry-forward (cross-issue context assembly)
- **What**: Before dispatching each child, summaries from ALL completed children are concatenated into `current-context.md` (via `koto context get <child> summary.md`) and written into the new child's koto context with `koto context add`. Explicitly not skipped even when only one prior child completed. (`references/cross-issue-context.md:1-16`; wired into SKILL.md:221-224)
- **Why valuable**: Gives each issue N+1 awareness of what issues 1..N found, decided, or changed — load-bearing when later issues build on earlier ones in the same chain. This is the concrete mechanism for knowledge carry-forward across issues. The shared branch is the other half: all children commit to one branch (`SHARED_BRANCH`), so issue N+1 sees issue N's actual code, not just its summary.
- **Plan-level or per-issue**: **PLAN-LEVEL** (orchestrator assembles and injects). The per-issue child consumes it as `context.md`/baseline input. Must move to `/execute`.

## 3. Per-issue lifecycle with evidence artifacts
- **What**: Each issue runs the full `work-on.md` machine, producing a sequence of koto-context artifacts per child: `context.md` (issue/outline context), `baseline.md` (pre-change state), `introspection.md` (staleness, issue-backed only), `plan.md` (analysis output incl. `decisions` records), implementation commits, `scrutiny_results.json`, `review_results.json`, `qa_results.json`, and `summary.md` (requirements-mapping table: AC → Status → Evidence). Each artifact is gated by a `context-exists` gate so the state cannot advance without it. (`work-on.md` states; `references/phases/phase-5-finalization.md:28-64`)
- **Why valuable**: Every issue leaves an auditable trail — baseline, plan, decision records, review verdicts, summary with AC-to-evidence mapping. The `summary.md` per child is what the orchestrator harvests to build the combined PR body AND what cross-issue context assembly forwards.
- **Plan-level or per-issue**: **PER-ISSUE.** Stays in /work-on (or whatever single-issue surface /execute delegates to). The orchestrator depends on `summary.md` existing per child.

## 4. Review panels (three panels per code issue, right-sized by issue_type)
- **What**: Per code issue, three sequential gated panels each spawning three parallel reviewers: **scrutiny** (completeness, justification, intent), **review** (pragmatic, architect, maintainer), **qa_validation** (QA). Each panel accepts `passed | blocking_retry | blocking_escalate`; `blocking_retry` returns to `implementation`, `blocking_escalate → done_blocked`. Retry loop capped at 2 cycles. Panels carry `override_default` so skipping is auditable via `koto overrides list`. (`work-on.md:502-590`; `references/review-panel-orchestration.md:1-19`)
- **Right-sizing**: Panels run ONLY for `issue_type: code`. `docs` and `task` issues skip all three panels and route straight to `finalization` (`work-on.md:471-484`). The `issue_type` hint flows from the PLAN outline's `**Type**:` field, is confirmed/overridden during analysis, and re-submitted at implementation for routing.
- **Why valuable**: Nine reviewer perspectives per code issue, with a bounded retry-then-escalate loop, prevents low-quality code from advancing. Right-sizing avoids wasting nine-reviewer scrutiny on docs/task issues. The auditable-skip property (`override_default` + `koto overrides list`) means a bypass is never silent.
- **Plan-level or per-issue**: **PER-ISSUE.** Stays in the single-issue machine. /execute must preserve that each code child runs panels and each docs/task child skips them.

## 5. CI-to-green choreography with DRAFT-vs-READY discipline (#117)
- **What**: The orchestrator opens a **DRAFT** PR at setup. After children complete, ordering is deliberately: `pr_finalization` (assemble + `gh pr edit` the body, does NOT mark ready) → `plan_completion` (cascade pulls chain to terminal, THEN `gh pr ready`) → `ci_monitor`. CI re-runs on the `ready_for_review` event under ready posture, against the now-finalized chain. `ci_monitor` gates on `ci_passing` AND `merge_state_clean`; `failing_fixed` lets the agent's direct observation override a stale gate; `failing_unresolvable → done_blocked`. (`work-on-plan.md:106-167, 299-360`; SKILL.md:236-255)
- **DIRTY-handling (#162)**: A separate `merge_state_clean` gate distinguishes an actually-green PR from a DIRTY-suppressed one (GitHub stops creating check-runs on conflict, which would otherwise read as `length == 0` = passing). DIRTY routes to `escalate_dirty_merge_state → done_blocked` naming conflict files; no auto-retry because rebase requires judgment. (`work-on-plan.md:131-178, 314-329`)
- **Why valuable**: The draft-first posture means CI never runs strict-mode lifecycle checks against a mid-PR chain state that would legitimately fail; the cascade finalizes the chain first, THEN flips ready, THEN CI validates the terminal chain. The two-gate CI check closes the false-green hole that DIRTY merge states open.
- **Plan-level or per-issue**: **PLAN-LEVEL.** The shared-branch/single-PR CI choreography is orchestrator-owned. Per-issue children with `SHARED_BRANCH` set submit `pr_status: shared` and skip their own PR/CI entirely (`work-on.md:940-953`; phase-6-pr.md:44-50). Must move to /execute.

## 6. Finalization cascade (`plan_completion` + `run-cascade.sh`)
- **What**: `run-cascade.sh --push <PLAN_DOC>` performs an ATOMIC finalization commit that walks the PLAN's `upstream` frontmatter chain and applies each terminal transition in ONE commit: PLAN → Done-then-DELETED (`git rm`), DESIGN → Current (incl. `git mv` into current/ and Implementation-Issues strip), PRD → Done, BRIEF → Done, ROADMAP feature Status → Done + Downstream rewrite, and optional ROADMAP → Done + `git rm` gated by all-features-Done AND all-referenced-issues-CLOSED. The chain walk/per-node transition is owned by `shirabe finalize-chain`; the script orchestrates git and the roadmap handler. (`scripts/run-cascade.sh:1-909`; `work-on-plan.md:180-360`)
- **Self-verifying**: The script runs a `--lifecycle-chain ... --mode=ready` probe BEFORE transitions (pre-probe expects a failure naming the present PLAN; a clean pass means already-terminal → `cascade_status: skipped`, no-op exit 0) and AFTER the commit (post-verify expects a clean pass; failure → `partial` with the validator's structured L-code findings logged). The agent never invokes the validator directly. (`run-cascade.sh:263-321, 653-881`)
- **Why valuable**: Closes the whole artifact chain's lifecycle in one atomic commit, so the audit trail at HEAD is internally consistent — no half-finalized chain, no dangling PLAN. The pre/post probe pins cascade behavior end-to-end deterministically (exit-code-only control flow). Status values `completed | partial | skipped` all route to `ci_monitor`, never silently dropping a partial.
- **Plan-level or per-issue**: **PLAN-LEVEL.** The cascade operates on the PLAN doc and its whole upstream chain; only the orchestrator has the PLAN_DOC and the finalized shared branch. Must move to /execute.

## 7. Gate auto-advance / koto state-machine sequencing (`spawn_and_await` + `materialize_children`)
- **What**: `spawn_and_await` runs `plan-to-tasks.sh <PLAN_DOC>` to emit a JSON task array (`{name, vars, waits_on}` per issue, deps parsed from the Implementation Issues table / outline Dependencies into `waits_on: [issue-N]`), injects `SHARED_BRANCH` into each task's vars, and submits via `koto next --with-data`. koto's `materialize_children` (from_field `tasks`, `default_template work-on.md`, `failure_policy: skip_dependents`) lazily materializes one child per task and sequences them by the `waits_on` DAG. The `batch_done` children-complete gate blocks the orchestrator until all children reach terminal states; then evidence (`all_success | needs_attention`) routes to `pr_finalization` or `escalate`. Re-submitting the same tasks array is deduplicated by koto, which makes setup idempotent on crash/re-run. (`work-on-plan.md:79-104, 263-298`; `plan-to-tasks.sh:1-237`)
- **Resume/idempotency**: `orchestrator_setup`'s branch/PR script is idempotent (reuses existing branch+PR); `status: override` skips creation when already on the right `impl/<slug>` branch with an open PR. The whole machine resumes via `koto workflows` + `koto next`. (`work-on-plan.md:231-247`; SKILL.md:132-208)
- **Failure isolation**: `failure_policy: skip_dependents` means a failed issue's dependents are auto-skipped (enter with `mode: skipped` → `skipped_due_to_dep_failure` terminal carrying `skipped_marker`), rather than the whole batch aborting. Skipped children record `skipped_because_chain`.
- **Why valuable**: Issues run in dependency order with automatic gating; one failure prunes only its dependent subtree, preserving independent work. The state machine is crash-resumable and idempotent. This is the execution engine that makes "drive a whole PLAN through one PR" tractable.
- **Plan-level or per-issue**: **PLAN-LEVEL.** The orchestrator owns task materialization, the DAG, the batch gate, and skip-dependents. Must move to /execute.

## 8. Batch escalation + combined PR body assembly (`escalate` / `pr_finalization`)
- **What**: `pr_finalization` reads `batch_final_view` and assembles a per-child PR-description table (`name`, `outcome`, `reason`, `reason_source`, `skipped_because_chain`). On batch failure, `escalate` summarizes which children failed (name + reason) and which were skipped (name + chain) plus operator next-steps into `failure_reason`, routing to `done_blocked` for batch-view visibility. (`work-on-plan.md:106-129, 208-217, 299-312, 362-371`; SKILL.md:226-238)
- **Why valuable**: The combined PR is self-documenting (every issue's outcome and reason visible in the body), and failures produce an actionable operator summary rather than an opaque stall.
- **Plan-level or per-issue**: **PLAN-LEVEL.** Must move to /execute.

## 9. (Additive, conditional) Coordinated multi-repo lifecycle
- **What**: When the PLAN's `execution_mode: coordinated` (or `--coordinated` / CLAUDE.md headers), the orchestrator additionally drives the coordinated lifecycle's **track** phase: refreshes the coordination PR body (PR-index + merge-order block) each pass via `gh pr edit`, runs `shirabe validate --merge-gate` as the merge-last gate, halts-and-surfaces on any coordination step that cannot complete (R21), and on abandonment closes the coordination PR unmerged (R20). This is strictly ADDITIVE (R3): absent coordination intent, behavior is exactly the single-shared-branch/single-PR flow. (`SKILL.md:43-130`)
- **Why valuable**: Extends multi-issue execution across repos without changing single-repo behavior. Likely out of scope for the initial /execute parity bar but a regression risk to flag.
- **Plan-level or per-issue**: **PLAN-LEVEL** (and cross-repo). Flag as a parity consideration; confirm whether /execute's initial scope includes coordinated mode or defers it.

# Single-issue delegation surface

The orchestrator delegates each issue down to the `work-on.md` per-issue state machine, materialized as a koto child. The delegation surface (the contract /execute would call down to) is:

- **Template**: `work-on.md` (the `default_template` in `materialize_children`).
- **Per-child vars injected by the orchestrator** (via `plan-to-tasks.sh` + jq):
  - `ISSUE_SOURCE`: `github` or `plan_outline` (drives `plan_context_injection` routing)
  - `ISSUE_NUMBER`: GitHub issue number (github source only)
  - `ARTIFACT_PREFIX`: workflow name / context-key + branch prefix for this child
  - `PLAN_DOC`: path to the parent PLAN
  - `ISSUE_TYPE`: `code | docs | task` hint from the outline `**Type**:` field (confirmed/overridden in analysis)
  - `SHARED_BRANCH`: the orchestrator's `impl/<slug>` branch — when set, child skips branch creation (`setup_plan_backed` submits `override`) and skips PR creation (`pr_creation` submits `shared`)
- **Entry contract**: child submits `{mode: plan_backed, issue_source, issue_number}`; or `{mode: skipped}` when koto skip_dependents fires.
- **Per-child path** (plan-backed): `entry → plan_context_injection → (plan_validation for plan_outline) → setup_plan_backed → analysis → implementation → [scrutiny → review → qa_validation for code] → finalization → pr_creation(shared) → done`. Staleness is skipped in plan-backed mode.
- **Outputs the orchestrator reads back**: each child's `summary.md` (for cross-issue context + PR body), terminal state (for `batch_outcome`), and `batch_final_view` fields (`outcome`, `reason`, `reason_source`, `skipped_because_chain`).

So /execute's down-call is: "materialize a `work-on.md` child per PLAN task, inject the six vars above (especially `SHARED_BRANCH`), collect `summary.md` + terminal state + batch_final_view." Everything in capabilities #1, #2, #5, #6, #7, #8 is orchestrator-side and must live in /execute; capabilities #3, #4 are owned by the single-issue surface and are consumed by /execute via this delegation contract.

# Backward-compat surface for existing PLANs

Any existing PLAN doc must keep working under /execute. The compatibility surface is:

- **PLAN frontmatter**: `schema: plan/v1` (mode detection), `execution_mode: single-pr | multi-pr | coordinated`, and the `upstream:` frontmatter chain (consumed by the cascade's `finalize-chain`).
- **PLAN body**: the `## Implementation Issues` table (multi-pr: issue `#N` + Dependencies column) or per-issue outlines with `**Type**:` and `Dependencies:` lines (plan_outline) — both parsed by `plan-to-tasks.sh` into `{name, vars, waits_on}`.
- **Branch/PR convention**: `impl/<slug>` branch where `<slug>` = PLAN filename minus `PLAN-` prefix; one draft PR titled `impl: <slug>`.
- **wip/ artifacts**: `wip/work-on_<slug>_impact.json` (drift gate).
- **koto session**: init as `koto init <plan-slug> --template work-on-plan.md --var PLAN_DOC=<path>`; resume via `koto workflows` + `koto next`.
- **Cascade contract**: `run-cascade.sh --push <PLAN_DOC>` reads `upstream` and `git rm`s the PLAN; existing PLANs rely on this exact finalization. `WORK_ON_ALLOW_UNTRACKED_ACS=1` is an existing env escape hatch (suppresses L06 only) that must be preserved.

/execute must accept the same PLAN inputs and produce the same branch/PR/cascade outcomes, or it is not parity.

# Parity-or-better requirement candidates

1. /execute MUST run an upstream-drift gate once before dispatching issues: fetch+rebase on main, classify `none|informational|intent-changing`, and halt with an actionable rationale on intent-changing (parity with #1; better = per-issue re-check, not just once).
2. /execute MUST carry forward completed-issue summaries into each subsequent issue's context before dispatch (parity with #2).
3. /execute MUST drive issues through one shared branch and one PR, with the orchestrator owning the PR and children skipping their own (parity with #5/#7).
4. /execute MUST sequence issues by their dependency DAG and isolate failures via skip-dependents (failed issue prunes only its dependent subtree), not abort the batch (parity with #7).
5. /execute MUST preserve per-issue review-panel right-sizing: code issues run scrutiny+review+QA with bounded retry-then-escalate; docs/task skip; skips remain auditable (parity with #4).
6. /execute MUST run the atomic finalization cascade with pre/post lifecycle self-verification and DRAFT-before-READY ordering, including DIRTY-merge-state detection (parity with #5/#6).
7. /execute MUST be crash-resumable and idempotent (reuse existing branch/PR, dedup re-submitted tasks) (parity with #7).
8. /execute MUST produce a self-documenting combined PR body (per-issue outcome/reason/skip-chain) and an actionable operator failure summary on batch escalation (parity with #8).
9. /execute MUST accept all existing PLAN inputs unchanged (schema, execution_mode, upstream chain, Implementation Issues table / outlines) and preserve the `WORK_ON_ALLOW_UNTRACKED_ACS` escape hatch (backward-compat).
10. Decide explicitly whether coordinated multi-repo mode (#9) is in /execute's initial parity scope or a documented deferral — losing it silently would be a regression for coordinated PLANs.

# Summary

`/work-on`'s multi-issue PLAN execution delivers eight orchestrator-owned value capabilities — an upstream-drift gate, cross-issue context carry-forward, dependency-DAG sequencing with skip-dependents failure isolation, shared-branch/single-draft-PR CI choreography with DRAFT-before-READY discipline and DIRTY detection, an atomic self-verifying finalization cascade over the whole upstream chain, crash-resumable idempotent setup, and a self-documenting combined PR body — plus two per-issue capabilities (full gated per-issue lifecycle artifacts and right-sized three-panel review) that it consumes through a clean single-issue delegation contract (`work-on.md` child + six injected vars, returning `summary.md` + terminal state + batch_final_view). The plan-level capabilities (#1, #2, #5, #6, #7, #8) must move into /execute; the per-issue capabilities (#3, #4) stay behind the single-issue surface /execute calls down to. Parity-or-better means /execute reproduces all eight plan-level behaviors, accepts every existing PLAN input unchanged (schema/execution_mode/upstream-chain/issue-table), and makes an explicit in-or-deferred call on coordinated multi-repo mode rather than dropping it silently.
