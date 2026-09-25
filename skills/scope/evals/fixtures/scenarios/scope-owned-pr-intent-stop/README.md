# scope-owned-pr-intent-stop

One owned open PR (#42) on the topic branch records intent=stop: a run with --intent=continue rewrites that field with gh pr edit --body-file and opens nothing.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys).
The repository is eval-org/eval-repo, default branch main; the
authenticated user is eval-user. `@HEAD_BRANCH@` stands for the topic branch
`setup-topic.sh` checks out.
