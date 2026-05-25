---
complexity: simple
complexity_rationale: Pure documentation addition to a single CLAUDE.md file with no logic, no validation script beyond grep-for-trigger-phrases, and no security implications.
---

## Goal

Update the shirabe repo's `CLAUDE.md` to surface `/charter`'s entry triggers and discovery surface per the parent-skill pattern's R17a discipline, including the four `/charter`-specific trigger phrases from R17b.

## Context

This issue ships Stage 3 of the design's three-stage implementation approach — surfacing `/charter` through the same CLAUDE.md channels that authors already use to discover shipped shirabe skills (`/strategy`, `/explore`, `/decision`, `/design`, `/prd`, `/roadmap`, `/vision`, `/work-on`, `/plan`). Without this surfacing, `/charter` is invocable but undiscoverable — an author who reaches for "I want to open a charter for X" has no signal that the skill exists.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md`

This issue authors against the following design section:

```
Design Stage 3 (CLAUDE.md surfacing); PRD R17a (pattern-level), R17b (/charter-specific trigger phrases); AC26b
```

R17a is pattern-level: every parent skill SHALL ship CLAUDE.md updates that surface its entry triggers and discovery surface. R17b binds the parent-specific trigger phrase list for `/charter`. The pattern-level contribution from this issue is the surfacing-discipline application; the `/charter`-specific contribution is the four verbatim trigger phrases.

The trigger phrases that MUST appear in the CLAUDE.md update (verbatim, per R17b):

- "start a strategic conversation about X"
- "open a charter for Y"
- "I need to think through the bet on Z"
- direct `/charter <topic>` invocations

The mention SHOULD align with how shipped shirabe skills are already surfaced in the file — same prose style, same level of detail. Read the existing `CLAUDE.md` first to determine where shipped skills are listed (if anywhere); place `/charter` alongside its peers in the natural listing or add a discovery-surface section that names `/charter`'s entry triggers.

### Workspace fragment claim (no separate cross-repo PR)

Per Design Stage 3, the workspace-level CLAUDE.md is composed from per-repo fragments: each repo updates its own fragment, and workspace tooling assembles the composite. The shirabe repo's `CLAUDE.md` IS the workspace fragment for shirabe. So updating shirabe's `CLAUDE.md` satisfies both the shirabe-side and the workspace-fragment halves of AC26b; the workspace tooling assembles the composite on next refresh. No separate workspace-repo PR is required.

### Independence

This issue has no blocking dependencies. The trigger phrases reference `/charter` by name, not by file existence — the surfacing can land before, during, or after `/charter`'s SKILL.md exists. Authors who try the trigger phrases before `/charter` ships will see a "skill not found" response, which is the same failure mode any pre-implementation discovery surface produces. The issue can be picked up at any point in the implementation timeline.

### Public-repo discipline

This is a public repo. The CLAUDE.md addition MUST NOT reference private repos, internal resources, or pre-announcement features. The trigger phrases and skill name only — no internal tooling references, no competitor names, no business-strategy framing.

## Acceptance Criteria

- [ ] `CLAUDE.md` (at repo root) mentions `/charter` (literal substring, case-insensitive).
- [ ] `CLAUDE.md` contains the literal substring "start a strategic conversation" (case-insensitive).
- [ ] `CLAUDE.md` contains the literal substring "open a charter" (case-insensitive).
- [ ] `CLAUDE.md` contains the literal substring "think through the bet" (case-insensitive).
- [ ] `CLAUDE.md` contains the literal substring "/charter" (the slash-command name) at least once outside of any verbatim trigger-phrase quotation, in a context that names it as a shipped slash command.
- [ ] The `/charter` mention is placed in the same listing or section that names other shipped shirabe slash commands (`/strategy`, `/explore`, `/decision`, etc.); if no such listing exists, a short discovery-surface section is added that names `/charter`'s entry triggers.
- [ ] The prose style and level of detail of the `/charter` mention is consistent with how peer shipped skills are described in the same file.
- [ ] The CLAUDE.md addition contains no private-repo references, no pre-announcement features, no internal-tooling names.
- [ ] Tests pass (run project's test command).
- [ ] CI green.

## Dependencies

None.

This issue is independent — it can land at any point in the implementation timeline. The trigger phrases name `/charter` by string, not by file existence; landing this update before `/charter`'s SKILL.md exists is acceptable because pre-implementation discovery surfaces produce the same "skill not found" failure mode any other not-yet-shipped feature would.

## Downstream Dependencies

None. This is a leaf issue in the plan's dependency graph. After it lands, `/charter` is discoverable through the same CLAUDE.md channels authors already use for shipped shirabe skills, satisfying AC26b and closing the pattern-level R17a discipline for `/charter`.
