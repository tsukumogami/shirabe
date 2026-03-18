# Phase 3: Deep Investigation

Research agents examine the chosen approach in depth. No design doc writing yet.

## Goal

Build a thorough understanding of how the chosen approach works in practice:
- Read relevant code, trace patterns, identify edge cases
- Map integration points and dependencies
- Surface implementation details that affect architecture
- All findings go to wip/ -- no design doc sections written

This phase is investigation only. Phase 4 synthesizes findings into the design doc.

## Resume Check

If `wip/research/design_<topic>_phase3_*.md` files exist, summarize their findings
and skip to Phase 4.

## Steps

### 3.1 Identify Investigation Areas

Read the selected approach from the wip/ summary and the advocate report
(`wip/research/design_<topic>_phase1_advocate-<approach>.md`).

Identify 2-4 areas that need deeper investigation. Common areas:
- **Codebase integration**: How does this fit with existing code? What needs changing?
- **Edge cases**: What happens in unusual scenarios? Error paths?
- **Dependencies**: What does this approach depend on? Are those dependencies stable?
- **Patterns**: Are there similar patterns in the codebase we can follow or must diverge from?

Tailor areas to the specific problem. Don't investigate what the advocate already covered
thoroughly.

### 3.2 Launch Research Agents

Launch 2-3 agents in parallel using the Agent tool with `run_in_background: true`.

Each agent investigates one area. Assign based on what the design needs most.

**Research agent prompt template:**

```
You are investigating a specific aspect of a technical design.

## Design Context
[Selected approach from wip/ summary]
[Relevant sections from advocate report]

## Your Investigation Area
<area description and specific questions to answer>

## Instructions
1. Read relevant code and docs in the codebase
2. Answer the specific questions for your area
3. Note anything surprising or that changes the approach

## Output
Write your full findings to `wip/research/design_<topic>_phase3_<area>.md`.

Format:
# Phase 3 Research: <Area>

## Questions Investigated
- <question 1>
- <question 2>

## Findings
<detailed findings with code references>

## Implications for Design
<how these findings affect the architecture>

## Surprises
<anything unexpected that the architect should know>

## Summary
<2-3 sentences: key findings>

Return only the Summary section to this conversation.
```

### 3.3 Synthesize Findings

After all agents complete:

1. Read summaries from each agent
2. Check for contradictions or new constraints
3. If findings reveal the selected approach has a deal-breaker:
   - Present the decision using AskUserQuestion following the pattern in
     `references/decision-presentation.md`
   - **Description field:** Present the evidence for the deal-breaker, citing
     specific findings from the investigation agents
   - **Recommendation heuristic:** Recommend returning to Phase 2 unless the
     risk is minor or mitigable with a known workaround
   - **Options:**
     1. "Return to Phase 2 for a different approach (Recommended)" -- when the
        deal-breaker is severe or unmitigable
     2. "Accept risk and continue with current approach" -- with justification
        noting the specific risk being accepted
4. When research surfaces a decision point (a choice between alternatives that
   affects the design), present it to the user via AskUserQuestion using the
   pattern from `references/decision-presentation.md`. Record the decision
   and append it to the Considered Options section in the design doc using the
   existing format (Decision N: context / chosen / rejected).

Update `wip/design_<topic>_summary.md`:

```markdown
## Investigation Findings (Phase 3)
- <area-1>: <key finding>
- <area-2>: <key finding>
- <Contradictions or concerns if any>

## Current Status
**Phase:** 3 - Deep Investigation
**Last Updated:** <date>
```

Commit: `docs(design): investigate <topic> approach details`

### 3.4 Decision Review Checkpoint

Before moving on, review all `wip/research/design_<topic>_phase3_*.md` files and
the conversation history for decisions that were made but not yet recorded in
Considered Options.

For each unrecorded decision:

1. Identify the choice that was made and what alternatives existed
2. Present it to the user via AskUserQuestion for confirmation (see
   `references/decision-presentation.md`)
3. Append to Considered Options using the standard Decision N format

This catches decisions that emerged organically during discussion or that research
agents noted in their findings without the orchestrator acting on them at the time.

## Quality Checklist

Before proceeding:
- [ ] All investigation areas covered by at least one agent
- [ ] Findings written to `wip/research/design_<topic>_phase3_*.md`
- [ ] No unresolved contradictions between agents
- [ ] No deal-breaker risks discovered (or user chose to proceed anyway)
- [ ] All decisions discovered during investigation are recorded in Considered Options
- [ ] wip/ summary updated with investigation findings

## Artifact State

After this phase:
- Research reports in `wip/research/design_<topic>_phase3_*.md`
- wip/ summary updated with findings
- Design doc Considered Options updated with any new decisions (no new sections)

## Next Phase

Proceed to Phase 4: Architecture (`phase-4-architecture.md`)
