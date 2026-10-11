# Phase 2: Discover

Fan out research agents on leads from the scope phase.

## Goal

Investigate the leads produced in Phase 1 by sending one agent per lead. Each
agent researches its assigned question, writes full findings to a file in the
round's scratch directory, and returns a short summary. The orchestrator then
ingests that directory as `research/` keys; no agent runs koto. The round
number tracks which discover-converge iteration we're in.

## Resume Check

On a resumed invocation, ask the session where the run stands:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/explore/scripts/explore-state.sh" resume-phase <topic>
```

`3`, `4` or `5` means discovery is done or the run is further on: go to that
phase and don't re-run discovery. On `2`, check the current round. If keys
`research/r<N>_lead-*` already exist for it (`koto context list
explore-<topic> --prefix research/r<N>_lead-`), skip to Phase 3 (Converge) to
present those findings.

## Inputs

This phase receives from the orchestrator:

- **Round number** (`N`): 1 for the first pass, incremented on each "explore
  further" cycle. The orchestrator tracks this.
- **Leads**: On the first round, read from key `work/scope.md`. On subsequent
  rounds, the orchestrator captures new leads from the user during convergence
  and updates the scope key.
- **Prior findings** (rounds 2+): accumulated in key `work/findings.md` from
  previous rounds.

## Steps

### 2.1 Read Leads

Read the current leads from key `work/scope.md` (`koto context get
explore-<topic> work/scope.md`, the `## Research Leads` section). On later rounds, the orchestrator will have updated this section with
the user's new leads.

If there are more than 8 leads, cluster related ones. Each agent can handle a
cluster of 2-3 related questions. The goal is at most 8 parallel agents.

### 2.2 Build Agent Prompts

For each lead (or lead cluster), construct a prompt with:

1. **Assigned lead** -- the research question(s) this agent is responsible for
2. **Exploration context** -- the Core Question and Context sections from the scope key
3. **Prior findings** (if round 2+) -- key takeaways from key `work/findings.md`
   so the agent builds on what's already known rather than re-covering ground
4. **Visibility context** -- the resolved visibility (Private/Public) from Phase 0,
   so agents don't leak private references into artifacts destined for public repos
5. **Instructions** -- what to do and how to write output
6. **Output file path** -- where to write findings, in the round's scratch
   directory (Step 2.2a)
7. **Return instruction** -- return a 3-line summary to chat

### 2.2a Allocate the Round's Output Directory

Before building the prompts, allocate one private directory for the round:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch
```

It prints the path; call it `<dir>`. Every lead writes exactly one file there,
named `r<N>_lead-<name>.md`, and nowhere else. Agents never write keys and run
no koto command: the orchestrator ingests the directory in Step 2.4.

**Lead slugs:** `<name>` is lowercase letters, digits and single hyphens, with
no leading or trailing hyphen. Step 2.4 rejects any other name.

**Agent prompt template:**

```
You are investigating a research question as part of a structured exploration.

## Your Lead
[The research question or question cluster]

## Exploration Context
[Core Question + Context sections from the scope key work/scope.md]

## What We Already Know
[If round 2+: key takeaways from the findings key. If round 1: "This is the
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
Write your full findings to this file and to no other path:
<dir>/r<N>_lead-<name>.md

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

**Exception: adversarial demand lead**

If the scope key contains a lead entry marked `(lead-adversarial-demand)` in the
`## Research Leads` section, bypass the generic template for that lead. Use the
embedded body of that lead entry as the complete agent prompt — do not wrap it in
the generic template above. The embedded prompt already contains its own output
instructions and format; wrapping it would give the agent two competing sets of
output instructions.

The output file for this lead follows the same convention:
`<dir>/r<N>_lead-adversarial-demand.md`. Substitute that path for
`{{LEAD_OUTPUT_FILE}}` in the embedded prompt before launching it.

### 2.3 Launch Agents

Launch all agents in parallel using the Agent tool with `run_in_background: true`.

Naming convention for lead slugs: kebab-case the lead's core concept.
- "What deployment models exist for plugin systems?" -> `plugin-deployment-models`
- "How do other CLI tools handle version resolution?" -> `version-resolution-patterns`

File path per agent: `<dir>/r<N>_lead-<name>.md`

### 2.4 Collect Results

Wait for all agents to complete. As each returns its 3-line summary, track it.

Then ingest the round's directory. The call deletes any file whose name is not
`r<N>_lead-<slug>.md` (reporting `rejected=<name>`), adds the rest as
`research/<name>` keys, and removes the directory:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/explore/scripts/explore-state.sh" ingest-leads <topic> <N> <dir>
```

Each `added=research/<name>` line is a lead that landed. Treat a
`rejected=<name>` line like a failed agent: note which lead it was and surface
the gap in Phase 3. A non-zero exit means at least one add failed; stop and
report it.

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
- [ ] All leads from the scope key have been assigned to agents
- [ ] Keys `research/r<N>_lead-*` exist, one per lead that returned output
      (`ingest-leads` printed an `added=` line for each)
- [ ] Each agent returned a summary (or failure was noted)

## Artifact State

After this phase:
- Key `work/scope.md` still in `explore-<topic>`
- Keys `research/r<N>_lead-<name>.md` (one per lead)
- Prior rounds' `research/` keys still present (not overwritten)
- No `work/findings.md` key yet (Phase 3 creates/updates it)

## Next Phase

Proceed to Phase 3: Converge (`phase-3-converge.md`)
