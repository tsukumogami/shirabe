# coord-outline-one-repo

An outline-shaped coordinated PLAN (`PLAN-coord-outline-test.md`, `tracking_level: none`) in one repository with two PR groups: `core` (outlines 1 and 2) has no predecessor, and `cli` (outline 3) waits on it. Nothing is indexed yet. Every PR the run opens gets one passing required check on a base whose rules require it, and merges when asked, so with `--merge` the run merges the `core` PR, then the `cli` PR, then the coordination PR, and without it the run pauses after readying the `core` PR. `gh shim-mark-merged eval-org/eval-repo 11` marks the `core` PR merged between two runs, as a human merge would.

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
