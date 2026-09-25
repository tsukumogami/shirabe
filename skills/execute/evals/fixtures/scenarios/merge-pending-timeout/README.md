# merge-pending-timeout

A check still pending on a head commit older than the eval's small EXECUTE_CI_WAIT_LIMIT_SECS: the verdict is `error:execute:ci-timeout`.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
