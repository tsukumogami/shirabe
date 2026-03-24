---
status: Proposed
problem: |
  The /plan skill's Phase 6 review is passive — it checks coverage and dependency
  structure but does not challenge whether the plan would catch incorrect implementations.
  A new /review-plan skill must replace Phase 6 with adversarial review that maps
  findings to concrete loop-back targets, produces a machine-readable verdict artifact
  consumed by /plan, and is also callable standalone like /decision.
---

# DESIGN: Plan Review

## Status

Proposed

## Context and Problem Statement

The shirabe pipeline runs explore → prd → design → plan → work-on. The `/plan` skill
has a Phase 6 review that checks completeness and sequencing, but it's a passive
completeness check — not an adversarial challenge. Issue #19 surfaced three failure
modes this review would not have caught:

1. A design contradiction (two sections of the design doc specifying different method
   names for the same purpose) was inherited unchanged into the plan, producing two
   issues with mutually exclusive behaviors.
2. Acceptance criteria were anchored to fixture data, meaning both the correct and
   incorrect implementation passed the same test.
3. A must-run QA scenario was classified as low-priority and deferred, removing the
   only end-to-end validation before implementation started.

None of these are detectable by asking "does the issue set cover the design?" — the
current review question. They require asking "would this plan catch the wrong
implementation?"

The skill needs to sit symmetrically between `/plan` (creates all issues for a plan)
and `/work-on` (implements one issue at a time), operating at plan level before any
single issue is implemented. It should be callable standalone (full adversarial mode)
or as a required sub-operation inside `/plan` (fast-path mode), analogous to how
`/decision` is called by `/design`.

## Decision Drivers

- **Loop-back capability**: when the review finds critical issues, `/plan` must loop
  back to the appropriate earlier phase rather than proceeding to issue creation
- **Deterministic cleanup**: each finding category maps to a specific loop target, and
  clearing the right wip/ artifacts causes the existing resume logic to re-enter at
  the correct phase — no new resume infrastructure should be needed
- **Machine-readable verdict**: the artifact must be parseable by `/plan` to determine
  whether to proceed or loop back, and which phase to re-enter
- **Two-tier execution model**: fast-path inside `/plan` (single agent, low latency)
  and full adversarial mode when called standalone (multi-agent, higher thoroughness)
- **Analogous to /decision**: the sub-operation interface, structured verdict artifact,
  and two-tier complexity model from `/decision` are the structural target to match

## Decisions Already Made

- `/work-on` Phase 0 integration is deferred: the discovery problem (issue number →
  review artifact path) is unsolved, and extending `extract-context.sh` introduces
  a new coupling between skills that is out of scope for the initial design.
- The review artifact lives in `wip/` only (not committed to the repo), consistent
  with other intermediate skill artifacts.
- Four mandatory review categories cover all three issue #19 failure modes:
  - A (Scope Gate): plan size vs. design complexity
  - B (Design Fidelity): whether the plan inherits design contradictions
  - C (AC Discriminability): whether ACs would pass for the wrong implementation
  - D (Sequencing/Priority Integrity): whether must-run QA scenarios are deprioritized
  Category E (completeness beyond coverage) is conditional on design/prd input types.
- Loop-back target mapping is deterministic by finding category:
  - Design contradiction → Phase 1 Analysis
  - Coverage gap, atomicity violation → Phase 3 Decomposition
  - AC quality failure → Phase 4 Agent Generation
  - Dependency errors → Phase 5 Dependencies
