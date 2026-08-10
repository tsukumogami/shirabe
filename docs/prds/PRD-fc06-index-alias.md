---
schema: prd/v1
status: Done
problem: |
  FC06 accepts a roadmap Dependencies token only when it matches an entity-row
  key in the same Implementation Issues table. The issueless renderer keys rows
  on the feature label, so the dependency cells must repeat those labels in
  full; a feature with three upstreams carries three complete labels where the
  older renderer wrote `F1, F2, F3`. The two columns are locked to the same
  form, and the compact one is unreachable without giving up the readable key
  column.
goals: |
  FC06's roadmap arm resolves a Dependencies token matching `^F[0-9]+$` against
  the nth entity row of the same table when no key matched it, so the key
  column can stay in labels while the dependency column stays in indices. The
  resolution is document-local and positional, tried only after the key lookup
  fails, so a feature literally labelled `F2` keeps today's behaviour and an
  out-of-range index still errors. `render_issueless_table` emits the compact
  form once the validator accepts it, and the three prose surfaces that
  describe the emitted cell are updated to match. Roadmaps written against the
  label form keep validating with no migration.
upstream: docs/briefs/BRIEF-fc06-index-alias.md
---

# PRD: fc06-index-alias

## Status

Done

## Problem Statement

FC06 is the validator's document-local cross-reference check for the
Implementation Issues table. For each entity row it reads the Dependencies
cell, splits it into tokens, discards the ones that aren't document-local
(cross-repo `owner/repo#N` refs, bare URLs), and requires every remaining token
to match an entity-row key in the same table. A token that matches nothing is
an error: `dependency "X" in row "Y" names no row in this table`.

The check has one resolution rule — string equality against the key set — and
that rule is what couples the two columns. When the issueless renderer keyed
rows on `F1`, `F2`, `F3`, the dependency cells said `F1, F2, F3` and FC06 was
happy. When the renderer moved to feature labels (the form the shared roadmap
profile specifies, and the form the issue-creating renderer has always used),
the dependency cells had to move with it, because the only tokens FC06 accepts
are the keys.

The result is a dependency column as wide as the sum of the labels it points
at. The upstream design recorded the widening as an accepted negative on the
grounds that the label form is what the spec asks for. That reasoning covers
the key column, where the spec really does specify the label. Nothing specifies
the dependency column's form; it follows the key column only because FC06 has
no other way to resolve a token.

Every roadmap already carries a second naming scheme for the same features. The
Dependency Graph directly below the table uses `F<n>` nodes, numbered
positionally from the Features section, and `parse_features` assigns those
indices in document order. So a reader gets `F3 --> F5` in the graph and two
full labels in the table row, and has to map between the two by hand. The index
is already the document's short handle for a feature. It just isn't a handle
FC06 will follow.

## Goals

Give FC06 a second, narrower resolution rule for the roadmap profile: a token
that looks like an index and matches no key resolves positionally against the
table's entity rows. That single addition unlocks the compact dependency cell
without touching anything else about the check.

Keep the check's failure modes intact. The point of FC06 is catching a
dependency that names a row which isn't there — a deleted feature, a renamed
one, a typo. Positional resolution against real rows preserves that: an index
past the end of the table resolves to nothing and reports the same error it
reports today.

Keep the change document-local. FC06 does not read the Features section, the
Dependency Graph, or any other part of the document to resolve a dependency
token, and this addition must not be the thing that makes it start. The nth
entity row of the table is the only input.

Let the renderer emit the compact form, and bring the three prose surfaces that
document the emitted form back into agreement with what the tool produces.
Require no migration: both forms validate, so a roadmap populated before this
change stays valid.

## User Stories

**As a roadmap author**, I want the Dependencies column to name features by
index so the table stays narrow enough to read, while the key column keeps the
labels that let me tell rows apart.

**As a roadmap reviewer**, I want the table's dependency tokens to match the
Dependency Graph's node names so I can check the two views against each other
without translating between labels and indices.

**As someone hand-editing a roadmap**, I want either form to work in a
dependency cell, so I can write the index when I know it and the label when I
don't, and mix them in one table if that's what the edit calls for.

**As someone who owns an existing roadmap**, I want my label-form dependency
cells to keep validating, so this change costs me nothing.

**As a maintainer of the validator**, I want the alias confined to the roadmap
profile and to tokens no key matched, so the check's behaviour on plan
documents and on real-label collisions is provably unchanged.

## Requirements

**R1 — Positional alias resolution.** For the roadmap profile, a Dependencies
token on an entity row that matches the pattern `^F[0-9]+$` and matches no
entity-row key SHALL resolve against the nth entity row of the same
Implementation Issues table, where `n` is the token's integer part, counting
entity rows only (description and child rows are not counted) and numbering
from 1. A token that resolves this way produces no FC06 finding.

**R2 — Key-first precedence.** The alias SHALL be attempted only for a token
that matched no entity-row key. A token that matches a key is resolved as a
key. A roadmap whose feature is literally labelled `F2` therefore keeps exactly
today's behaviour, and a table containing both a row keyed `F2` and a positional
second row resolves `F2` to the key.

**R3 — Document-local resolution.** The alias SHALL be resolved from the parsed
Implementation Issues table alone. FC06 SHALL NOT read the Features section,
the Dependency Graph, frontmatter, or any other part of the document to resolve
a dependency token.

**R4 — Out-of-range still errors.** A token matching `^F[0-9]+$` whose index
is 0, or exceeds the table's entity-row count, SHALL produce the existing
`names no row in this table` error at the existing severity, with the existing
message text.

**R5 — Roadmap profile only.** The alias SHALL NOT apply to a `plan/v1` issues
table. A token matching `^F[0-9]+$` in a plan-profile Dependencies cell is
resolved exactly as it is today.

