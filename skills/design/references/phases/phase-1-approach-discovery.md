# Phase 1: Approach Discovery (EXPAND)

Fan out advocate agents to investigate viable approaches with equal depth.

## Goal

Produce honest, equal-depth investigations of multiple approaches:
- Each approach gets a dedicated advocate agent
- Advocates argue FOR their approach while acknowledging weaknesses
- No approach is "chosen" -- that happens in Phase 2
- Cap at 5 advocates maximum

## Resume Check

If `wip/research/design_<topic>_phase1_advocate-*.md` files exist, skip to Phase 2.

## Steps

### 1.1 Generate Candidate Approaches

Read the design doc's Context and Problem Statement and Decision Drivers sections.
Read the wip/ summary for additional context.

Brainstorm candidate approaches. Cast a wide net -- this is divergent thinking.
Consider:
- Different architectural patterns that could solve the problem
- Build vs buy/adopt decisions
- Different levels of ambition (minimal vs comprehensive)
- Unconventional approaches the user might not have considered

### 1.2 Quick-Filter

Remove obviously infeasible candidates -- those that violate hard constraints from
Decision Drivers or are impossible given the codebase. This is a lightweight check,
not deep analysis. When in doubt, keep the candidate.

### 1.3 Cluster and Cap

If more than 5 candidates remain after filtering:
1. Group similar approaches (e.g., "use Redis" and "use Memcached" are both "external cache")
2. Pick 1 representative per cluster (the strongest variant)
3. Cap at 5 advocates maximum

If 2-5 candidates remain, proceed directly.

Present the candidate list to the user before launching advocates:
- Name each approach (short, descriptive)
- 1-line description

Then proceed directly to launching advocates. The user can interject at any point to
course-correct if something looks off.

### 1.4 Launch Advocate Agents

Launch one agent per approach in parallel using the Agent tool with `run_in_background: true`.

Each advocate receives identical context (the design doc + wip/ summary) plus their
assigned approach. This ensures equal-depth investigation.

**Anti-bias requirement:** Each advocate must investigate their approach with equal depth
and rigor. Do not sandbag approaches expected to lose -- genuine investigation of all
alternatives is what makes the recommendation in Phase 2 trustworthy.

**Advocate prompt template:**

```
You are an advocate for a specific technical approach. Your job is to investigate
this approach thoroughly and argue FOR it -- while honestly acknowledging its
weaknesses. A good advocate builds credibility by surfacing deal-breaker risks
alongside strengths.

## Problem Context
[Contents of design doc: Context and Problem Statement + Decision Drivers]

## Your Assigned Approach
Name: <approach name>
Description: <1-2 sentences>

## Instructions
1. Read relevant code, docs, and patterns in the codebase
2. Investigate how this approach would work in practice
3. Identify strengths -- what makes this approach good for this problem?
4. Identify weaknesses -- what are the costs, risks, or limitations?
5. Surface deal-breaker risks -- anything that could make this approach fail?
6. Estimate implementation complexity (files to change, new infrastructure needed)

## Output
Write your full investigation to `wip/research/design_<topic>_phase1_advocate-<approach>.md`.

Format:
# Advocate: <Approach Name>

## Approach Description
<How this approach works, in concrete terms>

## Investigation
<What you read, what you found, how the approach fits the codebase>

## Strengths
- <Strength 1>: <evidence or reasoning>
- <Strength 2>: <evidence or reasoning>

## Weaknesses
- <Weakness 1>: <evidence or reasoning>
- <Weakness 2>: <evidence or reasoning>

## Deal-Breaker Risks
- <Risk>: <why this could make the approach fail entirely>
(or "None identified" with brief justification)

## Implementation Complexity
- Files to modify: <estimate>
- New infrastructure: <yes/no, what>
- Estimated scope: <small/medium/large>

## Summary
<2-3 sentences: the honest case for this approach>

Return only the Summary section to this conversation.
```

### 1.5 Collect Results

Wait for all advocate agents to complete. Read the summary each returns.

Update `wip/design_<topic>_summary.md`:

```markdown
## Approaches Investigated (Phase 1)
- <approach-1>: <1-line from advocate summary>
- <approach-2>: <1-line from advocate summary>
- ...

## Current Status
**Phase:** 1 - Approach Discovery
**Last Updated:** <date>
```

Commit: `docs(design): investigate approaches for <topic>`

## Quality Checklist

Before proceeding:
- [ ] At least 2 approaches investigated (3-5 preferred)
- [ ] Each advocate wrote findings to `wip/research/design_<topic>_phase1_advocate-<approach>.md`
- [ ] Each advocate identified both strengths AND weaknesses

## Artifact State

After this phase:
- Advocate reports in `wip/research/design_<topic>_phase1_advocate-*.md`
- wip/ summary updated with investigated approaches
- Design doc unchanged (no sections added yet)

## Next Phase

Proceed to Phase 2: Present Approaches (`phase-2-present-approaches.md`)
