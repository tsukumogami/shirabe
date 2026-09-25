---
schema: plan/v1
status: Active
execution_mode: coordinated
tracking_level: none
split_rationale: |
  Hard Constraint. The library change and the application change live in two
  repositories, so they land as two PRs.
milestone: "Coordinated multi-repo test"
issue_count: 2
---

# PLAN: coord-multi-test

## Status

Active

An eval fixture: a coordinated PLAN at `tracking_level: none` whose two work
items sit in two repositories, each with `Group: default`, so each repository
is one PR node. Neither waits on the other.

## Scope Summary

Add a parser to the library repository and a status page to the application
repository.

## Decomposition Strategy

One PR node per repository; the two are independent.

## Issue Outlines

### Issue 1: feat(repo): add the parser

**Repo**: eval-org/eval-repo

**Group**: default

**Goal**: Add `parse()`.

**Acceptance Criteria**:
- [ ] `parse()` accepts the documented input

**Dependencies**: None

### Issue 2: feat(app): add the status page

**Repo**: eval-org/eval-app

**Group**: default

**Goal**: Add a status page.

**Acceptance Criteria**:
- [ ] the status page renders

**Dependencies**: None

## Dependency Graph

```mermaid
graph TD
    I1["Issue 1"]
    I2["Issue 2"]
```

## Implementation Sequence

Issue 1 and Issue 2 in either order.
