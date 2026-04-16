---
name: work-on-plan
version: "1.0"
description: >
  Plan orchestrator template. Creates a shared branch and draft PR, spawns
  per-issue work-on.md children, awaits batch completion, finalizes the PR
  description, marks it ready, and monitors CI to green.
initial_state: orchestrator_setup

variables:
  PLAN_DOC:
    description: Path to the PLAN.md document driving this orchestration run
    required: true

states:
  orchestrator_setup:
    accepts:
      status:
        type: enum
        values: [completed, blocked]
        required: true
      detail:
        type: string
        description: Failure reason if blocked
    transitions:
      - target: spawn_and_await
        when:
          status: completed
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "orchestrator_setup blocked: ${evidence.detail}"

  spawn_and_await:
    gates:
      batch_done:
        type: children-complete
    accepts:
      tasks:
        type: tasks
        required: true
      batch_outcome:
        type: enum
        values: [all_success, needs_attention]
        required: false
    materialize_children:
      from_field: tasks
      failure_policy: skip_dependents
      default_template: work-on.md
    transitions:
      # Gate guards ensure children are complete; evidence routes success vs attention.
      - target: pr_finalization
        when:
          batch_outcome: all_success
          gates.batch_done.all_complete: true
      - target: escalate
        when:
          batch_outcome: needs_attention
          gates.batch_done.all_complete: true
      - target: escalate

  pr_finalization:
    accepts:
      finalization_status:
        type: enum
        values: [updated, update_failed]
        required: true
      pr_url:
        type: string
        description: URL of the pull request
    transitions:
      - target: ci_monitor
        when:
          finalization_status: updated
      - target: done_blocked
        when:
          finalization_status: update_failed
        context_assignments:
          failure_reason: "pr_finalization failed: could not update or ready the PR"

  ci_monitor:
    gates:
      ci_passing:
        type: command
        command: "gh pr checks $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number // empty') --json state --jq '[.[] | select(.state != \"SUCCESS\")] | length == 0' | grep -q true"
    accepts:
      ci_outcome:
        type: enum
        values: [passing, failing_fixed, failing_unresolvable]
        required: true
      rationale:
        type: string
        description: What was fixed or why CI failures are unresolvable
    transitions:
      - target: plan_completion
        when:
          ci_outcome: passing
          gates.ci_passing.exit_code: 0
      # failing_fixed: agent pushed a follow-up commit to fix CI; gate may be stale.
      # Agent's direct observation is the authoritative signal.
      - target: plan_completion
        when:
          ci_outcome: failing_fixed
      - target: done_blocked
        when:
          ci_outcome: failing_unresolvable
        context_assignments:
          failure_reason: "ci_monitor: unresolvable CI failures: ${evidence.rationale}"
      - target: plan_completion

  plan_completion:
    accepts:
      cascade_status:
        type: enum
        values: [completed, partial, skipped]
        required: true
      cascade_detail:
        type: string
        description: Summary of what the cascade did or why steps were skipped
    transitions:
      - target: done

  escalate:
    accepts:
      failure_reason:
        type: string
        required: true
        description: Summary of which children failed and why, for the batch view
    transitions:
      - target: done_blocked
        context_assignments:
          failure_reason: ${evidence.failure_reason}

  done:
    terminal: true

  done_blocked:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
        description: Reason for blocking failure (populated via context_assignments)
---

## orchestrator_setup

Create the shared branch and draft PR. This runs once before children are spawned.

```bash
PLAN_SLUG=$(basename {{PLAN_DOC}} .md | sed 's/^PLAN-//')
git checkout impl/$PLAN_SLUG 2>/dev/null || git checkout -b impl/$PLAN_SLUG
git push -u origin impl/$PLAN_SLUG 2>/dev/null || true
gh pr list --head impl/$PLAN_SLUG --json number --jq '.[0].number' | grep -q . || \
  gh pr create --draft --title "impl: $PLAN_SLUG" --body "Implements $(basename {{PLAN_DOC}})."
```

The script is idempotent — if the branch or PR already exists (e.g., after a crash and re-run), it reuses them.

Submit `status: completed` after branch and draft PR exist, or `status: blocked` with `detail` if either step fails.

## spawn_and_await

Spawn and coordinate per-issue work-on children from the PLAN document.

**Tick 1 — spawn**: run `plan-to-tasks.sh`, inject the shared branch into each task's vars, then submit `tasks`:

