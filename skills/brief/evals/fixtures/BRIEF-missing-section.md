---
schema: brief/v1
status: Draft
problem: |
  This fixture intentionally omits the User Journeys required section so
  shirabe validate emits an FC04 error. It exists to drive a validate
  failure, not to frame a real feature.
outcome: |
  The validate layer reports the missing required section by name when the
  body omits one of the five brief sections.
---

# BRIEF: missing-section-fixture

## Status

Draft

This fixture intentionally omits the User Journeys section to exercise the
FC04 missing-required-section rejection path in the brief evals.

## Problem Statement

This fixture exists to drive a validate failure. It omits the User Journeys
section so that FC04 fires and names the missing section.

## User Outcome

The validate layer rejects a brief that is missing a required section and
the error names the section that is absent.

## Scope Boundary

IN:

- Exercising the FC04 missing-required-section path.

OUT:

- Real feature framing. This is a test fixture only.
