---
schema: roadmap/v1
status: Active
theme: |
  Fixture roadmap for the coordinate skill's evals: four features with one
  dependency edge, in Active status.
scope: |
  Eval fixture only.
---

# ROADMAP: Plugin System

## Status

Active

## Theme

Fixture roadmap for the coordinate skill's evals.

## Features

### Feature 1: Plugin manifest

**Needs:** `needs-design`
**Dependencies:** None
**Status:** Not Started

### Feature 2: Plugin loader

**Needs:** `needs-design`
**Dependencies:** Feature 1
**Status:** Not Started

### Feature 3: Plugin registry

**Needs:** `needs-prd`
**Dependencies:** None
**Status:** Not Started

### Feature 4: Plugin sandbox

**Needs:** `needs-design`
**Dependencies:** None
**Status:** Not Started

## Sequencing Rationale

Feature 2 needs the manifest from Feature 1. Features 3 and 4 are
independent.

## Progress

Not started.

## Implementation Issues

| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|
| Plugin manifest | needs-design | None | needs-design |
| Plugin loader | needs-design | F1 | needs-design |
| Plugin registry | needs-prd | None | needs-prd |
| Plugin sandbox | needs-design | None | needs-design |
