# merge-other-pr-evidence

The owned PR stays OPEN after the merge call. The agent's merge_attempt evidence names a different, already-MERGED PR (#99); nothing reads it, and the confirm read of the owned PR decides.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
