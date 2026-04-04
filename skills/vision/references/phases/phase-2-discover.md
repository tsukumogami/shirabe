# Phase 2: Discover

Parallel specialist agents investigate research leads from Phase 1.

## Goal

Deepen understanding of the project's strategic positioning by sending specialist agents
to investigate the research leads identified during scoping. Return with findings that
inform the VISION draft in Phase 3.

## Resume Check

If `wip/research/vision_<topic>_phase2_*.md` files exist, summarize their findings and
skip to Phase 3.

## Approach: Parallel Specialist Agents with Role Selection

Launch 2-4 agents to investigate research leads from `wip/vision_<topic>_scope.md`. Select
roles based on the thesis and scope.

### 2.1 Select Roles

Read `wip/vision_<topic>_scope.md` and select 2-4 roles from the pool below. Match roles
to research leads -- every lead should map to at least one role.

### Role Descriptions

**Audience validator**: Investigates whether the target audience exists and is underserved.
Looks for evidence of the audience's current situation: what tools they use, what
workarounds they've built, what friction they experience. Checks whether the audience
is large enough and reachable enough to matter.

**Value proposition analyst**: Investigates whether the category of value is distinct.
Looks at what exists in the space, whether the proposed value proposition overlaps with
existing solutions, and whether the differentiation is real or aspirational. Examines
the landscape without recommending features.

**Org fit researcher**: Investigates how this project relates to sibling projects in
the same org or ecosystem. Maps shared infrastructure, overlapping audiences, and
capability gaps. Asks: what would be lost if this were standalone? What does the org
context add?

**Competitive landscape analyst** (private repos only): Investigates market alternatives
and positioning. Names specific competitors, maps their strengths and gaps, identifies
where the proposed project's thesis creates differentiation. Skip this role entirely in
public repos.

**Success criteria researcher**: Investigates whether the proposed outcomes are
observable and measurable. Looks for analogues -- similar projects that track similar
metrics. Identifies what signals would validate or invalidate the thesis. Pushes back
on vanity metrics or unmeasurable claims.

### 2.2 Launch Agents

Launch agents in parallel using the Agent tool with `run_in_background: true`.

Each agent receives:
- The scope document (`wip/vision_<topic>_scope.md`)
- Their assigned research leads
- Their role description
- Output instructions

**Agent prompt template:**

```
You are investigating strategic positioning for a project from the perspective of a [ROLE].

## Context
[Contents of wip/vision_<topic>_scope.md]

## Your Research Leads
[Specific leads assigned to this role]

## Instructions
1. Investigate your assigned leads by reading relevant code, docs, existing artifacts,
   and any available evidence
2. For each lead, capture: what you found, implications for the VISION, open questions
3. Note anything surprising or that contradicts the initial thesis direction

## Output
Write your full findings to `wip/research/vision_<topic>_phase2_<role>.md` using the Write tool.

Format:
# Phase 2 Research: <Role>

## Lead 1: <topic>
### Findings
<what you discovered>
### Implications for VISION
<what the VISION should account for>
### Open Questions
<things that need human input>

## Lead 2: <topic>
[same structure]

## Summary
<2-3 sentences: key findings and their impact on the VISION>

Return only the summary to this conversation.
```

### 2.3 Depth Calibration

Not all leads need deep investigation. Calibrate agent effort based on the lead:

- **Quick leads** (the answer is in 1-2 files or is common knowledge): Agent reads,
  summarizes, returns. No persisted file needed -- return the summary directly.
- **Deep leads** (requires reading multiple files, tracing patterns, analyzing the
  landscape): Agent writes full findings to `wip/research/vision_<topic>_phase2_<role>.md`
  and returns a summary.

Tell each agent which of their leads are quick vs. deep in the prompt.

### 2.4 Synthesize Findings

After all agents complete, synthesize their findings:

1. Read the summary from each agent
2. Identify themes across agents (multiple agents noticing the same signal = high
   confidence)
3. Identify contradictions (agents disagreeing = needs human input)
4. List new questions or thesis adjustments surfaced by the research

When research reveals competing thesis framings or strategic trade-offs where evidence
points toward one direction, record the decision. Note what was decided, what
alternatives existed, and what evidence drove the choice.

Present the synthesis to the user:
- Key findings (what we learned)
- Thesis adjustments (if research suggests the thesis should shift)
- Decisions made (choices driven by research evidence, with reasoning)
- New questions (things we need the user to decide)

### 2.5 Loop Back Decision

After presenting findings, present the loop decision using AskUserQuestion following
the pattern in `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`.

**Recommendation heuristic:** If findings give enough evidence to draft the VISION
and no major thesis gaps remain, recommend proceeding. If new leads emerged that need
investigation, recommend looping. If unsure, recommend proceeding -- Phase 3's review
will catch remaining gaps.

**Options (order by recommendation heuristic):**
1. "Proceed to Phase 3 (Recommended)" -- when thesis is supported and coverage is
   sufficient
2. "Investigate more leads" -- new leads emerged that need another round of agents
3. "Restart scoping (Phase 1)" -- research revealed the thesis direction was
   fundamentally wrong

**Description field:** Ground the recommendation in the synthesis -- cite which
findings support the thesis or which gaps suggest more investigation.

If the user picks "Investigate more leads," launch another round of agents for the
new leads only.

If the user picks "Restart scoping," delete `wip/vision_<topic>_scope.md` before
returning to Phase 1 so the resume check doesn't skip re-scoping.

## Quality Checklist

Before proceeding:
- [ ] All research leads from Phase 1 have been investigated
- [ ] Findings synthesized and presented to user
- [ ] User agrees thesis direction is supported enough to draft

## Artifact State

After this phase:
- Scope document still at `wip/vision_<topic>_scope.md`
- Research findings at `wip/research/vision_<topic>_phase2_*.md` (for deep leads)
- No VISION draft yet

## Next Phase

Proceed to Phase 3: Draft (`phase-3-draft.md`)
