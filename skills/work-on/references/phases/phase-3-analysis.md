# Analysis

Research the codebase and create an implementation plan.

## Plan Complexity

Parse issue labels:
- **Full plan** (bug, enhancement, refactor): alternatives, risks, testing strategy
- **Simplified plan** (docs, config, chore): files and steps only

For full plans, load the project's language skill from the extension file.

## Agent Delegation

Launch an analysis agent (Task tool, `subagent_type="general-purpose"`) with:
- Issue details from `gh issue view <N>`
- Workflow name (`<WF>`) so the agent can read from and write to koto context
- Issue type: "full-plan" or "simplified-plan"
- Agent instructions: `../agent-instructions/phase-3-analysis.md`
- Language skill path (full-plan only, if defined in extension)

The agent reads baseline and context from koto, writes the plan to koto context,
and returns a brief summary. The main agent does not need to read these artifacts
— the sub-agent handles them directly.

Commit: `docs: create implementation plan`

## Evidence

- `plan_outcome: plan_ready` — plan complete
- `plan_outcome: scope_changed_retry` — scope changed, revising (up to 3 times)
- `plan_outcome: scope_changed_escalate` — too many scope changes
- `plan_outcome: blocked_missing_context` — cannot proceed
