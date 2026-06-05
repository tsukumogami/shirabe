---
complexity: testable
complexity_rationale: "Three-reviewer roster per DESIGN verified table."
---

# Issue 13: docs(roadmap): add team.yaml and Team Shape section

## Goal

Create `skills/roadmap/team.yaml` and add a brief `## Team Shape` section to `skills/roadmap/SKILL.md`. Content matches DESIGN Component 2's verified migration table for `/roadmap`.

## Acceptance Criteria

- [ ] **AC13.1** — File `skills/roadmap/team.yaml` exists and parses as valid YAML.
- [ ] **AC13.2** — `parent_layer.peers: []`.
- [ ] **AC13.3** — `child_layer.peers` contains exactly three reviewer entries with phase `phase-4-validate`:
    - `theme-coherence-reviewer` ("evaluates whether features belong under one theme")
    - `sequencing-and-dependency-reviewer` ("evaluates dependency graph between features")
    - `annotation-and-boundary-reviewer` ("evaluates per-feature annotations and roadmap scope boundary")
- [ ] **AC13.4** — No `upper_bound` field on any reviewer.
- [ ] **AC13.5** — `skills/roadmap/SKILL.md` has the `## Team Shape` section cross-referencing `./team.yaml`.
- [ ] **AC13.6** — Source-of-truth alignment matches DESIGN's verified migration table for /roadmap.

## Dependencies

**Dependencies**: Issue 1
