# Phase 2 Research: Current-State Analyst

## Lead 1: Roadmap Upstream Semantics

### Findings

The roadmap format spec (`skills/roadmap/references/roadmap-format.md`) defines three frontmatter fields -- `status`, `theme`, `scope` -- with no `upstream` field. This is the only artifact type in the pipeline that lacks one. Every other type has `upstream` as an optional field:

- **VISION**: `upstream: docs/visions/VISION-<parent>.md` -- points to a parent VISION (project-level pointing to org-level). Optional, project-level only.
- **PRD**: `upstream: docs/roadmaps/ROADMAP-<name>.md` -- points to a roadmap. Optional.
- **Design Doc**: `upstream: docs/prds/PRD-<name>.md` -- points to a PRD. Optional, set by /design Phase 0.
- **Plan**: `upstream: docs/designs/DESIGN-<topic>.md` -- points to a design doc, PRD, or roadmap. Optional.

The traceability chain as designed is: VISION -> Roadmap -> PRD -> Design -> Plan -> Issues -> PRs. With Roadmap missing `upstream`, the VISION-to-Roadmap link is broken.

Looking at what a roadmap's upstream *should* point to: the natural answer is a VISION document. The ROADMAP-strategic-pipeline.md describes the full chain and Feature 3 explicitly says "add `upstream` to Roadmap frontmatter." The two existing roadmaps (ROADMAP-koto-adoption.md and ROADMAP-strategic-pipeline.md) have no upstream field, confirming the gap.

Could a roadmap's upstream be another roadmap? Nothing in the format spec forbids hierarchical roadmaps, but the content boundaries section says roadmaps sequence multiple features with dependencies -- they don't derive from other roadmaps. A roadmap derives from a strategic direction (VISION). The PRD layer is what connects roadmap features to implementation. So roadmap-to-roadmap upstream seems unlikely and unnecessary.

The VISION format spec already has a "Downstream Artifacts" optional section for linking to PRDs, designs, and plans that depend on it. A roadmap with `upstream` pointing to a VISION would be the reverse link completing the bidirectional traceability.

### Implications for Requirements

1. **Upstream target type**: Roadmap `upstream` should point to a VISION document path. The format should be `upstream: docs/visions/VISION-<name>.md`, matching the relative-path convention used by all other artifact types.

2. **Optional, not required**: Every other artifact type makes upstream optional. Roadmaps should follow suit -- some roadmaps may emerge from exploration without a formal VISION.

3. **Validation rules**: The roadmap format spec has validation rules for drafting and for downstream reference. Upstream validation should follow the same pattern as other types: if present, the path should be syntactically valid. Whether to validate that the file exists or that its status is appropriate (Active VISION) is a design decision.

4. **No roadmap-to-roadmap upstream**: The format should constrain upstream to VISION paths only, not other roadmaps. This keeps the hierarchy clean.

### Open Questions

1. Should `upstream` be validated at creation time (path exists, VISION is in Accepted/Active status) or is it purely informational? Other types don't seem to enforce existence checks during creation.

2. Should the /roadmap creation skill auto-populate `upstream` when invoked from /explore with a VISION context, the way /design Phase 0 auto-populates upstream from a PRD?

3. The VISION format has a "Downstream Artifacts" section. Should creating a roadmap with `upstream` pointing to a VISION automatically update that VISION's Downstream Artifacts? The strategic pipeline roadmap calls this a "stretch goal" and notes it's "currently manual and often missing."

## Lead 2: Existing Upstream Usage

### Findings

**All upstream values are relative paths within the same repo.** Every instance found:

| Artifact | upstream value |
|----------|---------------|
| `DESIGN-roadmap-creation-skill.md` | `docs/prds/PRD-roadmap-skill.md` |
| `DESIGN-reusable-release-system.md` | `docs/prds/PRD-reusable-release-system.md` |
| `PRD-roadmap-skill.md` | `docs/roadmaps/ROADMAP-strategic-pipeline.md` |
| `PRD-plan-skill-rework.md` | `docs/roadmaps/ROADMAP-strategic-pipeline.md` |
| VISION format spec (template) | `docs/visions/VISION-<parent>.md` |
| Plan format spec (template) | `docs/designs/DESIGN-<topic>.md` |

