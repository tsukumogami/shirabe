# merge-pending-open

A check still pending on a head commit well inside the CI wait limit: the verdict is `pending:checks`, with or without `--merge`. `merge_route` routes a pending verdict only on `recheck: waited` evidence, so the run stands at `merge_route` instead of chaining through it.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
