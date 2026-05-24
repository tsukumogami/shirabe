---
schema: strategy/v1
status: Draft
bet: |
  Adopting plugin X pencils out over two quarters. This fixture
  intentionally includes a Competitive Considerations section in
  what is treated as public-visibility content, exercising the R8
  rejection path.
scope: project
---

# STRATEGY: public-leak-fixture

## Status

Draft

## Strategic Context

This fixture exists to exercise R8 visibility gating. It contains
a Competitive Considerations section that must be rejected when
the validator runs with `--visibility public` (or with visibility
unset, fail-closed).

## Defensibility Thesis

The fixture's content is fabricated test material; nothing in the
Competitive Considerations section below reflects real competitive
positioning.

## Building Blocks

### Block 1: placeholder
Single block sufficient for FC04 to not fire.

## Coordination Dependencies

(none — fixture)

## Bet-Specific Falsifiability

- *If validate does not emit R8 for this fixture in public
  visibility*, the visibility-gating layer is broken. → *Corrective:
  investigate `checkStrategyPublic` and the case "Strategy" dispatch
  arm in ValidateFile.*

## Competitive Considerations

This section's mere presence (in public visibility) should drive
the R8 rejection. The content here is synthetic test material — no
real competitive positioning is encoded.

## Non-Goals

1. **This fixture is not a real strategy.** Testing only.

## Downstream Artifacts

- None.
