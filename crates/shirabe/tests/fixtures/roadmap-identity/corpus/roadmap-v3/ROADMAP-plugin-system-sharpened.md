---
schema: roadmap/v3
status: Draft
theme: |
  A plugin system a maintainer can install plugins into, list them, find one
  by name and search them by keyword, built in the order each step reads
  what the one before it recorded.
scope: |
  Covers the loader, the registry and the search command. Publishing
  plugins and a plugin marketplace are out.
---

# ROADMAP: Plugin system

## Status

Draft

## Theme

A plugin system a maintainer can install plugins into, list them, find one by
name and search them by keyword. The steps share one record of what was
loaded, so they have to land in order.

## Milestones

### Milestone 1: A maintainer lists the plugins they installed

**Outcome:** A maintainer who installed three plugins sees each one listed by
name with the version it loaded, without reading the plugin directory by
hand.

**Evidence:**
- A reviewer, from a clean install with the three sample plugins, runs
  `widgets list` and sees exactly those three names and versions.
- The same reviewer removes one plugin's manifest and sees `widgets list`
  name the plugin it skipped and why, and exit non-zero.

**Left open:** the list command's output layout and where the loader keeps
its record.

**Needs:** `needs-design` -- the manifest shape
**Dependencies:** None
**Status:** Not started

### Milestone 2: A maintainer finds a plugin by name

**Outcome:** A maintainer finds an installed plugin by name and gets its
path, and is told plainly when no plugin by that name is installed.

**Evidence:**
- A reviewer, from a clean install with the three sample plugins, runs the
  find command for one of them and sees its path; for a name no plugin
  carries, sees a message naming it and a non-zero exit.

**Left open:** the registry's storage format and the find command's name.

**Dependencies:** Milestone 1
**Status:** Not started

### AB3: A maintainer searches plugins by keyword

**Outcome:** A maintainer searching for a keyword sees every installed plugin
whose description carries it, and only those.

**Evidence:**
- A reviewer, with the three sample plugins installed, searches for a word
  only one description carries and sees that one plugin; searching for a
  word none carries, sees an empty result and a zero exit.

**Left open:** None

**Dependencies:** Milestone 2, acme/widgets#12
**Status:** Not started

## Sequencing Rationale

The list comes first because the find and search commands read the record
the loader writes. Search depends on find only for the registry it builds;
it waits on an upstream change to the manifest format as well.

## Progress

Nothing has started.

## Implementation Issues

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

| Milestone | Issues | Dependencies | Status |
|-----------|--------|--------------|--------|

## Dependency Graph

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

```mermaid
graph TD
```
