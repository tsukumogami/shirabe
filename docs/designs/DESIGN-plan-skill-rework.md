---
upstream: docs/prds/PRD-plan-skill-rework.md
---

# DESIGN: Plan Skill Rework

## Status

Proposed

## Context and Problem Statement

The /plan skill's Phase 7 always produces a PLAN doc, regardless of input type.
For design docs and PRDs this works: the PLAN doc adds decomposition structure
(issues table, dependency graph, implementation sequence) that the upstream
artifact shouldn't carry. For roadmaps it's redundant. The roadmap format
already reserves an Implementation Issues section and a Dependency Graph section
(added in F2), but Phase 7 writes these into a separate PLAN doc instead.

The result is two documents tracking the same initiative. The roadmap has the
features, sequencing rationale, and progress tracking. The PLAN doc has the
GitHub issue links and dependency graph. When features change, both need
updating. The roadmap is the source of truth for what's planned; the PLAN doc
is a derivative that adds only the issue mapping.

The technical change is scoped to Phase 7's output path. Phases 1-6 already
handle roadmap input correctly: Phase 1 validates Active status, Phase 3 uses
feature-by-feature decomposition, Phase 4 generates planning issues with
needs-* labels. Only Phase 7's "write a PLAN doc" step needs to branch on
input type.

## Decision Drivers

- Phase 7 must branch cleanly on `input_type` without affecting existing
  single-pr and multi-pr paths for design docs and PRDs
- The roadmap's reserved sections have a specific format contract (defined in
  `roadmap-format.md`) that the output must match
- GitHub issue creation (batch script, placeholder substitution) is unchanged;
  only where the Issues table and Mermaid graph are written changes
- Roadmap mode is always multi-pr (features are independent work items handled
  by different people or in different repos)
- `parsePlanDoc()` in Go only parses PLAN docs and must not need changes
- The roadmap stays Active after enrichment (no status transition)
- Backward compatibility: existing PLAN docs and /implement workflows are
  unaffected
