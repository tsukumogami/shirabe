---
schema: plan/v1
status: Draft
execution_mode: single-pr
upstream:
  - skills/execute/evals/fixtures/designs/DESIGN-cascade-test-new-shape.md
  - skills/execute/evals/fixtures/roadmaps/ROADMAP-cascade-test.md
milestone: "Cascade Test"
issue_count: 1
---

# PLAN: Cascade Test New Shape

## Status

Draft

## Scope Summary

Test fixture for the e2e cascade eval, in the shape the upstream-legality rule
produces: the PLAN names its DESIGN and the ROADMAP, and no durable artifact in
the chain names the ROADMAP at all.

## Decomposition Strategy

Horizontal. The fixture exists to exercise the cascade's walk, not a real
decomposition.

## Issue Outlines

### Issue 1: test issue

**Goal**: Exercise the cascade against a chain in the new shape.

**Acceptance Criteria**:
- [ ] The cascade reaches the ROADMAP through the PLAN.

**Dependencies**: None

## Implementation Sequence

One issue, no sequencing.
