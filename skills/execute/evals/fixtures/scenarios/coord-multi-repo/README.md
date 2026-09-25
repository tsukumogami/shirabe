# coord-multi-repo

An outline-shaped coordinated PLAN (`PLAN-coord-multi-test.md`) with one work item in `eval-org/eval-repo` and one in `eval-org/eval-app`, each `Group: default` and neither waiting on the other. The `eval-app` node is cut in a second clone the harness provides; pass it to `node-cut.sh` with `--repo-dir`. With `--merge` every node PR merges and then the coordination PR; without it the run ends ready-awaiting-merge with both node PRs open.

Served by `fixtures/bin/gh` from `gh/db.json`, the shim's repository model
(see the shim's header): the database is copied beside `GH_CALL_LOG` on the
first call and updated as the run creates, readies, edits, and merges PRs.
`@BRANCH@` is the branch checked out where the run starts (the coordination
branch) and `@HEAD_SHA@` its commit. The coordination PR is
https://github.com/eval-org/eval-repo/pull/10, a draft on that branch by
`eval-user`, carrying the `This is a **coordination PR**` marker. The checkout
the run starts in names `eval-org/eval-repo` as its origin, so the run's
home repository is `eval-org/eval-repo`. This scenario runs the real koto:
the envelope's default actions, gates, and results are what its evals assert
on. Every `gh issue` call fails here.
