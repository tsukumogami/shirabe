# coord-head-missing

The `core` node PR (#11) is ready and green, but its index line carries no `head=` field at all. The run starts with no record in its session, so setup recovers it from the body: the run line names the run, #11 has no index entry naming another run (a node PR is the run's by the ownership lookup and its index entry, never its text), and #11's head is read live. Without `--merge` nothing is merged; the `cli` node waits on `core`, and the run pauses with `recovered=` in its exit lines.

Served by `fixtures/bin/gh` from `gh/db.json`, the shim's repository model
(see the shim's header): the database is copied beside `GH_CALL_LOG` on the
first call and updated as the run creates, readies, edits, and merges PRs.
`@BRANCH@` is the branch checked out where the run starts (the coordination
branch) and `@HEAD_SHA@` its commit. The coordination PR is
https://github.com/eval-org/eval-repo/pull/10, a draft on that branch by
`eval-user`, carrying the `This is a **coordination PR**` marker. Its body is the rendering `/execute`'s `coord-render.sh` posts mid-run: a composed Part 1, one top-level `---`, the marker, the run lines (`store=`, `run=`), the PR Index with `head=` on each line and no line for the coordination PR itself, and the merge-order block from the node list setup sealed. Its one index line has had its `head=` field removed by hand, the one departure from what `/execute` renders. The checkout
the run starts in names `eval-org/eval-repo` as its origin, so the run's
home repository is `eval-org/eval-repo`. This scenario runs the real koto:
the envelope's default actions, gates, and results are what its evals assert
on. Every `gh issue` call fails here.
