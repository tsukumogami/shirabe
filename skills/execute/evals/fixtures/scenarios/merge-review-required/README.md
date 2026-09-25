# merge-review-required

Merge state BLOCKED and review decision REVIEW_REQUIRED: the verdict is `awaiting:merge-state:BLOCKED:review=REVIEW_REQUIRED`.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
