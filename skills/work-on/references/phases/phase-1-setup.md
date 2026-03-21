# Phase 1: Setup

Create feature branch and establish a clean baseline for development.

## Resume Check

If `wip/issue_<N>_baseline.md` exists, skip to Phase 2.

## Steps

### 1.1 Review Issue

Review the issue with `gh issue view <issue-number>`:
- Understand requirements and acceptance criteria
- Note related issues or dependencies
- Identify the appropriate branch prefix: `feature/`, `fix/`, or `chore/`

### 1.2 Create Feature Branch

Create a branch from latest main using the naming convention:
Branch naming:
- `feature/<N>-<desc>` for new functionality
- `fix/<N>-<desc>` for bug fixes
- `chore/<N>-<desc>` for maintenance

### 1.3 Establish Baseline

Run the project's test suite to establish a clean starting state. Use project-specific commands from the language skill defined in your extension file, or from the project's CLAUDE.md.

Record results including:
- Test pass/fail counts
- Any pre-existing failures
- Build status
- Coverage metrics (if available)

### 1.4 Document Baseline

Create `wip/issue_<N>_baseline.md` (Write tool):

```markdown
# Issue <N> Baseline

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
- Key functions: <list relevant coverage>
- Command used: <coverage generation command>

## Pre-existing Issues
<document any known issues not related to this work>
```

If the project tracks coverage, this baseline enables comparison during Phase 3.

### 1.5 Commit Baseline

Commit using format: `docs: establish baseline for <short-description>`

## Success Criteria

- [ ] Feature branch created from latest main
- [ ] All tests pass (or pre-existing failures documented)
- [ ] Build succeeds
- [ ] `wip/issue_<N>_baseline.md` committed

## Next Phase

Proceed to Phase 2: Introspection (`phase-2-introspection.md`)
