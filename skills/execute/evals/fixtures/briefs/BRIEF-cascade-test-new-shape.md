---
schema: brief/v1
status: Accepted
problem: |
  The cascade fixtures were authored when a BRIEF recorded the ROADMAP it was
  framed against, which is the shape the legality rule now forbids. Nothing in
  the eval suite exercises a chain authored under the current rule.
outcome: |
  A chain in which no durable artifact names the ROADMAP, and the PLAN carries
  it instead, cascades exactly as the old shape did: the roadmap feature is
  updated and the roadmap is deleted under the same conditions.
upstream: skills/execute/evals/fixtures/strategies/STRATEGY-cascade-test.md
---

# BRIEF: Cascade Test New Shape

## Status

Accepted

This BRIEF records the STRATEGY it resolved one hop up from its grounding
ROADMAP, which is the point of the fixture. It never names the ROADMAP itself —
that is deleted when its features land, and the PLAN names it instead. The walk
terminates on the STRATEGY, and the cascade stops there rather than
transitioning it.

## Problem Statement

Test fixture for the cascade eval — the BRIEF node of a chain authored under the
upstream-legality rule. It records a STRATEGY rather than the ROADMAP, so the
cascade must reach the ROADMAP through the PLAN rather than through this
document, and must stop cleanly on the STRATEGY rather than reporting it as an
unrecognized node.

## User Outcome

The cascade transitions this BRIEF Accepted to Done in place, and reaches the
ROADMAP without ever walking through it.

## User Journeys

### The cascade walks a new-shape chain

The cascade starts from the PLAN, transitions this BRIEF to Done, and reaches
the ROADMAP through the PLAN's own second upstream entry.

## Scope Boundary

**IN:** the BRIEF node of the new-shape cascade fixture chain.

**OUT:** the old-shape chain, which is kept frozen in
`BRIEF-cascade-test-full.md` as the evidence that a pre-existing corpus still
cascades.
