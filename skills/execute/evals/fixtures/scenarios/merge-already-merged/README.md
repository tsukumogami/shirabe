# merge-already-merged

The PR is already MERGED when merge_readiness reads it: the verdict is `merged`, and the run still passes merge_confirm before the merged terminal.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
