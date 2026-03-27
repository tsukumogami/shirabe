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
- Baseline: `koto context get <WF> baseline.md`
- Design context (if exists): `koto context get <WF> context.md`
- Issue type: "full-plan" or "simplified-plan"
- Agent instructions: `../agent-instructions/phase-3-analysis.md`
- Language skill path (full-plan only, if defined in extension)

The agent writes the plan locally and stores it in koto context:

```bash
koto context add <WF> plan.md --from-file <plan-file>
```

Commit: `docs: create implementation plan`

## Evidence

- `plan_outcome: plan_ready` — plan complete
- `plan_outcome: scope_changed_retry` — scope changed, revising (up to 3 times)
- `plan_outcome: scope_changed_escalate` — too many scope changes
- `plan_outcome: blocked_missing_context` — cannot proceed
