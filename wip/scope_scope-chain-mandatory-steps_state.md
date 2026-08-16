```yaml
topic: scope-chain-mandatory-steps
chain_started: 2026-08-16T03:06:25Z
last_updated: 2026-08-16T03:08:00Z
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
    started_at: 2026-08-16T03:10:00Z
    completed_at: 2026-08-16T03:15:04Z
child_snapshots:
  brief:
    status: Draft
    content_hash: 3f1174177af4e69ec5340ffdcacc4921f50728ed
    captured_at: 2026-08-16T03:15:04Z
consolidation_judgments: []
worktree_rebases:
  - phase: brief
    upstream_commits: [8e07f07, 85fda73]
    impact: informational
    rebased_at: 2026-08-16T03:10:00Z
    notes: >-
      #292 appended preflight eval scenarios to skills/{scope,charter,execute}/
      evals.json (scope 26->28, charter 21->22, execute 34->35). Every scenario
      this chain cites keeps its id and name; artifacts cite by id and name
      rather than by suite count.
r6_predicates:
  p1: fires
  p1_reason: >-
    Four implementation choices left explicitly open for the DESIGN — the
    chain-proposal prompt's replacement shape, the interactive entry to R8
    bail-handling, the fate of the direct-invocation redirect, and the
    contents of /explore's handoff artifact.
  p2: does-not-fire
  p2_reason: >-
    No new component. Every write target already exists: skills/explore/,
    skills/scope/, skills/charter/, references/parent-skill-pattern.md,
    references/parent-skill-state-schema.md, skills/scope/evals/evals.json.
  p3: fires
  p3_reason: >-
    The change lands on references/parent-skill-pattern.md, a shared contract
    two parent skills and two eval suites depend on.
```
