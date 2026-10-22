---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "eval fixture"
issue_count: 3
---

# PLAN: lead-shape-test

## Status

Draft

## Scope Summary

Three-issue linear fixture for the lead-shape eval: each issue builds on the
one before it, so the owning session details issues 2 and 3 from what landed.

## Decomposition Strategy

Linear: loader, then validation, then the page that documents both.

## Issue Outlines

### Issue 1: feat: add a config loader

**Complexity**: simple

**Goal**: Add a module that reads a TOML config file into a struct.

**Acceptance Criteria**:
- [ ] Config loader module exists
- [ ] CI green

**Dependencies**: None.

---

### Issue 2: feat: validate the loaded config

**Complexity**: testable

**Goal**: Reject a config whose required keys are missing.

**Acceptance Criteria**:
- [ ] Validation names each missing key
- [ ] CI green

**Dependencies**: Blocked by Issue 1.

---

### Issue 3: docs: document the config file

**Complexity**: simple

**Goal**: Document the config file's keys and the validation errors.

**Acceptance Criteria**:
- [ ] The config page lists every key and error
- [ ] CI green

**Dependencies**: Blocked by Issue 2.

## Implementation Sequence

Issue 1, then Issue 2, then Issue 3.