**R6 — Renderer emits the compact form.** `render_issueless_table` SHALL emit
Dependencies cells naming depended-on features by their `F<n>` index while the
key column continues to carry the feature label (or its `F<n>` fallback). A row
whose key fell back to `F<n>` needs no special handling, because its key and its
alias are the same token.

**R7 — Issue-creating mode unchanged.** The mode that creates GitHub issues
SHALL continue to render Dependencies cells naming the depended-on features by
their row keys. Its output is unaffected by this change.

**R8 — Cross-repo references preserved.** A cross-repo reference in a feature's
`**Dependencies:**` line SHALL continue to round-trip verbatim into the rendered
cell, alongside any index tokens.

**R9 — Both forms validate.** A roadmap whose dependency cells carry full
feature labels SHALL continue to validate cleanly. No migration step is
required for documents written before this change.

**R10 — Prose surfaces describe the emitted form.** The `--no-issues` help text,
the "Dependencies cells in issueless mode" section of
`skills/roadmap/references/roadmap-format.md`, and the issueless paragraph in
`skills/roadmap/SKILL.md` SHALL describe the dependency-cell form the renderer
actually emits.

## Acceptance Criteria

- [ ] A roadmap whose Implementation Issues table has label keys and `F<n>`
      dependency cells validates with exit code 0 and no FC06 finding.
- [ ] The same roadmap with an out-of-range index (`F99` in a two-row table)
      fails validation with `[FC06] dependency "F99" ... names no row in this
      table`.
- [ ] `F0` in a dependency cell fails with the same error; there is no zeroth
      entity row.
- [ ] A roadmap with a feature literally labelled `F2` resolves `F2` in a
      dependency cell to that row's key, not positionally, and the behaviour is
      covered by a test that fails if precedence is inverted.
- [ ] A `plan/v1` document with `F1` in a Dependencies cell still reports the
      FC06 error; a test pins the profile gate.
- [ ] Description rows and child reference rows between entity rows do not
      shift the alias numbering; a test covers a table with description rows
      interleaved.
- [ ] `render_issueless_table` emits `F<n>` dependency cells and label keys, and
      the existing round-trip tests `run_issueless_render_validates_clean` and
      `populated_output_passes_validate` still pass.
- [ ] A new round-trip case renders a roadmap whose feature labels are long
      enough to be worth compacting and validates the rendered output clean,
      covering the alias end to end.
- [ ] A roadmap whose dependency cells carry full feature labels still
      validates clean.
- [ ] Issue-creating mode's rendered table is byte-identical to what it
      produced before the change.
- [ ] `shirabe roadmap populate --help` describes the emitted dependency-cell
      form, and so do the two named skill prose surfaces.
- [ ] `cargo test --workspace` passes and `cargo clippy --workspace
      --all-targets` introduces no new warnings.

## Out of Scope

- **Any other relaxation of FC06.** Tokens that aren't `^F[0-9]+$` indices are
  resolved exactly as they are today, and an out-of-range index is still an
  error. This is not licence to loosen the check generally.
- **The plan profile.** `F<n>` carries no meaning in a `plan/v1` table and is
  not aliased there.
- **The key column's rendering.** The label keying and the `F<n>` fallback,
  along with the stderr warnings when the fallback fires, ship as they are.
- **What the Issues column carries in issueless mode.** A separate divergence
  from the shared roadmap profile, deliberately left alone.
- **The default value of `--no-issues` and when populate runs.** Separate work
  with its own scope.
- **The Dependency Graph's rendering.** It already uses `F<n>` nodes and needs
  no change.

## Known Limitations

The alias is positional, so inserting a feature in the middle of the Features
section renumbers every index after it. A dependency cell that named `F3` now
means what used to be `F4`, and FC06 cannot tell — both are valid rows. The
same hazard already exists in the Dependency Graph, which has used positional
`F<n>` nodes since it was written, and re-running `shirabe roadmap populate
--no-issues` re-derives both sections from the Features section, which is the
intended repair. Authors who want a reference that survives reordering can
write the full label, which keeps working.

On a strategy-derived roadmap the features are headed `### ED1:`, `### SE2:`
and so on, and `parse_features` numbers them positionally regardless. An index
of `F4` on such a roadmap refers to a numbering scheme that appears nowhere in
the prose. This is the same cosmetic mismatch the Dependency Graph and the
`F<n>` key fallback already carry, recorded in the upstream design.

## Decisions and Trade-offs

**Positional resolution rather than a Features-section lookup.** The index
could have been resolved by reading the Features section and matching the nth
feature's label against the key column. That would survive a table whose row
order diverges from the Features order, but it would make FC06 read outside the
table, which is the property that keeps the check cheap and predictable. The
renderer writes both sections from the same feature list in the same order, so
the two resolutions agree on every document the tool produces; the positional
one is strictly simpler.

**Key lookup first.** Trying the alias first would change behaviour for a
roadmap with a feature labelled `F2`, which is a legal label today. Trying it
second means the alias is reachable only on tokens that are already errors, so
the change can only turn existing errors into successes and never the reverse.

**Roadmap profile only.** A plan table's keys are `#N` issue numbers and its
rows have no positional identity an author would name. Restricting the alias to
the roadmap profile keeps the plan arm provably untouched, and the parsed table
already carries the profile.

## Downstream Artifacts

- `docs/plans/PLAN-fc06-index-alias.md` — the single-pr implementation plan.

## Related

- `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md` — records
  the widened dependency cell as an accepted negative of the label keying.
- `references/issues-table.md` — the shared roadmap profile specifying the
  feature label as the key form.
- `references/dependency-diagram.md` — the `F<n>` node convention the alias
  reuses.
