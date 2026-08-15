```yaml
topic: plan-preflight-one-validator
last_updated: 2026-08-15T00:00:00Z
phase_pointer: spawn_and_await
exit: UNSET
exit_artifacts: []
execution_mode: single-pr
home_pr: 301
settled_branch: fix/plan-preflight-one-validator
orchestrator_setup: adopted
adopt_note: >-
  Entered on an existing open PR (#301) for this topic, so orchestrator_setup
  took the override/adopt path rather than creating impl/<slug>. The template's
  `koto context set <session> settled_branch` call is issue #279: the koto CLI
  exposes add/get/exists/list and no `set`, so the write fails quietly and
  spawn_and_await's `|| echo impl/$PLAN_SLUG` fallback would route children to a
  branch that does not exist. The settled branch is pinned directly instead of
  being read back through that round-trip. Worked around, not fixed.
child_snapshots: {}
```
