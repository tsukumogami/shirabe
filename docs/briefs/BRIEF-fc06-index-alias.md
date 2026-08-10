---
schema: brief/v1
status: Done
problem: |
  FC06 requires every token in a roadmap's Dependencies cell to name an
  entity-row key in the same Implementation Issues table. Since the issueless
  renderer started keying rows on the feature label, that requirement forces
  the dependency column to repeat those labels in full. A feature with three
  upstreams renders a cell carrying three complete labels where the older
  renderer wrote `F1, F2, F3`. The key column and the dependency column are
  locked together, and the only way to shorten one today is to degrade the
  other.
outcome: |
  A roadmap author reading the Implementation Issues table sees a key column
  that names features the way people talk about them and a dependency column
  compact enough to scan. FC06 resolves an `F<n>` dependency token against the
  nth entity row of the same table, so the two columns can carry different
  forms without the validator objecting. Roadmaps written before the change
  keep validating unchanged, and a stale or mistyped index still fails.
upstream: docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md
---

# BRIEF: fc06-index-alias

## Status

Done

## Problem Statement

A roadmap's Implementation Issues table has two columns that name features:
the key column, which identifies each row, and the Dependencies column, which
points at other rows. FC06 is the check that keeps the second honest. It reads
every Dependencies token on an entity row and requires that token to name an
entity-row key somewhere in the same table. The check is document-local by
design: it does not consult the Features section, a graph model, or GitHub.
That's what makes it cheap and what makes it catch stale references.

The issueless renderer used to key the table on `F1`, `F2`, `F3`. Those keys
were short, so the dependency cells were short too, but a reader could not tell
from the table which feature `F2` was without scrolling up to the Features
section. The shared roadmap profile in `references/issues-table.md` has always
specified the feature label as the key, and the issue-creating renderer had
been using labels for as long as it existed. So the issueless renderer moved to
labels, with an `F<n>` fallback for the rare label that can't serve as a
validator key.

Moving the key column dragged the dependency column with it. FC06 only accepts
tokens that match a key, so once the keys became labels, the dependency cells
had to become labels too. On a roadmap with descriptive feature names the
result is a cell like:

```markdown
| A4 — Establish the number | needs-spike | A1 — Establish the baseline, A2 — Introduce the resolver cache, A3 — Surface the failure modes | needs-spike |
```

The design that made this change recorded the widening as a known negative and
accepted it, on the grounds that it is the shape the shared spec asks for and
the mode that creates issues already lives with it. That reasoning holds for
the key column. It does not hold for the dependency column, where nothing in
the spec demands the long form — it's an artifact of FC06 having one way to
resolve a token.

The compact form isn't available as an author choice today. Write `F1` in a
dependency cell of a label-keyed table and FC06 reports `dependency "F1" ...
names no row in this table`. There is no way to opt into a short dependency
column short of giving up the readable key column, and no way to mix the two.

## User Outcome

A roadmap author runs `shirabe roadmap populate --no-issues` and gets a table
whose key column carries feature labels and whose Dependencies column carries
`F<n>` indices. Both columns say what they need to say in the form that suits
them. The table fits in a terminal and reads cleanly on GitHub.

An author who hand-edits a dependency cell can write either form. `F2` and the
full label of the second feature both resolve, because FC06 tries the key set
first and only falls back to positional resolution for a token no key matched.
A roadmap populated before this change keeps validating with no edit, so
nothing needs migrating.

The check keeps its teeth. `F99` in a five-row table is still an error, with
the same message it produces today, because the alias resolves against real
rows rather than pattern-matching the token and waving it through. A plan
document is untouched: `F<n>` means nothing in a `plan/v1` table and isn't
aliased there.

## User Journeys

**Populating a roadmap with an optional-issues repo.** An author finishes the
Features section of a new roadmap and runs `shirabe roadmap populate --no-issues
ROADMAP-x.md`. The renderer fills the Implementation Issues table with labelled
rows and `F<n>` dependency cells, and fills the Dependency Graph with `F<n>`
nodes. The author runs `shirabe validate` and gets a clean result. The two
sections now agree on the token that names a feature in a cross-reference,
which they did not before.

**Reading someone else's roadmap.** A reviewer opens a roadmap with eight
features and long labels. The Dependencies column is a list of short indices
they can match against the Dependency Graph directly below, because the graph
uses the same `F<n>` numbering. Previously the graph said `F3 --> F5` and the
table repeated two full labels, and the reviewer had to map between them.

**Fixing a stale dependency.** An author deletes a feature and forgets to
update a dependency cell that pointed at it by index. The index now runs past
the end of the table, FC06 reports it as naming no row, and the author fixes
the cell. Nothing about the alias makes an out-of-range reference quieter than
it is today.

**Hand-editing a label-keyed cell.** An author who prefers the explicit form
writes the full label in a dependency cell of a table whose other cells use
indices. It validates. The two forms coexist within one table because
resolution is per-token, not per-table.

## Scope Boundary

**In scope.** FC06's roadmap arm gains positional resolution for a Dependencies
token matching `^F[0-9]+$` that matches no entity-row key: the token resolves
against the nth entity row of the same table, counting entity rows only,
1-based. `render_issueless_table` goes back to emitting `F<n>` dependency cells
while keeping labels in the key column. The three prose surfaces that describe
the emitted dependency-cell form get updated: the `--no-issues` help text, the
"Dependencies cells in issueless mode" section of
`skills/roadmap/references/roadmap-format.md`, and the issueless paragraph in
`skills/roadmap/SKILL.md`.

**Out of scope.** The plan profile, which keeps its current behaviour with no
aliasing. Any other relaxation of FC06 — an out-of-range index still errors,
and a token that isn't an `F<n>` index is resolved exactly as it is today. The
key column's rendering, including the `F<n>` fallback and its warnings, which
shipped with the label-keying change and stays as it is. What the Issues column
carries in issueless mode, a separate divergence from the shared spec that is
deliberately left alone. The default value of `--no-issues` and when populate
runs, which are a different piece of work.

## References

- `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md` — the
  design that keyed the issueless table on labels and recorded the widened
  dependency cell as an accepted negative.
- `docs/prds/PRD-roadmap-issueless-table-rendering.md` — the requirements that
  design implements.
- `references/issues-table.md` — the shared roadmap profile that
  specifies the feature label as the key form.
