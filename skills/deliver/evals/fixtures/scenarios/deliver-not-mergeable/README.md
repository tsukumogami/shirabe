# deliver-not-mergeable

The base also requires an approving review, and every PR the run opens reads
`reviewDecision` REVIEW_REQUIRED. Nothing can merge without a human: a single-pr
run ends ready-awaiting-merge, and a coordinated run readies the first group's
PR and pauses (paused-awaiting-merges) with the next group waiting on it.

Served by `fixtures/bin/gh`, which adapts /scope's and /deliver's calls to
/execute's repository model (`skills/execute/evals/fixtures/bin/gh`, `gh/db.json`
mode) and logs every call to `$GH_CALL_LOG`. The repository is
`eval-org/eval-repo`, the user `eval-user`, and the base `main`, protected by a
rule requiring the `build` check. A PR `gh pr create` opens takes the next
number (42 unless the scenario seeds one), `mergeStateStatus` CLEAN, and the
check result this scenario gives. `@BRANCH@` is the topic branch the fixture repository is on,
`@HEAD_SHA@` its commit, and each open PR's head follows what origin holds.
PR #77 is an unrelated merged PR on another branch, for the cases where a
child names some other merged PR. koto is the real engine.
