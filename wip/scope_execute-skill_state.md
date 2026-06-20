```yaml
topic: execute-skill
chain_started: 2026-06-19T20:55:34Z
last_updated: 2026-06-20T01:00:00Z
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
  - brief
  - prd
seed_context: >
  /execute = NEW single-agent parent owning plan-level execution for the two
  ephemeral-home shapes: single-pr + coordinated (shirabe#196). Delegates each
  single issue to a narrowed /work-on. multi-pr OUT (independent per-issue /work-on
  vs repo-persisted PLAN, no carry-forward). koto direction = hierarchical (parent
  + per-issue child sessions), mechanism deferred to design; cross-repo koto limit
  may defer coordinated nested-koto. Parity-or-better with today's 8 value caps.
child_snapshots:
  brief:
    status: Accepted
    content_hash: 5093df35792de6b0dfa2ecc5478d7af163d3b2ab
    captured_at: 2026-06-20T00:00:00Z
    jury: both-PASS
  prd:
    status: Accepted
    content_hash: 4b56093e256d480ac834ada92a239aec641d2149
    captured_at: 2026-06-20T01:00:00Z
    jury: all-PASS (completeness/clarity/testability)
    validator: clean
parent_orchestration:
  invoking_child: design
  suppress_status_aware_prompt: true
  rationale: fresh-chain
```
