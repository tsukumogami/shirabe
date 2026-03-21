# Phase 2: Introspection

Evaluate whether the issue specification is still valid before investing in analysis and implementation.

## Resume Check

If `wip/issue_<N>_introspection.md` exists, read it and proceed based on its recommendation.

## Staleness Detection

Run the deterministic staleness check. If the issue-staleness script exists, use it:

```bash
STALENESS_SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/issue-staleness/scripts/check-staleness.sh"
if [ -f "$STALENESS_SCRIPT" ]; then
  "$STALENESS_SCRIPT" <N>
else
  # Fallback: always recommend introspection when staleness script is unavailable
  echo '{"introspection_recommended": true, "reason": "staleness script not available"}'
fi
```

### If `introspection_recommended: false`

Skip to Phase 3: Analysis. The issue is fresh enough that deep introspection adds no value.

### If `introspection_recommended: true`

Continue with agent-based introspection below.

## Agent Execution

**This phase is agent-executed** to save main chat context tokens.

Launch an introspection agent using the Task tool with `subagent_type="general-purpose"`.

### Agent Inputs

Provide the agent with:
- Issue number and staleness signals (JSON from the script output)
- The `issue-introspection` skill path: `${CLAUDE_PLUGIN_ROOT}/skills/issue-introspection/SKILL.md`
- Output file path: `wip/issue_<N>_introspection.md`

### Agent Prompt Template

```
You are performing issue introspection for issue #<N>.

Staleness signals detected:
<paste JSON from staleness script>

Follow the process in the issue-introspection skill:
${CLAUDE_PLUGIN_ROOT}/skills/issue-introspection/SKILL.md

Write your findings to: wip/issue_<N>_introspection.md

Return a brief summary (2-3 sentences):
- Your recommendation: Proceed / Clarify / Amend / Re-plan
- Key finding that led to this recommendation
- Any blocking concerns
```

### Agent Output

The agent will:
- Read design docs and sibling issues as needed
- Assess spec validity against current codebase state
- Write `wip/issue_<N>_introspection.md` with findings
- Return summary with recommendation

## Handle Recommendation

Based on agent summary:

| Recommendation | Action |
|----------------|--------|
| **Proceed** | Continue to Phase 3: Analysis |
| **Clarify** | Use AskUserQuestion to resolve ambiguity, then proceed |
| **Amend** | Present suggested amendments to user, update issue if approved, then proceed |
| **Re-plan** | Stop workflow, inform user the issue needs significant revision |

For **Clarify** and **Amend**: After user interaction, update `wip/issue_<N>_introspection.md` with resolution, then proceed.

For **Re-plan**: Do not proceed to Phase 3. The issue needs to be revised before implementation can begin.

## Commit Introspection

After completing introspection (or skipping), if `wip/issue_<N>_introspection.md` was created:

Commit using format: `docs: complete issue introspection`

## Success Criteria

- [ ] Staleness check completed
- [ ] If recommended: agent introspection completed
- [ ] Recommendation acted upon
- [ ] Any blockers resolved or escalated

## Next Phase

Proceed to Phase 3: Analysis (`phase-3-analysis.md`)
