---
complexity: testable
complexity_rationale: "Most complex roster — four peers across three phases, mixing worker (decision-researcher with upper_bound 9) and reviewers. Ground-truth fidelity is critical; adversarial review previously caught fabricated role names. Single-pr mode does not require Security Checklist; testable is correct."
---

# Issue 9: docs(design): add team.yaml and Team Shape section

## Goal

Create `skills/design/team.yaml` and add a brief `## Team Shape` section to `skills/design/SKILL.md`. Content matches DESIGN Component 2's verified migration table for `/design` — the most complex of the seven rosters.

## Acceptance Criteria

- [ ] **AC9.1** — File `skills/design/team.yaml` exists and parses as valid YAML.
- [ ] **AC9.2** — `parent_layer.peers: []`.
- [ ] **AC9.3** — `child_layer.peers` contains exactly four entries:
    - `role: decision-researcher`, `cardinality: worker`, `upper_bound: 9`, `phase: phase-2-execution`, `purpose:` ("walks the decision protocol per pending architectural question")
    - `role: security-researcher`, `cardinality: reviewer`, `phase: phase-5-security`, `purpose:` ("investigates security implications of the chosen architecture")
    - `role: architecture-reviewer`, `cardinality: reviewer`, `phase: phase-6-final-review`, `purpose:` ("evaluates structural integrity of the final DESIGN")
    - `role: security-reviewer`, `cardinality: reviewer`, `phase: phase-6-final-review`, `purpose:` ("evaluates security posture of the final DESIGN")
- [ ] **AC9.4** — `decision-researcher` has `upper_bound: 9` (canonical per DESIGN's cite of `docs/designs/current/DESIGN-shirabe-progression-authoring.md:1192`). No other entry has `upper_bound`.
- [ ] **AC9.5** — `skills/design/SKILL.md` has the `## Team Shape` section cross-referencing `./team.yaml`.
- [ ] **AC9.6** — Source-of-truth alignment matches DESIGN's verified migration table for /design verbatim. DO NOT re-derive from skim-reading SKILL.md (the adversarial review caught fabricated role names this way the first time).

## Dependencies

**Dependencies**: Issue 1
