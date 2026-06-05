---
complexity: testable
complexity_rationale: "Two coupled file edits. Three-reviewer roster per DESIGN verified table; ground-truth must be preserved."
---

# Issue 8: docs(prd): add team.yaml and Team Shape section

## Goal

Create `skills/prd/team.yaml` and add a brief `## Team Shape` section to `skills/prd/SKILL.md`. Content matches DESIGN Component 2's verified migration table for `/prd`.

## Acceptance Criteria

- [ ] **AC8.1** — File `skills/prd/team.yaml` exists and parses as valid YAML.
- [ ] **AC8.2** — `parent_layer.peers: []`.
- [ ] **AC8.3** — `child_layer.peers` contains exactly three reviewer entries with phase `phase-4-validate`:
    - `completeness-reviewer` ("finds gaps in requirements vs problem statement")
    - `clarity-reviewer` ("evaluates wording and unambiguity")
    - `testability-reviewer` ("evaluates AC verifiability")
- [ ] **AC8.4** — No `upper_bound` field on any reviewer.
- [ ] **AC8.5** — `skills/prd/SKILL.md` has the `## Team Shape` section cross-referencing `./team.yaml`.
- [ ] **AC8.6** — Source-of-truth alignment matches DESIGN's verified migration table for /prd.

## Dependencies

**Dependencies**: Issue 1
