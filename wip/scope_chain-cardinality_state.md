```yaml
topic: chain-cardinality
chain_started: 2026-08-13T18:04:17Z
last_updated: 2026-08-13T20:27:07Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
visibility: Public
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran:
  - brief
  - prd
child_snapshots:
  brief:
    status: Accepted
    content_hash: 7869352009564a8e9b575c134412cc1db2eb1b7a
    captured_at: 2026-08-13T18:20:10Z
  prd:
    status: Accepted
    content_hash: 4274e046b166178feb9d514bee2a532d744789e8
    captured_at: 2026-08-13T20:27:07Z
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
      setting - a plan whose DESIGN shares a PRD with eight siblings, an author
      partway through a run whose upstream turns out to have another consumer. The
      PRD's seven user stories carry every actor and every want, but compress those
      walk-throughs to one line each. The abort is the mechanism working, not a hop
      that was never considered. Note this is the same section, and the same reason,
      that aborted the absorb when PR #260 dogfooded this judgment on its own chain.
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
parent_orchestration:
  invoking_child: design
  suppress_status_aware_prompt: true
  rationale: fresh-chain
```
