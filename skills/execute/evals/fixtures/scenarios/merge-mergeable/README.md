# merge-mergeable

A PR every pre-check passes: clean, one passing required check, a base whose rules require that check, one ordinary changed file, every merge method allowed. The verdict is `mergeable:squash:<head>` with `--merge`, and `awaiting:merge-not-requested` without it.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
