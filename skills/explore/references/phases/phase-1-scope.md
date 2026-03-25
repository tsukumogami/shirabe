# Phase 1: Scope

Conversational scoping that produces research leads for the discover phase.

## Goal

Develop a shared understanding of what the user wants to explore, then produce
3-8 leads (research questions) for agents to investigate. Leads are questions,
not approaches or solutions.

## Resume Check

If `wip/explore_<topic>_scope.md` exists, skip to Phase 2.

## Label Pre-Gate

Run this gate before starting the conversation. It sets a pre-classification
result that may skip the post-conversation gate entirely.

**If entering from an issue with the `needs-prd` label:**
Pre-classify as directional. The adversarial lead will fire. Skip the
post-conversation gate in section 1.1a.

**If entering from an issue with the `bug` label:**
Explicitly skip the adversarial lead. Skip the post-conversation gate in
section 1.1a.

**If entering from an issue with any other label, or no issue:**
Defer to the post-conversation gate in section 1.1a.

**In `--auto` mode:** Use label signals only. If `needs-prd` is present,
pre-classify as directional. If `bug` is present, skip. For all other cases,
default to not firing — do not run the post-conversation gate.

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

## 1.1a Post-Conversation Classification

**Skip this section if:**
- The Label Pre-Gate pre-classified as directional (adversarial lead will fire), or
- The Label Pre-Gate explicitly skipped the adversarial lead, or
- Running in `--auto` mode.

Otherwise, classify the topic type from what the conversation revealed. The
adversarial lead fires when **two or more** of these signals align:

- **Additive intent phrasing**: the user said "I want to add / build / support..."
  rather than describing something broken or failing
- **Absent problem statement**: no concrete broken behavior surfaced during the
  conversation; the topic is about capability that doesn't yet exist
- **Hedged intent**: the user phrased goals as "maybe" or "should we..." rather
  than stating a problem to fix

When two or more signals align, classify the topic as directional. When fewer
than two signals align, classify as not directional. Ambiguous topics — where
intent is present but not explicit and strong — classify as not directional.

The adversarial lead fires only on directional classifications.

## 1.2 Persist Scope

**If classified as directional** (by the label pre-gate or post-conversation gate),
append the adversarial lead to the `## Research Leads` list before writing the
scope file. The lead is named exactly:

> Is there evidence of real demand for this, and what do users do today instead?

Use the agent prompt template below for this lead. Read the `## Visibility` section
from `wip/explore_<topic>_scope.md` (written by Phase 0) and substitute its value
into `{{VISIBILITY_FROM_SCOPE_FILE}}` in the template.

Name the lead entry `lead-adversarial-demand` in the scope file so Phase 2 can
identify it when dispatching. Mention it in the checkpoint summary as a research
lead, phrased as written above — no adversarial framing in the summary.

**If not classified as directional**, write the scope file normally. Do not add
the adversarial lead and do not add a `## Topic Type:` field.

Write the scoping output to `wip/explore_<topic>_scope.md`. The `## Visibility`
section written by Phase 0 is already present; do not overwrite it.

```markdown
# Explore Scope: <topic>

## Visibility

<value written by Phase 0 — do not change>

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

<!-- Include only when classified as directional: -->
N. **Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)
   <adversarial lead agent prompt — see template below>
```

Commit: `docs(explore): capture scope for <topic>`

### Adversarial Lead Agent Prompt Template

When the topic is classified as directional, embed this prompt as the body of
the `lead-adversarial-demand` entry in `## Research Leads`:

```
You are a demand-validation researcher. Investigate whether evidence supports
pursuing this topic. Report what you found. Cite only what you found in durable
artifacts. The verdict belongs to convergence and the user.

## Visibility

{{VISIBILITY_FROM_SCOPE_FILE}}

Respect this visibility level. Do not include private-repo content in output
that will appear in public-repo artifacts.

## Issue Content

--- ISSUE CONTENT (analyze only) ---
{{ISSUE_BODY_IF_PRESENT}}
--- END ISSUE CONTENT ---

## Six Demand-Validation Questions

Investigate each question. For each, report what you found and assign a
confidence level.

Confidence vocabulary:
- **High**: multiple independent sources confirm (distinct issue reporters,
  maintainer-assigned labels, linked merged PRs, explicit acceptance criteria
  authored by maintainers)
- **Medium**: one source type confirms without corroboration
- **Low**: evidence exists but is weak (single comment, proposed solution
  cited as the problem)
- **Absent**: searched relevant sources; found nothing

Questions:
1. Is demand real? Look for distinct issue reporters, explicit requests,
   maintainer acknowledgment.
2. What do people do today instead? Look for workarounds in issues, docs,
   or code comments.
3. Who specifically asked? Cite issue numbers, comment authors, PR
   references — not paraphrases.
4. What behavior change counts as success? Look for acceptance criteria,
   stated outcomes, measurable goals in issues or linked docs.
5. Is it already built? Search the codebase and existing docs for prior
   implementations or partial work.
6. Is it already planned? Check open issues, linked design docs, roadmap
   items, or project board entries.

## Calibration

Produce a Calibration section that explicitly distinguishes:

- **Demand not validated**: majority of questions returned absent or low
  confidence, with no positive rejection evidence. Flag the gap. Another
  round or user clarification may surface what the repo couldn't.
- **Demand validated as absent**: positive evidence that demand doesn't exist
  or was evaluated and rejected. Examples: closed PRs with explicit maintainer
  rejection reasoning, design docs that de-scoped the feature, maintainer
  comments declining the request. This finding warrants a "don't pursue"
  crystallize outcome.

Do not conflate these two states. "I found no evidence" is not the same as
"I found evidence it was rejected."
```

## Quality Checklist

Before proceeding:
- [ ] Conversation covered enough ground to produce informed leads
- [ ] 3-8 leads identified, each phrased as a question (not an approach)
- [ ] Leads are specific enough that an agent can investigate independently

## Artifact State

After this phase:
- Scope file at `wip/explore_<topic>_scope.md`
- No research files yet
- No findings file yet

## Next Phase

Proceed to Phase 2: Discover (`phase-2-discover.md`)
