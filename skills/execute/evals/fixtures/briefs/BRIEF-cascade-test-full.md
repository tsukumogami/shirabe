---
schema: brief/v1
status: Accepted
upstream: skills/execute/evals/fixtures/roadmaps/ROADMAP-cascade-test.md
problem: |
  The full-chain cascade fixtures form PLAN -> DESIGN -> PRD -> ROADMAP with no
  BRIEF, so the cascade's BRIEF -> Done transition is never exercised in the
  eval suite. This fixture frames a placeholder feature so the full chain has a
  BRIEF node to transition.
outcome: |
  The cascade transitions this BRIEF Accepted -> Done in place and continues the
  upstream walk to its ROADMAP feature.
---

# BRIEF: cascade-test-full

## Status

Accepted

This fixture is the BRIEF node of the full-chain cascade eval. It frames a
placeholder feature so the cascade's transition_brief step is exercised.

## Problem Statement

The full-chain cascade fixtures form PLAN -> DESIGN -> PRD -> ROADMAP with no
BRIEF, so the cascade's BRIEF -> Done transition is never exercised in the eval
suite. The gap this fixture fills is a BRIEF node sitting between the PRD and
the ROADMAP so the full chain reads PLAN -> DESIGN -> PRD -> BRIEF -> ROADMAP.

## User Outcome

A cascade run over the full chain reaches this BRIEF, transitions it
Accepted -> Done in place without moving the file, and continues the upstream
walk to the ROADMAP feature it points at.

## User Journeys

### Cascade transitions the BRIEF

The cascade walks up from the PRD, reaches this BRIEF, flips its status to Done
in both frontmatter and body, and continues to the upstream ROADMAP.

### Downstream PRD tracing upstream

The full-chain PRD's upstream points at this BRIEF; a reader follows the link
to confirm the chain is self-contained under the execute fixtures tree.

## Scope Boundary

IN:

- Acting as the BRIEF node of the full-chain cascade eval fixture.
- Exercising the cascade's Accepted -> Done BRIEF transition.

OUT:

- Real feature framing. This is a test fixture only.
- Any downstream requirements work, which lives in the PRD this BRIEF feeds.
