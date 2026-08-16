```yaml
topic: fold-record-removal
chain_started: 2026-08-16T15:27:30Z
last_updated: 2026-08-16T16:15:00Z
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
  - name: brief
    started_at: 2026-08-16T15:31:30Z
  - name: prd
    started_at: 2026-08-16T15:37:29Z
child_snapshots:
  brief:
    status: Accepted
    content_hash: 523051d58592cb0bb7aa9f35ed82ef1ad5b867b2
    captured_at: 2026-08-16T15:37:29Z
  prd:
    status: Accepted
    content_hash: 3d8ae9f010506b5c0ae4c8c68ac5a98313187210
    captured_at: 2026-08-16T16:15:00Z
consolidation_judgments:
  - hop: brief->prd
    stage: content
    verdict: keep
    rationale: >
      The BRIEF holds framing the PRD does not carry. Its four user journeys
      exercise distinct entry points and none survives in the PRD, whose user
      stories are role-scoped rather than journey-shaped. The PRD also cites
      the BRIEF as its upstream and restates only the problem, per the
      citation-vs-restatement rule, so folding would lose the journeys rather
      than compress them.
worktree_rebases:
  - phase: brief
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-16T15:31:30Z
  - phase: prd
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-16T15:37:29Z
  - phase: design
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-16T16:15:00Z
parent_orchestration:
  invoking_child: design
  suppress_status_aware_prompt: true
  rationale: fresh-chain
design_roster_predicates:
  p1_architectural_alternatives: fires
  p2_new_component_references: does-not-fire
  p3_complex_classification: fires
```
