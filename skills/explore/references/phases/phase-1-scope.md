# Phase 1: Scope

Conversational scoping that produces research leads for the discover phase.

## Goal

Develop a shared understanding of what the user wants to explore, then produce
3-8 leads (research questions) for agents to investigate. Leads are questions,
not approaches or solutions.

## Resume Check

If `wip/explore_<topic>_scope.md` exists, skip to Phase 2.

## Approach: Conversation, Not a Form

This phase is a dialogue. Ask open-ended questions and follow the user's energy.
Don't present a checklist or template to fill out. Instead, track coverage
internally and steer toward gaps when the conversation allows it.

### Coverage Tracking (internal)

Keep mental track of what you understand in these areas. Don't show this table
to the user or ask about each area explicitly -- weave them into the conversation.

| Area | What to understand |
|------|-------------------|
| Intent | What the user is trying to accomplish or figure out |
| Prior knowledge | What they already know, what they've tried |
| Uncertainty | Where they say "I'm not sure" or "maybe" -- these become leads |
| Constraints | Hard limits, deadlines, compatibility needs |
| Scope edges | What's in, what's out, adjacent concerns to avoid |
| Stakes | What happens if we get it wrong, who cares about this |

### Conversation Guidelines

- **Start from context.** If `$ARGUMENTS` gave a topic, build on it: "What
  specifically about <topic> are you trying to figure out?" If an issue provided
  context, summarize what you read and ask what's missing.
- **Follow energy.** When the user is animated about an aspect, go deeper there
  before circling back to gaps. Their enthusiasm points toward the real question.
- **Don't front-load decisions.** This phase produces leads, not conclusions.
  If the user starts proposing solutions, acknowledge them but redirect: "That's
  one possibility. What made you think of that approach?" The "why" behind a
  proposed solution is often a better lead than the solution itself.
- **Name uncertainty.** When the user hedges ("I think maybe..." or "probably"),
  call it out gently: "Sounds like that's an open question. Worth investigating?"
  Uncertainty is where leads come from.
- **Use concrete scenarios.** Ask "Walk me through what happens when..." to
  ground abstract goals in specific situations.
- **2-4 questions per turn.** Don't overwhelm. Group related questions naturally.

### When to Stop

Stop when you can brief a research team. Signals:
- You have surface coverage across most areas in the tracking table
- You've identified 3-8 concrete things worth investigating
- The user isn't revealing new dimensions with each answer
- You know what's in scope and what isn't

Don't over-scope. The discover phase will surface things you can't anticipate here.
Two or three conversational turns is usually enough.

## 1.1 Checkpoint

Before committing to leads, present your understanding to the user. Keep it
lightweight -- an informational summary, not a formal review.

Present:
1. **What we're exploring** (2-3 sentences): the core question or goal
2. **Scope**: what's in, what's out
3. **Research leads** (3-8): each a clear question or topic to investigate,
   with a brief note on why it matters

Example leads (questions, not solutions):
- "What deployment models exist for plugin systems?" -- need to understand the
  landscape before picking an approach
- "How do other CLI tools handle version resolution?" -- several have solved
  this; worth knowing what worked
- "Is it feasible to use WASM for recipe sandboxing?" -- user mentioned WASM
  as a possibility; need to validate the assumption

The user can interject at any point to course-correct if something looks off.
Proceed to persist scope and move to Phase 2.

## 1.2 Persist Scope

Write the scoping output to `wip/explore_<topic>_scope.md`:

```markdown
# Explore Scope: <topic>

## Core Question
<2-3 sentences: what we're trying to figure out>

## Context
<Key background from the conversation -- what the user knows, what
constraints exist, what prompted this exploration>

## In Scope
- <item>

## Out of Scope
- <item>

## Research Leads

1. **<lead as question>**
   <1-2 sentences: why this matters, what we hope to learn>

2. **<lead as question>**
   <1-2 sentences: why this matters, what we hope to learn>

3. **<lead as question>**
   <1-2 sentences: why this matters, what we hope to learn>
```

Commit: `docs(explore): capture scope for <topic>`

## Quality Checklist

Before proceeding:
- [ ] Conversation covered enough ground to produce informed leads
- [ ] 3-8 leads identified, each phrased as a question (not an approach)
- [ ] Leads are specific enough that an agent can investigate independently
- [ ] Leads are open enough to return unexpected findings
- [ ] Checkpoint was presented to the user (core question, scope, leads)
- [ ] Scope written to `wip/explore_<topic>_scope.md`

## Artifact State

After this phase:
- Scope file at `wip/explore_<topic>_scope.md`
- No research files yet
- No findings file yet

## Next Phase

Proceed to Phase 2: Discover (`phase-2-discover.md`)
