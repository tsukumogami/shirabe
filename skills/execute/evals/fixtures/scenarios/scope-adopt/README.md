# scope-adopt

A single-pr `/scope --intent=continue` run pushed the topic branch `docs/merge-test` and opened one owned draft PR there. `/execute` adopts it: no `pr create`, and no push to or checkout of `impl/merge-test`.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
