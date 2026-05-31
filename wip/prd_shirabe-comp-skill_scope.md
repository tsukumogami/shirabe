# Scope: PRD shirabe-comp-skill

Source: `docs/briefs/BRIEF-shirabe-comp-skill.md` (status: Accepted).

## Problem
shirabe promotes seven artifact types to first-class — VISION, STRATEGY, ROADMAP, BRIEF, PRD, DESIGN, PLAN — each with a loadable skill, format reference, Phase 4 jury, and `shirabe validate` coverage. Competitive analysis (COMP) is recognized only by example: prior COMP docs exist, the format lives in a workspace-level reference outside shirabe, and authors reach it indirectly through `/explore`'s produce phase. `/charter`'s competitive sub-phase has no child to delegate to. Without a `/comp` skill, COMP stays second-class.

## Goals
- Promote COMP to a first-class shirabe artifact type with infrastructure that matches the other six.
- Ship `/comp` as a loadable phased skill following the `/strategy` and `/prd` pattern.
- Add `comp/v1` to `shirabe validate`'s Formats map; activate CI through the existing reusable workflow.
- Enforce COMP's private-only visibility rule at three independent layers: skill refusal, validate-CLI, CI guardrail.
- Define a `/charter` → `/comp` delegation contract so the strategic chain has a real child to invoke when competitive framing belongs in the conversation.

## In Scope
- COMP frontmatter schema and section structure resident in shirabe.
- `skills/comp/references/comp-format.md` format reference.
- `skills/comp/SKILL.md` plain-English loadable skill.
- Phase 4 jury rubric for competitive-analysis content quality and structural format.
- `internal/validate/formats.go` Formats-map extension for `comp/v1`.
- Visibility enforcement at skill, validate-CLI, and CI layers.
- `/charter` → `/comp` delegation contract surface (what `/comp` accepts, returns, and how it fails).
- Release-notes obligation for adopter path-filter widening.
- `shirabe` CLAUDE.md guidance for when to reach for `/comp`.

## Out of Scope
- `/charter` skill changes (consumed in /charter's own scope).
- Migration of existing COMP documents (no retrofit).
- Deprecation of any workspace-level COMP tooling that already exists.
- External-adopter behavior tracking.
- Changes to `/explore`'s existing COMP routing.

## Open Questions to Resolve
1. Lifecycle ladder (`Draft → Final` vs. richer multi-state).
2. Jury reviewer count and rubric (two vs. three reviewers).
3. Visibility enforcement implementation (path-based vs. schema-based vs. generic framework).
4. Format-spec source of truth (copy from workspace skill verbatim, port with shirabe-conformant edits, or rewrite).
5. `/charter` → `/comp` contract shape (inputs, outputs, failure handling).

## Architectural Alternatives to Surface as Requirements-Level Decisions
- Visibility enforcement layer choice (validate-CLI vs skill-only) — at least one must surface so `/design` has a decision question.
- Jury structure shape (extend existing reviewer rubric vs new reviewer category for competitive content).
- Format-spec location (shared with `/strategy` style or distinct).

## Visibility
Public repo (shirabe). Public-PRD content rules apply: no private repo references, no issue-by-number, no private artifact citation by name.
