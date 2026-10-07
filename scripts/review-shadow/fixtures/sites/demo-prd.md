---
schema: prd/v1
status: Draft
problem: |
  Authors lose track of which drafts a reviewer has read.
goals: |
  Every draft shows whether a reviewer has read it.
---

# PRD: demo

## Status

Draft

## Acceptance Criteria

Listing (R1, R2):

- [ ] `drafts list` prints one line per open draft.
- [ ] A draft a reviewer opened shows `read` on its line,
      and one nobody opened shows `unread`.

Errors (R3):

- [x] With no drafts, `drafts list` exits 0 and prints nothing.

## Out of Scope

Notifications.
