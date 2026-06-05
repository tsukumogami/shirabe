---
complexity: testable
complexity_rationale: "Single worker entry with upper_bound 20; subtle exclusion of /review-plan (child invocation, not peer). DESIGN-validated clarification."
---

# Issue 10: docs(plan): add team.yaml and Team Shape section

## Goal

Create `skills/plan/team.yaml` and add a brief `## Team Shape` section to `skills/plan/SKILL.md`. Content matches DESIGN Component 2's verified migration table for `/plan`. Critical exclusion: `/review-plan` is a CHILD invocation (via Skill tool — that is the contract this whole work establishes), not a peer; it must NOT appear in `child_layer.peers`.

## Acceptance Criteria

- [ ] **AC10.1** — File `skills/plan/team.yaml` exists and parses as valid YAML.
- [ ] **AC10.2** — `parent_layer.peers: []`.
- [ ] **AC10.3** — `child_layer.peers` contains exactly one entry:
    - `role: decomposer`, `cardinality: worker`, `upper_bound: 20`, `phase: phase-4-agent-generation`, `purpose:` ("generates an issue body per outline from Phase 3; runtime count equals the issue count emitted by Phase 3, capped at the upper bound")
- [ ] **AC10.4** — `/review-plan` is NOT listed as a peer (it is a child invocation per Decision 1's contract surface — not a peer).
- [ ] **AC10.5** — `skills/plan/SKILL.md` has the `## Team Shape` section cross-referencing `./team.yaml`.
- [ ] **AC10.6** — Source-of-truth alignment matches DESIGN's verified migration table for /plan verbatim.

## Dependencies

**Dependencies**: Issue 1
