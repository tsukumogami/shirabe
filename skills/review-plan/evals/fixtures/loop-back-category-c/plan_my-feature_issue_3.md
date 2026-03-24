# Issue 3: Integration tests for tsuku list

## Goal

Add integration tests that verify end-to-end behavior of the list command and
filter flag under realistic conditions.

## Acceptance Criteria

1. With no tools installed, `tsuku list` returns empty output and exits with code 0
   (clean-state scenario verified before any tool installation).
2. After installing a single tool, `tsuku list` output contains exactly that tool's
   name and version on one line.
3. With two tools installed, `tsuku list --filter <pattern>` output contains only
   the tools whose names match the pattern; non-matching tools do not appear.
4. `tsuku list` exits with a non-zero exit code when the state file is corrupted
   (replaced with invalid JSON).

## Dependencies

Issue 2

## Complexity

testable
