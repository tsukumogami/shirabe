---
complexity: testable
complexity_rationale: "Single attachment-point edit in /scope's Phase 2 reference. Must preserve existing 'child's existing input mode' wording and use the cross-reference text identical to Issue 6's."
---

# Issue 5: docs(scope): cross-reference Dispatch Contract from Phase 2 Child Invocation

## Goal

Add a leading cross-reference sentence to the `## Child Invocation` section of `skills/scope/references/phases/phase-2-chain-orchestration.md`. Points at the new `## Dispatch Contract` section as the source of the dispatch mechanism. Existing "the child's existing input mode" wording is preserved.

## Acceptance Criteria

- [ ] **AC5.1** — `skills/scope/references/phases/phase-2-chain-orchestration.md`'s `## Child Invocation` section begins with a cross-reference to `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` `## Dispatch Contract`.
- [ ] **AC5.2** — Existing "the child's existing input mode: `/<child-name> <topic-slug>`" wording is preserved (or absorbed into the contract section per DESIGN — if absorbed, the Phase 2 step becomes a back-reference).
- [ ] **AC5.3** — Cross-reference text is identical to Issue 6's text (verify per Issue 13's combined AC13 symmetry check).

## Dependencies

**Dependencies**: Issue 1
