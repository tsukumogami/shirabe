# Pull Request and CI

Create the PR and monitor CI until all checks pass.

## Pre-PR Verification

Rebase on latest main if behind. Resolve conflicts and re-run tests.

Review with `git diff main...HEAD` — no unintended changes.

### Design Document Status

If the issue body contains `Design: \`<path>\``, update the design doc's
dependency diagram per `phase-6-design-diagram-update.md`. Skip if no
`Design:` reference.

## Push Branch

```bash
git push -u origin <branch>
```

After rebase: `git push --force-with-lease`.

## Create PR

Title: conventional commits format. Body: apply the reasoning framework from
your project's PR creation skill. Include `Fixes #<N>`.

## CI Monitoring

If checks fail:
1. Review failure logs
2. Fix locally (test failure, lint, build, flaky test, environment)
3. Push the fix
4. Re-check

If stuck after 2-3 iterations, ask the user.

If a check is red and you cannot fix it, ask the user.

## Evidence (pr_creation)

- `pr_status: created` + `pr_url`
- `pr_status: creation_failed_retry` (up to 3)
- `pr_status: creation_failed_escalate`

## Evidence (ci_monitor)

- `ci_outcome: passing`
- `ci_outcome: failing_fixed`
- `ci_outcome: failing_unresolvable` + `rationale`
