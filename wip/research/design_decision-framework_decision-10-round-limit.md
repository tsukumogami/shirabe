# Decision 10: How Should --auto Mode Handle Loops Across All Skills?

## Context

Several shirabe skills contain loops where the workflow can repeat a phase
based on a decision point:

- **explore**: Phase 2 (Discover) -> Phase 3 (Converge) -> "Explore further?"
  loops back to Phase 2 with incremented round number. This is the primary
  discover-converge loop. (Blocking point E7)
- **prd**: Phase 2 (Discover) -> "Proceed to Phase 3?" can loop back for more
  investigation or restart scoping entirely. (Blocking point P4)
- **design**: Phase 2 -> "None of these" loops back to Phase 1 to investigate
  new approaches. (Blocking point D4)

In interactive mode, the user controls termination. In `--auto` mode, no human
is available, so the agent must decide when to stop looping. The non-interactive
mode design (see `wip/research/explore_decision-making-skill-impact_r2_lead-non-interactive.md`)
established that `--auto` auto-selects recommended options at all decision
points, but didn't specify how to prevent unbounded loops.

## The Problem

Without a termination guarantee, an agent in `--auto` mode could loop
indefinitely if its recommendation heuristic keeps finding gaps. Each round
produces new findings that surface new gaps, which trigger another round.
The heuristic "if gaps exist, explore further" is correct for thoroughness
but has no natural stopping point.

The risk runs both ways:
- **Under-exploring**: cutting off too early means the workflow produces
  shallow analysis that misses important considerations
- **Over-exploring**: running too many rounds wastes compute and context
  window, with diminishing returns after the first 1-2 rounds

## Options

### (a) Per-skill round limits

Each skill hardcodes its own maximum: explore max 3, prd max 2, design max 1.

**Pros:**
- Tuned to each skill's loop characteristics. Explore's loop is broader and
  benefits from more rounds; design's "none of these" loop is narrower.
- Simple to implement: one constant per skill.
- Easy to reason about: reading a SKILL.md tells you exactly how many rounds
  that skill will run.

**Cons:**
- Inconsistent mental model. Users must remember different limits for different
  skills.
- The limits are arbitrary. Why 3 for explore and not 2? There's no principled
  basis for the specific numbers without usage data.
- Limits live in skill files, not in the `--auto` specification. When someone
  reads the auto-mode docs, they don't see the limits; they have to check each
  skill.

### (b) Universal round limit

All discover-converge/research loops share a single configurable limit
(default 3), applied uniformly across skills.

**Pros:**
- One number to learn, one place to document it.
- Configurable: `--auto --max-rounds=2` overrides the default for users who
  want faster or deeper runs.
- Consistent behavior: all skills follow the same contract.

**Cons:**
- Design's "none of these" loop is structurally different from explore's
  discover-converge loop. Applying the same limit to both conflates different
  loop types. Design's loop means "the approach space was wrong"; explore's
  loop means "I want more coverage." A universal limit of 3 makes sense for
  explore but is excessive for design (3 rounds of "none of these" suggests
  the problem is poorly scoped, not under-explored).
- Doesn't account for loop purpose. Some loops are broadening (explore more
  of the space) and others are corrective (go back and fix something). A
  universal limit treats them identically.

### (c) Adaptive termination

No fixed limit. The agent evaluates "marginal value of another round" based
on coverage metrics. If the last round produced less than 20% new findings
compared to the accumulated total, auto-terminate.

**Pros:**
- Principled: stops when there's diminishing return, not at an arbitrary
  number.
- Self-adjusting: simple topics terminate after 1 round, deep topics get more.
- No configuration needed.

**Cons:**
- "20% new findings" is hard to measure. What counts as a finding? How do you
  compare the size of round 2's insights to round 1's? The metric is
  subjective enough that the agent's assessment would be unreliable.
- Unpredictable: the user can't know in advance how many rounds will run.
  This makes debugging and cost estimation difficult.
- Fragile: if the agent miscounts findings or uses a different granularity,
  the threshold triggers at the wrong time. A round with 2 critical findings
  and a round with 10 trivial findings look very different under this metric.
