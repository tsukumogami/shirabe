```yaml
topic: scope-artifact-persistence
chain_started: 2026-08-15T01:09:08Z
last_updated: 2026-08-15T16:30:00Z
phase_pointer: phase-3
exit: full-run
exit_artifacts:
  - docs/plans/PLAN-scope-artifact-persistence.md
plan_execution_mode: single-pr
planned_chain: [brief, prd, design, plan]
chain_ran: [brief, prd, design, plan]
chain_skipped: []
visibility: Public
execution_mode: auto
max_rounds: 5

child_snapshots:
  brief:
    path: docs/briefs/BRIEF-scope-artifact-persistence.md
    status: Accepted
    jury: content-quality PASS (after one FAIL and revision), structural-format PASS
  prd:
    path: docs/prds/PRD-scope-artifact-persistence.md
    status: In Progress
    jury: completeness PASS, clarity PASS, testability PASS (round 3)
    note: >-
      Requirements 22 -> 31, criteria 17 -> 40 across three jury rounds plus six
      post-acceptance amendments the design phase forced.
  design:
    path: docs/designs/DESIGN-scope-artifact-persistence.md
    status: Planned
    jury: architecture PASS (round 2), security closed with no blocking findings (round 3)
    note: >-
      Six decision questions, two on the full adversarial path with five
      persistent validators each.
  plan:
    path: docs/plans/PLAN-scope-artifact-persistence.md
    status: Active
    issue_count: 22
    execution_mode: single-pr

consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: false}
      Scope Boundary:    {target: Requirements + Out of Scope, carried: true}
    verdict: keep
    finding: >-
      The BRIEF's four User Journeys narrate the feature hop by hop; the PRD's
      five User Stories carry the same actors and outcomes in compressed form and
      drop the per-hop operational detail. That detail did independent work — it
      is what let the PRD jury check requirements against intended behaviour.
    note: >-
      Second recorded instance of the one absorbable hop failing its carry check
      on User Journeys; #260's own dogfood run failed the same way.

  - hop: prd->design
    absorbable: false
    verdict: keep
    finding: >-
      Not absorbable under the shipped mapping test: a DESIGN's required sections
      have no home for the PRD's Goals, User Stories, Requirements, Acceptance
      Criteria or Out of Scope. The verdict is reached without reading either
      document, which is the defect this chain's own PLAN exists to fix.

  - hop: design->plan
    absorbable: false
    verdict: keep
    finding: >-
      Not absorbable under the shipped mapping test: a single-pr PLAN's five
      required sections have no home for any of the DESIGN's reasoning sections.
      Same structural verdict, same absence of a content judgment.

dogfood_note: >-
  This chain ran under the mechanism it replaces, so it leaves all four artifacts
  regardless of what the new judgment would have decided. Two of its three hops
  reached `keep` without either document being read. Under the shipped design the
  prd->design and design->plan hops would each have been decided against the two
  bodies; whether either would have folded is unknowable from here, which is the
  point.
```
