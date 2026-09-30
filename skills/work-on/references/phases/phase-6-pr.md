# Pull Request and CI

Create the PR and monitor CI until all checks pass.

## Pre-PR Verification

If the branch is behind main, merge the latest main into it (`git fetch origin`,
then `git merge --no-edit origin/main`, which takes the default message
rather than opening an editor). Never rebase: a merge keeps every reviewed commit
in the branch's history, so the commit `pre_pr.md` names stays an ancestor of
`HEAD`. Resolve conflicts and re-run tests on the merged tip.

Review the diff against the remote's default branch: `git diff
origin/main...HEAD` when it is `main` (`git symbolic-ref
refs/remotes/origin/HEAD` names it). That is what the PR will show, and it
needs no local `main`. Diffing from `impl_base` here would also show whatever
the merge pulled in. No unintended changes.

### Design Document Status

Don't update the design diagram here. When the issue body contains
`Design: \`<path>\``, finalization updated it and `pre_pr.md`'s
`design_diagram` line names its path. Confirm that path appears in
that diff. If it doesn't, the record and the diff disagree: go
back through `finalization` rather than updating the diagram at this point.

## Push Branch

```bash
git push -u origin <branch>
```

Push plainly, never with a force option. A merge from main only adds commits,
so a plain push is always enough.

## Create PR

Author the title and body to the **mechanical** rule in
`references/pr-body-conformance.md`, which `shirabe validate --pr-body`
enforces in CI. For the **subjective**
Part 2 section selection (which reviewer-context sections this change needs),
apply the reasoning framework from your project's PR creation skill. Include
`Fixes #<N>` in Part 2 — `pr_creation`'s `closing_keyword` gate reads the pull
request GitHub actually has and blocks the run when the body does not close the
issue, so this is an obligation the workflow enforces rather than a convention
it asks for. Free-form work has no issue to close and the gate passes without
consulting the body.

If `deferral_approval` approved a deferral, name the deferred criterion and the
recorded approval in Part 2.

## CI Monitoring

If checks fail:
1. Review failure logs
2. Fix locally (test failure, lint, build, flaky test, environment)
3. Push the fix
4. Re-check

A check you cannot fix, or one still red when `ci_monitor`'s retry cap is
spent, ends the run as `failing_unresolvable`; the state's directive carries
the cap. An unattended run never asks the user instead.

## Evidence (pr_creation)

- `pr_status: created` + `pr_url`
- `pr_status: shared` — set when running as a plan-backed child with `SHARED_BRANCH`
  set. No PR is created or monitored; the phase routes directly to done. Using
  `created` instead would enter `ci_monitor` and monitor the orchestrator's PR,
  not this child's work.
- `pr_status: creation_failed_retry` (the state's directive carries the cap)
- `pr_status: creation_failed_escalate`

## Evidence (ci_monitor)

- `ci_outcome: passing`
- `ci_outcome: failing_fixed`
- `ci_outcome: failing_unresolvable` + `rationale`
