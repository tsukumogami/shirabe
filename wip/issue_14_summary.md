# Issue 14 Summary

## What Was Implemented

Replaced the cross-plugin `manage-milestone.sh` dependency in `create-issues-batch.sh` with
direct `gh api` calls, making the plan skill fully self-contained.

## Changes Made

- `skills/plan/scripts/create-issues-batch.sh`: Removed `skill_scripts_dir` path resolution
  and `manage-milestone.sh` calls. Added inline `gh repo view` + `gh api` calls to find or
  create milestones.
- `skills/plan/scripts/create-issues-batch_test.sh`: Added `test_milestone_uses_gh_api_directly`
  — uses a mock `gh` binary to verify the correct API endpoint is called and that no
  reference to `manage-milestone.sh` remains.

## Key Decisions

- **Use `gh api` directly rather than bundling `manage-milestone.sh`**: The milestone
  operations needed (find by title, create) are two simple REST calls. Bundling the full
  script would import code the plan skill doesn't need.
- **Resolve repo via `gh repo view`**: More reliable than parsing git remotes; consistent
  with how `gh` itself resolves context.

## Trade-offs Accepted

- The new code doesn't paginate the milestone list (capped at 100 per page). In practice,
  repos with 100+ milestones are rare, and `manage-milestone.sh` had the same default cap.

## Test Coverage

- New tests added: 1 (mock-gh milestone integration test)
- Existing tests: 10 passed (no regressions)
- Total: 12 passed, 0 failed

## Requirements Mapping

| AC | Status | Evidence |
|----|--------|----------|
| `create-issues-batch.sh` works without cross-plugin dependencies | Implemented | `manage-milestone.sh` reference removed; `gh api` calls inline |
| Either bundle `manage-milestone.sh` or use `gh` CLI directly | Implemented | `gh api` chosen (no bundling needed) |
| Plan skill is fully self-contained | Implemented | No `$SCRIPT_DIR/../../` path traversal remains |
