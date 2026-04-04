# Phase 5: VISION Handoff

Write `wip/vision_<topic>_scope.md` matching /vision Phase 1's output format.
Synthesize content from the exploration findings -- don't just copy raw
research output.

```markdown
# /vision Scope: <topic>

## Problem Statement
<2-3 sentences synthesized from exploration. State why this project should
exist, grounded in what the exploration discovered.>

## Initial Scope
### This Project IS
- <identity statement from exploration findings>
- <identity statement>

### This Project IS NOT
- <identity boundary with reasoning>

## Research Leads
1. <lead>: <rationale from exploration>
2. <lead>: <rationale>

## Coverage Notes
<Gaps or uncertainties to resolve in /vision Phase 2. What did the exploration
NOT answer that a vision process should address? Note any coverage dimensions
from /vision Phase 1 that lack even surface coverage: thesis clarity, audience
definition, org fit, success criteria, scope boundaries, value proposition.>

## Decisions from Exploration
<If wip/explore_<topic>_decisions.md exists, include accumulated decisions
here. These are scope narrowing, option eliminations, and priority choices
already made during exploration that the vision should treat as settled.
If the decisions file doesn't exist, omit this section.>
```

After writing, hand off to /vision:

1. Commit: `docs(explore): hand off <topic> to /vision`
2. Invoke the vision skill: `/shirabe:vision <topic>`
3. The vision skill detects the handoff artifact and resumes at Phase 2
   (Discover). Phase 1 (Scope) is already done -- the handoff artifact
   fills that role.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `wip/vision_<topic>_scope.md` (new)
- Session continues in /vision at Phase 2