```bash
PLAN_SLUG=$(basename {{PLAN_DOC}} .md | sed 's/^PLAN-//')
TMP=$(mktemp)
TASKS=$(${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}})
TASKS_WITH_BRANCH=$(echo "$TASKS" | jq --arg b "impl/$PLAN_SLUG" '[.[] | .vars.SHARED_BRANCH = $b]')
echo "{\"tasks\": $TASKS_WITH_BRANCH}" > "$TMP"
koto next work-on-plan --with-data @"$TMP"
rm -f "$TMP"
```

koto materializes one child per task using `work-on.md` with `failure_policy: skip_dependents`. Children receive `SHARED_BRANCH` and commit directly to it without creating their own branches.

**Tick 2 — complete**: once all children reach terminal states, the `batch_done` gate unblocks. Re-submit the same `tasks` array alongside `batch_outcome` — koto deduplicates children that already exist:

```bash
PLAN_SLUG=$(basename {{PLAN_DOC}} .md | sed 's/^PLAN-//')
TMP=$(mktemp)
TASKS=$(${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}})
TASKS_WITH_BRANCH=$(echo "$TASKS" | jq --arg b "impl/$PLAN_SLUG" '[.[] | .vars.SHARED_BRANCH = $b]')
echo "{\"tasks\": $TASKS_WITH_BRANCH, \"batch_outcome\": \"all_success\"}" > "$TMP"
koto next work-on-plan --with-data @"$TMP"
rm -f "$TMP"
```

Check progress at any time with `koto status work-on-plan`. Set `batch_outcome` to:
- `all_success` if all children reached a non-failure terminal state
- `needs_attention` if any children reached `done_blocked` or were skipped

## pr_finalization

Assemble the pull request description from the batch results, update the PR, and mark it ready for review.

1. Read `koto context get work-on-plan batch_final_view` to get per-child outcome data.
2. Assemble a PR description. For each child include:
   - `name`: child workflow name
   - `outcome`: `success`, `failure`, or `skipped`
   - `reason`: failure or skip reason (if applicable)
   - `reason_source`: where the reason came from
   - `skipped_because_chain`: dependency chain that caused the skip (if skipped)
3. Update the PR description: `gh pr edit <pr-number> --body "<assembled description>"`
4. Mark ready for review: `gh pr ready <pr-number>`

Submit `finalization_status: updated` with `pr_url` after the PR is updated and marked ready, or `finalization_status: update_failed` if either step fails.

## ci_monitor

Monitor CI on the shared branch until all checks pass.

Read `references/phases/phase-6-pr.md` for CI monitoring guidance.

If the gate fails (CI not yet green), fix what you can and submit `ci_outcome: failing_fixed`.
If failures are unresolvable, submit `ci_outcome: failing_unresolvable` with rationale.

## plan_completion

Run the completion cascade using `run-cascade.sh` (see `skills/work-on/scripts/run-cascade.sh`).
The script walks the `upstream` frontmatter chain from the PLAN doc, transitions each artifact,
and emits a JSON result that drives the evidence fields below.

```bash
RESULT=$(${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/run-cascade.sh --push {{PLAN_DOC}})
CASCADE_STATUS=$(echo "$RESULT" | jq -r '.cascade_status')
```

Submit `cascade_status` from the JSON output and a brief `cascade_detail` summarising what ran.

- `cascade_status: completed` — all applicable steps ran successfully
- `cascade_status: partial` — some steps ran, some were skipped due to missing upstream links or files
- `cascade_status: skipped` — PLAN doc had no `upstream` field; no upstream documents to transition

All three values route to `done`.

## escalate

One or more children reached `done_blocked` or were skipped due to dependency failure. Inspect `batch_final_view` to understand which children failed and why.

Read `koto context get work-on-plan batch_final_view` to get the full per-child data. Summarize:
- Which children failed (name + `reason` field)
- Which children were skipped (name + `skipped_because_chain`)
- What the user should do to resolve the blockers

Submit `failure_reason` with this summary. The workflow routes to `done_blocked` and the `failure_reason` is written to context for the batch view.

## done

Plan orchestration is complete. All per-issue children succeeded, the PR description has been updated, and CI is green.

## done_blocked

Plan orchestration reached a blocking condition. One of: orchestrator setup failed, some children failed and could not be resolved, the PR could not be finalized, or CI failures are unresolvable.

The `failure_reason` context key contains the details. Use `koto context get work-on-plan failure_reason` to read it.
