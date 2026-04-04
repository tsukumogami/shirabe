# Phase 1: Scope

Conversational scoping to understand the project's thesis, audience, and strategic
positioning, producing research leads for Phase 2.

## Goal

Develop a shared understanding of WHY this project should exist through dialogue. By the
end of this phase you should have: a clear thesis direction, initial audience definition,
org fit rationale, and a list of topics worth investigating in Phase 2.

## Resume Check

If `wip/vision_<topic>_scope.md` exists and this is NOT a loop-back from Phase 2, skip
to Phase 2.

If this IS a loop-back (Phase 2 determined the thesis direction was fundamentally wrong),
delete `wip/vision_<topic>_scope.md` first, then re-scope from scratch.

## Approach: Conversational with Coverage Tracking

Ask open-ended questions, adapting to what the user already knows. Internally track
coverage of the dimensions below -- don't present them as a checklist to the user, but
weave them into the conversation naturally. Circle back to gaps when appropriate.

### Coverage Dimensions (tracked internally)

| Dimension | What to understand |
|-----------|-------------------|
| Thesis clarity | What's the core bet? What belief drives this project? What insight makes it worth pursuing? |
| Audience definition | Who benefits? What's their current situation? What friction do they face today? |
| Org fit | How does this relate to existing projects? Why build this HERE and not elsewhere? What positioning does it build on? |
| Success criteria | What project-level outcomes would validate the thesis? Not features -- adoption signals, ecosystem health, quality indicators. |
| Scope boundaries | What is this project deliberately NOT? Where does its identity end? |
| Value proposition | What category of value does this deliver? One level above features -- what changes for the audience? |

### Conversation Guidelines

- **Start broad**: "What's the core belief behind this project?" or build on the topic
  from `$ARGUMENTS`
- **Follow the user's energy**: If they're passionate about a specific aspect, explore it
  before circling back to gaps
- **Don't front-load decisions**: This phase produces leads, not conclusions
- **Identify uncertainty**: Note areas where the user says "I'm not sure" or "maybe" --
  these become research leads
- **Use concrete examples**: Ask for scenarios ("Who would use this? Walk me through their
  day without it") to ground abstract positioning
- **2-4 questions per turn**: Don't overwhelm. Group related questions naturally.
- **Thesis as hypothesis**: Push toward "We believe [audience] needs [capability] because
  [insight]" framing. If the user describes a problem, ask what bet they'd make about
  solving it.

### When to Stop Scoping

Stop when you have enough to brief a research team. Signals:
- All 6 dimensions have at least surface coverage
- You have 2-4 concrete research leads (topics worth investigating)
- The user isn't revealing new dimensions with additional questions
- The thesis direction feels clear enough to test (even if not final)

Don't over-scope. Phase 2 discovers things you can't anticipate here.

## 1.1 Checkpoint

Before investing in research, present your understanding to the user. This is a
lightweight informational checkpoint, not a formal review.

Present:
1. **Thesis direction** (1-2 sentences): The core bet, framed as a hypothesis
2. **Audience sketch** (1-2 sentences): Who benefits and their current situation
3. **Org fit rationale** (1-2 sentences): Why this belongs here
4. **Research leads**: Topics worth investigating in Phase 2, with brief rationale for each

The user can interject at any point to course-correct if something looks off.
Proceed to persist scope and move to Phase 2.

## 1.2 Persist Scope

Write the scoping output to `wip/vision_<topic>_scope.md`:

```markdown
# /vision Scope: <topic>

## Thesis Direction
<1-2 sentences: the core bet, framed as hypothesis>

## Audience Sketch
<1-2 sentences: who benefits and their current situation>

## Org Fit Rationale
<1-2 sentences: why this belongs here, what it builds on>

## Initial Scope
### This Project IS
- <identity statement>

### This Project IS NOT
- <identity boundary with reasoning>

## Research Leads
1. <lead>: <rationale>
2. <lead>: <rationale>
3. <lead>: <rationale>

## Coverage Notes
<Any gaps or uncertainties to resolve in Phase 2>
```

Commit: `docs(vision): capture scope for <topic>`

## Quality Checklist

Before proceeding:
- [ ] All 6 coverage dimensions have at least surface coverage
- [ ] Thesis direction is framed as a hypothesis (not a problem statement)
- [ ] Audience is described by situation (not just a label)
- [ ] 2-4 concrete research leads identified

## Artifact State

After this phase:
- Scope document at `wip/vision_<topic>_scope.md`
- No VISION draft yet
- No research files yet

## Next Phase

Proceed to Phase 2: Discover (`phase-2-discover.md`)
