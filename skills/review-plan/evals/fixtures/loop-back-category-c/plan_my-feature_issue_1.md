# Issue 1: Implement tsuku list command

## Goal

Add a `tsuku list` subcommand that reads the installation state and prints each
installed tool on its own line.

## Acceptance Criteria

1. When tools are installed, `tsuku list` outputs each tool in `<name> <version>`
   format, one per line, sorted alphabetically by name.
2. When no tools are installed, `tsuku list` outputs nothing and exits with code 0.
3. When the state file is missing or unreadable, `tsuku list` exits with a non-zero
   exit code and writes an error message to stderr.

## Dependencies

None

## Complexity

testable
