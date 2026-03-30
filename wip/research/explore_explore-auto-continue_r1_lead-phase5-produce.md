# Lead 1: Phase 5 Produce File Analysis

## Current Handoff Pattern

| Artifact Type | Stops or Continues? | Auto-Invokes Skill? |
|---|---|---|
| PRD | Continues | No — reads /prd SKILL.md, tells agent to continue at Phase 2 |
| Design Doc | Continues | No — reads /design SKILL.md, tells agent to continue at Phase 1 |
| Plan | Stops | No — tells user to run `/plan <topic>` |
| Decision Record | Continues | Yes — invokes decision skill via Skill tool |
| Rejection Record | Stops | No |
| No Artifact | Stops | No |
| Deferred (roadmap/spike/comp) | Stops | No |

## Key Finding

The produce files for PRD and Design Doc already say "continue" — they instruct
the agent to read the downstream skill and continue at the appropriate phase. But
they don't actually invoke the Skill tool to load the skill. Only the Decision
Record handoff explicitly invokes the downstream skill.

The issue isn't that the files say "stop" — they say "continue." The problem is
the agent doesn't have the downstream skill loaded, so it can't follow the
instruction. The agent reads "Continue at Phase 1" but has no way to execute
Phase 1 because the /design skill isn't in its context.
