---
schema: design/v1
status: Planned
problem: |
  A person has no way to print a greeting for a name.
decision: |
  Add a greet command that prints a greeting, read from a config file.
rationale: |
  One command and one config value cover every case the problem names.
---

# DESIGN: greeting command

## Status

Planned

## Context and Problem Statement

A person has no way to print a greeting for a name.

## Decision Drivers

- The greeting is configurable.

## Considered Options

### Option 1: a greet command

Chosen.

## Decision Outcome

Add a `greet` command.

## Solution Architecture

The command reads an optional config file and prints one line per name.

## Implementation Approach

Build the command end to end first, then the config file.

## Security Considerations

The command reads one local file and writes to stdout only.

## Consequences

One more command to maintain.
