---
complexity: simple
complexity_rationale: Single-paragraph documentation addition to a markdown pattern reference — no code, no behavior change, no new tests beyond grep-against-file verification.
---

## Goal

Append a single paragraph to the Slot 5 spec in `references/parent-skill-resume-ladder-template.md` documenting the refuse-and-redirect prompt shape parents emit when a terminal-artifact lifecycle state is owned by a downstream skill, preserving the existing 9-row meta-ladder count.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md` (Solution Architecture / Component 3)

The resume-ladder template (`references/parent-skill-resume-ladder-template.md:99-124`) defines Slot 5 — status-aware re-entry — as a parent-specific body slot. The slot's current spec describes the Re-evaluate / Revise / Bail triad parents emit when a child doc's status would otherwise trigger the child's own re-entry prompt. The spec does not yet name the refuse-and-redirect variant that applies when the lifecycle state is owned by a downstream skill rather than by the parent's chain.

`/scope`'s PLAN doc is the motivating case: PLAN-Active state is owned by `/work-on`, PLAN-Done by `/release`, neither owned by `/scope` itself. When `/scope` re-runs into a PLAN-Active or PLAN-Done state, the correct re-entry shape is to refuse re-entry and redirect to the downstream-owning skill — not to offer the Re-evaluate / Revise / Bail triad (which would imply the parent owns the artifact's revision flow). Without this paragraph in the pattern reference, the refuse-and-redirect shape is `/scope`-specific lore rather than a documented Slot 5 variant other parents can adopt.

The paragraph also covers the vacuous case: parents whose chains have no downstream-owning skill (e.g., `/charter`'s STRATEGY is Accepted-terminal) have vacuous Slot 5 entries for the corresponding states — the template accommodates both cases without changing the 9-row meta-ladder count.

Verbatim paragraph to append (per Component 3.1 of the design):

> Some parents' terminal artifacts have lifecycle states owned by downstream skills (e.g., `/scope`'s PLAN doc has an Active state owned by `/work-on` and a Done state owned by `/release`). The parent's Slot 5 entries for those states SHALL refuse re-entry and emit a redirect prompt naming the downstream-owning skill. The redirect prompt SHALL contain the literal substring `redirect to /<skill-name>` (case-insensitive) and SHALL NOT contain the Re-evaluate / Revise / Bail triad (refuse-and-redirect is not a re-evaluation exit; the downstream skill owns the artifact). When the parent's chain has no downstream-owning skill (e.g., `/charter`'s STRATEGY is Accepted-terminal), the parent's Slot 5 entries for the corresponding lifecycle states are vacuous — the slot template accommodates both cases without changing the 9-row meta-ladder count.

## Acceptance Criteria

- [ ] The paragraph above is appended to the Slot 5 spec section ("### Slot 5 — status-aware re-entry") in `references/parent-skill-resume-ladder-template.md`, after the existing Slot-filling rules bullet list
- [ ] The paragraph wording matches the verbatim text in the Context section above (block quote stripped; markdown links allowed if added to skill names)
- [ ] The paragraph names both the populated case (downstream-owning skill exists) and the vacuous case (no downstream-owning skill, e.g., `/charter`'s STRATEGY)
- [ ] `grep -q 'refuse-and-redirect' references/parent-skill-resume-ladder-template.md` returns 0
- [ ] `grep -qi 'redirect to /<skill-name>' references/parent-skill-resume-ladder-template.md` returns 0 (the literal-substring rule the paragraph documents is itself present in the paragraph)
- [ ] The 9-row meta-ladder count is preserved: the Ladder Shape diagram (lines 17-31 of the existing file) and the Slot 5 / Slot 6 / Slot 7 section headers remain unchanged
- [ ] No other content in `references/parent-skill-resume-ladder-template.md` is modified beyond the appended paragraph
- [ ] The Slots 6 and 7 sections still follow Slot 5 in the document (the append lands inside Slot 5's section, not after Slot 7)
- [ ] CI green

## Dependencies

None.

## Downstream Dependencies

<<ISSUE:10>>

`/scope`'s SKILL.md (Component 5) cites this paragraph as the pattern-level basis for its 9-row Slot 5 (which contains the PLAN-Active → `/work-on` and PLAN-Done → `/release` refuse-and-redirect rows). Until this paragraph lands, `/scope`'s SKILL.md cannot cite the refuse-and-redirect shape as a documented Slot 5 variant.
