---
topic: doc-vs-github-state-reconciliation
chain_started: 2026-06-05T20:11:49-04:00
last_updated: 2026-06-05T21:05:00-04:00
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
visibility: Public
execution_mode: auto
execution_mode_changed_at: 2026-06-05T21:05:00-04:00
plan_execution_mode: single-pr
post_scope_action: work-on
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
child_snapshots: {}
r6_verdicts:
  p1: fires
  p1_reason: "Issue #153 names gh-subprocess vs raw HTTP client as two acceptable implementations; trait-based vs fixture-based test strategy also open"
  p2: fires
  p2_reason: "New crates/shirabe-validate/src/gh.rs module — network/IO substrate has no precedent in the crate"
  p3: fires
  p3_reason: "Issue body: 'meaningfully heavier than FC07/FC08 because it is the first network-dependent check; authentication, rate limits, and offline-mode behavior all need explicit handling'"
r4_verdict: fires
r4_reason: "No upstream BRIEF at docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md"
r5_verdict: fires
r5_reason: "No upstream PRD at docs/prds/PRD-doc-vs-github-state-reconciliation.md"
worktree_rebases:
  - phase: brief
    upstream_commits: [ceb04fbf3b8b06e379a61511031e10ff7c2498a1]
    impact: informational
    rebased_at: 2026-06-05T20:25:00-04:00
    notes: "ceb04fb (PR #146) replaced scripts/transition-status.sh with `shirabe transition` subcommand; plugin cache refreshed to 0.9.1-dev which references the subcommand; clean rebase of one local commit (handoff doc)"
parent_orchestration:
  invoking_child: brief
  suppress_status_aware_prompt: true
  rationale: fresh-chain
---

# Scope state: doc-vs-github-state-reconciliation

Phase 0 complete. Slug validated against `^[a-z0-9-]+$`. Visibility detected
from `CLAUDE.md`. No existing state file or child wip intermediates for this
topic — fresh chain. No stale `parent_orchestration:` block to self-heal.

Phase 1 complete. No canonical-path artifacts exist for this topic. All four
gates fire; planned chain is `brief -> prd -> design -> plan`. Chain proposal
awaits author confirmation (Proceed / Adjust / Bail).
