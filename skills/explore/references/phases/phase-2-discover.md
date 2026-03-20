# Phase 2: Discover

Fan out research agents on leads from the scope phase.

## Goal

Investigate the leads produced in Phase 1 by sending one agent per lead. Each
agent researches its assigned question, writes full findings to a file, and
returns a short summary. The round number tracks which discover-converge
iteration we're in.

## Resume Check

If `wip/research/explore_<topic>_r<N>_lead-*.md` files already exist for the
current round AND no `wip/explore_<topic>_findings.md` has been written for
this round, skip to Phase 3 (Converge) to present those findings.

If the findings file already exists, the orchestrator handles routing -- don't
re-run discovery.

## Inputs

This phase receives from the orchestrator:

- **Round number** (`N`): 1 for the first pass, incremented on each "explore
  further" cycle. The orchestrator tracks this.
- **Leads**: On the first round, read from `wip/explore_<topic>_scope.md`. On
  subsequent rounds, the orchestrator captures new leads from the user during
  convergence and updates the scope file.
- **Prior findings** (rounds 2+): accumulated in `wip/explore_<topic>_findings.md`
  from previous rounds.

## Steps

### 2.1 Read Leads

Read the current leads from `wip/explore_<topic>_scope.md` (the `## Research Leads`
section). On later rounds, the orchestrator will have updated this section with
the user's new leads.

If there are more than 8 leads, cluster related ones. Each agent can handle a
cluster of 2-3 related questions. The goal is at most 8 parallel agents.

### 2.2 Build Agent Prompts

For each lead (or lead cluster), construct a prompt with:

1. **Assigned lead** -- the research question(s) this agent is responsible for
2. **Exploration context** -- the Core Question and Context sections from the scope file
3. **Prior findings** (if round 2+) -- key takeaways from `wip/explore_<topic>_findings.md`
   so the agent builds on what's already known rather than re-covering ground
4. **Visibility context** -- the resolved visibility (Private/Public) from Phase 0,
   so agents don't leak private references into artifacts destined for public repos
5. **Instructions** -- what to do and how to write output
6. **Output file path** -- where to write findings
7. **Return instruction** -- return a 3-line summary to chat

**Agent prompt template:**

```
You are investigating a research question as part of a structured exploration.

## Your Lead
[The research question or question cluster]

## Exploration Context
[Core Question + Context sections from wip/explore_<topic>_scope.md]

## What We Already Know
[If round 2+: key takeaways from the findings file. If round 1: "This is the
first round of investigation. No prior findings."]

## Visibility
[Private|Public] -- if Public, do not reference private issues or internal-only
resources in your findings.

## Instructions
1. Investigate your lead by reading relevant code, docs, config files, and
   existing patterns in the codebase
2. For each sub-question in your lead, capture:
   - What you found (concrete evidence, not speculation)
   - Why it matters for the exploration
   - Open questions that need human input or further investigation
3. Note anything surprising or that contradicts the scope assumptions
4. Keep findings grounded in what you actually read -- cite file paths and
   specific content when possible

## Output
Write your full findings to: wip/research/explore_<topic>_r<N>_lead-<name>.md

Use this format:

# Lead: <lead question>

## Findings
<What you discovered, organized by sub-topic. Cite specific files and code.>

## Implications
<What this means for the exploration. What decisions does this inform?>

## Surprises
<Anything unexpected that changes assumptions or opens new questions.>

## Open Questions
<What still needs investigation or human input.>

## Summary
<3 sentences: the key finding, its main implication, and biggest open question.>

Return ONLY the Summary section (3 lines) to this conversation.
```

### 2.3 Launch Agents

Launch all agents in parallel using the Agent tool with `run_in_background: true`.

Naming convention for lead slugs: kebab-case the lead's core concept.
- "What deployment models exist for plugin systems?" -> `plugin-deployment-models`
- "How do other CLI tools handle version resolution?" -> `version-resolution-patterns`

File path per agent: `wip/research/explore_<topic>_r<N>_lead-<name>.md`

### 2.4 Collect Results

Wait for all agents to complete. As each returns its 3-line summary, track it.

If an agent fails (tool error, timeout, empty output):
- Note the failure and which lead it was investigating
- Don't retry automatically -- surface the gap during Phase 3 convergence
- The user can decide during convergence whether to re-investigate in the next round

### 2.5 Summary

After all agents finish, present a brief status:

```
Round <N> discovery complete. <X> of <Y> leads investigated successfully.
[If any failed: "<Z> leads had issues and will be flagged during convergence."]
Proceeding to convergence.
```

Don't synthesize findings here. That's the convergence phase's job. Just confirm
the agents ran and hand off.

## Quality Checklist

Before proceeding to Phase 3:
- [ ] All leads from the scope file have been assigned to agents
- [ ] Agent output files exist at `wip/research/explore_<topic>_r<N>_lead-*.md`
- [ ] Each agent returned a summary (or failure was noted)

## Artifact State

After this phase:
- Scope file still at `wip/explore_<topic>_scope.md`
- Research files at `wip/research/explore_<topic>_r<N>_lead-<name>.md` (one per lead)
- Prior rounds' research files still present (not overwritten)
- No findings file yet (Phase 3 creates/updates it)

## Next Phase

Proceed to Phase 3: Converge (`phase-3-converge.md`)
