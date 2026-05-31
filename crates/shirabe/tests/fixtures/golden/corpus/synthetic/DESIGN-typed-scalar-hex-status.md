---
schema: design/v1
problem: A problem.
decision: A decision.
rationale: A rationale.
status: 0x1F
---

# DESIGN: typed-scalar hex status preservation

## Status

0x1F

## Context and Problem Statement

The status value `0x1F` is a YAML hexadecimal integer token. The parser MUST
preserve the original source text ("0x1F") rather than parsing-and-reformatting
it to its decimal value ("31") — Go's yaml.Node.Value keeps the as-written
token. If the Rust parser reformats it, the FC02 message bytes diverge AND an
extra FC03 (frontmatter "31" vs body "0x1F") fires that Go never emits. This is
the second typed-scalar regression guard (alongside the float `1.50` case) for
DESIGN Decision 1 typed-scalar preservation, covering the non-decimal integer
shape.

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
