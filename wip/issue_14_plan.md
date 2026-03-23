# Issue 14 Plan

## Approach

Replace the `manage-milestone.sh` cross-plugin dependency in `create-issues-batch.sh` with
self-contained `gh api` calls. The two operations used are:
- Find milestone by title (to check if it exists)
- Create milestone (if it doesn't exist)

Both are straightforward REST API calls that need no shared library.

## Steps

- [x] Step 1: Remove the `skill_scripts_dir` variable and `manage-milestone.sh` calls
      (lines 271–285 in create-issues-batch.sh). Replace with an inline `ensure_milestone`
      function that uses `gh api` directly.
- [x] Step 2: Run existing tests to verify no regressions.
- [x] Step 3: Add a test that covers the milestone path. Since milestone creation requires
      a real API call, test via a mock `gh` binary in PATH to verify the correct `gh api`
      subcommand is called when `--milestone` is provided without `--dry-run`.
