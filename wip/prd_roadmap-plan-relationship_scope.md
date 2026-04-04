# /prd Scope: roadmap-plan-relationship

## Problem Statement

The workflow system has two artifact types that both sequence work items with dependencies: Roadmap (portfolio-level, sequences features) and Plan (implementation-level, sequences issues). They share structural traits (ordered items, dependency graphs, progress tracking, Draft -> Active -> Done lifecycle) but are treated as fully separate artifacts with separate skills. The F2 design for /roadmap essentially recreates /plan's structure with different agent roles — duplicating dependency management, progress tracking, and lifecycle patterns. The boundary between "roadmap" and "plan" is unclear, and it's not obvious whether they should be separate types, modes of the same type, or a shared base with specializations.

## Initial Scope

### In Scope
- Defining the relationship between roadmap and plan artifacts
- Whether they should share structure, lifecycle, or tooling
- What's genuinely different vs what's duplicated
- How the answer affects the /roadmap creation skill (F2)
- Impact on existing /plan skill and its consumers (/implement, /work-on)

### Out of Scope
- Changes to /prd, /design, or /vision skills
- Go code changes to workflow-tool
- The specific agent roles and jury criteria for /roadmap (that's the design's job)
- Retroactive changes to already-shipped Plan artifacts

## Research Leads

1. **What structural components do roadmaps and plans actually share?**: Compare the two format specs side by side. Map every section, frontmatter field, and lifecycle rule. Quantify the overlap.

2. **What's genuinely different between them, and are those differences fundamental or incidental?**: Features vs issues, needs-* vs complexity labels, PRD-level vs implementation-level. Are these hard boundaries or just different parameterizations of the same concept?

3. **How do other workflow systems handle multi-level planning?**: Do tools like Linear, Notion, Jira, or Shape Up distinguish between "high-level roadmap" and "implementation plan," or do they use a single planning abstraction with hierarchy?

4. **What are the options for the relationship model?**: Separate types (status quo), shared base with specializations, single type with modes, or hierarchy (roadmap contains plans). What are the trade-offs?

5. **What would break if we unified them?**: /plan has specific consumers (/implement, /work-on, workflow-tool). /plan produces GitHub issues and milestones. Roadmaps are consumed by /plan itself. What constraints does the existing codebase impose?

## Coverage Notes

The user flagged this during F2 design review. The current ROADMAP-strategic-pipeline.md cross-cutting decisions assume separate skills per doc type, but that decision was about creation workflows — it doesn't mandate separate artifact structures. The PRD should determine whether "separate but similar" or "unified with modes" better serves the pipeline.
