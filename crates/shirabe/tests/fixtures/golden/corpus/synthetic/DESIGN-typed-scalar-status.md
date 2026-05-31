---
schema: design/v1
problem: A problem.
decision: A decision.
rationale: A rationale.
status: 1.50
---

# DESIGN: typed-scalar status preservation

## Status

1.50

## Context and Problem Statement

The status value `1.50` is a YAML float token. The parser MUST preserve the
original source text ("1.50") rather than canonicalizing it to "1.5" — Go's
yaml.Node.Value keeps the as-written token. If the Rust parser reformats it,
the FC02 message bytes diverge AND an extra FC03 (frontmatter "1.5" vs body
"1.50") fires that Go never emits. This fixture is the permanent regression
guard for DESIGN Decision 1 typed-scalar preservation.

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
