# Phase 1: Scope

Conversational scoping to understand what the user wants to build and why, producing
research leads for Phase 2.

## Goal

Develop a shared understanding of the problem space through dialogue. By the end of this
phase you should have: a clear problem statement, initial scope boundaries, and a list of
topics worth investigating in Phase 2.

## Resume Check

If `wip/prd_<topic>_scope.md` exists and this is NOT a loop-back from Phase 2, skip to Phase 2.

If this IS a loop-back (Phase 2 determined the scope was fundamentally wrong), delete
`wip/prd_<topic>_scope.md` first, then re-scope from scratch.

## Approach: Conversational with Coverage Tracking

Ask open-ended questions, adapting to what the user already knows. Internally track
coverage of the dimensions below -- don't present them as a checklist to the user, but
weave them into the conversation naturally. Circle back to gaps when appropriate.

### Coverage Dimensions (tracked internally)

| Dimension | What to understand |
|-----------|-------------------|
| Who is affected | Users, personas, roles, systems impacted |
| Current situation | What exists today, how people cope, workarounds |
| What's missing or broken | The gap between current state and desired state |
| Why now | What changed, what's the trigger, what happens if we don't act |
| Scope boundaries | What's in, what's explicitly out, adjacent concerns |
| Success criteria | How we'll know it's done, what "good" looks like |

### Conversation Guidelines

- **Start broad**: "Tell me about the problem you're trying to solve" or build on the
  topic from `$ARGUMENTS`
- **Follow the user's energy**: If they're passionate about a specific aspect, explore it
  before circling back to gaps
- **Don't front-load decisions**: This phase produces leads, not conclusions
- **Identify uncertainty**: Note areas where the user says "I'm not sure" or "maybe" --
  these become research leads
- **Use concrete examples**: Ask for scenarios ("Walk me through what happens when...")
  to ground abstract requirements
- **2-4 questions per turn**: Don't overwhelm. Group related questions naturally.

### When to Stop Scoping

Stop when you have enough to brief a research team. Signals:
- All 6 dimensions have at least surface coverage
- You have 2-4 concrete research leads (topics worth investigating)
- The user isn't revealing new dimensions with additional questions
- The scope feels bounded (you know what's in and what's out)

Don't over-scope. Phase 2 discovers things you can't anticipate here.

## 1.1 Checkpoint

Before investing in research, present your understanding to the user. This is a
lightweight informational checkpoint, not a formal review.

Present:
1. **Problem statement** (2-3 sentences): Who is affected, what's broken/missing, why now
2. **Initial scope**: What's in, what's out
3. **Research leads**: Topics worth investigating in Phase 2, with brief rationale for each

The user can interject at any point to course-correct if something looks off.
Proceed to persist scope and move to Phase 2.

## 1.2 Persist Scope

Write the scoping output to `wip/prd_<topic>_scope.md`:

```markdown
# /prd Scope: <topic>

## Problem Statement
<2-3 sentences>

## Initial Scope
### In Scope
- <item>

### Out of Scope
- <item>

## Research Leads
1. <lead>: <rationale>
2. <lead>: <rationale>
3. <lead>: <rationale>

## Coverage Notes
<Any gaps or uncertainties to resolve in Phase 2>
```

Commit: `docs(prd): capture scope for <topic>`

## Quality Checklist

Before proceeding:
- [ ] All 6 coverage dimensions have at least surface coverage
- [ ] Problem statement is clear and specific (who, what, why now)
- [ ] 2-4 concrete research leads identified
- [ ] Checkpoint was presented to the user (scope, leads, boundaries)
- [ ] Scope document written to `wip/prd_<topic>_scope.md`

## Artifact State

After this phase:
- Scope document at `wip/prd_<topic>_scope.md`
- No PRD draft yet
- No research files yet

## Next Phase

Proceed to Phase 2: Discover (`phase-2-discover.md`)
