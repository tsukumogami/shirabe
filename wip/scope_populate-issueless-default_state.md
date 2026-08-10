```yaml
topic: populate-issueless-default
chain_started: 2026-08-10T00:00:00Z
last_updated: 2026-08-10T00:00:00Z
phase_pointer: phase-4
exit: full-run
exit_artifacts:
  - docs/plans/PLAN-populate-issueless-default.md
visibility: Public
execution_mode: auto
max_rounds: 5
plan_execution_mode: single-pr

planned_chain:
  - brief
  - prd
  - design
  - plan
chain_ran:
  - brief
  - prd
  - design
  - plan
chain_skipped: []

child_snapshots:
  brief:
    status: Accepted
    path: docs/briefs/BRIEF-populate-issueless-default.md
  prd:
    status: Accepted
    path: docs/prds/PRD-populate-issueless-default.md
  design:
    status: Current
    path: docs/designs/current/DESIGN-populate-issueless-default.md
  plan:
    status: Draft
    path: docs/plans/PLAN-populate-issueless-default.md

validator_pass_through:
  brief: exit 0
  prd: exit 0
  design: exit 0
  plan: exit 0

decisions_settled:
  where_auto_populate_runs: >-
    Both -- after the Phase 4 jury resolves and before the approval
    walkthrough, and again on the activate path. They cover different entry
    paths rather than duplicating; idempotence makes the overlap free.
  issue_filing_action: >-
    Retain `/roadmap populate <path>` and give it `--issues`. No new input
    mode: the existing mode already carries the R14 gate, and a second verb
    doing almost the same thing costs more than it clarifies.
  mode_resolution: >-
    flag > `## Roadmap Issues:` header > issueless default. Confirmed against
    SKILL.md:145-154 and claude-md-conventions.md:64 rather than taken from
    the brief. The header's fail-closed direction inverts.
  both_flags: >-
    Clear error via clap `conflicts_with`, detected at parse time so no
    mutation and no `gh` call can occur.
```
