# pr-adopt-fork

The only PR on the head branch comes from a fork (isCrossRepository true): it is never adopted, edited, readied, or merged.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
