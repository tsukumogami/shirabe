# Design Summary: completion-cascade

## Input Context (Phase 0)
**Source:** Freeform topic
**Problem:** Post-implementation cleanup (cascade) runs manually today. The partial
  automation in work-on-plan.md is hardcoded and incomplete; compression is missing.
**Constraints:**
- Shirabe is public; no private-tools dependency at runtime
- Cascade failures must not block `done`
- Compression is lossy; preservation rules must be precise
- Must handle chains that skip artifact types (e.g., DESIGN → ROADMAP, no PRD)

## Current Status
**Phase:** 1 - Decision Decomposition
**Last Updated:** 2026-04-15
