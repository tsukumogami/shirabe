---
topic: pr-template-gate
chain_started: 2026-07-05T03:06:30Z
last_updated: 2026-07-05T03:12:00Z
phase_pointer: phase-3
exit: full-run
exit_artifacts:
  - docs/plans/PLAN-pr-template-gate.md
plan_execution_mode: single-pr
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
  - design
  - plan
child_snapshots:
  brief:
    status: Accepted
    path: docs/briefs/BRIEF-pr-template-gate.md
  prd:
    status: Accepted
    path: docs/prds/PRD-pr-template-gate.md
  design:
    status: Planned
    path: docs/designs/DESIGN-pr-template-gate.md
  plan:
    status: Active
    path: docs/plans/PLAN-pr-template-gate.md
design_roster_shape:
  P1_architectural_alternatives: fires
  P2_new_component: does-not-fire
  P3_complex: fires
framing_shift: no-signal-yet-cold-start
---

# /scope state: pr-template-gate

Full tactical chain (BRIEF -> PRD -> DESIGN -> PLAN) for
tsukumogami/shirabe#221 — enforce PR-template conformance at a gate.

## Chain proposal (Phase 1, accepted: Proceed)

- /brief: fires (R4 EITHER-signal — no upstream BRIEF)
- /prd: fires (R5 — no Accepted PRD at canonical path)
- /design: fires (R7 shape-dependent — P1 fires, P2 does-not-fire, P3 fires)
- /plan: fires (ALWAYS)
