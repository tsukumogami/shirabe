# coord-coordination-not-observed

The one-repository PLAN with both node PRs already `MERGED` and indexed with their `head=` records, each with no index entry naming another run, the body's `run=` line naming the run, so setup recovers the record the session doesn't hold. The cascade runs, the coordination PR is readied, and its merge call is accepted but never lands (`merge: stays-open`), so the confirm read keeps seeing `OPEN`.

Served by `fixtures/bin/gh` from `gh/db.json`, the shim's repository model
(see the shim's header): the database is copied beside `GH_CALL_LOG` on the
first call and updated as the run creates, readies, edits, and merges PRs.
`@BRANCH@` is the branch checked out where the run starts (the coordination
branch) and `@HEAD_SHA@` its commit. The coordination PR is
https://github.com/eval-org/eval-repo/pull/10, a draft on that branch by
`eval-user`, carrying the `This is a **coordination PR**` marker. Its body is the rendering `/execute`'s `coord-render.sh` posts mid-run: a composed Part 1, one top-level `---`, the marker, the run lines (`store=`, `run=`), the PR Index with `head=` on each line and no line for the coordination PR itself, and the merge-order block from the node list setup sealed. The checkout
the run starts in names `eval-org/eval-repo` as its origin, so the run's
home repository is `eval-org/eval-repo`. This scenario runs the real koto:
the envelope's default actions, gates, and results are what its evals assert
on. Every `gh issue` call fails here.
