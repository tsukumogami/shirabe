---
status: Proposed
upstream: docs/prds/PRD-complexity-routing-expansion.md
problem: |
  placeholder
decision: |
  placeholder
rationale: |
  placeholder
---

# DESIGN: Complexity Routing Expansion

## Status

Proposed

## Context and Problem Statement

The /explore skill routes work through three complexity levels
(Simple/Medium/Complex) but the pipeline supports five. Two levels are
missing from the routing tables: Trivial (fire-and-forget fixes that don't
need issues or artifacts) and Strategic (VISION/Roadmap work that spawns
per-feature sub-pipelines).

The technical problem is content design, not code. Three routing-related
sections in `/explore/SKILL.md` need to expand consistently:

1. **Complexity-Based Routing table** — the primary target. Currently 3
   rows, needs 5. Each row needs observable signals that agents can detect
   from user input, and a recommended command path.

2. **Artifact Type Routing Guide** — situation-based advice. Already has a
   trivial row ("This is simple, just do it" -> `/work-on`) but no
   strategic row.

3. **Quick Decision Table** — question-based routing. Missing both trivial
   and strategic entries.

A secondary issue: Phase 4's crystallize step says "five supported types"
but the crystallize framework defines ten. VISION is missing from Phase 4's
explicit type list.

## Decision Drivers

- Signals must be observable from user input (an agent can classify without
  running the full workflow first)
- Adjacent levels need tiebreaker rules to resolve boundary ambiguity
- Existing Simple/Medium/Complex semantics must not change (backward
  compatible)
- All changes are markdown edits to /explore skill files
- The three routing sections must tell a consistent story
- Detection should be top-down (Strategic first, Trivial last) to avoid
  the costlier misclassification of treating strategic work as simple
