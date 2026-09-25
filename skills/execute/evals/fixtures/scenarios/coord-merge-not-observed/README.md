# coord-merge-not-observed

The one-repository PLAN of `coord-outline-one-repo`, except that every PR the run opens accepts its merge call and never merges (`merge: stays-open`): `gh pr merge` exits 0 and every later read still says `OPEN`. The `core` PR's merge is called once, recorded as not observed, and never called again; the `cli` node never starts.

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
