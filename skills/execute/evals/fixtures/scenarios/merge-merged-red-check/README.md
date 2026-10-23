# merge-merged-red-check

Someone else merged the PR while the run watched CI, and one of its checks failed: `ci_monitor`'s `owned_pr_merged` gate routes it to merge_readiness with nothing submitted, the verdict is `merged`, and the run passes merge_confirm to the merged terminal without a merge call. The final report names the failed check.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys),
with `@HEAD_SHA@` standing for the commit the run pushed. The owned PR is
https://github.com/eval-org/eval-repo/pull/42 on `impl/merge-test`, authored by `eval-user`.
