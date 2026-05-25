---
schema: brief/v1
status: Draft
problem: |
  Authors entering the tactical chain partway up have no codified framing
  step between a sequenced roadmap feature and a PRD's requirements. The
  problem the feature solves, the user outcome, the journeys, and the scope
  go unwritten until the PRD smuggles them in alongside requirements.
outcome: |
  An author frames a named feature — its problem, outcome, journeys, and
  scope boundary — before requirements exist, and the framing resolves
  cleanly downstream when the PRD picks it up.
---

# BRIEF: example-happy-path

## Status

Draft

This fixture is a happy-path example used by the brief skill's evals to
exercise validate's structural happy path. All five required sections are
present and the body status word matches the frontmatter.

## Problem Statement

Authors move from a roadmap line item straight to a PRD with no place to
write down why the feature exists before its requirements do. The framing —
the gap a user feels, the outcome they should reach, the paths through the
feature, the boundary of what it holds in and pushes out — has nowhere to
live, so it either goes unwritten or gets entangled with requirements in the
PRD. A reader landing cold cannot tell the problem from the solution.

## User Outcome

An author with a named-but-unframed feature writes down the problem and the
outcome a user should experience, walks the concrete journeys, and draws the
scope boundary — all before a single requirement is written. The downstream
PRD picks the framing up directly and the requirements conversation starts
from a settled problem rather than re-deriving it.

## User Journeys

### Cold standalone framing

A PRD author with a named feature but no written framing invokes
`/brief checkout-flow`. The skill scopes the problem and outcome
conversationally, drafts the four content sections, and the author leaves
with a Draft brief ready for review.

### Downstream consumer tracing upstream

A PRD author opens a Draft PRD whose `upstream:` points at this brief, reads
the framing to ground the requirements, and confirms the problem the PRD
answers matches the problem the brief framed.

### Review-and-accept pass

A reviewer reads a Draft brief, confirms the Phase 4 jury returned all-PASS,
and approves the Draft -> Accepted transition so the framing locks before
the PRD begins.

## Scope Boundary

IN:

- Framing a single named feature: its problem, outcome, journeys, and scope.
- A two-reviewer jury (content quality, structural format) before acceptance.
- A Draft -> Accepted -> Done lifecycle with no directory movement.

OUT:

- PRD-level requirements, acceptance criteria, and user stories — those live
  one altitude down in the PRD the brief feeds.
- Feature sequencing against other features — that is upstream roadmap work.
- The downstream PRD's own authoring workflow — a separate skill picks the
  accepted brief up as upstream.
