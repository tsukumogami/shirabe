```yaml
topic: execute-skill
chain_started: 2026-06-19T20:55:34Z
last_updated: 2026-06-20T02:00:00Z
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
  - design
seed_context: >
  /execute = NEW implementation-altitude single-agent parent. Owns single-pr +
  coordinated plan execution; delegates each issue to narrowed /work-on. DESIGN:
  hybrid koto(single-pr)/plain(coordinated); extract work-on-plan template+cascade
  into /execute, keep work-on.md per-issue, /work-on PLAN input = thin execution_mode
  dispatcher; substrate = on-home-PR durable + wip-yaml scratch (satisfies I-6).
child_snapshots:
  brief:
    status: Accepted
    content_hash: 5093df35792de6b0dfa2ecc5478d7af163d3b2ab
  prd:
    status: Accepted
    content_hash: 4b56093e256d480ac834ada92a239aec641d2149
  design:
    status: Accepted
    content_hash: e2ce58826cc09a642033927b2a5d1588b744c4a2
    jury: both-PASS (architecture/security)
    validator: clean
parent_orchestration:
  invoking_child: plan
  suppress_status_aware_prompt: true
  rationale: fresh-chain
```
