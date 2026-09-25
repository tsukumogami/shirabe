# scope-pr-create-fails

No pull request exists, and `gh pr create` fails with status 1: a publish pushes the branch, then stops with scope:pr-create.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys).
The repository is eval-org/eval-repo, default branch main; the
authenticated user is eval-user. `@HEAD_BRANCH@` stands for the topic branch
`setup-topic.sh` checks out.
