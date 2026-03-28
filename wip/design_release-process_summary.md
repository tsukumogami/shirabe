# Design Summary: release-process

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** Shirabe's plugin manifests drift from git tags because versions are manual. The marketplace reads version at the tagged commit, making drift a correctness bug.
**Constraints:** Must integrate with org /prepare-release and /release skills. Full automation — version set at release time. Sentinel value on main, real versions at tags only.

## Current Status
**Phase:** 0 - Setup (Explore Handoff)
**Last Updated:** 2026-03-28
