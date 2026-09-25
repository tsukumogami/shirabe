# merge-dirty

A conflicted PR: merge state DIRTY, and GitHub reports no check runs. ci_monitor routes through escalate_dirty_merge_state to done_blocked.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
