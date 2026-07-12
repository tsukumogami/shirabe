# Roadmap Document Format Reference

Structure, lifecycle, validation rules, and quality guidance for
Roadmap documents. The roadmap profile of the shared issues-table
framework owns the Implementation Issues shape; the shared
dependency-diagram convention owns the mermaid graph. This file
carries the roadmap-specific deltas, lifecycle, and quality guidance.

## Table of Contents

- [Shared References](#shared-references)
- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Reserved Sections](#reserved-sections)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Shared References

Both the issues-table format (roadmap profile) and the
dependency-diagram convention live at the plugin root and are
consumed by both the roadmap and plan workflows:

- `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` -- the shared
  issues-table framework. The roadmap profile keys on features with
  the `Feature | Issues | Dependencies | Status` shape, the `Issues`
  fan-out column listing the issue links the feature decomposed into,
  and the migration rules for the divergent committed shapes
  (`Feature | Status | Downstream Artifact` and `Issue | Phase |
  Dependencies | Label`). This reference owns table shape, description
  rows, and strikethrough rules.

- `${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md` -- the
  shared dependency-diagram convention. Owns the mermaid syntax
  rules, the fixed status-class palette, node format, class
  assignment, initial status, status updates, and legend.

- `${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md` -- the
  five principles both workflows derive from. A roadmap is multi-pr
  because each feature delivers observable incremental value (P1),
  not because "the input is a roadmap."

## Frontmatter

Every roadmap begins with YAML frontmatter:

```yaml
---
schema: roadmap/v1
status: Draft
theme: |
  1 paragraph describing the overarching theme or initiative this
  roadmap tracks. What capability area is being built out, and why
  does it need coordinated sequencing across multiple features?
scope: |
  1 paragraph bounding what's included and excluded. Which features
  are in this roadmap, and what adjacent work is deliberately left out?
upstream: docs/visions/VISION-<name>.md  # optional
---
```

Required fields: `schema`, `status`, `theme`, `scope`. Optional:
`upstream` (path to the VISION document that this roadmap traces to,
when one exists). Each field other than `schema` should be 1
paragraph using YAML literal block scalars (`|`).

The `upstream` field links the roadmap to the strategic artifact that
motivated it. When present, it points to a VISION document (the
natural parent in the traceability chain). Roadmaps that emerge from
exploration without a formal VISION omit this field. For cross-repo
upstream references and the visibility-direction rules, see
`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`.

Frontmatter status must match the Status section in the body --
agent workflows parse frontmatter to determine lifecycle state, so
divergence causes silent errors.

## Required Sections

Every roadmap has these sections in order:

1. **Status** -- current lifecycle state
2. **Theme** -- what initiative this roadmap coordinates and why
   sequencing matters
3. **Features** -- ordered list of features with names, descriptions,
   dependencies, and status. Each feature should reference its
   downstream artifact (PRD, design doc, or plan) when one exists.
4. **Sequencing Rationale** -- why features are ordered this way.
   What constraints drive the ordering: technical dependencies, user
   value delivery, risk reduction?
5. **Progress** -- current state of the roadmap. Which features are
   done, in progress, or not started. Updated as work progresses.

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

The `Needs` annotation is optional. Features without it are treated
as ready for direct implementation. When present, it determines which
`needs-*` label gets applied during issue creation.

#### Heading forms

A feature heading uses one of two forms:

- **Classic:** `### Feature <N>: <label>` -- the default, where `<N>`
  is the 1-based feature number.
- **Strategy-derived prefix:** `### <PREFIX><N>: <label>` -- a short
  alphabetic tag immediately followed by the feature number, no space
  between them (e.g. `### ED1:`, `### SE2:`, `### SR10:`, `### NW1:`).
  This variant fits product-spanning roadmaps derived from a strategy,
  where a per-direction prefix keeps features grouped by their strategic
  building block.

Both forms are equivalent to the tooling: features are numbered
positionally in source order regardless of the tag, so a
`**Dependencies:** Feature 1` edge resolves against the first feature
whether it is written `### Feature 1:` or `### ED1:`. Pick one form per
roadmap and use it consistently.

## Reserved Sections

Two sections follow Progress. They're structurally part of the
roadmap but are NOT populated by `/roadmap` -- they exist as empty
placeholders at creation time and are filled later by a tool, never
by hand.

How they get filled depends on the repo's `## Roadmap Issues:`
CLAUDE.md header (see
`${CLAUDE_PLUGIN_ROOT}/references/fixes/claude-md-conventions.md`).
The header defaults to `required` when absent:

- **`## Roadmap Issues: required` (default).** `/plan` fills both
  sections during decomposition, keying the table and diagram on
  the GitHub issues it creates (one issue per feature).
- **`## Roadmap Issues: optional`.** An issueless render of
  `shirabe roadmap populate` fills both sections from the Features
  section -- no issues are created. The table is feature-keyed
  (`F<n>` rows, the feature's `needs-*` label in the Issues
  column), and the diagram uses `F<n>` nodes. The bare-key
  Dependencies convention below applies in this mode.

Either way the sections are tool-generated. Don't hand-edit them.

6. **Implementation Issues** -- table mapping features to GitHub
   issues. Empty at creation. The canonical roadmap profile shape
   (`Feature | Issues | Dependencies | Status`), description rows, and
   strikethrough rules are defined in
   `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md`.

Under `## Roadmap Issues: required` (the default) the marker reads
as below, since `/plan` fills the table from the issues it creates.
Under `## Roadmap Issues: optional` the marker instead reads
`<!-- Populated by an issueless 'shirabe roadmap populate' from the
Features section. Do not fill manually. -->`. The instruction not to
hand-edit holds in both modes.

```markdown
## Implementation Issues

<!-- Populated by /plan during decomposition. Do not fill manually. -->

| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|
```

7. **Dependency Graph** -- Mermaid diagram showing feature
   dependencies and issue relationships. Empty at creation. Mermaid
   syntax rules, the fixed status-class palette, node format, and
   legend are defined in
   `${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md`.

As with Implementation Issues, the marker is conditioned on the
preference: under `## Roadmap Issues: optional` it reads
`<!-- Populated by an issueless 'shirabe roadmap populate' from the
Features section. Do not fill manually. -->`, and the diagram uses
`F<n>` feature nodes instead of `I<n>` issue nodes. Don't hand-edit
it in either mode.

```markdown
## Dependency Graph

<!-- Populated by /plan during decomposition. Do not fill manually. -->

```mermaid
graph TD
```
```

These sections must appear in every roadmap file, even when empty.
Their presence signals that the roadmap is structurally complete and
ready for downstream planning workflows.

## Content Boundaries

A roadmap is NOT:

- **A PRD**: PRDs define requirements for a single feature. Roadmaps
  sequence multiple features. If you're writing detailed
  requirements, that's a PRD.
- **A plan**: Plans break a single artifact into implementable
  issues. Roadmaps operate one level above, coordinating across
  multiple PRDs or design docs.
- **A project timeline**: Roadmaps don't include dates or time
  estimates. They capture ordering and dependencies, not schedules.

If you're defining requirements for one feature, write a PRD. If
you're breaking one design into issues, write a plan. If you're
sequencing multiple features with dependencies, write a roadmap.

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

- **Draft -> Active**: Feature list is complete and sequencing is
  justified. Human must explicitly approve.
- **Active -> Done**: Every feature has reached a terminal state
  (delivered or explicitly dropped with rationale documented).
- **Done -> any**: Forbidden. A completed roadmap is a historical
  record. Create a new roadmap for follow-on work.
- **Active -> Draft**: Forbidden. If the feature list needs
  significant revision, create a new roadmap version.

### Edit Rules

Active roadmaps can update the Progress section and reserved sections
(Implementation Issues, Dependency Graph) freely. Changes to the
Features list or Sequencing Rationale require creating a new roadmap
-- those sections are locked once the roadmap leaves Draft.

## File Location

Roadmaps live at `docs/roadmaps/ROADMAP-<name>.md` (kebab-case). No
directory movement based on status -- all roadmaps stay in
`docs/roadmaps/` regardless of lifecycle state.

## Validation Rules

### During drafting

- Frontmatter has `schema`, `status`, `theme`, `scope` fields
- Frontmatter status matches Status section in body
- All 5 required sections present (FC04) and in canonical order (FC15)
- Both reserved sections present (may be empty)
- Status is "Draft"
- At least 2 features listed (single-feature work doesn't need a
  roadmap)

### When referenced by downstream workflows

- Status must be "Active" to serve as upstream context
- If status is "Draft": inform the referencing workflow that the
  roadmap isn't yet approved

### Status consistency

- Frontmatter `status` and body Status section must always match
- Features marked as done in the Features section should be
  reflected in Progress
- Reserved sections should only contain content if populated by
  `/plan`

### Validation enforcement

The validator runs FC05 (issues-table schema conformance) and FC06
(cross-reference existence) on roadmap docs. See
`${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` for the canonical
roadmap profile contract those checks enforce.

### Dependencies cells in issueless mode

Under `## Roadmap Issues: optional`, the Implementation Issues
table is feature-keyed, and each Dependencies cell MUST be a bare
feature key or `None` -- `F1`, `F1, F2`, or `None`. Nothing else.

FC06 rejects annotated forms. `F1 (soft)` and `None (ext:
onboarding)` each fail with `dependency "..." names no row in this
table`, because the parenthetical isn't a feature key. Soft-versus-hard
nuance and external dependencies don't go in the cell -- they belong
in the feature prose and the Sequencing Rationale, which is where
the reader looks for that context anyway. Keep the cell to keys; put
the reasoning in prose.

## Quality Guidance

### Theme

- Identifies a coherent capability area, not a grab-bag of unrelated
  work
- Explains why coordination matters (shared infrastructure,
  user-facing story)
- Scoped to one initiative -- don't combine unrelated streams

### Features

- Each feature is independently describable in 1-2 sentences
- Dependencies between features are explicit, not implied
- Feature granularity matches the PRD level (one feature = one PRD)
- Features without downstream artifacts note what's needed next

### Sequencing Rationale

- Explains ordering constraints, not just lists the order
- Distinguishes hard dependencies (technical blockers) from soft
  preferences (nice-to-have ordering)
- Acknowledges where parallel execution is possible

### Progress

- Updated as features move through their lifecycle
- Notes both completions and drops (with reasoning for drops)
- Matches the status annotations in the Features section

### Common Pitfalls

- Too granular: tracking individual issues instead of features
- Too broad: mixing unrelated initiatives into one roadmap
- Missing rationale: listing features without explaining why this
  order
- Stale progress: not updating the Progress section as work completes
- Editing reserved sections manually instead of letting /plan
  populate them
