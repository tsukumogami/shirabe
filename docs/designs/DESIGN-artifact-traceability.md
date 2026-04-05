---
status: Proposed
upstream: docs/prds/PRD-artifact-traceability.md
problem: |
  placeholder
decision: |
  placeholder
rationale: |
  placeholder
---

# DESIGN: Artifact Traceability

## Status

Proposed

## Context and Problem Statement

Five artifact types form the pipeline's traceability chain. Four of them
(VISION, PRD, Design Doc, Plan) have an optional `upstream` frontmatter
field linking to the parent artifact. Roadmaps don't, breaking the chain
between strategic intent (VISION) and feature sequencing (Roadmap).

The technical problem has three parts:

1. **Schema gap.** The roadmap format spec defines `status`, `theme`, and
   `scope` in frontmatter but no `upstream` field. Adding it requires
   updating the format spec, the creation workflow, and verifying the
   transition script doesn't reject the new field.

2. **Workflow inconsistency.** The /design skill's Phase 0 sets `upstream`
   from the source PRD at creation time. The /prd skill defines `upstream`
   in its format spec but never populates it during creation. The /roadmap
   skill has no upstream field at all. Two of three creation workflows that
   should set upstream don't.

3. **No cross-repo reference convention.** All existing `upstream` values
   are relative paths within the same repo. When artifacts span repos
   (common in multi-repo workspaces), there's no documented format for the
   reference. The `spawned_from.repo` field in design docs is a partial
   precedent but uses structured YAML rather than a compact string.

## Decision Drivers

- Must follow existing patterns: `upstream` is optional, set at creation
  time, uses relative paths for same-repo references
- Must work with existing transition scripts without breaking them (they
  don't validate upstream, so adding the field is safe)
- Cross-repo convention must respect the directional visibility rule:
  public repos must not reference private artifacts
- Changes are markdown and shell only (no compiled code)
- Convention should be documented once and linked from each skill, not
  duplicated across format specs
- The /design Phase 0 pattern (creation workflow sets upstream from input
  context) is the model to follow
