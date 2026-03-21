# Phase 0: Setup + Context (PRD Mode)

Extract problem context from an accepted PRD and establish the design doc skeleton.

## Goal

Translate the PRD's "what/why" into implementation-oriented framing:
- Synthesize (not copy-paste) the problem statement into technical terms
- Derive decision drivers from requirements and constraints
- Create the design doc skeleton and wip/ summary
- Transition the PRD status to "In Progress"

## Resume Check

If `wip/design_<topic>_summary.md` exists, skip to Phase 1.

## Steps

### 0.1 Branch Setup

If already on a `docs/<topic>` branch, skip branch creation. Otherwise:
- Create `docs/<topic>` (kebab-case) from latest main
- Confirm you're on the correct branch

### 0.2 Read PRD

Read the PRD file from the path provided in `$ARGUMENTS`. Verify:
- File exists and is a valid PRD (`docs/prds/PRD-*.md`)
- Status is "Accepted"

If the PRD status is not "Accepted", STOP and inform the user. Design work requires
an accepted PRD.

### 0.3 Synthesize Problem Statement

Write the design doc's "Context and Problem Statement" section. Translate the PRD's
problem framing into implementation terms:
- What technical challenge does this create?
- What system boundaries are involved?
- What existing code/architecture is affected?

Don't copy the PRD verbatim. A design doc reader needs a different framing: the PRD
explains what to build and why; the design doc explains what technical problem needs
solving.

### 0.4 Derive Decision Drivers

Extract decision drivers from the PRD's requirements and constraints. Add
implementation-specific drivers (performance, compatibility, maintainability) that
the PRD may not cover.

Write the "Decision Drivers" section in the design doc.

### 0.5 Create Design Doc Skeleton

Write the initial design doc to `docs/designs/DESIGN-<topic>.md`:

```markdown
---
upstream: docs/prds/PRD-<name>.md
---

# DESIGN: <Topic>

## Status

Proposed

## Context and Problem Statement

<Synthesized from PRD in step 0.3>

## Decision Drivers

<Derived from PRD in step 0.4>
```

The `upstream` field creates a machine-readable link from the design doc back to
its source PRD.

### 0.6 Transition PRD Status

Update the PRD's status from "Accepted" to "In Progress" (both frontmatter and body).
Commit: `docs(prd): mark <prd-name> in progress`

### 0.7 Create wip/ Summary

Write `wip/design_<topic>_summary.md`:

```markdown
# Design Summary: <topic>

## Input Context (Phase 0)
**Source PRD:** docs/prds/PRD-<name>.md
**Problem (implementation framing):** <1-2 sentences>

## Current Status
**Phase:** 0 - Setup (PRD)
**Last Updated:** <date>
```

Commit: `docs(design): initialize design for <topic> from PRD`

## Quality Checklist

Before proceeding:
- [ ] On branch `docs/<topic>`
- [ ] Problem statement is in implementation terms (not a PRD copy)
- [ ] Decision drivers include both PRD-derived and implementation-specific factors

## Artifact State

After this phase:
- Design doc exists with: Status, Context and Problem Statement, Decision Drivers
- PRD is marked "In Progress"
- `wip/design_<topic>_summary.md` exists

## Next Phase

Proceed to Phase 1: Approach Discovery (`phase-1-approach-discovery.md`)
