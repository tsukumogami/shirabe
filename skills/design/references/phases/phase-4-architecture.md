# Phase 4: Architecture

Synthesize Phase 3 findings into formal design doc sections. No new research.

## Goal

Write the core technical sections of the design doc:
- Solution Architecture (how components fit together)
- Implementation Approach (how to build it)
- Consequences (trade-offs of this design)

This phase only writes based on what Phase 3 discovered. If you need more
information, go back to Phase 3 rather than doing inline research here.

## Resume Check

If the design doc has a "Solution Architecture" section, skip to Phase 5.

## Steps

### 4.1 Read Investigation Findings

Read all Phase 3 research reports from `wip/research/design_<topic>_phase3_*.md`.
Read the wip/ summary for selected approach context.

### 4.2 Write Solution Architecture

```markdown
## Solution Architecture

### Overview

<High-level description of the solution -- what it does, how it works>

### Components

<Components and their relationships. Use a diagram or structured list.>

### Key Interfaces

<Important APIs, data structures, contracts, or integration points>

### Data Flow

<How data moves through the system. Include wip/ artifacts if the design
produces workflow state.>
```

Be concrete. Name files, functions, and paths where possible. A reader should be
able to start implementing from this section.

### 4.3 Write Implementation Approach

Break the implementation into sequential phases with dependencies:

```markdown
## Implementation Approach

### Phase 1: <Name>
<What gets built first, why this order>
Deliverables:
- <specific file or component>

### Phase 2: <Name>
<What gets built next, dependencies on Phase 1>
Deliverables:
- <specific file or component>
```

Keep phases small enough to be one commit each. Don't over-plan -- Phase 5
(/plan) will create issues if the design is complex.

### 4.4 Implicit Decision Review

Re-read the Solution Architecture and Implementation Approach text you just wrote.
Look for statements that could reasonably have gone a different way -- these are
implicit decisions baked into the prose as assertions rather than documented as
choices.

Examples of implicit decisions:
- "We use polling to check status" (webhooks was also viable)
- "Strict validation rejects malformed input" (permissive parsing was an option)
- "Each component gets its own goroutine" (sequential processing was possible)
- "State is stored in a JSON file" (SQLite, environment variables were alternatives)

For each implicit decision found:

1. Identify the choice made and at least one alternative that was viable
2. Present it to the user via AskUserQuestion for confirmation (see
   `references/decision-presentation.md`)
3. Append to Considered Options using the standard Decision N format
   (context / chosen / rejected)

These don't need full advocate agents -- just the structured format so future
readers understand that a choice was made and why.

### 4.5 Write Consequences

```markdown
## Consequences

### Positive
- <Benefit with brief explanation>

### Negative
- <Cost or limitation with brief explanation>

### Mitigations
- <How we address each negative consequence>
```

Be honest about negatives. Every design has trade-offs. If you can't identify
any negatives, you haven't thought hard enough.

## Quality Checklist

Before proceeding:
- [ ] Solution Architecture is concrete enough to implement
- [ ] Components and their relationships are clear
- [ ] Key interfaces are defined (not vague)
- [ ] Implementation is phased with dependencies noted
- [ ] Both positive AND negative consequences documented
- [ ] Implicit decisions from architecture text promoted to Considered Options
- [ ] No new research was done (only synthesis of Phase 3 findings)

## Artifact State

After this phase, the design doc has:
- All previous sections (Context, Drivers, Options, Outcome)
- Solution Architecture section (new)
- Implementation Approach section (new)
- Consequences section (new)

## Next Phase

Proceed to Phase 5: Security (`phase-5-security.md`) -- THIS IS MANDATORY
