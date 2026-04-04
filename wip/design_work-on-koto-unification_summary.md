# Design Summary: work-on-koto-unification

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** Unify work-on and /implement into a single koto-backed workflow that handles free-form tasks, single issues, and multi-issue plans, while migrating to koto v0.6.0 structured gate output.
**Constraints:** Koto has no sub-workflows or iteration; orchestrator must be skill-layer; review panels stay in markdown; gate migration is independent.

## Security Review (Phase 5)
**Outcome:** Option 3 (N/A with justification)
**Summary:** Design restructures internal workflow orchestration without new attack surfaces, external dependencies, or data exposure paths.

## Current Status
**Phase:** 5 - Security
**Last Updated:** 2026-04-04
