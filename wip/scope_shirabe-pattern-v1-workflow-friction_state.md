---
topic: shirabe-pattern-v1-workflow-friction
visibility: Public
chain_started: 2026-06-06T03:35:13Z
last_updated: 2026-06-06T03:35:13Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
child_snapshots:
  brief:
    status: Accepted
    content_hash: 173e7afead8ba8dbe2e9065a320a4f5fb97217d6
    captured_at: 2026-06-06T03:45:00Z
    commit_sha: 5d2d085
  prd:
    status: Accepted
    content_hash: 0b1f0b39744e243b116e6fcca0c6b9ca5d9ebe39
    captured_at: 2026-06-06T05:30:00Z
    commit_sha: 49c0e1a
plan_execution_mode: single-pr
parent_orchestration:
  invoking_child: prd
  suppress_status_aware_prompt: true
  rationale: fresh-chain
addressed_issues:
  - tsukumogami/shirabe#156
  - tsukumogami/shirabe#159
  - tsukumogami/shirabe#162
---

# /scope state — shirabe-pattern-v1-workflow-friction

Tracks state for the /scope run resolving three pattern-v1 workflow-friction bugs identified during shirabe v0.7.0/0.7.1-dev dogfooding:

- shirabe#156 (C2) — `plan-to-tasks.sh` single-pr `**Dependencies:**` regex drops all deps silently
- shirabe#159 (C5) — `/design` Phase 0 + `/plan` Phase 1 status-gate asymmetry vs `/prd`'s brief-handoff
- shirabe#162 (C8) — `/work-on` doesn't run worktree-discipline between commits

Branched off post-PR-151 main (be6a37c, v0.9.0 + 0.9.1-dev). Single-pr execution mode.
