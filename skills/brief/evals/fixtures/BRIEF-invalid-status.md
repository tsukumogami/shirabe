---
schema: brief/v1
status: Published
problem: |
  This fixture intentionally uses an invalid status value to exercise the
  FC02 rejection path. "Published" is not in the valid-statuses enum.
outcome: |
  The validate layer rejects a brief whose status is outside the valid set
  and lists the valid statuses in the error.
---

# BRIEF: invalid-status-fixture

## Status

Published

This fixture exists to exercise FC02. Status "Published" is not in the
valid-statuses enum (Draft, Accepted, Done).

## Problem Statement

This fixture exists to drive a validate failure. The frontmatter status
"Published" is outside the brief/v1 valid-statuses set, so FC02 fires.

## User Outcome

The validate layer rejects the invalid status and the error lists the valid
set (Draft, Accepted, Done).

## User Journeys

### Validate rejects the invalid status

A tester runs `shirabe validate` against this fixture and observes an FC02
error naming the valid statuses.

## Scope Boundary

IN:

- Exercising the FC02 invalid-status path.

OUT:

- Real feature framing. This is a test fixture only.
