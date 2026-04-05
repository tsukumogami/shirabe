# /prd Scope: Artifact Traceability

## Problem Statement

The artifact pipeline has traceability fields on most types (VISION, PRD, Design
Doc) but Roadmaps lack an `upstream` field, and there's no documented convention
for cross-repo references. This means the VISION-to-PR chain has a gap at the
Roadmap level, and references between repos are ad-hoc.

## Initial Scope

### In Scope
- Add `upstream` to Roadmap frontmatter schema
- Document the cross-repo reference convention
- Update roadmap format spec and transition script to handle upstream
- Investigate the `private:` prefix concept from the original feature description

### Out of Scope
- Automating Downstream Artifacts section updates (stretch goal, deferred)
- Changes to Design Doc schema (already has `upstream` and `spawned_from`)
- Changes to PRD, VISION, or Plan schemas (already have `upstream`)
- Go code changes to workflow-tool

## Research Leads

1. **Roadmap upstream semantics**: What should a roadmap's upstream point to?
   Always a VISION? Could it be another roadmap? What validation rules apply?

2. **Cross-repo reference convention**: Where should this convention live? How
   do existing artifacts use cross-repo refs today? What does the `private:`
   prefix mean operationally, and is it needed given public repos must never
   reference private artifacts?

3. **Validation and enforcement**: Should format specs validate that upstream
   paths exist? Should transition scripts check upstream? What happens at
   visibility boundaries?

## Coverage Notes

- User notes public repos should never reference private artifacts, questioning
  the need for `private:` prefix. Agents should investigate the original rationale.
