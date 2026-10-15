---
schema: roadmap/v2
status: Active
theme: |
  Fixture milestone roadmap for the coordinate skill's evals: one milestone
  delivered by a pull request and one whose Evidence is host state.
scope: |
  Eval fixture only.
---

# ROADMAP: Milestones

## Status

Active

## Theme

Fixture milestone roadmap for the coordinate skill's evals.

## Features

### MV1: the plugin list

**Outcome:** A maintainer lists the plugins they installed.

**Evidence:**
- A reviewer, from a clean install with three sample plugins, runs
  `widgets list` and sees exactly those three names.
- The same reviewer removes one manifest and sees it named as skipped.

**Left open:** the output layout.

**Dependencies:** None
**Status:** In progress

### MV2: the host serves

**Outcome:** The host answers on its public name.

**Evidence:**
- An operator curls the host's public name and gets a 200.

**Left open:** None

**Dependencies:** None
**Status:** In progress

## Progress

- 2026-10-01: MV1 and MV2 started
