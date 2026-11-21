---
schema: roadmap/v4
status: Active
theme: |
  Plugins a maintainer can find.
scope: |
  The loader, the registry, search, the old index and the docs.
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
**Status:** Not started

### Milestone 3: Search

**Outcome:** A maintainer searches plugins by keyword and sees the matches.

**Evidence:**
- A reviewer searches for a keyword two sample plugins share and sees both.

**Left open:** None

**Dependencies:** None
**Status:** Verified

### Milestone 4: Old index

**Outcome:** A maintainer reads the old plugin index from the registry.

**Evidence:**
- A reviewer opens the old index and sees every plugin it lists.

**Left open:** None

**Dependencies:** None
**Status:** Dropped

### Milestone 5: Docs

**Outcome:** A maintainer reads how to write a plugin from one page.

**Evidence:**
- A reviewer follows the page and loads the plugin it describes.

**Left open:** None

**Dependencies:** None
**Status:** In progress

## Sequencing Rationale

The loader comes first because the registry reads what it loads.

## Progress

The loader landed and search was verified.

## Implementation Issues

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

| Milestone | Issues | Dependencies | Status |
|-----------|--------|--------------|--------|

## Dependency Graph

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

```mermaid
graph TD
```
