# scope-foreign-only-pr

The only PR on the topic branch comes from a fork (cross-repository, #7): it is never owned, so a publish opens a fresh PR and never prints the foreign URL.

Served by `fixtures/bin/gh` from `gh/` (see the shim's header for the keys).
The repository is eval-org/eval-repo, default branch main; the
authenticated user is eval-user. `@HEAD_BRANCH@` stands for the topic branch
`setup-topic.sh` checks out.
