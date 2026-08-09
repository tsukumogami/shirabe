# /brief Discover: roadmap-issueless-table-rendering

## Phase
1

## Grounding evidence gathered

Source report: tsukumogami/shirabe#261 (two findings on `shirabe roadmap
populate --no-issues`).

### The key-column contradiction is real and load-bearing

- `crates/shirabe/src/populate.rs:197` renders the key column as `format!("F{}",
  f.id)`.
- `references/issues-table.md` (Roadmap Profile) specifies the key form as "the
  feature label naming the feature", and the canonical shape shows
  `| <feature label> | ... |`.
- `populate --help` (`crates/shirabe/src/populate.rs:73-79`) documents the `F<n>`
  keying as the intended behaviour.
- `skills/roadmap/references/roadmap-format.md` (Reserved Sections) also
  documents `F<n>` rows for issueless mode.

So two documents state one contract and one states the opposite. That is the
framing question this brief has to settle: whether the spec or the
implementation is the thing to change.

### The label is already available at the render site

The same run emits the label into the diagram from the same `Feature` struct:
`render_issueless_diagram` calls `strip_label_decoration(&f.label)` to produce
`F4["A4 -- Establish the number"]`. No new input is needed.

### FC06 is what pushed the implementation to `F<n>`, and it does not require it

`DESIGN-roadmap-issueless-preference.md` (Decision C) chose bare-key dependency
cells because annotated cells like `F1 (soft)` trip FC06. The recorded reasoning
is about annotations, not about which token the key column carries. The
issue-creating path already keys rows on the feature label and satisfies FC06 by
resolving each `Feature N` reference to that feature's label
(`render_deps_cell`), so a label-keyed issueless table is reachable with the
helper that already exists.

FC07 is unaffected either way: its node, edge, and class passes filter on
`ISSUE_KEYED_NODE_ID` (`^I[0-9]+$`), so the `F<n>` diagram nodes contribute
nothing to reconcile.

### Defect 2 reproduces today, but not as reported

Reproduced against a five-feature fixture with a binary built from `main` at
`70cd921`:

- Feature bodies written as ordinary paragraphs produce single-sentence cells
  (max 194 chars). The #232 fix (`concise_description`, landed in #237 on
  2026-07-11) does cover the issueless path -- `render_issueless_table` calls it
  at line 210.
- Feature bodies whose first sentence terminator arrives late still produce
  unbounded cells: a bullet-list body yielded 459 chars and a semicolon-chained
  paragraph yielded 534 chars, in a fixture deliberately kept small. The
  heuristic has no ceiling, so a real 21-feature roadmap scales the same failure
  to thousands of characters.

The version the report cites, `v0.15.1-dev`, is a floating sentinel: it has been
the plugin version on every commit since 2026-07-07 (`5829562`), which is four
days *before* the #237 fix landed. It cannot distinguish a pre-fix build from a
post-fix one, and the row the report pastes (raw `Feature 1, Feature 2, Feature
3` in the Dependencies cell) matches no released renderer -- both the pre-#237
and post-#237 code emit `F1, F2, F3` there. So the 3,780-character observation is
consistent with a pre-#237 build, and the residual defect on `main` is a
different, narrower thing: the fix is heuristic and unbounded rather than absent.

## Problem / outcome pair

**Problem.** A roadmap populated in issueless mode is not readable on its own
terms: every row of the Implementation Issues table is keyed by an opaque `F<n>`
whose meaning lives in another section, and the description row that would
otherwise identify the row is a heuristic slice of prose with no length ceiling.

**Outcome.** An author who runs `shirabe roadmap populate --no-issues` gets a
table they can read top-to-bottom without cross-referencing, and the tool's own
documentation agrees with the shared format spec about what that table looks
like.

## Open framing questions deferred downstream

1. Which side of the key-column contradiction changes -- the spec or the
   implementation. (PRD Decisions and Trade-offs.)
2. Whether an over-long description is bounded at render time or surfaced to the
   author to fix at the source. (PRD Decisions and Trade-offs.)
