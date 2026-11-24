---
schema: roadmap/v4
status: Active
theme: |
  Plugins a maintainer can find.
scope: |
  The loader, the registry and search.
---

# ROADMAP: plugins

## Status

Active

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

### Milestone 12: Search

**Outcome:** A maintainer searches plugins by keyword and sees the matches.

**Evidence:**
- A reviewer searches for a keyword two sample plugins share and sees both.

**Left open:** None

**Dependencies:** None
**Status:** Verified

## Sequencing Rationale

The loader comes first because the registry reads what it loads.

## Progress

| Milestone | Status | Verdict |
|-----------|--------|---------|
| Milestone 1: Loader | Completed | -- |
| Milestone 2: Registry | In progress | -- |
| Milestone 12: Search | ~~Verified~~ | verified (2026-11-01) |

- 2026-11-01: Milestone 12 -- verified

## Implementation Issues

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

| Milestone | Issues | Dependencies | Status |
|-----------|--------|--------------|--------|

## Dependency Graph

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

```mermaid
graph TD
```