- Still needs a hard cap as a safety net, which means you're really doing
  option (a) or (b) plus an adaptive heuristic on top.

### (d) First-round-only in --auto

Non-interactive mode always runs exactly 1 round, then proceeds. Multi-round
loops are an interactive-only feature.

**Pros:**
- Simplest possible implementation. No configuration, no heuristics.
- Predictable cost and duration.
- Forces the agent to make the most of a single round, which may produce
  better-focused research leads.

**Cons:**
- Under-explores by construction. The whole point of multi-round exploration
  is that round 1 surfaces leads that round 2 investigates. Cutting this off
  means `--auto` produces strictly worse output than interactive mode.
- For explore specifically, one round often isn't enough. The skill was
  designed for iterative deepening -- the first round is deliberately broad.
- Creates a two-class system where auto-mode output is known to be shallow.
  Users may not trust auto-mode results, defeating the purpose.

## Analysis

### Loop types are not equivalent

The three loops have different characteristics:

| Loop | Purpose | Typical rounds | What triggers another round |
|------|---------|---------------|---------------------------|
| explore discover-converge | Broaden coverage | 1-3 | Significant gaps in findings |
| prd discover | Fill research gaps | 1-2 | New leads from synthesis |
| design "none of these" | Correct approach space | 0-1 | Fundamental mismatch with needs |

Explore's loop is expansive -- each round adds breadth. Prd's loop is gap-filling
-- it targets specific missing information. Design's loop is corrective -- it
means the initial framing was wrong.

A universal limit ignores these differences. But per-skill limits, while more
accurate, scatter the configuration across files.

### The real question: where should limits live?

The auto-mode specification needs to be the single source of truth for
non-interactive behavior. Per-skill quirks should be documented in skill files,
but the limit mechanism should be centralized.

### Adaptive termination needs a hard cap anyway

Option (c) is appealing in theory but requires a fallback limit. If you need
the fallback, you've already built option (a) or (b). The adaptive part becomes
an optimization on top -- "terminate early if diminishing returns, but never
exceed N." That's worth considering as a refinement, but it isn't an
alternative to having a cap.

### One round is too few; unlimited is too many

Option (d) sacrifices quality for simplicity. The skills are designed for
iterative deepening, and removing that in auto mode creates a meaningful
quality gap. But unbounded looping (no cap at all) is also unacceptable.
The answer is somewhere between 1 and infinity.

## Decision

**Chosen: (a) Per-skill round limits, with a centralized override.**

This is a hybrid of (a) and (b). Each skill defines its own default maximum
based on its loop characteristics, but `--auto` accepts `--max-rounds=N` as
an override that applies to all skills.

### Specific limits

| Skill | Loop type | Default max rounds | Rationale |
|-------|-----------|-------------------|-----------|
| explore | Discover-converge | 3 | Designed for iterative broadening; first round is deliberately broad, second and third deepen |
| prd | Discover loop-back | 2 | Gap-filling is more targeted; if 2 rounds don't fill the gaps, scoping was likely wrong |
| design | "None of these" | 1 | A corrective loop; if the first correction doesn't help, the problem needs re-scoping, not more looping |

### How it works

1. Each skill's SKILL.md documents its default max rounds in the Auto Mode
   section.
2. When `--auto` is active, the loop decision point counts rounds. If the
   current round equals the max, the agent proceeds (selects "Ready to decide"
   / "Proceed to Phase 3" / accepts the recommended approach) regardless of
   the recommendation heuristic.
3. `--max-rounds=N` overrides all skill defaults. If specified, all skills
   use N as their cap.
4. When the cap forces termination, the agent records an Approach-level
   assumption: "Terminated exploration at round N (max reached). Gaps
   remaining: [list]."

### Why not pure (b)?

Design's "none of these" loop is structurally different from explore's
discover-converge loop. Giving design 3 rounds of "none of these" means the
agent could fan out 3 separate batches of advocate agents investigating
approaches, which is expensive and unlikely to help -- if the first round of
corrective approaches doesn't work, the issue is problem framing, not
approach coverage. Per-skill defaults encode this structural knowledge.

