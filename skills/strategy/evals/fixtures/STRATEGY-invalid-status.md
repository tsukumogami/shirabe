---
schema: strategy/v1
status: Invalid
bet: |
  Adopting plugin X pencils out over two quarters. This fixture
  intentionally uses an invalid status value to exercise the FC02
  rejection path.
scope: project
---

# STRATEGY: invalid-status-fixture

## Status

Invalid

## Strategic Context

This fixture exists to exercise FC02. Status "Invalid" is not in
the valid-statuses enum (Draft, Accepted, Active, Sunset).

## Defensibility Thesis

The fixture exists to drive a validate failure, not to articulate
a real bet.

## Building Blocks

### Block 1: placeholder
Single block sufficient for FC04 to not also fire.

## Coordination Dependencies

(none — fixture)

## Bet-Specific Falsifiability

- *If validate does not emit FC02 for this fixture*, the
  status-enum enforcement is broken. → *Corrective: investigate the
  Formats-map entry's ValidStatuses and the checkFC02 function.*

## Non-Goals

1. **This fixture is not a real strategy.** Testing only.

## Downstream Artifacts

- None.
