# Phase 2 findings: roadmap-issueless-table-rendering

Investigated directly against `main` at `70cd921` with a binary built from that
commit and the installed `shirabe` validator.

## Lead 1 — what the shared spec requires

`references/issues-table.md` (Roadmap Profile) is unambiguous: "Key form: the
feature label naming the feature (free text identifying the feature; not a
clickable link by itself, though the label may contain a link to the per-feature
body section)", with the canonical shape showing `| <feature label> | ... |`.
There is no issueless-mode carve-out anywhere in that file.

Two other documents say the opposite for issueless mode:

- `crates/shirabe/src/populate.rs` `--no-issues` help text: "a feature-keyed
  Implementation Issues table (rows keyed `F1`, `F2`, ...)".
- `skills/roadmap/references/roadmap-format.md` Reserved Sections: "The table is
  feature-keyed (`F<n>` rows, the feature's `needs-*` label in the Issues
  column)", plus a "Dependencies cells in issueless mode" section requiring bare
  `F<n>` keys.

The design that introduced issueless mode
(`docs/designs/current/DESIGN-roadmap-issueless-preference.md`) does not decide
the key form. Its Decision C is about dependency-cell *annotations* — `F1 (soft)`
and `None (ext: ...)` trip FC06 — and its evidence is a fixture mirroring an
adopter's hand-written shape. The `F<n>` key came in with that fixture rather
than from a recorded decision.

## Lead 2 — does keying on the label break FC06 or FC07?

No, on both counts, and the issue-creating renderer already proves it.

FC06 (`crates/shirabe-validate/src/checks.rs`) builds its key set from entity
rows' first cells and requires each Dependencies token to name one of them.
`extract_entity_key` and `extract_deps` both run values through
`normalize_feature_ref`, which unwraps `[label](target)` to `label`, so labels
work as keys and as dependency tokens. The issue-creating path already renders
label keys and resolves each `Feature N` reference to that feature's label via
`render_deps_cell`, and its round-trip test asserts a clean validate.

FC07 is indifferent. Its node, edge, and class passes all filter on
`ISSUE_KEYED_NODE_ID` (`^I[0-9]+$`), and the issueless diagram emits `F<n>`
nodes, so the diagram contributes nothing to reconcile in either keying.

Probe: a hand-written five-feature roadmap with label keys, label dependency
cells, strikethrough on the Done row, and the existing `F<n>` diagram runs
`shirabe validate --visibility=public` to exit 0 with no error or notice other
than the FC09 no-PR-context skip.

**Constraint the probe surfaces.** `extract_deps` splits a Dependencies cell on
commas with no escaping. A feature label containing a comma would split into
tokens that name no row, and FC06 is error-level. The issue-creating path already
carries this exposure; label keys extend it to issueless mode.

## Lead 3 — regression, or a path never covered?

Neither, precisely. The #232 item-2 fix landed in #237 (`4df0c02`, 2026-07-11)
and it did cover the issueless path: `render_issueless_table` calls
`concise_description` at the same place the issue-creating renderer does. Before
that commit the issueless renderer interpolated `f.description` verbatim, which
is exactly the whole-body concatenation the report describes.

What the fix did not do is bound the result. `concise_description` prefers the
text after `**Functional outcome:**` and otherwise takes `first_sentence`, which
returns the entire string when it finds no `.`, `!`, or `?` followed by
whitespace. Reproduced on `main`: a feature body opening with a bullet list
produced a 459-character cell and one written as a semicolon-chained paragraph
produced 534, in a fixture deliberately kept small. There is no ceiling, so the
same failure scales with body length.

The version the report cites cannot separate the two eras. `0.15.1-dev` is a
floating sentinel set on 2026-07-07 (`5829562`), four days before the fix, and
still current today; every commit in between reports the same string. The row the
report pastes (`| F4 | None | Feature 1, Feature 2, Feature 3 | Not started |`)
carries raw `Feature N` tokens in the Dependencies cell, which no version of the
issueless renderer emits — both before and after #237 it emits `F1, F2, F3` — so
that row is a paraphrase rather than literal output and cannot date the build
either.

Conclusion to record: the #232 fix covered this path and remains in place; what
survives is a narrower, still-live defect — the extraction is unbounded.

## Lead 4 — what the renderer emits today

Against a five-feature fixture with multi-paragraph bodies:

- Key column: `F1`..`F5`, struck through on the Done feature.
- Issues column: the feature's `needs-*` label, or `None`.
- Dependencies column: `F1, F2, F3` (bare keys, correct under FC06).
- Status column: the feature's `**Status:**`, or its `needs-*` label.
- Description rows: single sentences, 119-194 characters for ordinary prose
  bodies; unbounded for bodies without an early sentence terminator.
- Diagram: `F<n>` nodes labeled with the feature label, edges from the parsed
  dependencies, palette and legend restricted to assigned classes.

The label the table lacks is already computed one function away:
`render_issueless_diagram` calls `strip_label_decoration(&f.label)` for every
node.
