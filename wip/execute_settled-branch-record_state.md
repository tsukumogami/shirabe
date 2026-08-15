---
schema: execute-state/v1
---

```yaml
topic: settled-branch-record
last_updated: 2026-08-15T19:05:00Z
phase_pointer: orchestrator_setup
exit: UNSET
exit_artifacts: []
execution_mode: single-pr
autonomy: auto
home_pr: 306
settled_branch: docs/settled-branch-record
setup_path: override
setup_path_reason: >-
  Entered on docs/settled-branch-record, a non-main branch with open PR #306
  (the /scope chain's PR). Adopted as the home PR: no second PR opened, none
  linked. Branch creation skipped, which is why the settled branch has to be
  recorded rather than derived.
child_execution_note: >-
  The four PLAN issues are executed in-process on the shared branch rather than
  as koto-materialized /work-on children, because agent dispatch is not
  available in this session. Dependency order from the PLAN is preserved.
```
