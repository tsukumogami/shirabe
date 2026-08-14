```yaml
topic: upstream-link-legality
chain_started: 2026-08-14T00:00:00Z
last_updated: 2026-08-14T00:00:00Z
phase_pointer: phase-3
exit: full-run
exit_artifacts:
  - docs/briefs/BRIEF-upstream-link-legality.md
  - docs/prds/PRD-upstream-link-legality.md
  - docs/designs/DESIGN-upstream-link-legality.md
  - docs/plans/PLAN-upstream-link-legality.md
visibility: Public
plan_execution_mode: single-pr
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran:
  - brief
  - prd
  - design
  - plan
child_snapshots:
  brief:
    path: docs/briefs/BRIEF-upstream-link-legality.md
    status: Accepted
    jury: all-PASS
  prd:
    path: docs/prds/PRD-upstream-link-legality.md
    status: Accepted
    jury: all-PASS-after-two-revision-rounds
  plan:
    path: docs/plans/PLAN-upstream-link-legality.md
    status: Active
    execution_mode: single-pr
    review: PASS-after-two-revision-rounds
  design:
    path: docs/designs/DESIGN-upstream-link-legality.md
    status: Accepted
    jury: all-PASS-after-two-revision-rounds
consolidation_judgments:
  - hop: brief-to-prd
    verdict: keep
    carry_check:
      - section: Problem Statement
        carried: false
        finding: >-
          The brief argues the two defects are one problem because they fail on
          different properties, are introduced by different actors, and a fix
          for either leaves the other untouched. The PRD carries the first
          clause only; the other two do not arrive, and they are the argument
          for why a direction check and a lifetime check ship together.
      - section: User Outcome
        carried: true
        landed_in: Goals
      - section: User Journeys
        carried: true
        landed_in: User Stories
      - section: Scope Boundary
        carried: true
        landed_in: Requirements and Out of Scope
    reason: >-
      A failed carry aborts the absorb. Both artifacts stay on disk.
phase_1_result: empty-cold-start
shape_predicates:
  p1_architectural_alternatives: fires
  p2_new_component_references: does-not-fire
  p3_complex_classification: fires
```
