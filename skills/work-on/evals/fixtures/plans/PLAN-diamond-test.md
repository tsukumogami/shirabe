---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "eval fixture"
issue_count: 4
---

# PLAN: diamond-test

## Status

Draft

## Scope Summary

Minimal 4-issue diamond dependency fixture for eval scenarios.

## Issue Outlines

### Issue 1: feat: add auth service

**Complexity**: simple

**Goal**: Add a basic auth service.

**Acceptance Criteria**:
- [ ] Auth service module exists
- [ ] CI green

**Dependencies**: None.

---

### Issue 2: feat: add user model

**Complexity**: simple

**Goal**: Add user model definition.

**Acceptance Criteria**:
- [ ] User model file exists
- [ ] CI green

**Dependencies**: None.

---

### Issue 3: feat: wire auth to user model

**Complexity**: testable

**Goal**: Wire the auth service to the user model.

**Acceptance Criteria**:
- [ ] Auth service references user model
- [ ] CI green

**Dependencies**: Blocked by Issue 1, Issue 2.

---

### Issue 4: test: e2e auth flow

**Complexity**: testable

**Goal**: End-to-end auth flow test covering login and logout.

**Acceptance Criteria**:
- [ ] E2e test for login passes
- [ ] E2e test for logout passes
- [ ] CI green

**Dependencies**: Blocked by Issue 3.
