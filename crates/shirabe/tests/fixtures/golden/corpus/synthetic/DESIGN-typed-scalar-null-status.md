---
schema: design/v1
problem: A problem.
decision: A decision.
rationale: A rationale.
status: ~
---

# DESIGN: typed-scalar null status preservation

## Status

~

## Context and Problem Statement

The status value `~` is a YAML null token. The parser MUST preserve the
original source text ("~") rather than resolving it to a null/empty value.
This is the most severe break mode: if the parser yields empty, check_fc02
short-circuits on the empty-status guard and SILENTLY DROPS the FC02
annotation Go emits (status "~"). Source-text preservation keeps "~" so FC02
fires identically. Third typed-scalar regression guard (null / dropped-
annotation shape), alongside the float 1.50 and hex 0x1F cases.

## Decision Drivers

Body.

## Considered Options

Body.

## Decision Outcome

Body.

## Solution Architecture

Body.

## Implementation Approach

Body.

## Security Considerations

Body.

## Consequences

Body.
