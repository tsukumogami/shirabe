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

If the issue references a design document, update the dependency diagram to reflect the completed work.

#### 6.1.5.1 Extract Design Doc Path

Look for `Design: \`<path>\`` in the issue body (from Phase 1 issue reading).

**If no `Design:` reference found:** Skip this step silently. Not all issues reference design docs.

#### 6.1.5.2 Validate Path

Before reading the file, validate the path:

- **No path traversal**: Reject paths containing `..`
- **Markdown file**: Path must end with `.md`
- **Expected directory**: File must be within `docs/` directory
- **File exists**: Verify file exists at the path

**If validation fails:** Log warning, skip diagram update, continue to Push Branch.

#### 6.1.5.3 Find and Update Diagram

1. Read the design document
2. Locate the `### Dependency Graph` section with Mermaid diagram
3. Find the current issue's node: `I<N>` where N is the issue number
4. Change its class from `:::ready` or `:::blocked` to `:::done`

**Regex pattern for node with class:**
```
I(\d+)\[([^\]]+)\]:::(\w+)
```
- Group 1: Issue number
- Group 2: Label
- Group 3: Current class (done/ready/blocked)

#### 6.1.5.4 Recalculate Downstream Status

For each node that depends on this issue:

1. Parse all edges to find nodes blocked by this issue:
   ```
   I<N>.*-->.*I(\d+)
   ```
2. For each downstream node, check if ALL its blocking dependencies are now `:::done`
3. If all blockers are done, change the downstream node from `:::blocked` to `:::ready`

**Edge pattern:**
```
I(\d+).*-->.*I(\d+)
```
- Group 1: Source (blocker) issue number
- Group 2: Target (blocked) issue number

#### 6.1.5.5 Validate and Commit

1. Verify the modified Mermaid syntax is valid (all `classDef` statements present, balanced brackets)
2. Stage the design document with the implementation changes
3. The design doc update will be included in the same commit/PR as the implementation

**Error handling:**
- Diagram section not found: Log warning, skip update (old format design)
- Node for issue not found: Log warning, skip update
- Syntax validation fails: Log error, abort diagram update, continue PR without it

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

## Writing Style

See `skills/writing-style/SKILL.md` for writing style guidelines. Key: no emojis, no AI references, active voice.
