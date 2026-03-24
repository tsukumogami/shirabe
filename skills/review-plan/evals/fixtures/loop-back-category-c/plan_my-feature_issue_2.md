# Issue 2: Add --filter flag to tsuku list

## Goal

Add a `--filter <pattern>` flag that filters the list output to only show tools
whose names contain the pattern.

## Acceptance Criteria

1. Running `tsuku list --filter rip` outputs exactly `ripgrep 14.1.0`, matching the
   content of testdata/filter_rip.golden.
2. Running `tsuku list --filter fd` outputs exactly `fd 10.1.0`, matching the
   content of testdata/filter_fd.golden.
3. Running `tsuku list --filter xyz` produces output matching testdata/filter_empty.golden
   (empty file).

## Dependencies

Issue 1

## Complexity

testable
