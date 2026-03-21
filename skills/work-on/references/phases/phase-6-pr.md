# Phase 6: Pull Request

Create the pull request and monitor CI until all checks pass.

## Resume Check

If PR already exists for this branch:
- Check PR status with `gh pr view`
- If CI failing, continue CI monitoring loop
- If CI passing, verify and complete

## Steps

### 6.1 Pre-PR Verification

Rebase on latest main if behind. If merge conflicts occur, resolve them and re-run tests.

Review changes with `git diff main...HEAD` to verify no unintended changes.

### 6.1.5 Update Design Document Status

If the issue body contains `Design: \`<path>\``, update the design doc's
dependency diagram. Read `phase-6-design-diagram-update.md` for the full
procedure (path validation, node status changes, downstream recalculation).

If no `Design:` reference is found, skip silently.

### 6.2 Push Branch

Push the branch (with `-u` to set upstream tracking).

**Force push after rebase:**
- If you rebased and the branch was already pushed: `git push --force-with-lease`
- `--force-with-lease` is safer than `--force` (fails if someone else pushed)
- After creating a PR, force pushes will update the PR automatically
- If PR has reviewer comments, notify them after force push

### 6.3 Create Pull Request

See `skills/writing-style/SKILL.md` for PR writing style guidelines.

**Key points:**
- Title: Conventional commits format
- Body: Apply the reasoning framework to determine appropriate sections
- Issue link: `Fixes #<N>` to auto-close issue

### 6.4 CI Monitoring Loop

**A PR is NOT complete until ALL CI checks pass.**

Wait ~60 seconds for CI to initialize, then monitor with `gh pr checks --watch`.

If checks fail:
1. Review failure logs via GitHub or `gh pr checks <pr-number>`
2. Identify failure type:
   - **Test failure**: Fix the code or test, verify locally
   - **Lint/format failure**: Run linter locally, fix issues
   - **Build failure**: Check for missing dependencies or syntax errors
   - **Flaky test**: If same test passes locally, may need re-run or investigation
   - **Environment issue**: Check CI logs for version mismatches
3. Fix locally and verify with pre-commit checks
4. Push the fix
5. Return to monitoring

If stuck on CI failures for more than 2-3 iterations, ask the user for guidance.

Repeat until all checks pass.

**No Exceptions:** NEVER rationalize away failing checks as "expected", "non-blocking", or "acceptable". If a check is red and you cannot fix it, ask the user. The user decides what failures are acceptable, not you.

### 6.5 Enable Auto-merge (Optional)

For straightforward changes, enable auto-merge with squash strategy.

## Success Criteria

- [ ] Branch rebased on latest main
- [ ] PR created with proper format
- [ ] All CI checks passing
- [ ] Issue linked with `Fixes #<N>`

## Completion

When all CI checks pass:
- Report PR URL to user
- Workflow complete
