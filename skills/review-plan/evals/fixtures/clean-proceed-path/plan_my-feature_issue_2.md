# Issue 2: Add --filter flag to tsuku list

## Goal

Add a `--filter <pattern>` flag that filters the list output to only show tools
whose names contain the pattern.

## Acceptance Criteria

1. When the filter matches one or more installed tools, only those tools appear in
   the output; non-matching tools are excluded.
2. When the filter matches no installed tools, output is empty and exit code is 0.
3. When an empty string is passed as the filter pattern, output is the same as
   running `tsuku list` without a filter.
4. Filter matching is case-insensitive.

## Dependencies

Issue 1

## Complexity

testable
