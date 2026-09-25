# merge-not-observed

The merge call exits 0, and the PR keeps reporting OPEN (a merge queue that accepted without merging): the confirm read records `not-merged:merge-not-observed`.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
