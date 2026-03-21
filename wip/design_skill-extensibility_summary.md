# Design Summary: skill-extensibility

## Input Context (Phase 0)
**Source:** /explore handoff (shirabe#2), upstream context from tsukumogami/vision PR #355
**Problem:** Extract 5 workflow skills into shirabe and design extensibility for
downstream consumers. Claude Code has no plugin-to-plugin extensibility.
**Constraints:**
- LLM-read markdown (not code) — extensibility is text composition
- CLAUDE.md layering already handles 60-70% of customization needs
- koto per-skill templates required; cross-workflow chaining is Phase Future
- Tools PR #601 merged — extraction uses tools main as source
- Skills communicate via artifacts with YAML frontmatter status gates

## Approaches Investigated (Phase 1)
- CLAUDE.md-only: adequate for known tools repo needs, but requires shirabe update for unanticipated consumers; fails silently on semantic changes
- Two-layer (CLAUDE.md + extension files): tested and confirmed deterministic; ~80-line extension file covers all tools repo needs; no new infrastructure
- Wrapper skills: structurally fails the consumption goal; tools repo would remain a parallel maintainer

## Selected Approach (Phase 2)
Two-layer model selected. CLAUDE.md for cross-skill project-wide behavior;
`.claude/shirabe-extensions/<name>.md` + `.local.md` loaded via `@` includes in
SKILL.md. Client-side resolution confirmed (0 tool calls). Downstream extends
without requiring shirabe changes.

## Investigation Findings (Phase 3)
- extraction-audit: 11-13% project-specific content (~185-220 lines of 1,668). /design has most to remove (tsuku security block, label lifecycle, swap-to-tracking.sh). /explore nearly generic. Five of six helpers portable; label-reference.md folds into CLAUDE.md.
- consumption-model: out of scope for this design doc; filed tsukumogami/tools#604 for migration. Extension mechanism is installation-agnostic regardless.
- breaking-change-contract: three breaking categories (removing @ slot lines, renaming phase names in workflow overview, renaming CLAUDE.md headers). CHANGELOG.md with dedicated extension contract section is sufficient signal for now.

## Current Status
**Phase:** 6 - Final Review
**Last Updated:** 2026-03-17

## Open Decisions
1. Extension mechanism (CLAUDE.md-only vs two-layer vs other)
2. Consumption model (submodule vs two plugins vs merged install)
3. Sequencing (extract-first vs design extensibility upfront)
4. Breaking change contract for markdown-based skills

## Prior Research
Full round-1 research from vision PR #355 available in:
- Findings: `wip/explore_skill-extensibility_findings.md`
- Scope: `wip/explore_skill-extensibility_scope.md`
