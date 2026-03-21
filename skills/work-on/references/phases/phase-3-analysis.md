# Phase 3: Analysis

Research the codebase and create a detailed implementation plan.

## Resume Check

If `wip/issue_<N>_plan.md` exists, skip to Phase 4.

## Agent Execution

**This phase is agent-executed** to save main chat context tokens.

Launch an analysis agent using the Task tool with `subagent_type="general-purpose"`.

### Auto-detect Issue Type

Parse issue labels to determine plan complexity:
- **Full plan** (bug, enhancement, refactor): Detailed analysis with alternatives, risks, testing strategy
- **Simplified plan** (docs, config, chore): Basic approach with files and steps only

### Conditional Skill Loading

To minimize agent context, only pass the language skill for full-plan issues (bug/enhancement/refactor). Check the project extension file for the language skill path. Skip for simplified-plan issues (docs/config/chore).

### Agent Inputs

Provide the agent with:
- Issue details (JSON from `gh issue view <N>`)
- Baseline file path: `wip/issue_<N>_baseline.md`
- Issue type classification: "full-plan" or "simplified-plan"
- Agent instructions: `../agent-instructions/phase-3-analysis.md`
- Conditional: language skill path from extension file (full-plan only, if defined)

### Agent Output

The agent will:
- Write `wip/issue_<N>_plan.md` (Write tool) using the appropriate template
- Return a brief summary (2-3 sentences): file count, approach chosen, step count

### Commit Plan

After agent completes, commit using format: `docs: create implementation plan`

## Next Phase

Proceed to Phase 4: Implementation (`phase-4-implementation.md`)
