---
schema: strategy/v1
status: Draft
bet: |
  Adopting plugin X for the data layer pencils out over the next two
  quarters if the migration cost stays below team-week N and the
  performance characteristics hold under load. The bet is durable so
  long as the upstream plugin remains under active maintenance and
  the API surface stays additive.
scope: project
---

# STRATEGY: example-happy-path

## Status

Draft

## Strategic Context

The team's data layer currently uses an in-house adapter that
introduces friction at every schema change. Upstream plugin X
covers the same surface with first-party maintenance. The shape of
this STRATEGY is a happy-path example used by the strategy skill's
evals to exercise validate's structural happy path.

## Defensibility Thesis

The bet is that the team's medium-term defensibility improves by
adopting plugin X over maintaining the in-house adapter. The
maintenance load drops and the API surface tracks community
conventions, which compounds in onboarding and integration costs.

## Building Blocks

### Block 1: migration shim
A thin compatibility layer that lets existing call sites continue to
work during the cutover.

### Block 2: cutover orchestration
Tooling that sequences the migration with rollback at each step.

### Block 3: regression coverage
Test infrastructure that exercises plugin X against the current
in-house behavior to catch divergence.

### Block 4: deprecation
Plan and timeline for removing the in-house adapter once plugin X
is stable in production.

### Block 5: operational handoff
Runbooks and monitoring updates that operate against plugin X's
surface rather than the in-house adapter's.

## Coordination Dependencies

```
Block 1 (shim)  -->  Block 2 (cutover)  -->  Block 4 (deprecation)
                          |
                          v
                     Block 3 (regression coverage)
                          |
                          v
                     Block 5 (operational handoff)
```

Block 1 ships first because the rest of the work needs the shim's
compatibility layer.

## Bet-Specific Falsifiability

- *If plugin X's maintenance becomes inactive within the bet
  window*, the bet's durability assumption fails. → *Corrective:
  re-evaluate whether to fork plugin X or revert to the in-house
  adapter; the migration shim from Block 1 makes the revert
  tractable.*
- *If performance regressions exceed N% under production load*,
  the bet's performance assumption fails. → *Corrective: invest in
  Block 3 to characterize the regression and decide whether
  application-level mitigations are sufficient or the migration
  needs to halt.*

## Non-Goals

1. **This strategy is not a long-term identity change.** The team
   continues to ship the same product surface; only the data layer
   substrate changes.
2. **This strategy does not commit to migrating other shared
   substrates** (logging, telemetry, etc.) to plugin X's
   counterparts. Those decisions live in their own strategies if
   ever warranted.

## Downstream Artifacts

- `docs/roadmaps/ROADMAP-plugin-x-migration.md` — sequences the
  five Building Blocks against availability of the team's
  implementation capacity.
- `docs/designs/DESIGN-plugin-x-shim.md` — Block 1 implementation
  specifics, picked up after the roadmap settles.
