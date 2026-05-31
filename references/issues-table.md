# Issues Table

The one issues-table framework both roadmap and plan workflows consume.
Parameterized into two altitude profiles -- the plan profile keys on
issues, the roadmap profile keys on features -- so the altitude
distinction survives while the shared core stays defined once.

Cited by P4 in `workflow-principles.md`.

## Table of Contents

- [Shared Core](#shared-core)
- [Shared Rendering](#shared-rendering)
- [Plan Profile](#plan-profile)
- [Roadmap Profile](#roadmap-profile)
- [Migration Rules](#migration-rules)
- [Validation](#validation)

## Shared Core

Both profiles render a GFM pipe table whose columns include the same
three core concerns, in this order:

1. **Key column** (position 1) -- the primary entity link. Header
   label and link target are profile-specific (see below).
2. **Dependencies column** -- `None` or comma-separated clickable
   links to other rows' keys. Same semantics at both altitudes.
3. **Status column** -- an explicit completion or lifecycle marker
   for the row.

A profile may add **one** profile-specific column. The position of
profile-specific columns is fixed per profile (see each profile
below).

## Shared Rendering

Both profiles share these rendering rules.

### Description row

Every entity row is followed immediately by an italic description row
of 1-3 sentences in the first cell, with empty remaining cells:

```markdown
| <entity row> | <deps> | <status> |
| _<1-3 sentences explaining what this entity delivers and how it
  connects to the rest of the work>_ | | |
```

**Writing guidelines:**

- Don't repeat the entity title -- explain what the entity delivers.
- Be concrete: mention specific files, patterns, or interfaces.
- Each description builds on the previous one; a reader going
  top-to-bottom should get the full build sequence.
- Keep to 1-3 sentences.

### Strikethrough on done

When an entity reaches a terminal state, strike through every row
associated with it -- the entity row, its description row, and any
child reference row between them. Use `~~text~~` markdown syntax.

```markdown
| ~~<entity row>~~ | ~~<deps>~~ | ~~<status>~~ |
| ~~^_<child reference, if present>_~~ | | | |
| ~~_<description>_~~ | | |
```

All row types (when present) must be struck through together. The
description remains readable (just with strikethrough styling) to
preserve the build narrative.

## Plan Profile

The plan profile parameterizes the shared core with:

- **Key column header:** `Issue`
- **Key link form:** `[#N: <title>](<url>)` where `N` is the GitHub
  issue number and the link points at the issue
- **Profile-specific column:** `Complexity` (position 3, between
  Dependencies and Status if a Status column is present; the
  canonical plan table uses `Issue | Dependencies | Complexity`
  without a separate Status column -- Complexity carries the
  routing role)
- **Child reference row:** for issues with a `tracks-design` or
  `tracks-plan` label, a child reference row is inserted between
  the entity row and its description row

### Canonical plan table shape

```markdown
| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#N: <title>](<url>) | None | simple |
| _<description>_ | | |
| [#M: <title>](<url>) | [#N](<url>) | testable |
| _<description>_ | | |
```

### Complexity values

`simple`, `testable`, or `critical`.

### Child reference row

When a `tracks-design` or `tracks-plan` issue spawns a child design,
a child reference row links readers to the child without importing
its details:

```markdown
| [#N: <title>](<url>) | None | simple |
| ^_Child: [DESIGN-<name>.md](<relative-path>)_ | | | |
| _<description text>_ | | |
```

The `^` prefix distinguishes child reference rows from description
rows. Only issues with a tracking label may carry a child reference
row -- this invariant is bidirectional and may be enforced in CI.

### Milestone heading

In multi-pr mode, the Implementation Issues section includes a
milestone heading immediately above the table:

```markdown
## Implementation Issues

### Milestone: [<Name>](<milestone-url>)

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
...
```

## Roadmap Profile

The roadmap profile parameterizes the shared core with:

- **Key column header:** `Feature`
- **Key form:** the feature label naming the feature (free text
  identifying the feature; not a clickable link by itself, though
  the label may contain a link to the per-feature body section)
- **Profile-specific column:** `Issues` -- the one-to-many fan-out
  of clickable issue links the feature decomposed into, encoding
  the feature-to-issues altitude jump. This is the roadmap
  profile's defining addition.

### Canonical roadmap table shape

```markdown
| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|
| <feature label> | [#N](<url>), [#M](<url>) | None | In Progress |
| _<description>_ | | | |
| <feature label> | [#P](<url>) | <feature> | Done |
| _<description>_ | | | |
```

### Status values

Free-text lifecycle marker matching the feature's state in the
roadmap's Progress section -- typically `Not Started`, `In Progress`,
`Done`, or a `needs-*` annotation when the feature is awaiting an
upstream artifact (`needs-prd`, `needs-design`, `needs-spike`,
`needs-decision`).

### Issues fan-out column

The Issues column lists every issue the feature decomposed into, as
comma-separated clickable links. `None` is allowed before the feature
has been decomposed (the empty placeholder state at roadmap creation
time).

## Migration Rules

The corpus carries pre-standardization table shapes. Migration brings
them into the canonical profile without losing information.

### Plan: legacy `Title` column

A legacy `Issue | Title | Dependencies | Complexity` shape folds the
`Title` column into the issue link text of the canonical shape:

- Source: `| [#N](<url>) | <title text> | <deps> | <complexity> |`
- Target: `| [#N: <title text>](<url>) | <deps> | <complexity> |`

The legacy shape is not perpetuated as a permanent dual format. The
validator's `FC05` message points the author at this migration.

### Roadmap: divergent committed shapes

Two shapes are known to exist in the committed corpus and migrate
into the canonical roadmap profile:

- `Feature | Status | Downstream Artifact` -- the `Downstream Artifact`
  column is dropped during migration (the per-feature body sections
  above the table already carry the artifact references). Add an
  `Issues` fan-out column (empty `None` if the feature has not yet
  been decomposed into issues).
- `Issue | Phase | Dependencies | Label` -- this issue-keyed shape
  migrates to feature-keyed. Each row becomes one feature whose
  `Issues` column holds the original issue link. The `Phase` column
  is dropped (phase grouping moves to body prose). The `Label`
  column folds into `Status`: `needs-design` becomes `Status =
  needs-design`, `Done` becomes `Status = Done`, and similar.

In every migration, no issue link or dependency relationship is
dropped or altered in meaning; only the table shape changes.

## Validation

The Go validator in `internal/validate/` enforces the
machine-checkable subset of this reference:

- **FC05** -- issues-table schema conformance. Profile is selected by
  the doc's schema (plan/v1 or roadmap/v1). Header columns must match
  the profile's required columns in order; rows must be
  well-formed (entity, description, optional child reference).
- **FC06** -- cross-reference existence. Every value in a
  Dependencies cell must name an entity-row key that exists in the
  same table.

Both checks are error-level. A doc that names itself a roadmap or a
plan (via filename prefix `ROADMAP-` or `PLAN-`) must declare its
schema in frontmatter (`schema: roadmap/v1` or `schema: plan/v1`) for
these checks to engage; the SCHEMA gate fires a notice on a missing
or mismatched schema and skips the FC checks.
