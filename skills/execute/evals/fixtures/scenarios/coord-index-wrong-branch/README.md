# coord-index-wrong-branch

The index names #11 for the `core` node, but #11's head branch is `feature/elsewhere`, not `impl/coord-outline-test-pr-eval-repo-core`. The run starts with no record in its session, so setup tries to recover it from the body; #11 is not the owned PR on the node's branch, so setup stops `recovery-unproven` naming `pr-eval-repo-core`, and the run ends `outcome=error` with `step=execute:coord_setup` and touches nothing.

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
