```yaml
topic: execute-skill
chain_started: 2026-06-19T20:55:34Z
last_updated: 2026-06-19T20:57:00Z
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
chain_ran: []
r6_predicates_projected:
  p1: fires (architectural choices left open — track-phase re-seam, on-PR-DAG substrate vs wip-yaml, PR-merge-state hand-back, single-PR degenerate case)
  p2: fires (new component — a new /execute SKILL.md + references)
  p3: fires (Complex — new parent-skill on the execution chain)
seed_context: >
  Split out of SE8 (vision#499) per exploration on branch
  explore/se8-work-on-migration. /execute = single-agent parent (charter/scope
  shape) over a coordinated-PLAN DAG (shirabe#196), delegating each PR-node to
  the unchanged koto-based /work-on. SE2-independent (resumability from on-PR
  DAG). Pre-fit by DESIGN-shirabe-progression-authoring.md. ~90% clone of
  SE4/SE7 deliverable set.
parent_orchestration:
  invoking_child: brief
  suppress_status_aware_prompt: true
  rationale: fresh-chain
```
