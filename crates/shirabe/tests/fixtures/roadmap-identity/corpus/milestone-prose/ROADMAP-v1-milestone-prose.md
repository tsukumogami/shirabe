---
schema: roadmap/v1
status: Active
theme: |
  A plugin system a maintainer can install plugins into, list them and find
  one by name.
scope: |
  The loader, the registry and the find command. Publishing is out.
---

# ROADMAP: Plugin system, milestone prose

## Status

Active

## Theme

A plugin system a maintainer can install plugins into, list them and find one
by name. Its Dependencies lines are free prose, as a roadmap/v1 roadmap's may
be, and two of them mention another project's milestones.

## Features

### Feature 1: Plugin loader
**Needs:** `needs-design` -- the manifest shape
**Dependencies:** None
**Status:** Done

The loader reads each plugin's manifest.

### Feature 2: Plugin registry
**Dependencies:** Feature 1
**Status:** In Progress

The registry records what the loader found.

### Feature 3: Find command
**Dependencies:** Feature 2
**Status:** Not started

The find command reads the registry.

### Feature 4: Search command
**Dependencies:** None (lands after the upstream project's milestone 3)
**Status:** Not started

Search waits on an upstream release, not on a feature here.

### Feature 5: Plugin updates
**Dependencies:** Feature 1, and Milestones 2 and 3 of the upstream project
**Status:** Not started

Updates need the loader and two upstream milestones.

## Sequencing Rationale

The loader comes first because every other feature reads what it records.

## Progress

- The loader shipped.

## Implementation Issues

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|

## Dependency Graph

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

```mermaid
graph TD
```
