# Phase 5: PRD Handoff

Write `wip/prd_<topic>_scope.md` matching /prd Phase 1's output format.
Synthesize content from the exploration findings -- don't just copy raw
research output.

```markdown
# /prd Scope: <topic>

## Problem Statement
<2-3 sentences synthesized from exploration. State the problem clearly,
grounded in what the exploration discovered.>

## Initial Scope
### In Scope
- <item from exploration findings>
- <item>

### Out of Scope
- <item>

## Research Leads
1. <lead>: <rationale from exploration>
2. <lead>: <rationale>

## Coverage Notes
<Gaps or uncertainties to resolve in /prd Phase 2. What did the exploration
NOT answer that a PRD process should address?>

## Decisions from Exploration
<If wip/explore_<topic>_decisions.md exists, include accumulated decisions
here. These are scope narrowing, option eliminations, and priority choices
already made during exploration that the PRD should treat as settled.
If the decisions file doesn't exist, omit this section.>
```

After writing, hand off to /prd:

1. Commit: `docs(explore): hand off <topic> to /prd`
2. Invoke the PRD skill: `/shirabe:prd <topic>`
3. The PRD skill detects the handoff artifact and resumes at Phase 2
   (Discover). Phase 1 (Scope) is already done -- the handoff artifact
   fills that role.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `wip/prd_<topic>_scope.md` (new)
- Session continues in /prd at Phase 2
