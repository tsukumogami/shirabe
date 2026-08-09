```yaml
topic: scope-consolidation-over-skipping
chain_started: 2026-08-09T00:00:00Z
last_updated: 2026-08-09T00:00:00Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
visibility: Public
execution_mode: auto
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_ran:
  - brief
chain_skipped: []
child_snapshots:
  brief:
    status: Draft
    content_hash: 8e2ba349d92a07dd7aacad553ef4bf079215fbbc
    captured_at: 2026-08-09T00:00:00Z
gate_verdicts:
  brief: "fires (R4 mandatory-with-auto-skip: no BRIEF at docs/briefs/BRIEF-scope-consolidation-over-skipping.md)"
  prd: "fires (R5: no PRD at docs/prds/PRD-scope-consolidation-over-skipping.md)"
  design: "fires (R7 shape-dependent: P1 fires - six named architectural alternatives left open by the task brief; P2 does-not-fire - no new binary, service, or substrate; P3 fires - brief states the design questions are the work)"
  plan: "fires (ALWAYS)"
cold_start_projection: "slug carries the `consolidation` projection keyword; projected PRD-altitude work shape is a producer-side workflow-contract change across the tactical chain's parent skill and its four children"
validator_passthrough:
  brief: "exit 0 (clean), --visibility=public"
worktree_rebases: []
parent_orchestration:
  invoking_child: prd
  suppress_status_aware_prompt: true
  rationale: fresh-chain
```