### Why not pure (a)?

Per-skill limits without a centralized override mean users can't say "I want
a fast run" or "I want a deep run" without editing skill files. The
`--max-rounds` flag gives users a single knob.

### Adaptive termination as a refinement

The recommendation heuristic already evaluates gap coverage. In auto mode,
the agent can still terminate early (before hitting the cap) when the
heuristic recommends "Ready to decide." The cap is a ceiling, not a target.
Most auto-mode runs will terminate in fewer rounds than the max.

This captures the best part of option (c) -- data-driven early termination --
without the measurement problems. The heuristic is qualitative ("significant
gaps remain" vs "coverage is sufficient"), not quantitative ("20% new
findings"), which matches how the skills already work.

### Where limits are documented

- **Each skill's SKILL.md**: Auto Mode section states the default max rounds
  for that skill and what triggers early termination.
- **Centralized auto-mode docs**: Documents `--max-rounds` flag and lists all
  skill defaults in one table.
- **Assumptions file**: Records when a cap forced termination and what gaps
  remained.

## Decision Block

```
Decision 10: Auto-mode loop termination
Status: Proposed
Chosen: Per-skill round limits with centralized override
  - explore: max 3 rounds (discover-converge)
  - prd: max 2 rounds (discover loop-back)
  - design: max 1 round ("none of these" correction)
  - --max-rounds=N overrides all defaults
  - Cap forces termination with documented assumption
  - Heuristic-based early termination still applies (cap is ceiling, not target)
Rejected:
  - (b) Universal round limit: conflates structurally different loop types
  - (c) Adaptive termination alone: measurement problems, still needs a hard cap
  - (d) First-round-only: sacrifices too much quality for simplicity
```

## Impact on Existing Skill Files

### explore/SKILL.md (lines 202-223)

Add to Auto Mode section:

```markdown
**Loop limit**: In `--auto` mode, the discover-converge loop runs at most 3
rounds (or `--max-rounds` if specified). If the cap is reached, auto-select
"Ready to decide" regardless of the recommendation heuristic. Record an
Approach-level assumption documenting remaining gaps.

Between rounds, the recommendation heuristic still applies -- if round 1
produces sufficient coverage, the agent proceeds without running rounds 2-3.
```

### prd/SKILL.md (Phase 2 loop-back, P4)

Add to Auto Mode section:

```markdown
**Loop limit**: In `--auto` mode, the discover loop-back runs at most 2 rounds
(or `--max-rounds` if specified). If 2 rounds of investigation haven't filled
the gaps, the agent proceeds to Phase 3 and lets the drafting phase surface
remaining unknowns as open questions in the PRD.
```

### design/SKILL.md (Phase 2 "none of these", D4)

Add to Auto Mode section:

```markdown
**Loop limit**: In `--auto` mode, the "None of these" loop-back runs at most
1 round (or `--max-rounds` if specified). If the corrective round doesn't
produce a satisfactory approach, the agent selects the best available option
and records an Approach-level assumption with the concern that triggered the
original rejection.
```

## Interaction with Non-Interactive Mode Design

The non-interactive mode research (`wip/research/explore_decision-making-skill-impact_r2_lead-non-interactive.md`)
established that `--auto` auto-selects recommended options at all decision
points (Category B in the ask inventory). Loop decisions (E7, P4, D4) are
Category B points. This decision specifies when the auto-selection is
overridden by the cap.

The assumption documentation format already supports this. When the cap forces
termination, the assumption record follows the Approach level template:

```markdown
### A<N>: Exploration terminated at round cap

- **Phase**: explore/Phase 3 (round 3)
- **Context**: Max rounds reached. Recommendation heuristic suggested
  exploring further due to remaining gaps in [area].
- **What was decided**: Proceeded to crystallize despite identified gaps.
- **Evidence**: Rounds 1-3 covered [X, Y, Z]. Remaining gaps: [A, B].
- **If wrong**: Re-run explore with --max-rounds=5 or interactively.
- **Confidence**: Medium -- gaps exist but core coverage may be sufficient.
```
