---
schema: strategy/v1
status: Draft
bet: |
  Adopting plugin X pencils out over two quarters. This fixture
  contains a Competitive Considerations section and is expected to
  PASS validation when run with `--visibility private` (gate
  bidirectionality test).
scope: project
---

# STRATEGY: private-allowed-fixture

## Status

Draft

## Strategic Context

This fixture exists to exercise R8's gate bidirectionality. The
fixture is structurally identical in shape to `STRATEGY-public-leak.md`
but should PASS validation when `--visibility private` is passed —
otherwise an always-reject bug in `checkStrategyPublic` would slip
past the rejection test. The Competitive Considerations content
below is **synthetic test material**; it does not reflect any real
competitive positioning.

## Defensibility Thesis

The fixture's bet is a placeholder used to satisfy structural
required-sections checks; the real subject under test is the
visibility gate itself.

## Building Blocks

### Block 1: placeholder
Single block sufficient for FC04 to not fire.

## Coordination Dependencies

(none — fixture)

## Bet-Specific Falsifiability

- *If validate emits R8 for this fixture in private visibility*,
  the gate's private-acceptance path is broken. → *Corrective:
  investigate the `if cfg.Visibility == "private" { return nil }`
  branch in `checkStrategyPublic`.*

## Competitive Considerations

**Note:** the content of this section is synthetic test material
authored solely for the strategy skill's evals suite. It is not a
real competitive analysis. The section exists to verify that
`shirabe validate --visibility private` accepts STRATEGY documents
containing this section (the gate-bidirectionality check).

## Non-Goals

1. **This fixture is not a real strategy.** Testing only.

## Downstream Artifacts

- None.
