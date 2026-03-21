# Phase 1: Research

Spawn a research agent to build context and identify critical unknowns.

## Resume Check

If `wip/<prefix>_research.md` exists, skip to Phase 2.

## Steps

### 1.1 Identify Critical Unknowns

Read the context artifact. Determine what information would change the outcome
if answered differently. Focus on unknowns that differentiate between alternatives,
not background knowledge.

### 1.2 Spawn Research Agent

Launch a disposable research agent via the Agent tool:

```
Agent tool:
  prompt: |
    You are researching a decision: <question>

    Context: <from context artifact>
    Constraints: <constraints>
    Known options: <if any>

    Identify the critical unknowns -- things that would change the outcome
    if answered differently. Research the codebase, documentation, and any
    available resources to answer them.

    For unknowns you can't resolve:
    - In interactive mode: note them for user clarification
    - In non-interactive mode: make a reasonable assumption and document it
      explicitly ("Assumed: <X>. If wrong: <consequence>")

    Write your findings to wip/<prefix>_research.md with sections:
    - Research conducted (what you looked at)
    - Findings (what you learned)
    - Assumptions made (if any, with consequences)
    - Clean summary of the problem and critical unknowns

    Return a 3-5 line summary.
```

### 1.3 Collect Results

Read the research summary. If the agent made assumptions (non-interactive mode),
these will propagate into the decision report's Assumptions field.

## Quality Checklist

- [ ] Critical unknowns identified and investigated
- [ ] Research artifact written to wip/
- [ ] Assumptions documented if information gaps remain

## Next Phase

Proceed to Phase 2: Alternative Presentation (`phase-2-alternatives.md`)
