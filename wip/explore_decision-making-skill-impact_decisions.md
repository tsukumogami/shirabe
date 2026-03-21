# Exploration Decisions: decision-making-skill-impact

## Round 1
- Decision framework generalizes design's advocate pattern: the decision skill IS design Phase 1-2, extracted and made reusable
- Explore hands off to decision skill (doesn't merge): explore discovers THAT a decision is needed, decision skill MAKES the decision
- Cross-validation is the design skill's concern, not the decision skill's: keeps decision skill reusable across contexts
- Status derived from artifacts, not separate trackers: avoids dual-write consistency problems

## Round 2
- Non-interactive mode is a cross-cutting concern: all skills must support assumption-driven execution where the agent never blocks on user input
- Lightweight decisions use the same assumption-tracking pattern as heavyweight decisions: the difference is depth of evaluation (fast path vs full bakeoff), not a fundamentally different mechanism
- AskUserQuestion is not the universal decision mechanism: it's one option alongside research-first-then-assume. The agent should exhaust available information before asking, and in non-interactive mode, should assume and document instead of asking
