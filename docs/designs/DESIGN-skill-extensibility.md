---
status: Proposed
problem: |
  shirabe's five workflow skills need to be extracted into the plugin and made
  extensible so downstream consumers can layer project-specific behavior without
  forking. Claude Code has no plugin-to-plugin extensibility, and the skills
  contain 20-30% project-specific behavior (visibility detection, label lifecycle,
  scope routing) that must be customizable per project.
---

# DESIGN: Skill Extensibility

## Status

Proposed

## Context and Problem Statement

shirabe packages five workflow skills (/explore, /design, /prd, /plan, /work-on)
as a public Claude Code plugin. Extracting these skills into shirabe requires
separating generic workflow logic from project-specific customization so that
downstream consumers can adapt skills to their project's conventions without
forking and maintaining their own copies.

Claude Code's plugin system provides no mechanism for plugin-to-plugin
extensibility — no dependencies, no cross-plugin skill invocation, no composition.
Skills are namespaced per plugin, forming a flat additive pool. Any extensibility
mechanism must work within these constraints.

Skills are LLM-read markdown, not executable code. Extensibility works through
text composition. CLAUDE.md layering already provides project-wide context in
every session and handles 60-70% of customization needs (writing style,
visibility, scope defaults, label vocabulary). The remaining 20-30% is per-skill
behavior that CLAUDE.md cannot target precisely.

## Decision Drivers

- Skills are LLM-read markdown — extensibility works through text composition,
  not function overrides
- CLAUDE.md layering is free and covers most global customization needs
- LLMs naturally weight later-loaded instructions higher (append-based composition)
- Claude Code's plugin system may add dependency support in the future
  (anthropics/claude-code#27113)
- Extension mechanisms must survive shirabe skill updates without requiring
  downstream rewrites
- Extension loading must be deterministic — no LLM roundtrip to decide whether
  to load a customization file

## Considered Options

### Decision 1: Extension mechanism

**Context:** How should downstream consumers add project-specific behavior to
shirabe's base skills without forking them?

**Chosen: Two-layer (CLAUDE.md + per-skill extension files).**

CLAUDE.md handles cross-skill project-wide behavior (visibility detection, scope
defaults, writing style, label vocabulary). Per-skill extension files at
`.claude/skill-extensions/<name>.md` are loaded via `@` includes in the base
SKILL.md. The `@` resolution is handled client-side by Claude Code before the LLM
processes the skill — confirmed by testing: 0 tool calls, deterministic, works
with plugin registry install, `--plugin-dir`, and local paths. Missing files
produce silent skips (raw `@path` text visible to LLM but ignored in practice).
A `.local.md` variant (`.claude/skill-extensions/<name>.local.md`, gitignored)
enables personal machine-level overrides that aren't committed to the repo.

This cleanly separates what belongs in CLAUDE.md (applies to every conversation
in the project) from what belongs in extension files (applies only when a specific
skill runs). Typical downstream customizations — project-specific triage routing,
custom label vocabulary, internal tool invocations — fit in a small extension file
per skill. Most skills need little or no extension.

*Alternative rejected: CLAUDE.md-only.* Adequate for a small, stable set of
known customization points, but requires a shirabe update to unblock any downstream
consumer with an unanticipated need. Fails silently on header renames or semantic
changes with no error surface. Cannot redirect skill script invocations. Doesn't
scale beyond a small, stable header contract.

*Alternative rejected: Wrapper skills.* Downstream creates its own plugin with
skills that add project preamble then read the base SKILL.md. This results in
parallel maintenance rather than consumption — drift is the default outcome.
Read delegation (wrapper reads base SKILL.md at runtime) fails when the two
plugins are installed separately because Claude Code provides no cross-plugin
path resolution. Unnamespaced skill name conflicts have undefined behavior when
both plugins are active simultaneously.

### Decision 2: Phase-level extension granularity

**Context:** Should individual phases of multi-file workflow skills be independently
extensible?

**Chosen: Out of scope for this design.**

Phase-level extensions require either `@` includes in phase files (LLM-driven
Read calls, not deterministic) or loading all phase extensions up-front in SKILL.md
(deterministic but loads all phase extensions regardless of execution path). Both
mechanisms work, but the added complexity isn't justified by current known extension
needs. Skill-level extension files can express phase-specific intent ("when
executing Phase 0, also invoke upstream-context skill") without separate per-phase
files. This can be revisited if a downstream consumer demonstrates a clear need.

### Decision 3: Consumption model

**Context:** How downstream consumers install and wire up shirabe as a dependency
is out of scope for this design. shirabe's extension mechanism is installation-agnostic —
the `@.claude/skill-extensions/` path resolves from the workspace root regardless
of whether shirabe is installed via plugin registry, git submodule, or local path.
Concrete migration patterns for specific consumers belong in their own repositories.

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

## Solution Architecture

_To be completed_

## Implementation Approach

_To be completed_

## Security Considerations

_To be completed_

## Consequences

_To be completed_
