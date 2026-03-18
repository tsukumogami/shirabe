---
status: Proposed
problem: |
  shirabe's five workflow skills need to be extracted from the private tools
  repo and made extensible so downstream consumers can layer project-specific
  behavior without forking. Claude Code has no plugin-to-plugin extensibility,
  and the skills contain 20-30% project-specific behavior (visibility detection,
  label lifecycle, scope routing) that must be customizable per project.
---

# DESIGN: Skill Extensibility

## Status

Proposed

## Context and Problem Statement

shirabe packages five workflow skills (/explore, /design, /prd, /plan, /work-on)
as a public Claude Code plugin. These skills currently live in the private tools
repo with project-specific behavior woven into the skill logic. The extraction
into shirabe requires separating generic workflow logic from project-specific
customization, and the tools repo must become a shirabe consumer rather than
maintaining its own copies.

Claude Code's plugin system provides no mechanism for plugin-to-plugin
extensibility — no dependencies, no cross-plugin skill invocation, no composition.
Skills are namespaced per plugin, forming a flat additive pool. Any extensibility
mechanism must work within these constraints.

Skills are LLM-read markdown, not executable code. Extensibility works through
text composition. CLAUDE.md layering already provides project-wide context in
every session and handles 60-70% of customization needs (writing style,
visibility, scope defaults, label vocabulary). The remaining 20-30% is per-skill
phase logic that CLAUDE.md cannot target precisely.

## Decision Drivers

- Skills are LLM-read markdown — extensibility works through text composition,
  not function overrides
- CLAUDE.md layering is free and covers most global customization needs
- LLMs naturally weight later-loaded instructions higher (append-based composition)
- The tools repo is the first and primary downstream consumer
- Claude Code's plugin system may add dependency support in the future
  (anthropics/claude-code#27113)
- Extension mechanisms must survive shirabe skill updates without requiring
  downstream rewrites
- koto pipeline orchestration is Phase Future — extension model must work within
  single-workflow state machines for now

## Considered Options

### Decision 1: Extension mechanism

**Context:** How should downstream consumers add project-specific behavior to
shirabe's base skills without forking them?

**Chosen: Two-layer (CLAUDE.md + per-skill extension files).**

CLAUDE.md handles cross-skill project-wide behavior (visibility detection, scope
defaults, writing style, label vocabulary). Per-skill extension files at
`.claude/skill-extensions/<name>.md` are loaded via `@` includes in the base
SKILL.md. The `@` resolution is handled client-side by Claude Code before the LLM
processes the skill — confirmed by testing: 0 tool calls, deterministic, works with
`--plugin-dir`, registry install, and local path. Missing files produce silent skips
(raw `@path` text visible to LLM but ignored in practice). A `.local.md` variant
(`.claude/skill-extensions/<name>.local.md`, gitignored) enables personal
machine-level overrides that aren't committed to the repo.

This cleanly separates what belongs in CLAUDE.md (applies to every conversation in
the project) from what belongs in extension files (applies only when a specific skill
runs). The tools repo's customization needs — triage routing with upstream-context
invocation, cross-repo issue handling, private-repo research agent behavior — fit
in an ~80-line extension file for `/explore`. Other skills need less.

*Alternative rejected: CLAUDE.md-only.* Adequate for the tools repo's current
known needs, but requires a shirabe update to unblock any downstream consumer with
an unanticipated customization point. Fails silently on header renames or semantic
changes with no error surface. Cannot redirect skill script invocations. Doesn't
scale beyond a small, stable header contract.

*Alternative rejected: Wrapper skills.* The tools repo already uses this pattern
today, which is why extraction is needed. Inline duplication makes the tools repo
a parallel maintainer, not a consumer — drift is the default outcome. Read
delegation (wrapper reads base SKILL.md at runtime) fails under two separately
installed plugins because Claude Code provides no cross-plugin path resolution.
Unnamespaced skill name conflicts have undefined behavior when both plugins are
installed simultaneously.

### Decision 2: Phase-level extension granularity

**Context:** Should individual phases of multi-file workflow skills be independently
extensible?

**Chosen: Out of scope for this design.**

Phase-level extensions would require either `@` includes in phase files (not
deterministic — LLM-driven Read calls) or loading all phase extensions up-front in
SKILL.md (deterministic but loads all phase extensions regardless of execution path).
Testing confirmed both mechanisms work, but the added complexity isn't justified
by the tools repo's known needs. Skill-level extension files can express phase-specific
intent ("when executing Phase 0, also invoke upstream-context skill") without needing
separate per-phase files. This can be revisited if a downstream consumer demonstrates
a clear need.

## Decision Outcome

The two-layer extension model defines how downstream consumers customize shirabe skills:

1. **CLAUDE.md** — project-wide context loaded in every conversation. Skills read
   documented headers (`## Repo Visibility`, `## Planning Context`, etc.) to adapt
   global behavior. No changes to this existing mechanism.

2. **`.claude/skill-extensions/<name>.md`** — per-skill extension file. Each base
   SKILL.md includes `@.claude/skill-extensions/<name>.md` and
   `@.claude/skill-extensions/<name>.local.md` at its head. Both are resolved
   client-side; missing files are silently skipped. Downstream consumers create
   these files to extend specific skills without touching shirabe's source.

Key properties:
- Deterministic: extension loading requires 0 LLM tool calls
- Installation-agnostic: path resolves from workspace root regardless of how shirabe is installed
- Layered: repo-level extension committed to the project; `.local.md` gitignored for personal overrides
- Update-resilient: extension files express intent ("also invoke X"), not structure ("override phase-0-setup.md")
- No new infrastructure: `@` include is an existing Claude Code feature

## Extraction Plan

_To be completed_

For each of the five skills, identify:
- What generic workflow logic moves to shirabe as-is
- What project-specific behavior is removed from the base skill
- What helpers are portable (move to shirabe) vs project-specific (stay in tools)
- What cross-references break and how they are resolved

Known project-specific coupling per the audit:
- Visibility detection: reads `## Repo Visibility` from CLAUDE.md or infers from path
- Scope detection: reads `## Default Scope` from CLAUDE.md or accepts `--strategic`/`--tactical`
- Label vocabulary: references `label-reference.md` (tsuku-specific labels)
- Cross-repo issue handling: visibility rule prevents public repos from referencing private issues
- Private-only routing: conditional branches for competitor analysis, internal rationale

Portable helpers (move to shirabe):
- `writing-style.md` — universal AI writing pattern guidance
- `public-content.md` / `private-content.md` — visibility-based content rules
- `decision-presentation.md` — shared decision routing logic
- `design-approval-routing.md` — shared routing between /explore and /design

## Consequences

_To be completed_
