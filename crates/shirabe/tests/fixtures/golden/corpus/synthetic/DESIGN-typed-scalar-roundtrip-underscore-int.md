---
schema: design/v1
problem: A problem.
decision: A decision.
rationale: A rationale.
status: 1_000
---

# DESIGN: typed-scalar round-trip guard (underscore-int)

## Status

1_000

## Context and Problem Statement

The status value `1_000` round-trips identically through both Go's
yaml.Node.Value and Rust's source-text preservation. Included as a cheap
round-trip guard so the corpus exercises a typed scalar that should NOT
change, complementing the non-round-tripping 1.50 / 0x1F / ~ cases.

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
