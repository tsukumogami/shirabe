# Roadmap Document Format Reference

Structure, lifecycle, validation rules, and quality guidance for Roadmap
documents.

## Table of Contents

- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Reserved Sections](#reserved-sections)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Frontmatter

Every roadmap begins with YAML frontmatter:

```yaml
---
status: Draft
theme: |
  1 paragraph describing the overarching theme or initiative this
  roadmap tracks. What capability area is being built out, and why
  does it need coordinated sequencing across multiple features?
scope: |
  1 paragraph bounding what's included and excluded. Which features
  are in this roadmap, and what adjacent work is deliberately left out?
---
```

Required fields: `status`, `theme`, `scope`. Each field should be 1 paragraph
using YAML literal block scalars (`|`).

Frontmatter status must match the Status section in the body -- agent workflows
parse frontmatter to determine lifecycle state, so divergence causes silent
errors.

## Required Sections

Every roadmap has these sections in order:

1. **Status** -- current lifecycle state
2. **Theme** -- what initiative this roadmap coordinates and why sequencing
   matters
3. **Features** -- ordered list of features with names, descriptions,
   dependencies, and status. Each feature should reference its downstream
   artifact (PRD, design doc, or plan) when one exists.
4. **Sequencing Rationale** -- why features are ordered this way. What
   constraints drive the ordering: technical dependencies, user value delivery,
   risk reduction?
5. **Progress** -- current state of the roadmap. Which features are done, in
   progress, or not started. Updated as work progresses.

### Per-Feature Format

Each feature in the Features section follows this structure:

```markdown
### Feature 1: Recipe validation pipeline
**Needs:** `needs-design` -- architecture for validation stages undecided
**Dependencies:** None
**Status:** Not started

### Feature 2: Version resolution caching
**Needs:** `needs-spike` -- feasibility of SQLite cache unknown
**Dependencies:** Feature 1
**Status:** Not started
```

The `Needs` annotation is optional. Features without it are treated as ready
for direct implementation. When present, it determines which `needs-*` label
gets applied during issue creation.

## Reserved Sections

Two sections follow Progress. They're structurally part of the roadmap but
are NOT populated by `/roadmap` -- they exist as empty placeholders at creation
time and are filled later by `/plan` during decomposition.

6. **Implementation Issues** -- table mapping features to GitHub issues.
   Empty at creation.

```markdown
## Implementation Issues

<!-- Populated by /plan during decomposition. Do not fill manually. -->

| Feature | Issues | Status |
|---------|--------|--------|
```

7. **Dependency Graph** -- Mermaid diagram showing feature dependencies and
   issue relationships. Empty at creation.

```markdown
## Dependency Graph

<!-- Populated by /plan during decomposition. Do not fill manually. -->

```mermaid
graph TD
```
```

These sections must appear in every roadmap file, even when empty. Their
presence signals that the roadmap is structurally complete and ready for
downstream planning workflows.

## Content Boundaries

A roadmap is NOT:

- **A PRD**: PRDs define requirements for a single feature. Roadmaps sequence
  multiple features. If you're writing detailed requirements, that's a PRD.
- **A plan**: Plans break a single artifact into implementable issues. Roadmaps
  operate one level above, coordinating across multiple PRDs or design docs.
- **A project timeline**: Roadmaps don't include dates or time estimates. They
  capture ordering and dependencies, not schedules.

If you're defining requirements for one feature, write a PRD. If you're breaking
one design into issues, write a plan. If you're sequencing multiple features
with dependencies, write a roadmap.

## Lifecycle

### States

```
Draft --> Active --> Done
```

| Status | Meaning | Transition Trigger |
|--------|---------|-------------------|
| Draft | Under development, feature list may change | Created by /explore |
| Active | Feature list locked, execution in progress | Human approval |
| Done | All features delivered or explicitly dropped | All features complete |

### Transition Rules

- **Draft -> Active**: Feature list is complete and sequencing is justified.
  Human must explicitly approve.
- **Active -> Done**: Every feature has reached a terminal state (delivered or
  explicitly dropped with rationale documented).
- **Done -> any**: Forbidden. A completed roadmap is a historical record. Create
  a new roadmap for follow-on work.
- **Active -> Draft**: Forbidden. If the feature list needs significant revision,
  create a new roadmap version.

### Edit Rules

Active roadmaps can update the Progress section and reserved sections
(Implementation Issues, Dependency Graph) freely. Changes to the Features list
or Sequencing Rationale require creating a new roadmap -- those sections are
locked once the roadmap leaves Draft.

## File Location

Roadmaps live at `docs/roadmaps/ROADMAP-<name>.md` (kebab-case). No directory
movement based on status -- all roadmaps stay in `docs/roadmaps/` regardless
of lifecycle state.

## Validation Rules

### During drafting

- Frontmatter has `status`, `theme`, `scope` fields
- Frontmatter status matches Status section in body
- All 5 required sections present and in order
- Both reserved sections present (may be empty)
- Status is "Draft"
- At least 2 features listed (single-feature work doesn't need a roadmap)

### When referenced by downstream workflows

- Status must be "Active" to serve as upstream context
- If status is "Draft": inform the referencing workflow that the roadmap
  isn't yet approved

### Status consistency

- Frontmatter `status` and body Status section must always match
- Features marked as done in the Features section should be reflected in Progress
- Reserved sections should only contain content if populated by `/plan`

## Quality Guidance

### Theme

- Identifies a coherent capability area, not a grab-bag of unrelated work
- Explains why coordination matters (shared infrastructure, user-facing story)
- Scoped to one initiative -- don't combine unrelated streams

### Features

- Each feature is independently describable in 1-2 sentences
- Dependencies between features are explicit, not implied
- Feature granularity matches the PRD level (one feature = one PRD)
- Features without downstream artifacts note what's needed next

### Sequencing Rationale

- Explains ordering constraints, not just lists the order
- Distinguishes hard dependencies (technical blockers) from soft preferences
  (nice-to-have ordering)
- Acknowledges where parallel execution is possible

### Progress

- Updated as features move through their lifecycle
- Notes both completions and drops (with reasoning for drops)
- Matches the status annotations in the Features section

### Common Pitfalls

- Too granular: tracking individual issues instead of features
- Too broad: mixing unrelated initiatives into one roadmap
- Missing rationale: listing features without explaining why this order
- Stale progress: not updating the Progress section as work completes
- Editing reserved sections manually instead of letting /plan populate them
