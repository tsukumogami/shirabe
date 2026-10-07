# Analysis

Research the codebase and create an implementation plan.

## Earlier Children's Summaries

When `/execute` materialized this run as a child, read what the children
before it found, decided and changed, before planning. Every child keeps its
session, so the `summary.md` each one wrote at finalization is still readable
through koto. There is no context file to build and none to look for.

```bash
PARENT=$(koto session list | jq -r --arg wf "<WF>" '.[] | select(.id == $wf) | .parent_workflow // empty')
koto workflows --children "$PARENT"      # names this run's siblings
koto status <child>                      # is_terminal and current_state
koto context get <child> summary.md      # once per sibling that reached done
```

Skip the step when `PARENT` is empty: a root run has no siblings. The children
list includes this run; skip it. Read each sibling that reached `done` once,
and never poll or re-read a summary in a loop, including when a retry brings
the run back to analysis. The read count is deliberately small because each
`koto context get` is logged and uploaded as an event. Carry what bears on this
issue into the plan.

## Plan Complexity

Parse issue labels:
- **Full plan** (bug, enhancement, refactor): alternatives, risks, testing strategy
- **Simplified plan** (docs, config, chore, validation:simple): files and steps only

For full plans, load the project's language skill from the extension file.

## Agent Delegation

Delegation is **opt-out for simplified plans, required for full plans**.

### Full plans: delegate to a subagent

Launch an analysis agent (Task tool, `subagent_type="general-purpose"`) with:
- Issue details from `gh issue view <N>`
- Workflow name (`<WF>`) so the agent can read from and write to koto context
- Issue type: `full-plan`
- Agent instructions: `../agent-instructions/phase-3-analysis.md`
- Language skill path (if defined in extension)

The agent reads baseline and context from koto, writes the plan to koto context,
and returns a brief summary. The main agent does not need to read these artifacts
— the sub-agent handles them directly.

### Simplified plans: write the plan inline

For simplified-plan labels the main agent has already read the issue, baseline,
and any design context while walking phase 0-2; delegating to a fresh
general-purpose subagent only to regurgitate that context is pure overhead. The
simplified-plan template in `../agent-instructions/phase-3-analysis.md` is short
enough that the main agent writes it directly:

1. Read the simplified-plan template in `../agent-instructions/phase-3-analysis.md`.
2. Fill it in from the issue + baseline already in context.
3. Store it in koto context under `plan.md`, by stdin pipe or a `mktemp` file
   deleted after ingestion (see `../koto-context-conventions.md`).
4. Proceed to phase 4 with `plan_outcome: plan_ready`.

Delegate for simplified plans only when the main agent's context is genuinely
too limited to write the plan accurately (e.g., resuming a session with no
prior context on the issue).

## Retry Loop

`scope_changed_retry` re-enters this phase to write a *replacement* plan, and the `plan_artifact` gate holds the `plan.md` being replaced. Clear it before submitting:

```bash
OUTCOME_FIELD=plan_outcome
for KEY in plan.md scrutiny_results.json review_results.json qa_results.json light_results.json summary.md; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  REMOVE_STATUS=$?
  if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY was not confirmed cleared from context."
    echo "The stale artifact may still be in place, and its gate may accept it."
    echo "Do NOT submit plan_outcome: plan_ready on the next pass."
    echo "To stop the run, submit plan_outcome: scope_changed_escalate."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"scope_changed_retry\"}" --no-cleanup
```

The gate is `context-exists`: it asks whether `plan.md` is present, not which round wrote it. Left in place, the plan this phase is being re-entered to replace is the one that satisfies the gate on the way out. Why the block checks both signals is in `phase-4a-scrutiny.md`.

`implementation` reaches this phase by the same gate on a different edge (`scope_expanded_retry`) and clears the same key; see `phase-4-implementation.md`.
