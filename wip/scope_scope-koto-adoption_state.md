```yaml
topic: scope-koto-adoption
chain_started: 2026-08-20T22:14:07Z
last_updated: 2026-08-20T23:05:00Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain: [brief, prd, design, plan]
chain_ran:
  - child: brief
    started_at: 2026-08-20T22:14:07Z
  - child: prd
    started_at: 2026-08-20T22:26:00Z
chain_skipped: []
consolidation_judgments:
  - hop: brief->prd
    upstream: docs/briefs/BRIEF-scope-koto-adoption.md
    survivor: docs/prds/PRD-scope-koto-adoption.md
    preflight: clean
    verdict: keep
    finding: >-
      The BRIEF's Problem Statement carries three explicit misdiagnoses --
      that the reasoning was not unavailable, that the argument is not
      misfiled, and that prose cannot finish this. The third is the argument
      for reaching past prose to a substrate at all. The PRD states that
      conclusion and does not argue it, because arguing it is framing-altitude
      work the PRD deliberately does not carry. Compressing the BRIEF into a
      contribution section would lose it. Decided against the two bodies; no
      type contract was read.
visibility: Public
consumed_handoff: wip/scope_scope-koto-adoption_handoff.md
child_snapshots:
  brief:
    path: docs/briefs/BRIEF-scope-koto-adoption.md
    status: Accepted
    content_hash: a00cdbc3d3fd6d3c7ca156664e748927dc706491
    jury: all-pass
  prd:
    path: docs/prds/PRD-scope-koto-adoption.md
    status: Accepted
    content_hash: 0e1000010a098fc06f1beffc0474136cc46c5835
    jury: all-pass
    jury_rounds: 3
worktree_rebases:
  - child: brief
    behind: 0
    impact: None
  - child: prd
    behind: 0
    impact: None
  - child: design
    behind: 0
    impact: None
parent_orchestration:
  invoking_child: design
  suppress_status_aware_prompt: true
  rationale: fresh-chain
shape_predicates:
  p1_architectural_alternatives: fires
  p2_new_components: does-not-fire
  p3_complex_classification: fires
```
