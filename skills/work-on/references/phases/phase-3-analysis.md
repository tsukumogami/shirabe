# Analysis

Research the codebase and create an implementation plan.

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
3. Write the plan to a local file under the per-session tmp directory
   (see phase-1 for the path convention).
4. Store it in koto context: `koto context add <WF> plan.md --from-file <path>`.
5. Proceed to phase 4 with `plan_outcome: plan_ready` and `issue_type: docs|task|code`
   as appropriate.

Delegate for simplified plans only when the main agent's context is genuinely
too limited to write the plan accurately (e.g., resuming a session with no
prior context on the issue).

Commit: `docs: create implementation plan`

## Already-Complete Detection

Before writing a plan, check whether the issue goal is already satisfied. Read the
acceptance criteria from the issue (or plan outline) and verify each one against
current code. If every criterion is already met, submit `plan_outcome: already_complete`
— no plan needed, no commits required. Routes to `done_already_complete`.

This check is especially important for plan-backed children where an orchestrator may
schedule issues before earlier issues have run. An issue whose AC is satisfied by a
sibling's commit should exit via `already_complete` rather than writing a redundant plan.

## Issue Type Classification

After reading the issue (or plan outline), confirm the issue type. The PLAN outline may
supply an `ISSUE_TYPE` hint; treat it as a starting point, not a binding constraint.

Classify as:
- `code` — changes to executable source, tests, or CI configs; runs through full scrutiny/review/QA
- `docs` — changes to markdown, design docs, skills, or spec files; skips code review panels
- `task` — operational work (run a migration, execute a script) that produces no review artifact

Set `issue_type` in evidence. When the PLAN hint and your assessment agree, use it as-is.
When they differ, use your classification and note the override in `decisions`.

## Evidence

- `plan_outcome: plan_ready` — plan complete, submit with `issue_type`
- `plan_outcome: already_complete` — all acceptance criteria already satisfied; routes to `done_already_complete`
- `plan_outcome: scope_changed_retry` — scope changed, revising (up to 3 times)
- `plan_outcome: scope_changed_escalate` — too many scope changes
- `plan_outcome: blocked_missing_context` — cannot proceed
