# Exploration Findings: skill-extensibility

## Core Question

How should shirabe's workflow skills support extensibility for downstream consumers?

## Round 1

Source: tsukumogami/vision PR #355, supplemented by tools repo and PRD-shirabe.md audit.

### Key Insights

**Platform constraints:**
- Claude Code has zero plugin-to-plugin extensibility. The plugin system provides
  a flat additive pool of skills — no dependencies, no cross-plugin invocation,
  no composition. Any extensibility must work within these constraints.
- Skills are LLM-read markdown, not executable code. Extensibility works through
  text composition, not function overrides or hooks.
- CLAUDE.md layering is free and already used. It handles 60-70% of customization
  needs (writing style, visibility, scope, label vocabulary).
- LLMs naturally weight later-loaded instructions higher, making append-based
  composition the most natural model.

**Current skill structure:**
- 51 skills in the tools repo plugin. Five are the target: /explore, /design,
  /prd, /plan, /work-on.
- Skills are 70-80% generic workflow logic. Project-specific coupling is
  concentrated in: visibility detection (reads CLAUDE.md for `## Repo Visibility`
  or infers from path), scope detection, label lifecycle vocabulary, cross-repo
  issue handling, private-only routing branches.
- Each skill has SKILL.md + reference phase files. Helpers (writing-style,
  public/private content guidelines, decision-presentation, label-reference) are
  shared across skills via relative paths.

**Helpers — core vs project-specific:**
- Core (portable to shirabe): `writing-style.md`, `public-content.md`,
  `private-content.md`, `decision-presentation.md`, `design-approval-routing.md`
- Project-specific (tools repo keeps own copy): `label-reference.md` (tsuku label
  vocabulary, though the concept generalizes), any tsuku-specific routing logic

**Architecture decisions already made (PRD-shirabe.md):**
- Skills require koto and fail with a guided install message if absent
- Each skill gets its own koto template — no composite pipeline
- Skills communicate via artifacts with YAML frontmatter status gates
- Progressive disclosure: phase instructions loaded on demand
- Non-linear user workflows: users enter at whichever skill matches their starting point

**Tooling state:**
- Tools PR #601 merged 2026-03-17. Opinionated workflow refactor is done.
  Extraction source is now tools main branch.
- koto pipeline orchestration (cross-workflow chaining) is Phase Future per
  DESIGN-workflow-tool-oss.md. Extension model must work within single-workflow
  state machines.

**Candidate extensibility models:**
- CLAUDE.md-only: downstream projects customize entirely via project CLAUDE.md
  files. No per-skill extension mechanism. Works for global behavior but can't
  override individual skill phases.
- Two-layer: CLAUDE.md handles project-wide behavior, per-skill extension files
  in `.claude/skill-extensions/<name>.md` handle per-skill additions. Loaded via
  explicit include instructions in the base skill. Keeps base skills stable while
  allowing targeted overrides.
- Wrappers / fork: downstream copies skills and modifies them. No coordination
  with upstream. Breaks on shirabe updates.

**Consumption model options:**
- Submodule: tools repo includes shirabe as a git submodule in its plugin
  directory. Direct path. Requires manual submodule updates.
- Two plugins: shirabe installed as a separate Claude Code plugin alongside
  the tools plugin. Cleaner separation; blocked by Claude Code lacking dependency
  support (anthropics/claude-code#27113).
- Merged install: tools repo tooling merges shirabe skill files at install time.
  Maintains one plugin namespace but couples update mechanics.

**Sequencing insight:**
- Specialist review: extraction should be sequenced before extensibility work.
  Building the extensibility model on top of un-extracted skills means designing
  for two consumers of different shapes.

### User Decision

Ready to crystallize. Design Doc selected.

## Decision: Crystallize

## Accumulated Understanding

Two-layer extensibility model is the leading candidate:
1. CLAUDE.md for project-wide behavior (visibility, scope, writing style, labels)
2. Skill extension files for per-skill additions, loaded by the base skill if present

Extraction sequenced before extensibility. Tools repo consumes shirabe via
submodule initially; migrate to two plugins when Claude Code ships dependency
support.

Four open design decisions need permanent documentation in the design doc:
1. Extension mechanism: CLAUDE.md-only vs two-layer vs other
2. Consumption model: submodule vs two plugins vs merged install
3. Sequencing: extract-first vs design extensibility upfront
4. Breaking change contract for markdown-based skills
