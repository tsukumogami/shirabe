# Phase 2 Research: Codebase Analyst

## Lead 1: Validation and Enforcement Patterns

### Findings

**Transition scripts exist for three artifact types:**

1. `skills/roadmap/scripts/transition-status.sh` -- validates Draft->Active->Done. Checks frontmatter `status` field, validates transition legality, and enforces preconditions (Draft->Active requires at least 2 Feature headings). No directory movement.

2. `skills/design/scripts/transition-status.sh` -- validates Proposed->Accepted->Planned->Current (plus Superseded). Handles `superseded_by` field in frontmatter. Moves files between directories based on status (e.g., Current -> `docs/designs/current/`). No validation of `upstream` field.

3. `skills/vision/scripts/transition-status.sh` -- validates Draft->Accepted->Active->Sunset. Similar `superseded_by` handling. Moves files to `docs/visions/sunset/` on Sunset.

**What the transition scripts validate:**
- File existence
- Target status is in the valid set
- Transition is allowed (forward-only, no skipping)
- Specific preconditions: features count (roadmap), open questions resolved (vision)
- Frontmatter and body status kept in sync

**What the transition scripts do NOT validate:**
- No script checks `upstream` field at all -- the word "upstream" does not appear in any transition script
- No script validates that referenced paths (upstream, superseded_by) point to existing files
- No script checks that the upstream artifact is in the correct status

**Format specs define upstream but don't enforce it:**
- PRD format (`prd-format.md`): declares `upstream: docs/roadmaps/ROADMAP-<name>.md` as optional
- Design SKILL.md: declares `upstream: docs/prds/PRD-<name>.md` as optional
- Roadmap format (`roadmap-format.md`): does NOT define an `upstream` field at all -- this is the gap the new feature fills

**Validation rules in format specs are purely structural:**
- "Frontmatter has `status`, `theme`, `scope` fields" (roadmap)
- "Frontmatter has `status`, `problem`, `goals` fields" (PRD)
- "Frontmatter has all 4 fields (status, problem, decision, rationale)" (design)
- None of the validation rule sections mention checking `upstream`

**CI-level enforcement:**
- `check-evals.yml` -- checks that skills have eval definitions (runs `scripts/check-evals-exist.sh`)
- `check-templates.yml` -- validates koto template freshness
- `validate-templates.yml` -- compiles koto templates with `koto template compile`
- `check-sentinel.yml` -- checks plugin manifest versions
- No CI workflow validates document frontmatter or upstream references

### Implications for Requirements

1. **Adding `upstream` to the roadmap frontmatter schema** is a new field. The roadmap format reference needs updating to include it as optional (since not all roadmaps derive from a vision).

2. **No existing validation infrastructure for upstream paths.** If the feature wants to enforce that upstream paths point to real files or that upstream artifacts are in a valid status, that's entirely new capability. The current transition scripts are a natural place to add this, but it would be the first cross-document validation they perform.

3. **The `superseded_by` field in design and vision transition scripts is the closest precedent.** It's set during transitions and stored in frontmatter, but never validated as a real path. New upstream validation would exceed the current precedent.

4. **CI has no document format validation.** Any automated upstream validation would need a new workflow or an extension to an existing one.

### Open Questions

- Should upstream path validation be a transition precondition (fail the transition if the upstream file doesn't exist) or a soft warning?
- Should the transition script check the upstream artifact's status (e.g., a PRD's upstream roadmap should be Active)?
- Is CI-level format validation in scope for this feature, or is it deferred?

## Lead 2: Creation Workflow Upstream Setting

### Findings

**Design skill Phase 0 (PRD mode) explicitly sets upstream:**
- File: `skills/design/references/phases/phase-0-setup-prd.md`
- Step 0.5 creates the design doc skeleton with `upstream: docs/prds/PRD-<name>.md` in the frontmatter
- The upstream value is the literal path of the PRD that was passed as input
- This is the clearest example of the pattern: the creating skill sets upstream at creation time

**PRD format defines upstream but the creation workflow doesn't set it:**
- The PRD format reference shows `upstream: docs/roadmaps/ROADMAP-<name>.md` as an optional frontmatter field
- Searching all PRD phase files (`skills/prd/references/phases/phase-*.md`) finds zero mentions of "upstream"
- The PRD creation workflow has no mechanism to receive or set an upstream roadmap reference
- This is a gap: the format supports it, but the workflow doesn't populate it

**Roadmap format has no upstream field:**
- `skills/roadmap/references/roadmap-format.md` defines `status`, `theme`, `scope` as the frontmatter fields
- No mention of `upstream` in the roadmap format spec
- This confirms the new feature needs to add `upstream` to the roadmap schema

**The creation-time pattern:**
- Design -> PRD: upstream is set at creation time in Phase 0 (PRD mode). The skill receiving the upstream reference is responsible for writing it.
- PRD -> Roadmap: upstream is defined in the format but never populated by the creation workflow.
- Roadmap -> Vision: no upstream field exists at all yet.

**Handoff vs. upstream:**
- The `/roadmap` skill detects a handoff artifact (`wip/roadmap_<topic>_scope.md`) from `/explore`, but this is a temporary wip file, not a durable upstream reference
- The distinction matters: handoff is "who started me," upstream is "what artifact do I trace to"

### Implications for Requirements

1. **The pattern is clear but inconsistently applied.** The design skill's Phase 0 PRD mode is the model: the creating skill writes the upstream field. But the PRD skill doesn't follow this pattern even though its format supports it.

2. **For roadmaps, adding upstream requires both schema and workflow changes.** The format spec needs the field, and whatever workflow creates a roadmap (currently `/roadmap` or `/explore` handoff) needs to populate it.

3. **For PRDs, the format already supports upstream but the workflow gap needs fixing.** If a PRD is created from a roadmap feature, the `/prd` skill should set `upstream: docs/roadmaps/ROADMAP-<name>.md`. This is missing today.

4. **The pattern should be: the skill that creates a downstream artifact is responsible for setting upstream.** This matches how `/design` Phase 0 works. The new feature should extend this to `/prd` (setting upstream to the roadmap) and `/roadmap` (setting upstream to the vision, if one exists).

### Open Questions

- When `/prd` is invoked standalone (not from a roadmap feature), should upstream be left empty or should the skill ask?
- When `/roadmap` is invoked standalone (not from a vision), should upstream be left empty?
- Should there be a way to retroactively set upstream on an existing artifact that was created without one?

## Summary

Transition scripts validate status transitions and some structural preconditions, but perform zero upstream path validation -- `upstream` doesn't appear in any transition script. The design skill's Phase 0 (PRD mode) is the only workflow that currently sets `upstream` at creation time; the PRD format defines the field but no workflow populates it, and the roadmap format lacks the field entirely. Adding artifact traceability requires three changes: adding `upstream` to the roadmap frontmatter schema, extending creation workflows (/prd and /roadmap) to set upstream consistently following the design skill's Phase 0 pattern, and deciding whether to add path validation to transition scripts or CI (neither exists today).
