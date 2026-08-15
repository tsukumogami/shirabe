```yaml
topic: scope-artifact-persistence
chain_started: 2026-08-15T01:09:08Z
last_updated: 2026-08-15T01:44:00Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain: [brief, prd, design, plan]
chain_skipped: []
visibility: Public
execution_mode: auto
max_rounds: 5
phase_1:
  cold_start: true
  framing_shift: none
  discovery: no artifacts on disk at any canonical path for this topic
  r6_predicates:
    p1_architectural_alternatives:
      verdict: fires
      reason: >-
        Three architectural alternatives are left open for the DESIGN to
        settle: the surface of the durable operation record, whether the
        contribution section is authored by the child at drafting time or the
        parent at fold time, and the rollout posture for the R<n>
        citation-resolution rule.
    p2_new_components:
      verdict: does-not-fire
      reason: >-
        All work lands in existing components: skills/scope/, skills/work-on/,
        skills/execute/, crates/shirabe-validate/.
    p3_complex_classification:
      verdict: fires
      reason: >-
        Spans skill prose contracts, the Rust validator, the artifact format
        contracts and two sibling skills.
  design_roster: full (P1 and P3 both fire; three live decision questions)
  chain_proposal: Proceed (auto mode)

child_snapshots:
  brief:
    path: docs/briefs/BRIEF-scope-artifact-persistence.md
    status: Accepted
    jury: content-quality PASS (after one FAIL and revision), structural-format PASS
    note: >-
      The content reviewer's blocking finding was that the /charter exclusion was
      justified by the type-level mapping test this feature removes. Rewritten to
      rest on grounds that survive the change.
  prd:
    path: docs/prds/PRD-scope-artifact-persistence.md
    status: Accepted
    jury: completeness PASS, clarity PASS, testability PASS (round 3)
    rounds: 3
    note: >-
      Requirements 22 -> 30, criteria 17 -> 36. Round-2 blocking finding was that
      the R<n> citation rule as written would fail 77 documents already on disk,
      contradicting the regression requirement; scoped to the absorb event.

consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: false}
      Scope Boundary:    {target: Requirements + Out of Scope, carried: true}
    verdict: keep
    finding: >-
      The BRIEF's four User Journeys narrate the feature hop by hop — which
      verdict each hop reaches and why, what the procedure asks before deleting,
      what a reader sees on the survivor. The PRD's five User Stories carry the
      same actors and outcomes in compressed as-a/I-want/so-that form and drop
      the per-hop operational detail. That detail did independent work: it is
      what let the PRD jury check requirements against intended behaviour. Both
      artifacts stay.
    note: >-
      This is the second recorded instance of the one absorbable hop failing its
      carry check on User Journeys — #260's own dogfood run failed the same way.
      Evidence for the PRD's claim that the absorb path is under-exercised.
```
