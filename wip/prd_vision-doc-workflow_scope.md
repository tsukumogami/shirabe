# /prd Scope: vision-doc-workflow

## Problem Statement

The /explore workflow can crystallize into 9 artifact types (PRD, Design Doc, Plan, Roadmap, Spike Report, Decision Record, Competitive Analysis, Rejection Record, No Artifact), but none capture the pre-requirements layer: "why should this project exist, what does it offer, and how does it fit the org." When a user explores a new project idea, the closest options are PRD (too feature-specific) or Roadmap (too execution-focused). The result is that project thesis and strategic justification either go undocumented or get shoehorned into a roadmap's "Vision" section, losing their identity as a distinct decision layer.

## Initial Scope

### In Scope
- VISION as a new supported artifact type in the crystallize framework with signal/anti-signal table, tiebreaker rules, and disambiguation rules
- VISION document template with sections for thesis, audience, value proposition, org fit, success criteria, non-goals, open questions, and downstream artifacts
- VISION lifecycle: Draft -> Accepted -> Active -> Sunset (distinct from other types — stays Active rather than completing)
- Naming convention: `VISION-<name>.md` in `docs/visions/` directory
- Frontmatter schema with status, thesis (summary), scope (org/project), and upstream fields
- Scope gating: VISION available in strategic scope only; tactical scope is a hard anti-signal
- Visibility-aware content sections: competitive positioning and resource implications only in private repos
- Phase 5 produce handler for VISION (inline production, not a separate command)
- VISION reference skill (`skills/vision/SKILL.md`) defining format, lifecycle, validation rules, and content boundaries
- Org-level vs project-level support via the `scope` frontmatter field (org vs project)
- PROJECTS.md as a lifecycle-tracked project registry with states: Idea -> Evaluating -> Committed -> Active -> Maintained -> Archived -> Rejected

### Out of Scope
- Standalone `/vision` command (VISION is produced through /explore only)
- Intermediate artifact types between VISION and PRD (not needed at this org's scale)
- Reference standards for existing deferred types (roadmap, spike, ADR) — independently valuable, separate initiative
- Migration of existing informal vision content (roadmap "Vision" sections) to the new format
- Changes to /prd, /design, or /plan commands
- Go code changes to workflow-tool
- New-repo-playbook automation (remains a manual guide)
- Competitive Analysis skill in shirabe (stays in private plugin only)

## Research Leads

1. **What sections does the VISION template need, and what are the content boundaries vs PRD and Roadmap?**: The exploration produced a draft template (Lead: vision-template) with thesis, audience, value proposition, org fit, success criteria, non-goals. The PRD process should validate these sections and define content boundary rules.

2. **What are the exact crystallize signals, anti-signals, and tiebreaker rules for VISION?**: The exploration produced a draft signal table (Lead: crystallize-extension). The PRD process should specify these precisely as acceptance criteria.

3. **How does the Phase 5 produce handler work for VISION?**: VISION is produced inline (not via a separate command). The handler needs to populate the template from exploration findings, handle org-level vs project-level variants, and enforce visibility constraints.

4. **What does the VISION lifecycle look like in practice, and how does "Active" status differ from other artifacts?**: The exploration identified that VISIONs don't "complete" — they stay Active. The PRD should define transition triggers and what "Sunset" means.

5. **How does PROJECTS.md integrate with the /explore workflow?**: The exploration identified PROJECTS.md as part of the inception workflow but didn't specify the mechanics — when does it update, what triggers state transitions, how does it connect to VISION docs?

## Coverage Notes

The exploration has strong coverage on WHAT the VISION type should be and WHY it's needed. Gaps that the PRD process should address:

- **Acceptance criteria precision**: The exploration produced draft templates and signal tables but they need formalization into testable criteria
- **Skill eval scenarios**: VISION skill needs eval scenarios (per CLAUDE.md convention)
- **Content boundary edge cases**: When does a VISION's thesis section cross into PRD problem-statement territory? When does org fit become competitive analysis?
- **PROJECTS.md update mechanics**: Automatic during /explore produce, or manual?

## Decisions from Exploration

These are settled — the PRD should treat them as given:

- VISION is the only new pre-PRD artifact type; no intermediates (opportunity assessments, strategy briefs, etc. are absorbed as VISION sections)
- Name is VISION, not Project Brief — captures lasting project identity, not a one-time evaluation
- VISION is a supported crystallize type in /explore, not a standalone command
- Gated to strategic scope; tactical scope is a hard anti-signal in the crystallize framework
- Reference standards for existing deferred types (roadmap, spike, ADR) ship independently — not a prerequisite
- PROJECTS.md lifecycle tracking is in-scope for this work
- VISION lifecycle is Draft -> Accepted -> Active -> Sunset (stays Active, never "completes")
- Template works at both org-level and project-level via a `scope` frontmatter field
- The `upstream` frontmatter field links project-level VISIONs to org-level VISIONs
- Visibility controls content richness (what sections appear), not availability