All paths are relative to the repo root (`docs/...`). No cross-repo references exist in any actual artifact today.

**The cross-repo convention is proposed but not yet used.** Feature 3 in ROADMAP-strategic-pipeline.md proposes `owner/repo:path` with a `private:` prefix for visibility boundaries, but this is aspirational -- zero artifacts use it. The /explore skill handles cross-repo *issues* (e.g., `owner/repo#42`) via `gh` commands, and the /design skill mentions "For cross-repo source issues, use `gh` commands to read content." But these are runtime behaviors, not frontmatter conventions.

**The `private:` prefix question.** The scope document notes the user questioned whether `private:` is needed since public repos should never reference private artifacts. This is a valid concern. The CLAUDE.md instructions are explicit: "Only reference issues, PRs, and designs in public repos" and "Only link to public resources (no private repo links)." A `private:` prefix would only matter in private repos referencing other private repos, which is a narrow use case.

**Design Doc already has `upstream`.** The scope document notes "Changes to Design Doc schema (already has `upstream` and `spawned_from`)" as out of scope. This is correct -- the /design SKILL.md defines `upstream` as an optional field linking to a PRD, and `spawned_from` for child designs linking back to parent design + issue.

**PRD `source_issue` field.** PRDs have both `upstream` (to roadmap) and `source_issue` (GitHub issue number). This is the only artifact type with a separate issue-linking field, which makes sense because PRDs can be triggered by GitHub issues rather than upstream artifacts.

### Implications for Requirements

1. **Relative paths are the established convention.** The PRD should specify that `upstream` uses relative paths from the repo root, consistent with all existing usage. No need to invent a new format for the common case.

2. **Cross-repo convention is a separate concern.** Since no artifacts use cross-repo refs today, the convention should be documented but treated as additive. It shouldn't change how same-repo `upstream` works.

3. **The `private:` prefix may not be needed for the initial scope.** Public repos already have a governance rule against referencing private content. A prefix is only useful if tooling needs to programmatically distinguish private refs, and there's no such tooling today. The PRD could defer this to a future iteration or document it as a convention for private repos only.

4. **Design Doc upstream is already handled.** The scope document correctly excludes Design Doc changes. The existing `upstream` and `spawned_from` fields cover the PRD-to-Design link. No work needed there.

5. **Downstream Artifacts updates remain manual.** Every artifact type with an optional "Downstream Artifacts" section relies on manual maintenance. The bidirectional link (upstream in child, downstream list in parent) is only half-automated at best. The PRD should acknowledge this gap even if automation is out of scope.

### Open Questions

1. Should the cross-repo reference convention (`owner/repo:path`) be documented in a central location (e.g., a shared reference doc) or in each artifact's format spec? Given that it applies to all artifact types, a central doc seems cleaner.

2. What's the enforcement model for cross-repo refs? If a roadmap points to a VISION in another repo, should the transition script validate that the referenced file exists? That requires cloning or API access to the other repo, which is a significant complexity increase.

3. Is the `owner/repo:path` format the right syntax? It resembles Go import paths. Alternatives include full GitHub URLs (`https://github.com/owner/repo/blob/main/path`) or a shorter `repo:path` form that assumes the same org. The PRD should pick one and justify it.

## Summary

Roadmap is the only artifact type missing an `upstream` frontmatter field, creating a gap in the VISION-to-PR traceability chain. All existing `upstream` values use relative paths within the same repo -- no cross-repo references exist in practice despite being proposed in the strategic pipeline roadmap. The PRD should add `upstream` to the roadmap schema (optional, pointing to a VISION path), document a cross-repo convention as an additive feature, and defer the `private:` prefix and automated downstream-artifacts updates to future work.
