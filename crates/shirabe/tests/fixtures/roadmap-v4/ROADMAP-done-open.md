---
schema: roadmap/v4
status: Done
theme: |
  Plugins a maintainer can find.
scope: |
  The loader and the registry.
---

# ROADMAP: plugins

## Status

Done

## Theme

Plugins a maintainer can find.

## Milestones

### Milestone 1: Loader

**Outcome:** A maintainer who installed three plugins sees each one listed
by name with the version it loaded.

**Evidence:**
- A reviewer, from a clean install with three sample plugins, runs the list
  command and sees exactly those three names and versions.

**Left open:** None

**Dependencies:** None
**Status:** Completed

### Milestone 2: Registry

**Outcome:** A maintainer finds a plugin by name without reading the plugin
directory.

**Evidence:**
- A reviewer runs the find command for an installed plugin and sees its path.

**Left open:** None

**Dependencies:** Milestone 1
**Status:** In progress

## Sequencing Rationale

The loader comes first because the registry reads what it loads.

## Progress

The loader landed; the registry is under way.

## Implementation Issues

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

| Milestone | Issues | Dependencies | Status |
|-----------|--------|--------------|--------|

## Dependency Graph

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

```mermaid
graph TD
```
