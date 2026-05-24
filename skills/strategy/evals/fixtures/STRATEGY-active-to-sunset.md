---
schema: strategy/v1
status: Active
bet: |
  Adopting plugin X pencils out over two quarters. This fixture
  starts at Active and is the input for the Active -> Sunset
  transition test (the conventional sunset path).
scope: project
---

# STRATEGY: active-to-sunset-fixture

## Status

Active

## Strategic Context

This fixture exists to exercise `transition-status.sh`'s Active ->
Sunset path. The conventional sunset path: the bet was invalidated
after downstream work began. The test invokes the script with
target `Sunset` and a reason; the script must update status, embed
the reason in the body Status section, and `git mv` the file into
`docs/strategies/sunset/`.

## Defensibility Thesis

Placeholder bet sufficient to satisfy structural checks.

## Building Blocks

### Block 1: placeholder
Single block; sufficient for FC04 to not fire.

## Coordination Dependencies

(none — fixture)

## Bet-Specific Falsifiability

- *If the transition script fails to move the file to
  `docs/strategies/sunset/`*, the file-movement plumbing is broken.
  → *Corrective: investigate `move_to_directory` and `status_dir`
  in the strategy transition script.*

## Non-Goals

1. **This fixture is not a real strategy.** Testing only.

## Downstream Artifacts

- None.
