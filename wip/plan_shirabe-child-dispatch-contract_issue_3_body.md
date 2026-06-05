---
complexity: simple
complexity_rationale: "Single one-paragraph annotation in an existing reference; no schema fields change. Trivial to verify."
---

# Issue 3: docs(parent-skill-pattern): annotate state-schema with dispatch-contract cross-reference

## Goal

Add a one-paragraph annotation under the `parent_orchestration:` block schema in `references/parent-skill-state-schema.md` noting that the block is the pre-dispatch state element of the dispatch contract. Cross-reference the new `## Dispatch Contract` section. No schema fields change.

## Acceptance Criteria

- [ ] **AC3.1** — A one-paragraph annotation is added under the `parent_orchestration:` block schema in `references/parent-skill-state-schema.md`.
- [ ] **AC3.2** — Annotation cross-references `references/parent-skill-pattern.md`'s `## Dispatch Contract` section as the source.
- [ ] **AC3.3** — Annotation names the `parent_orchestration:` block as the pre-dispatch state element (matching the contract's `### Pre-Dispatch State` sub-section terminology).
- [ ] **AC3.4** — Schema fields (`invoking_child`, `suppress_status_aware_prompt`, `rationale`) are unchanged; only annotation prose is added.

## Dependencies

**Dependencies**: Issue 1
