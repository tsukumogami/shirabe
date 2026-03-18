# Phase 2: Discover

Parallel specialist agents investigate research leads from Phase 1.

## Goal

Deepen understanding of the problem space by sending specialist agents to investigate
the research leads identified during scoping. Return with findings that inform the PRD
draft in Phase 3.

## Resume Check

If `wip/research/prd_<topic>_phase2_*.md` files exist, summarize their findings and skip to
Phase 3.

## Approach: Parallel Specialist Agents with Role Selection

Launch 2-3 agents to investigate research leads from `wip/prd_<topic>_scope.md`. Select roles
based on the feature type being specified.

### 2.1 Select Roles

Read `wip/prd_<topic>_scope.md` and classify the feature type, then select 2-3 roles:

| Feature Type | Recommended Roles |
|-------------|------------------|
| User-facing feature | User researcher, Codebase analyst, UX perspective |
| Technical/infrastructure | Codebase analyst, Ops perspective, Architecture perspective |
| Process/workflow | User researcher, Current-state analyst, Maintainer perspective |

Don't force exactly 3 roles. Pick 2 if the scope is narrow, 3 if it's broad. The roles
should cover the research leads -- if a lead doesn't map to a selected role, either add
a role or fold the lead into an existing role's scope.

### Role Descriptions

**User researcher**: Investigates who is affected and how. Looks at existing user-facing
behavior, identifies edge cases and failure modes from the user's perspective, considers
different user types and their needs.

**Codebase analyst**: Investigates the current implementation. Reads relevant code, maps
dependencies, identifies constraints and integration points, finds patterns that the PRD
should account for.

**UX perspective**: Considers the user experience implications. How will users interact
with this feature? What mental models do they have? What errors or confusion might arise?

**Ops perspective**: Considers operational implications. Performance, monitoring, failure
modes, deployment, backwards compatibility.

**Architecture perspective**: Considers structural implications. How does this fit into
the existing system? What patterns apply? What constraints does the architecture impose?

**Current-state analyst**: Documents how things work today. Maps the current workflow,
identifies pain points, measures what exists vs. what's proposed.

**Maintainer perspective**: Considers long-term maintenance. What's the learning curve?
How will this interact with future changes? What documentation is needed?

### 2.2 Launch Agents

Launch agents in parallel using the Agent tool with `run_in_background: true`.

Each agent receives:
- The scope document (`wip/prd_<topic>_scope.md`)
- Their assigned research leads
- Their role description
- Output instructions

**Agent prompt template:**

```
You are investigating requirements for a new feature from the perspective of a [ROLE].

## Context
[Contents of wip/prd_<topic>_scope.md]

## Your Research Leads
[Specific leads assigned to this role]

## Instructions
1. Investigate your assigned leads by reading relevant code, docs, and existing patterns
2. For each lead, capture: what you found, implications for requirements, open questions
3. Note anything surprising or that contradicts the initial scope assumptions

## Output
Write your full findings to `wip/research/prd_<topic>_phase2_<role>.md` using the Write tool.

Format:
# Phase 2 Research: <Role>

## Lead 1: <topic>
### Findings
<what you discovered>
### Implications for Requirements
<what the PRD should account for>
### Open Questions
<things that need human input>

## Lead 2: <topic>
[same structure]

## Summary
<2-3 sentences: key findings and their impact on requirements>

Return only the summary to this conversation.
```

### 2.3 Depth Calibration

Not all leads need deep investigation. Calibrate agent effort based on the lead:

- **Quick leads** (the answer is in 1-2 files): Agent reads, summarizes, returns. No
  persisted file needed -- return the summary directly.
- **Deep leads** (requires reading multiple files, tracing patterns, analyzing behavior):
  Agent writes full findings to `wip/research/prd_<topic>_phase2_<role>.md` and returns a summary.

Tell each agent which of their leads are quick vs. deep in the prompt.

### 2.4 Synthesize Findings

After all agents complete, synthesize their findings:

1. Read the summary from each agent
2. Identify themes across agents (multiple agents noticing the same constraint = high confidence)
3. Identify contradictions (agents disagreeing = needs human input)
4. List new questions or scope adjustments surfaced by the research

When research reveals competing approaches or trade-offs where the evidence
points toward one option, record the decision. Note what was decided, what
alternatives existed, and what evidence drove the choice. These decisions
feed into the PRD's Decisions and Trade-offs section during Phase 3 drafting.

Present the synthesis to the user:
- Key findings (what we learned)
- Scope adjustments (if research suggests the scope should change)
- Decisions made (choices driven by research evidence, with reasoning)
- New questions (things we need the user to decide)

### 2.5 Loop Back Decision

After presenting findings, present the loop decision using AskUserQuestion
following the pattern in `references/decision-presentation.md`.

**Recommendation heuristic:** If findings are sufficient to draft requirements
and no major gaps remain, recommend proceeding. If new leads emerged that need
investigation, recommend looping. If unsure, recommend proceeding -- Phase 3's
review will catch remaining gaps.

**Options (order by recommendation heuristic):**
1. "Proceed to Phase 3 (Recommended)" -- when coverage is sufficient and scope is clear
2. "Investigate more leads" -- new leads emerged that need another round of agents
3. "Restart scoping (Phase 1)" -- research revealed the scope was fundamentally wrong

**Description field:** Ground the recommendation in the synthesis -- cite which
findings support sufficient coverage or which gaps suggest more investigation.

If the user picks "Investigate more leads," launch another round of agents for
the new leads only.

If the user picks "Restart scoping," delete `wip/prd_<topic>_scope.md` before
returning to Phase 1 so the resume check doesn't skip re-scoping.

## Quality Checklist

Before proceeding:
- [ ] All research leads from Phase 1 have been investigated
- [ ] Findings synthesized and presented to user
- [ ] User agrees scope is clear enough to draft requirements
- [ ] No unresolved contradictions between agents
- [ ] Deep findings persisted to `wip/research/prd_<topic>_phase2_*.md`

## Artifact State

After this phase:
- Scope document still at `wip/prd_<topic>_scope.md`
- Research findings at `wip/research/prd_<topic>_phase2_*.md` (for deep leads)
- No PRD draft yet

## Next Phase

Proceed to Phase 3: Draft (`phase-3-draft.md`)
