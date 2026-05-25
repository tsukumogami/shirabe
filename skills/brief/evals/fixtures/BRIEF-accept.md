---
schema: brief/v1
status: Draft
problem: |
  This fixture is a valid Draft brief used as the starting state for the
  lifecycle transition test. It frames a placeholder feature well enough to
  satisfy every structural check so the transition path is the only thing
  under test.
outcome: |
  The transition script moves the brief Draft -> Accepted -> Done in place,
  updating both the frontmatter and the body status word without moving the
  file out of docs/briefs/.
---

# BRIEF: accept-fixture

## Status

Draft

This fixture starts at Draft and is the input for the Draft -> Accepted and
Accepted -> Done transition tests. The brief never leaves docs/briefs/.

## Problem Statement

A lifecycle test needs a structurally valid Draft brief to transition. The
gap this fixture fills is having a stable starting state whose only purpose
is to exercise the transition script's status rewrite, not to frame a real
feature.

## User Outcome

A tester runs the transition script against this brief and the status word
advances Draft -> Accepted -> Done in both the frontmatter and the body,
with the file staying at its original path.

## User Journeys

### Accept the draft

A reviewer runs the transition script with target Accepted; the frontmatter
and body status both become Accepted and the file stays in place.

### Mark the accepted brief done

After the downstream PRD operationalizes the brief, a maintainer runs the
transition script with target Done; the status advances to the terminal
state in place.

## Scope Boundary

IN:

- Exercising the Draft -> Accepted and Accepted -> Done transitions.
- Confirming no directory movement on any transition.

OUT:

- Real feature framing. This is a test fixture only.
- Sunset or any downgrade path — the brief lifecycle has neither.
