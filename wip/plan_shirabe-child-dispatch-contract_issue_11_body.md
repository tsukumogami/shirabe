---
complexity: testable
complexity_rationale: "Three-reviewer roster per DESIGN verified table."
---

# Issue 11: docs(vision): add team.yaml and Team Shape section

## Goal

Create `skills/vision/team.yaml` and add a brief `## Team Shape` section to `skills/vision/SKILL.md`. Content matches DESIGN Component 2's verified migration table for `/vision`.

## Acceptance Criteria

- [ ] **AC11.1** — File `skills/vision/team.yaml` exists and parses as valid YAML.
- [ ] **AC11.2** — `parent_layer.peers: []`.
- [ ] **AC11.3** — `child_layer.peers` contains exactly three reviewer entries with phase `phase-4-validate`:
    - `thesis-quality-reviewer` ("evaluates whether the thesis is a falsifiable bet")
    - `content-boundary-reviewer` ("evaluates audience and value-proposition framing")
    - `section-guidance-reviewer` ("evaluates structural conformance to vision-format.md")
- [ ] **AC11.4** — No `upper_bound` field on any reviewer.
- [ ] **AC11.5** — `skills/vision/SKILL.md` has the `## Team Shape` section cross-referencing `./team.yaml`.
- [ ] **AC11.6** — Source-of-truth alignment matches DESIGN's verified migration table for /vision.

## Dependencies

**Dependencies**: Issue 1
