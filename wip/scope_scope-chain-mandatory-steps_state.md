```yaml
topic: scope-chain-mandatory-steps
chain_started: 2026-08-16T03:06:25Z
last_updated: 2026-08-16T03:42:19Z
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
  - name: prd
    started_at: 2026-08-16T03:16:00Z
    completed_at: 2026-08-16T03:42:19Z
child_snapshots:
  prd:
    status: Accepted
    content_hash: 558fb314fc32ad31a7bfe35378137916003b2cac
    captured_at: 2026-08-16T03:42:19Z
consolidation_judgments:
  - hop: brief->prd
    verdict: absorb
    stage: carry
    target: docs/briefs/BRIEF-scope-chain-mandatory-steps.md
    survivor: docs/prds/PRD-scope-chain-mandatory-steps.md
    preflight_exit: 0
    carried:
      problem-statement: true
      user-outcome: true
      user-journeys: true
      scope-boundary: true
    blob: 6f96746e956c2286409f7d5b71ca23a153a5d564
    finding: >-
      The brief holds nothing at an altitude the PRD does not reach. Its problem
      statement arrives at greater length, its user outcome as Goals, all five
      journeys as User Stories with the same actors and triggers, and its scope
      boundary as the requirements themselves plus Out of Scope. It carries no
      requirements, no architecture, and no sequencing.
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
  - phase: prd
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-16T03:16:00Z
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
