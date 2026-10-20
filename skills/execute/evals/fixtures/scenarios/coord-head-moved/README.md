# coord-head-moved

The `core` node PR (#11) is ready and green, but its index line records `head=` a commit that is not its live head. The run starts with no record in its session, so setup recovers it from the body: the run line names the run, #11 carries that run's marker (`<!-- shirabe-run: 5e7a1c0d9b8f4e3a2c1b0a9f8e7d6c5b -->`), and the head recorded is #11's live one, never the body's. Without `--merge` nothing is merged; the `cli` node waits on `core`, and the run pauses with `recovered=` in its exit lines.

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
