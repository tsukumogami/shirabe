# Design Summary: work-on-efficiency

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** The work-on plan orchestrator drives all child issues through 10+
state transitions regardless of issue type or pre-implementation status. Doc-only
issues run code review panels unnecessarily. Pre-implemented issues have no clean
exit path. Plan-backed children incorrectly own the shared PR. Hardcoded workflow
name breaks non-standard init names.
**Constraints:** No koto engine changes for shirabe-side fixes. Single-template
preferred over forks. False positive rate must be near zero for file-conflict detection.

## Current Status
**Phase:** Complete — design doc written via /explore handoff (all research
conducted in explore; design produced directly from findings)
**Last Updated:** 2026-04-16
