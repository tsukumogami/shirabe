# Phase 0: Setup + Context (Freeform Mode)

Brief conversational scoping to understand the design problem, then create the
design doc skeleton.

## Goal

Quickly establish enough context to start investigating approaches:
- Understand the technical problem through 2-4 targeted questions
- Establish scope boundaries (what's in, what's out)
- Create the design doc skeleton and the summary key

This is NOT a full /prd scoping session. Keep it brief -- the user already knows
what they want to design. You're getting just enough context for decision
decomposition in Phase 1.

## Resume Check

If key `work/summary.md` exists in `design-<topic>` (`koto context exists
design-<topic> work/summary.md`, after the open and adopt in SKILL.md's Session
and Keys), skip to Phase 1.

## Steps

### 0.1 Branch Setup

Under `/scope`'s dispatch key (SKILL.md, Output, "Under `/scope`"),
skip this step: work on the branch `/scope` invoked `/design` on, and
create or switch no branch.

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
---
schema: design/v1
status: Draft
problem: |
  <The problem from 0.3, 2-3 sentences>
---

# DESIGN: <Topic>

## Status

Draft

## Context and Problem Statement

<From scoping conversation>

## Decision Drivers

<From scoping conversation>

## Considered Options

Not written yet: a later /design phase replaces this line.

## Decision Outcome

Not written yet: a later /design phase replaces this line.

## Solution Architecture

Not written yet: a later /design phase replaces this line.

## Implementation Approach

Not written yet: a later /design phase replaces this line.

## Security Considerations

Not written yet: a later /design phase replaces this line.

## Consequences

Not written yet: a later /design phase replaces this line.
```

The skeleton is a complete Draft design that `shirabe validate` accepts, so
a validating pre-commit hook takes it. The six sections the run hasn't
reached hold only the stub marker defined in
`${CLAUDE_PLUGIN_ROOT}/skills/design/references/design-format.md` (The stub
marker); copy the line exactly. Each later phase replaces a section's marker
line with what it writes, never adds below it. Only step 6.5 writes
`decision` and `rationale` and moves the design to `Proposed`.

Commit the skeleton under the commit rule in
`${CLAUDE_PLUGIN_ROOT}/references/doc-check-steps.md` (Committing a partial
document): `docs(design): initialize design for <topic>`. The commit comes
before 0.5 writes the summary key, so a run whose summary key exists has
committed its skeleton.

### 0.5 Write the Summary Key

Write key `work/summary.md` in `design-<topic>` (`koto context add
design-<topic> work/summary.md`, the content on stdin):

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

## Quality Checklist

Before proceeding:
- [ ] On branch `docs/<topic>` (under `/scope`: the branch it invoked `/design` on)
- [ ] Problem statement is specific enough to evaluate approaches against
- [ ] Scope boundaries are clear (in and out)

## Artifact State

After this phase:
- Design doc committed at `status: Draft` with `problem` set and all nine
  sections: Context and Problem Statement and Decision Drivers written, the
  six later ones holding the stub marker
- Key `work/summary.md` in `design-<topic>`

## Next Phase

Proceed to Phase 1: Decision Decomposition (`phase-1-decomposition.md`)
