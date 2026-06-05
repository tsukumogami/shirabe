---
complexity: testable
complexity_rationale: "Two coupled file edits (team.yaml creation + SKILL.md prose). Schema-validatable YAML; cross-reference verifiable via grep. Roster must match DESIGN's verified migration table verbatim (ground-truth-rebuilt after adversarial review)."
---

# Issue 7: docs(brief): add team.yaml and Team Shape section

## Goal

Create `skills/brief/team.yaml` and add a brief `## Team Shape` section to `skills/brief/SKILL.md` pointing at the new file. Content matches DESIGN Component 2's verified migration table for `/brief`.

## Acceptance Criteria

- [ ] **AC7.1** — File `skills/brief/team.yaml` exists.
- [ ] **AC7.2** — File parses as valid YAML against the Decision 5 vocabulary.
- [ ] **AC7.3** — `parent_layer.peers` is the empty list `[]`.
- [ ] **AC7.4** — `child_layer.peers` contains exactly two entries:
    - `role: content-quality-reviewer`, `cardinality: reviewer`, `phase: phase-4-validate`, `purpose:` (one-line description of "evaluates Problem Statement / User Outcome / Journeys / Scope Boundary quality")
    - `role: structural-format-reviewer`, `cardinality: reviewer`, `phase: phase-4-validate`, `purpose:` (one-line description of "verifies schema, heading, and format conformance")
- [ ] **AC7.5** — No `upper_bound` field on either reviewer entry (per Decision 5: required iff cardinality is `worker`).
- [ ] **AC7.6** — `skills/brief/SKILL.md` has a new `## Team Shape` section with brief prose (one or two sentences) pointing at `./team.yaml` and including the v1-not-parsed-at-dispatch clarifier per DESIGN Decision 2 cross-reference text.
- [ ] **AC7.7** — Source-of-truth alignment: declaration matches DESIGN's verified migration table for /brief; if any deviation seems needed, escalate to /scope.

## Dependencies

**Dependencies**: Issue 1
