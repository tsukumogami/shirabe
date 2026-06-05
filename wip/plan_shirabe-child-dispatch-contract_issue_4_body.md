---
complexity: testable
complexity_rationale: "Verbatim symmetric edit across two parents' SKILL.md files. Symmetry check is the key acceptance signal; AC13 requires identical cross-reference text."
---

# Issue 4: docs(scope,charter): cross-reference Dispatch Contract from parent Team Shape sections

## Goal

Add a closing cross-reference sentence to `skills/scope/SKILL.md`'s `## Team Shape` section and to `skills/charter/SKILL.md`'s `## Team Shape` section. Both point at the new `## Dispatch Contract` section. The cross-reference text is VERBATIM between the two parents (only parent name differs where unavoidable; the reference target string is identical).

## Acceptance Criteria

- [ ] **AC4.1** — `skills/scope/SKILL.md`'s `## Team Shape` section ends with a cross-reference to `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` `## Dispatch Contract` section as the source of the dispatch mechanism.
- [ ] **AC4.2** — `skills/charter/SKILL.md`'s `## Team Shape` section ends with the same cross-reference.
- [ ] **AC4.3** — The cross-reference text in `/scope` and `/charter` differs only in parent name (`/scope` vs `/charter`) — pre-formatted diff (excluding parent names) is empty.
- [ ] **AC4.4** — Existing prose in both Team Shape sections (the parent runs single-agent at its own layer) is preserved; the cross-reference is additive.
- [ ] **AC4.5** — Both cross-references use the `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` form (matching the idiom both files already use throughout, per DESIGN Component 3 verification).
- [ ] **AC4.6** — Verify: `grep -F 'Dispatch Contract' skills/scope/SKILL.md skills/charter/SKILL.md` returns at least one hit per file.

## Dependencies

**Dependencies**: Issue 1
