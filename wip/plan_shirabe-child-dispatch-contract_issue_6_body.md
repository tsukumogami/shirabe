---
complexity: testable
complexity_rationale: "Four attachment points in a single file. Verbatim-identical cross-reference text required across all four; AC13 grep verifies the multi-point landing."
---

# Issue 6: docs(charter): cross-reference Dispatch Contract from Phase 2 per-child Invocation Rules

## Goal

Add a leading cross-reference sentence to each of the four per-child Invocation Rule sections in `skills/charter/references/phases/phase-2-chain-orchestration.md`: `## /vision Invocation Rule (R4)`, `## /comp Invocation Rule (R5 + R12)`, `## /strategy Invocation Rule (R6)`, `## /roadmap Invocation Rule (R7)`. Cross-reference text is IDENTICAL across all four and identical to Issue 5's /scope text. Per-child Invocation Rule content is preserved.

## Acceptance Criteria

- [ ] **AC6.1** — `## /vision Invocation Rule (R4)` begins with the cross-reference.
- [ ] **AC6.2** — `## /comp Invocation Rule (R5 + R12)` begins with the cross-reference.
- [ ] **AC6.3** — `## /strategy Invocation Rule (R6)` begins with the cross-reference.
- [ ] **AC6.4** — `## /roadmap Invocation Rule (R7)` begins with the cross-reference.
- [ ] **AC6.5** — Per-child Invocation Rule content (the conditional invocation logic in each rule) is preserved.
- [ ] **AC6.6** — All four cross-references are byte-identical to each other and identical to Issue 5's text. Verify: extract each leading sentence and diff — empty diff.
- [ ] **AC6.7** — Verify: `grep -c 'Dispatch Contract' skills/charter/references/phases/phase-2-chain-orchestration.md` returns at least `4`.

## Dependencies

**Dependencies**: Issue 1
