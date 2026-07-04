# Design Summary: session-work-summary

## Input Context (Phase 0)
**Source PRD:** docs/prds/PRD-session-work-summary.md (In Progress)
**Problem (implementation framing):** Surface a session's real PR set as a
standardized, findable block, driven by deterministic harness machinery rather
than agent discipline, split across the workspace's shirabe/niwa layer boundary.

## Decision Questions (Phase 1)
Each was researched to prototyped, empirically-tested depth during the upstream
/explore (5 rounds; research files in wip/research/explore_*). Considered Options
draw on those evaluated alternatives.

1. Cross-layer split — where the pipeline lives (dot-niwa vs shirabe-plugin vs layered).
2. Display channel — how the block reaches the user and the model.
3. State source & scoping — how the session's real PRs are identified.
4. Emission cadence — when the block appears; compaction handling.
5. Block format & marker — the on-screen shape and its searchable anchor.

## Current Status
**Phase:** 1 - Decomposition complete
**Last Updated:** 2026-07-04
