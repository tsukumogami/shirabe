# merge-files-short

The paginated changed-files read returns fewer files than the PR's `changedFiles`: the verdict is `error:execute:status-read`, never a clean result.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
