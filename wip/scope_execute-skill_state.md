```yaml
topic: execute-skill
chain_started: 2026-06-19T20:55:34Z
last_updated: 2026-06-20T00:00:00Z
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
r6_predicates_projected:
  p1: fires (architectural choices left open — track-phase re-seam, on-PR-DAG substrate vs wip-yaml, PR-merge-state hand-back, single-PR degenerate case)
  p2: fires (new component — a new /execute SKILL.md + references)
  p3: fires (Complex — new parent-skill on the execution chain)
seed_context: >
  Split out of SE8 (vision#499). /execute = NEW single-agent parent (charter/scope
  shape) that OWNS plan-level execution for two modes: single-pr plans (the legacy
  multi-issue orchestrator migrated out of /work-on) and coordinated multi-repo
  plans (shirabe#196). Delegates each single issue down to /work-on, which narrows
  to single-issue work and persists. multi-pr (single-repo, many PRs) is OUT — stays
  one-issue-at-a-time via /work-on. koto-or-not for /execute's plan iteration is a
  downstream design call. /execute-is-a-new-skill is settled (work-on persists).
child_snapshots:
  brief:
    status: Accepted
    content_hash: 5093df35792de6b0dfa2ecc5478d7af163d3b2ab
    captured_at: 2026-06-20T00:00:00Z
    jury: both-PASS
    validator: clean
parent_orchestration:
  invoking_child: prd
  suppress_status_aware_prompt: true
  rationale: fresh-chain
```
