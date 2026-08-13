```yaml
topic: chain-cardinality
chain_started: 2026-08-13T18:04:17Z
last_updated: 2026-08-13T21:33:13Z
phase_pointer: phase-3
exit: full-run
exit_artifacts:
  - docs/briefs/BRIEF-chain-cardinality.md
  - docs/prds/PRD-chain-cardinality.md
  - docs/designs/DESIGN-chain-cardinality.md
  - docs/plans/PLAN-chain-cardinality.md
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
    status: Accepted
    content_hash: 7869352009564a8e9b575c134412cc1db2eb1b7a
    captured_at: 2026-08-13T18:20:10Z
  prd:
    status: In Progress
    content_hash: 4274e046b166178feb9d514bee2a532d744789e8
    captured_at: 2026-08-13T20:27:07Z
  design:
    status: Planned
    content_hash: f4644806f4c28d68a30c49647d5e73faab05263a
    captured_at: 2026-08-13T21:33:13Z
  plan:
    status: Active
    content_hash: 7d1e72939d2f3116aba5f90d2a232e718b0a07e5
    captured_at: 2026-08-13T21:33:13Z
consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    carry_check:
      Problem Statement:
        target: Problem Statement
        carried: true
      User Outcome:
        target: Goals
        carried: true
      User Journeys:
        target: User Stories
        carried: false
      Scope Boundary:
        target: Requirements + Out of Scope
        carried: true
    verdict: keep
    finding: >-
      The mapping is total and stage 2 reached absorb, but the carry check failed on
      User Journeys. The BRIEF's four journeys are narratives that walk through a
      setting; the PRD's seven user stories carry every actor and want but compress
      those walk-throughs to one line each. The abort is the mechanism working. This
      is the same section, and the same reason, that aborted the absorb when PR #260
      dogfooded this judgment on its own chain.
  - hop: prd->design
    absorbable: false
    verdict: keep
    finding: >-
      Not absorbable, so stage 2 never runs. A DESIGN's required sections have no home
      for a PRD's Goals, User Stories, Requirements, Acceptance Criteria, or Out of
      Scope.
  - hop: design->plan
    absorbable: false
    verdict: keep
    finding: >-
      Not absorbable. A PLAN's required sections have no home for a DESIGN's Decision
      Drivers, Considered Options, Decision Outcome, Solution Architecture, Security
      Considerations, or Consequences.
worktree_rebases:
  - phase: brief
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-13T18:06:10Z
    notes: already current with origin/main; no rebase required
  - phase: prd
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-13T18:20:10Z
    notes: already current with origin/main; no rebase required
  - phase: design
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-13T20:27:07Z
    notes: already current with origin/main; no rebase required
  - phase: plan
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-13T21:33:13Z
    notes: already current with origin/main; no rebase required
```
