---
schema: design/v1
status: Accepted
problem: |
  `widgets config load` reports a malformed config file as "invalid input",
  without naming the file or the line.
decision: |
  Include the file path and line number in the parse error.
rationale: |
  The parser already tracks the line; the message just drops it.
---

# DESIGN: Error Message Fix

## Status

Accepted

## Context and Problem Statement

When `widgets config load` fails to parse a config file, it prints
`error: invalid input`. Users cannot tell which file or line is wrong. The
parser in `internal/config/parse.go` already records the line number on its
error value; `cmd/widgets/config.go` formats only the error's kind.

## Decision Drivers

- The message must name the file and the line.
- No change to exit codes.

## Considered Options

### Decision 1: Message format

Chosen: `error: <path>:<line>: <reason>`, the format the other subcommands use.
Rejected: a multi-line report, which is more change than the problem needs.

## Decision Outcome

Change the formatting call in `cmd/widgets/config.go` and add one test.

## Solution Architecture

- `cmd/widgets/config.go`: format the parse error as `<path>:<line>: <reason>`.
- `cmd/widgets/config_test.go`: one table case for a malformed file.

## Implementation Approach

A single change: update the formatting call and add the test case.

## Security Considerations

None. The message prints a path the user supplied.

## Consequences

Parse errors name their location. Nothing else changes.
