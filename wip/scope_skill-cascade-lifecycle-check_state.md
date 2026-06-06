---
topic: skill-cascade-lifecycle-check
last_updated: 2026-06-06
phase_pointer: phase-2-chain-orchestration
exit: null
exit_artifacts: []
visibility: Public
chain_plan:
  - brief: Mandatory
  - prd: Mandatory-with-auto-skip
  - design: Mandatory
  - plan: Mandatory
plan_execution_mode: single-pr
child_snapshots: {}
worktree_rebases: []
worktree_divergences: []
parent_orchestration: null
---

# Scope State: skill-cascade-lifecycle-check

Auto-run scope chain for shirabe issue #175. Stacks on PR #174
(`feat/lifecycle-draft-ready`). Drives BRIEF → PRD → DESIGN → PLAN to
terminal full-run exit with a single-pr PLAN that /work-on executes.
