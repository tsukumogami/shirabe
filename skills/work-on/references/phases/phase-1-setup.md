# Setup

Create feature branch and establish a clean baseline.

## Steps

### Review Issue

Review the issue with `gh issue view <issue-number>`:
- Understand requirements and acceptance criteria
- Note related issues or dependencies
- Identify the appropriate branch prefix: `feature/`, `fix/`, or `chore/`

### Create Feature Branch

Before creating a new branch, check whether you already have an appropriate one:
- If `SHARED_BRANCH` is set (plan-backed mode), use it — skip branch creation
- If the user instructed you to continue on the current branch, use it
- If already on a feature branch from a previous session on this work, use it

When none of the above apply, create a new branch:
- `feature/<N>-<desc>` for new functionality
- `fix/<N>-<desc>` for bug fixes
- `chore/<N>-<desc>` for maintenance

Continue with baseline establishment regardless of which branch path was taken — the baseline step applies in all cases.

### Establish Baseline

Run the project's test suite. Use project-specific commands from the language
skill or CLAUDE.md.

### Document Baseline

Write the baseline content to a local file, then store it in koto context:

```bash
koto context add <WF> baseline.md --from-file <baseline-file>
```

Baseline format:

```markdown
# Baseline

## Environment
- Date: <timestamp>
- Branch: <branch-name>
- Base commit: <commit-hash>

## Test Results
- Total: X tests
- Passed: Y
- Failed: Z (list if any)

## Build Status
<pass/fail + any warnings>

## Coverage (if tracked)
- Overall: X%
- Command used: <coverage generation command>

## Pre-existing Issues
<document any known issues not related to this work>
```

### Commit

`docs: establish baseline for <short-description>`

## Evidence

Submit `status: completed` after branch and baseline exist, `status: override`
if reusing an existing branch, or `status: blocked`.
