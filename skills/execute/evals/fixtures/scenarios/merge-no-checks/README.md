# merge-no-checks

No check was ever reported, and the head commit is past the grace window: `awaiting:no-checks`. The base requires a review rather than a named check, so no required check is left waiting to report.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
