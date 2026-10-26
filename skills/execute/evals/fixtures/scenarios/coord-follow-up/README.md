# coord-follow-up

The outline-shaped coordinated PLAN of `coord-outline-one-repo` (`PLAN-coord-outline-test.md`), mid-run: the `core` node PR (#11) is already MERGED, and the `cli` node has no PR yet. A follow-up to `core` is open as #21 (`fix/parser-empty-input`, titled `fix(core): handle an empty input`, with a Part 1): not a draft, opened by `eval-user` from this repository, based on `main`, with one passing check. The run starts with no record in its session, so setup recovers it from the coordination PR's rendering (the run line names the run, and no index entry names another run for #11) and then records the follow-up the invocation's `--follow-up pr-eval-repo-core=https://github.com/eval-org/eval-repo/pull/21` names, with its live head. The opener hands that value to koto as `FOLLOW_UP=pr-eval-repo-core https://github.com/eval-org/eval-repo/pull/21`, the `=` turned into a space because koto's own value allowlist has no `=`, and setup reads the node and URL back from it. With `--merge` the loop merges #21 first (its node is already MERGED), then cuts, readies and merges the `cli` node's PR (#22), and merges the coordination PR last.

Served by `fixtures/bin/gh` from `gh/db.json`, the shim's repository model
(see the shim's header): the database is copied beside `GH_CALL_LOG` on the
first call and updated as the run creates, readies, edits, and merges PRs.
`@BRANCH@` is the branch checked out where the run starts (the coordination
branch) and `@HEAD_SHA@` its commit. The coordination PR is
https://github.com/eval-org/eval-repo/pull/10, a draft on that branch by
`eval-user`, carrying the `This is a **coordination PR**` marker. Its body is the rendering `/execute`'s `coord-render.sh` posts mid-run: a composed Part 1, one top-level `---`, the marker, the run lines (`store=`, `run=`), the PR Index with `core`'s line (`merged`, with its merge commit as `head=`) and no line for the coordination PR itself, and the merge-order block from the node list setup sealed. The checkout
the run starts in names `eval-org/eval-repo` as its origin, so the run's
home repository is `eval-org/eval-repo`. This scenario runs the real koto:
the envelope's default actions, gates, and results are what its evals assert
on. Every `gh issue` call fails here.
