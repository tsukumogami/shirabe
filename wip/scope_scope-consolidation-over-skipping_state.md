```yaml
topic: scope-consolidation-over-skipping
chain_started: 2026-08-09T00:00:00Z
last_updated: 2026-08-09T00:00:00Z
phase_pointer: phase-4
exit: full-run
exit_artifacts:
  - docs/briefs/BRIEF-scope-consolidation-over-skipping.md
  - docs/prds/PRD-scope-consolidation-over-skipping.md
  - docs/designs/DESIGN-scope-consolidation-over-skipping.md
  - docs/plans/PLAN-scope-consolidation-over-skipping.md
plan_execution_mode: single-pr
visibility: Public
execution_mode: auto
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
  prd: "exit 0 (clean), --visibility=public"
  design: "exit 0 (clean), --visibility=public"
  plan: "exit 0 (clean), --visibility=public"
worktree_rebases: []
consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    mapping: "Problem Statement->Problem Statement; User Outcome->Goals; User Journeys->User Stories; Scope Boundary->Requirements (IN) + Out of Scope (OUT)"
    carry_check:
      problem_statement: carried
      user_outcome: carried
      user_journeys: not-carried
      scope_boundary: carried
    verdict: keep
    finding: "Absorb aborted at the per-section carry check. The PRD's six one-line User Stories do not carry the four narrative User Journeys; each journey walks through the judgment's behaviour and the stories compress that out."
  - hop: prd->design
    absorbable: false
    verdict: keep
    finding: "Mapping is not total. DESIGN's required sections have a home only for the PRD's Problem Statement (Context and Problem Statement); Goals, User Stories, Requirements, Acceptance Criteria and Out of Scope have none. Absorb unavailable per the Decision 4 rule."
  - hop: design->plan
    absorbable: false
    verdict: keep
    finding: "Mapping is not total. PLAN's required sections have no home for the DESIGN's Decision Drivers, Considered Options, Decision Outcome, Solution Architecture, Security Considerations or Consequences. Absorb unavailable per the Decision 4 rule, and forbidden independently by the durable-artifact floor."

```
