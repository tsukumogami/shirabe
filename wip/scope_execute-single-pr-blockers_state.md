```yaml
topic: execute-single-pr-blockers
chain_started: 2026-08-14T15:49:12Z
last_updated: 2026-08-14T16:42:00Z
phase_pointer: phase-3
exit: full-run
exit_artifacts:
  - docs/plans/PLAN-execute-single-pr-blockers.md
  - docs/designs/DESIGN-execute-single-pr-blockers.md
  - docs/prds/PRD-execute-single-pr-blockers.md
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
visibility: Public
execution_mode: auto
max_rounds: 5
source_issue: tsukumogami/shirabe#270
plan_execution_mode: single-pr
consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: true}
      Scope Boundary:    {target: Requirements + Out of Scope, carried: true}
    verdict: absorb
    absorbed: docs/briefs/BRIEF-execute-single-pr-blockers.md
    into: docs/prds/PRD-execute-single-pr-blockers.md
  - hop: prd->design
    absorbable: false
    verdict: keep
    reason: >-
      DESIGN has no home for a PRD's Goals, User Stories, Requirements,
      Acceptance Criteria, or Out of Scope.
  - hop: design->plan
    absorbable: false
    verdict: keep
    reason: >-
      PLAN has no home for a DESIGN's Decision Drivers, Considered Options,
      Decision Outcome, Solution Architecture, Security Considerations, or
      Consequences.
child_snapshots:
  prd:
    status: In Progress
    captured_at: 2026-08-14T16:20:00Z
  design:
    status: Accepted
    captured_at: 2026-08-14T16:35:00Z
  plan:
    status: Draft
    captured_at: 2026-08-14T16:42:00Z
```
