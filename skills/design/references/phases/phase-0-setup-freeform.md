# Phase 0: Setup + Context (Freeform Mode)

Brief conversational scoping to understand the design problem, then create the
design doc skeleton.

## Goal

Quickly establish enough context to start investigating approaches:
- Understand the technical problem through 2-4 targeted questions
- Establish scope boundaries (what's in, what's out)
- Create the design doc skeleton and wip/ summary

This is NOT a full /prd scoping session. Keep it brief -- the user already knows
what they want to design. You're getting just enough context for decision
decomposition in Phase 1.

## Resume Check

If `wip/design_<topic>_summary.md` exists, skip to Phase 1.

## Steps

### 0.1 Branch Setup

If already on a `docs/<topic>` branch, skip branch creation. Otherwise:
- Create `docs/<topic>` (kebab-case) from latest main
- Confirm you're on the correct branch

### 0.2 Quick Scoping Conversation

Ask 2-4 targeted questions to understand the problem. Adapt to what the user
already told you in `$ARGUMENTS`. Don't ask questions whose answers are obvious
from the topic.

Focus on:
- What specific technical problem needs solving?
- What constraints or requirements exist?
- What's the scope boundary (in vs out)?
- Is there existing code or architecture this affects?

Stop when you have enough context to decompose the problem into decision questions.
This should take 1-2 turns, not a long interview.

### 0.3 Confirm Understanding

Present a brief summary:
1. **Problem** (2-3 sentences): What technical problem we're solving
2. **Scope**: What's in, what's out
3. **Key constraints**: Anything that limits solution space

Ask: "Does this capture it? Anything I'm missing?"

Incorporate feedback before proceeding.

### 0.4 Create Design Doc Skeleton

Write the initial design doc to `docs/designs/DESIGN-<topic>.md`:

```markdown
# DESIGN: <Topic>

## Status

Proposed

## Context and Problem Statement

<From scoping conversation>

## Decision Drivers

<From scoping conversation>
```

### 0.5 Create wip/ Summary

Write `wip/design_<topic>_summary.md`:

```markdown
# Design Summary: <topic>

## Input Context (Phase 0)
**Source:** Freeform topic
**Problem:** <1-2 sentences>
**Constraints:** <key constraints>

## Current Status
**Phase:** 0 - Setup (Freeform)
**Last Updated:** <date>
```

Commit: `docs(design): initialize design for <topic>`

## Quality Checklist

Before proceeding:
- [ ] On branch `docs/<topic>`
- [ ] Problem statement is specific enough to evaluate approaches against
- [ ] Scope boundaries are clear (in and out)

## Artifact State

After this phase:
- Design doc exists with: Status, Context and Problem Statement, Decision Drivers
- `wip/design_<topic>_summary.md` exists

## Next Phase

Proceed to Phase 1: Decision Decomposition (`phase-1-decomposition.md`)
