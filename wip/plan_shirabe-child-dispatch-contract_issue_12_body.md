---
complexity: testable
complexity_rationale: "Three-reviewer roster per DESIGN verified table."
---

# Issue 12: docs(strategy): add team.yaml and Team Shape section

## Goal

Create `skills/strategy/team.yaml` and add a brief `## Team Shape` section to `skills/strategy/SKILL.md`. Content matches DESIGN Component 2's verified migration table for `/strategy`.

## Acceptance Criteria

- [ ] **AC12.1** — File `skills/strategy/team.yaml` exists and parses as valid YAML.
- [ ] **AC12.2** — `parent_layer.peers: []`.
- [ ] **AC12.3** — `child_layer.peers` contains exactly three reviewer entries with phase `phase-4-validate`:
    - `bet-quality-reviewer` ("evaluates whether the strategy names a falsifiable bet")
    - `altitude-reviewer` ("evaluates altitude band conformance")
    - `structural-format-reviewer` ("evaluates structural conformance to strategy-format.md")
- [ ] **AC12.4** — No `upper_bound` field on any reviewer.
- [ ] **AC12.5** — `skills/strategy/SKILL.md` has the `## Team Shape` section cross-referencing `./team.yaml`.
- [ ] **AC12.6** — Source-of-truth alignment matches DESIGN's verified migration table for /strategy.

## Dependencies

**Dependencies**: Issue 1
