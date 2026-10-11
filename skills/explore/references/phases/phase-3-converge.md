# Phase 3: Converge

Present findings from the current discovery round and help the user narrow focus.

## Goal

Synthesize what the research agents found, surface what matters, and give the
user enough information to decide: explore further or move to artifact type
selection. Update the accumulated findings key so that all rounds' knowledge
lives in one place.

## Resume Check

On a resumed invocation, ask the session where the run stands:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/explore/scripts/explore-state.sh" resume-phase <topic>
```

On `3`, resume here. Read key `work/findings.md` (if it exists) plus the
`research/` keys from rounds not yet covered in the findings (`koto context
list explore-<topic> --prefix research/`, then `koto context get` on each), and
present the accumulated results. On `4` or `5`, the run is further on: go to
that phase. On `2` or `none`, discovery has not run: go back.

If `research/` keys exist for the current round but no `work/findings.md` key
exists yet, this is a normal entry from Phase 2. Proceed with synthesis.

## Inputs

- **Current round's research keys**: `research/r<N>_lead-*` (list with `koto
  context list explore-<topic> --prefix research/r<N>_lead-`, read each with
  `koto context get explore-<topic> <key>`)
- **Accumulated findings** (if rounds 2+): key `work/findings.md`
- **Scope key**: `work/scope.md` (for original context)
- **Round number** (`N`): passed from the orchestrator

## Steps

### 3.1 Read Current Round

Read all research keys from the current round: `research/r<N>_lead-*`.

For each key, extract the key sections (Findings, Implications, Surprises,
Open Questions). If any agents failed during Phase 2, note the missing leads.

### 3.2 Read Prior Context

If this is round 2 or later, read key `work/findings.md` to
understand what previous rounds already established. Don't re-present old
findings as new -- build on them.

### 3.3 Synthesize and Present

Present findings to the user, organized by what's useful for narrowing decisions.
Don't dump raw agent output. Instead, synthesize across all agents and rounds
into four categories:

**Key insights** -- findings that matter most for deciding what to build or how
to approach it. Prioritize what's surprising or decision-relevant over
confirmations of already-known information. Cite which lead produced each insight.

**Tensions** -- where findings contradict each other or reveal trade-offs. These
often point to the real decisions. If Agent A found X works well but Agent B
found X creates problems in another area, that's a tension worth surfacing.

**Gaps** -- what's still missing. Leads that failed, questions agents couldn't
answer, areas where findings were thin. Gaps inform the next round's leads if
the user chooses to explore further.

**Open questions** -- what the user might want to investigate next. Pulled from
agents' "Open Questions" sections but also inferred from tensions and gaps.
These seed the next round's leads if the user continues.

After the synthesis, use AskUserQuestion to surface the most important
narrowing question. Pick the single question whose answer would most affect
next steps -- don't ask all three every time.

Choose from these (or craft a more specific variant based on the findings):

- **What matters most?** -- of all the findings, what's most relevant to
  your goals?
- **What surprised you?** -- anything change your thinking about the problem?
- **What's still unclear?** -- anything you expected to learn but didn't?

Provide a paragraph of context grounding the question in the specific findings
from this round. Offer 2-4 concrete answers as options (with justifications)
based on what the research surfaced, plus a free-form option.

**Be opinionated when narrowing.** Don't present directions as equally valid
when the evidence favors one over another. Recommend which directions to pursue
and which to eliminate, with reasons grounded in findings. Follow the guidance
in `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md` for how to frame recommendations
without false neutrality.

These questions serve two purposes: they help the user process the findings,
and their answers inform either the next round's leads (if exploring further)
or the crystallize phase's input (if ready to decide).

### 3.4 Capture Decisions

After the user responds to the narrowing questions, identify decisions that
were made during this round. Decisions include:

- **Scope narrowing** -- areas eliminated from consideration or deprioritized
- **Option elimination** -- approaches or solutions ruled out, with reasons
- **Priority choices** -- what the user said matters most, what to focus on next
- **Constraints accepted** -- trade-offs the user agreed to or constraints acknowledged

Write or append these to key `work/decisions.md`. The key is edited across
rounds: get it into a scratch directory, edit it there and put it back, as
"Session and Keys" in SKILL.md describes. If the key doesn't exist yet, create
it with this structure:

```markdown
# Exploration Decisions: <topic>

## Round 1
- <decision>: <rationale>

## Round 2
- <decision>: <rationale>
```

Each entry should state what was decided and why, in one or two lines. These
accumulate across rounds and feed into Phase 4 (Crystallize) and Phase 5
(Produce).

### 3.5 Decision Review Checkpoint

Before updating the findings key, scan the conversation and research outputs
for decisions that were made but not explicitly recorded in step 3.4. Look for:

- Directions the user dismissed or deprioritized during discussion
- Options that agents' findings effectively ruled out (and the user agreed)
- Implicit choices embedded in the user's narrowing answers

Add any missed decisions to key `work/decisions.md`.

### 3.6 Update Findings File

After the user responds to the narrowing questions, update key
`work/findings.md` with the accumulated knowledge (get it into a scratch
directory, edit, put it back; on the first round, create it).

This key grows across rounds. Use this structure:

```markdown
# Exploration Findings: <topic>

## Core Question
<From scope key, carried forward>

## Round 1
### Key Insights
- <insight with source lead>

### Tensions
- <tension>

### Gaps
- <gap>

### Decisions
- <decision made this round, with rationale>

### User Focus
<What the user said matters most, what surprised them, what's unclear>

## Round 2
### Key Insights
...

## Accumulated Understanding
<Updated each round: the current best understanding of the problem space,
what we know, and what's still open. This section is rewritten each round,
not appended to.>
```

The `## Accumulated Understanding` section is the running synthesis. Rewrite
it each round to reflect everything learned so far. This is what Phase 4
(Crystallize) will read to evaluate artifact type fit.

## Quality Checklist

Before handing back to the orchestrator:
- [ ] All current-round `research/` keys have been read
- [ ] Prior rounds' findings incorporated (not re-presented as new)
- [ ] Synthesis covers: key insights, tensions, gaps, open questions

## Artifact State

After this phase:
- Key `work/scope.md` in `explore-<topic>`
- Keys `research/r*_lead-*` from all rounds
- Key `work/findings.md` (created or updated)
- Key `work/decisions.md` (created or updated; may not exist if no decisions were made)
- No `## Decision: Crystallize` marker yet (the orchestrator adds this)

## What Happens Next

After this phase completes, control returns to the orchestrator (SKILL.md).
The orchestrator asks the user whether to explore further or decide what to
build. The loop decision is not part of this phase.

If the user chooses "explore further," the orchestrator captures new leads,
updates the scope key, increments the round number, and routes back to
Phase 2.

If the user chooses "ready to decide," the orchestrator adds the
`## Decision: Crystallize` marker to the findings key and routes to Phase 4.

## Next Phase

Returns to orchestrator. See SKILL.md "Phase Execution with Loop Management."
