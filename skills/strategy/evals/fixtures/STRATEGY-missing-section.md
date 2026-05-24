---
schema: strategy/v1
status: Draft
bet: |
  Adopting plugin X pencils out over two quarters under stated
  conditions. This fixture intentionally omits the Building Blocks
  required section so shirabe validate emits an FC04 error.
scope: project
---

# STRATEGY: missing-section-fixture

## Status

Draft

## Strategic Context

This fixture intentionally omits the Building Blocks section to
exercise the FC04 missing-required-section rejection path in the
strategy evals.

## Defensibility Thesis

The fixture exists to drive a validate failure, not to articulate
a real bet.

## Coordination Dependencies

(none — fixture)

## Bet-Specific Falsifiability

- *If validate does not emit FC04 for this fixture*, the validate
  layer's required-section enforcement is broken. → *Corrective:
  investigate the Formats-map entry and the checkFC04 function.*

## Non-Goals

1. **This fixture is not a real strategy.** It exists only for
   testing.

## Downstream Artifacts

- None.
