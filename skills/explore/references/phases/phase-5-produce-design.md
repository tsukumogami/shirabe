# Phase 5: Design Doc Handoff

Write two files. Synthesize content from the exploration findings.

**1. Design doc skeleton** at `docs/designs/DESIGN-<topic>.md`:

```markdown
---
status: Proposed
problem: |
  <1 paragraph from exploration findings. Be specific about what needs
  to be decided and why.>
---

# DESIGN: <Topic>

## Status

Proposed

## Context and Problem Statement

<From exploration findings. Cover what prompted the exploration, what was
discovered, and what architectural or technical decisions remain open.>

## Decision Drivers

<From exploration findings. List the factors that should influence the
technical decision. Pull from tensions, constraints, and user priorities
surfaced during exploration.>

## Decisions Already Made

<If wip/explore_<topic>_decisions.md exists, include the accumulated
decisions here. These are choices settled during exploration that the
design should treat as constraints, not reopen. If the decisions file
doesn't exist, omit this section.>
```

**2. Summary file** at `wip/design_<topic>_summary.md`:

```markdown
# Design Summary: <topic>

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** <1-2 sentences>
**Constraints:** <key constraints from exploration>

## Current Status
**Phase:** 0 - Setup (Explore Handoff)
**Last Updated:** <date>
```

After writing both files, hand off to /design:

1. Read the /design skill: `../design/SKILL.md`
2. Continue at Phase 1 (Approach Discovery). Phase 0 (Setup) is done -- the
   handoff artifacts fill that role.

Commit before handoff: `docs(explore): hand off <topic> to /design`

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `docs/designs/DESIGN-<topic>.md` (new)
- `wip/design_<topic>_summary.md` (new)
- Session continues in /design at Phase 1
