---
schema: strategy/v1
status: Accepted
bet: |
  Adopting plugin X pencils out over two quarters. This fixture
  starts at Accepted and is the input for the Accepted -> Sunset
  transition test (the lifecycle refinement permitting bet
  invalidation before downstream consumption).
scope: project
---

# STRATEGY: accepted-to-sunset-fixture

## Status

Accepted

## Strategic Context

This fixture exercises the lifecycle refinement named in design
Decision 3: a bet can be invalidated by external events before any
downstream artifact consumes the STRATEGY. The test invokes
`transition-status.sh` with target `Sunset` directly from Accepted,
without going through Active.

## Defensibility Thesis

Placeholder bet sufficient to satisfy structural checks.

## Building Blocks

### Block 1: placeholder
Single block; sufficient for FC04 to not fire.

## Coordination Dependencies

(none — fixture)

## Bet-Specific Falsifiability

- *If the transition script rejects Accepted -> Sunset*, the
  lifecycle refinement is mis-encoded. → *Corrective: investigate
  the `Accepted__Sunset` case in `validate_transition`.*

## Non-Goals

1. **This fixture is not a real strategy.** Testing only.

## Downstream Artifacts

- None.
