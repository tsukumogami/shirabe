# Explore Scope: skill-extensibility

## Core Question

How should shirabe's workflow skills support extensibility, so that downstream
consumers (like the tools repo) can layer project-specific behavior on top of
base skills without forking? And what does a complete extraction of the five
skills from the tools repo into shirabe require?

## Context

shirabe#2 asks for two things: extracting the five workflow skills into shirabe
as the canonical source, and designing an extensibility mechanism. The tools repo
currently has 51 skills in a single plugin, with project-specific behavior
(visibility detection, scope routing, label lifecycle, cross-repo issue handling,
tsuku-specific conventions) woven into the skill logic. After extraction, the
tools repo should install shirabe as a dependency and extend its skills with
private behavior rather than maintaining its own copies.

**Upstream exploration already completed** in tsukumogami/vision PR #355
(`docs/skill-extensibility` branch). Round 1 produced five leads and crystallized
to Design Doc. Key findings and open decisions are carried forward here.

**Tools PR #601 merged** (2026-03-17). The opinionated workflow refactor is done.
Extraction should target the current tools main branch as the source.

**PRD-shirabe.md architectural constraints** (already decided):
- Skills require koto and fail with a guided install message if absent
- Each skill gets its own koto template (not a composite pipeline)
- Skills communicate via artifacts with YAML frontmatter status gates
- Progressive disclosure: phase instructions loaded on demand

## In Scope

- Extensibility model: how downstream projects customize shirabe skills
- Extraction plan: what needs to change in each of the five skills
- Helper portability: which helpers are core vs project-specific
- Tools repo integration: how it becomes a shirabe consumer
- Breaking change contract for markdown-based skills

## Out of Scope

- Koto template integration (Feature 3, separate issue)
- CI validation portability (Feature 6, separate issue)
- The actual implementation of extraction (produces a design doc)
- Koto pipeline orchestration / cross-workflow chaining (Phase Future per DESIGN-workflow-tool-oss.md)

## Leads Investigated (Round 1 — via vision PR #355)

1. **How do Claude Code plugins handle extensibility today?**
   Result: Zero plugin-to-plugin extensibility. Flat additive pool only.

2. **What extensibility patterns exist in comparable plugin ecosystems?**
   Result: Append-based composition best fits LLM-read markdown. VS Code/ESLint-style
   "extends" patterns work for code but not for prompt-based systems.

3. **What project-specific behavior exists in the five target skills today?**
   Result: Skills are 70-80% generic. Project-specific coupling in: visibility
   detection, scope detection, label vocabulary, cross-repo issue handling,
   private-only routing (competitor analysis, internal rationale).

4. **How should the tools repo consume shirabe as a dependency?**
   Result: Submodule initially. Migrate to two plugins when Claude Code ships deps.

5. **What extensibility mechanism fits the "extension files loaded if present" model?**
   Result: Two-layer model — CLAUDE.md for project-wide behavior, per-skill
   extension files in `.claude/skill-extensions/<name>.md` for per-skill additions.

## Open Design Decisions (for the design doc to resolve)

1. Extension mechanism: CLAUDE.md-only vs two-layer (CLAUDE.md + skill extension files)
2. Consumption model: submodule vs two plugins vs merged install
3. Sequencing: extract-first vs design extensibility upfront
4. Breaking change contract for markdown-based skills
