---
name: work-on-plan
version: "1.0"
description: >
  Plan orchestrator template. Spawns and coordinates per-issue work-on.md children
  from a PLAN document via koto v0.8.0 batch execution. Takes a tasks evidence field
  (populated by plan-to-tasks.sh), materializes children, and coordinates final PR
  description assembly.
initial_state: spawn_and_await

variables:
  PLAN_DOC:
    description: Path to the PLAN.md document driving this orchestration run
    required: true

states:
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
        required: true
    materialize_children:
      from_field: tasks
      failure_policy: skip_dependents
      default_template: work-on.md
    transitions:
      # Gate guards ensure children are complete; evidence routes success vs attention.
      # Note: koto v0.8.0 children-complete gate exposes all_complete, not all_success/needs_attention.
      # W4 warning is expected — routing is evidence-driven per the design intent.
      - target: pr_coordination
        when:
          batch_outcome: all_success
          gates.batch_done.all_complete: true
      - target: escalate
        when:
          batch_outcome: needs_attention
          gates.batch_done.all_complete: true
      - target: escalate

  pr_coordination:
    accepts:
      pr_status:
        type: enum
        values: [created, creation_failed]
        required: true
      pr_url:
        type: string
        description: URL of the created or updated pull request
    transitions:
      - target: done
        when:
          pr_status: created
      - target: done_blocked
        when:
          pr_status: creation_failed
        context_assignments:
          failure_reason: "PR coordination failed after batch completion"

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

## spawn_and_await

Spawn and coordinate per-issue work-on children from the PLAN document.

**First tick**: run `plan-to-tasks.sh` to populate the tasks evidence, then submit it to koto:

```bash
# plan-to-tasks.sh is owned by /plan skill; outputs {name, vars, waits_on} JSON array
TMP=$(mktemp)
${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}} > "$TMP"
koto next work-on-plan --with-data @"$TMP"
rm -f "$TMP"
```

Submit `tasks` as the output of `plan-to-tasks.sh` — a JSON array of `{name, vars, waits_on}` objects. koto materializes children from this array, one per task, using `work-on.md` as the default template with `failure_policy: skip_dependents`.

Once children are dispatched, monitor their progress via `koto workflows`. When all children have reached terminal states, inspect their outcomes via `koto status` and `koto context get` to determine the batch outcome, then submit `batch_outcome`:
- `all_success` if `gates.batch_done.all_complete` is true and all children reached a non-failure terminal state
- `needs_attention` if `gates.batch_done.all_complete` is true but some children reached `done_blocked` or were skipped

## pr_coordination

Assemble the pull request description from the batch results. Read `koto context get work-on-plan batch_final_view` to get per-child outcome data.

For each child in `batch_final_view`, include:
- `name`: child workflow name
- `outcome`: `success`, `failure`, or `skipped`
- `reason`: failure or skip reason (if applicable)
- `reason_source`: where the reason came from
- `skipped_because_chain`: dependency chain that caused the skip (if skipped)

Create or update the PR with the assembled description. Submit `pr_status: created` with `pr_url`, or `pr_status: creation_failed` if the PR cannot be created.

## escalate

One or more children reached `done_blocked` or were skipped due to dependency failure. Inspect `batch_final_view` to understand which children failed and why.

Read `koto context get work-on-plan batch_final_view` to get the full per-child data. Summarize:
- Which children failed (name + `reason` field)
- Which children were skipped (name + `skipped_because_chain`)
- What the user should do to resolve the blockers

Submit `failure_reason` with this summary. The workflow routes to `done_blocked` and the `failure_reason` is written to context for the batch view.

## done

Plan orchestration is complete. All per-issue children succeeded and the PR has been created or updated.

## done_blocked

Plan orchestration reached a blocking condition. Either some children failed and could not be resolved, or the PR could not be created after successful batch completion.

The `failure_reason` context key contains the details. Use `koto context get work-on-plan failure_reason` to read it.
