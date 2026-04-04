# DESIGN: Vision Artifact Type

## Status

Proposed

## Context and Problem Statement

The /explore workflow can crystallize into 9 artifact types, but none capture
the pre-requirements layer: why a project should exist, what it offers, and
how it fits the organization. When exploring a new project idea, the closest
options are PRD (too feature-specific, assumes the project already exists) or
Roadmap (sequences features, doesn't justify the project itself). Project
thesis and strategic justification either go undocumented or get embedded in
roadmap "Vision" sections, losing their identity as a distinct decision layer.

This design adds VISION as a supported artifact type in the crystallize
framework, with a reference skill, Phase 5 produce handler, and integration
into the existing pipeline.

## Decision Drivers

- Must integrate into the existing crystallize framework without structural
  changes (the scoring mechanism is type-agnostic)
- Must have clear boundaries with PRD and Roadmap to prevent misrouting
- Must work at both org-level and project-level scope
- Gated to strategic scope (tactical is a hard anti-signal, per exploration
  decision D4)
- Visibility controls content richness, not availability (Strategic+Public
  and Strategic+Private both valid)
- Must follow the established skill pattern (frontmatter spec, required
  sections, lifecycle, validation, quality guidance)
- No new commands needed — VISION is produced through /explore only
