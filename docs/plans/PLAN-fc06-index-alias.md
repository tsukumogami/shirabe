---
schema: plan/v1
status: Draft
execution_mode: single-pr
upstream: docs/prds/PRD-fc06-index-alias.md
milestone: "FC06 index alias"
issue_count: 3
---

# PLAN: fc06-index-alias

## Status

Draft

Single-pr plan. The three issues below ship on one branch and one PR;
no GitHub issues are materialized. The upstream work item is
tsukumogami/shirabe#263.

## Scope Summary

Teach FC06's roadmap arm to resolve a Dependencies token matching
`^F[0-9]+$` against the nth entity row of the same Implementation Issues
table when that token matches no entity-row key, then let
`render_issueless_table` emit the compact form, then bring the three prose
surfaces that document the emitted cell back into agreement with the tool.

The change is confined to two functions and their doc comments:
`check_fc06` in `crates/shirabe-validate/src/checks.rs`, and the
`render_issueless_table` / `render_deps_cell` pair in
`crates/shirabe/src/populate.rs`. Nothing else about FC06 moves: an
out-of-range index still errors, a token that matches a key is still
resolved as a key, and the plan profile is untouched. The requirements are
R1-R10 in `docs/prds/PRD-fc06-index-alias.md`.

## Decomposition Strategy

Vertical, sliced by the layer that owns each behaviour, and sequenced so
the validator accepts the compact form before the renderer produces it.
Issue 1 is the validator change; issue 2 is the renderer change and depends
on issue 1, because the round-trip tests in issue 2 render a document and
then validate it, and that assertion only passes once FC06 resolves the
alias. Issue 3 is the prose, which depends on issue 2 because it describes
what issue 2 emits.

The grouping rule is one issue per code owner plus one for documentation.
There are two cross-issue edges, both on the critical path; there is no
parallelism to exploit and the whole plan is one PR anyway.

## Issue Outlines

### Issue 1: feat(validate): resolve F<n> index aliases in roadmap dependency cells

**Goal**: `check_fc06` resolves an `F<n>` Dependencies token positionally
against the table's entity rows, for the roadmap profile only, and only
after the key lookup has failed.

**Acceptance Criteria**:

- A roadmap-profile table with label keys and an `F<n>` dependency cell
  naming an in-range entity row produces no FC06 finding.
- The resolution counts entity rows only, 1-based; description and child
  rows interleaved between entity rows do not shift the numbering.
- A token matching an entity-row key is resolved as a key. A table with a
  row literally keyed `F2` resolves `F2` to that row regardless of its
  position, and a test fails if the precedence is inverted.
- `F0` and an index past the last entity row both produce the existing
  `[FC06] dependency "..." in row "..." names no row in this table` error,
  unchanged in text and severity.
- A `plan/v1` table with `F1` in a Dependencies cell still reports the
  error; the profile gate is pinned by a test.
- Resolution reads only the parsed issues table. No new call reaches the
  Features section, the Dependency Graph, or frontmatter.
- Tokens that are not `^F[0-9]+$` — cross-repo refs, `#N` tokens, labels —
  take exactly the path they take today.

**Dependencies**: None

**Type**: code.

**Files**: `crates/shirabe-validate/src/checks.rs`.

### Issue 2: feat(populate): emit F<n> dependency cells in the issueless table

**Goal**: `render_issueless_table` emits Dependencies cells naming
depended-on features by index while the key column keeps the feature label
(or its `F<n>` fallback), and the rendered document validates clean.

**Acceptance Criteria**:

- The issueless table's Dependencies cells carry `F<n>` tokens in feature
  order, de-duplicated, with cross-repo references preserved verbatim
  alongside them.
- A cell that resolves to no reference still renders `None`.
- A feature whose key fell back to `F<n>` needs no special handling; the
  test asserting this documents that the key and the alias are the same
  token.
- Issue-creating mode's rendered table is unchanged, and a test pins it.
- The existing round-trip tests `run_issueless_render_validates_clean` and
  `populated_output_passes_validate` pass unmodified in intent, and a new
  round-trip case renders a roadmap with long labels and validates the
  output clean, exercising the alias end to end.
- A stale feature index in an author's `**Dependencies:**` line contributes
  no token, as it does today.

**Dependencies**: Issue 1

**Type**: code.

**Files**: `crates/shirabe/src/populate.rs`,
`crates/shirabe/tests/populate_cli.rs`.

### Issue 3: docs(roadmap): describe the emitted dependency-cell form

**Goal**: The three prose surfaces that describe the issueless dependency
cell say what the renderer now emits.

**Acceptance Criteria**:

- The doc comment on `PopulateArgs::no_issues`, which becomes the
  `--no-issues` help text, describes the key column as the feature label
  (with its `F<n>` fallback) and the Dependencies column as `F<n>`
  indices.
- The "Dependencies cells in issueless mode" section of
  `skills/roadmap/references/roadmap-format.md` describes the same form and
  notes that the label form also validates.
- The issueless paragraph in `skills/roadmap/SKILL.md` matches.
- The edits stay inside the dependency-cell subject. They do not restate or
  revise anything about flags, defaults, or when populate runs.

**Dependencies**: Issue 2

**Type**: docs.

**Files**: `crates/shirabe/src/populate.rs`,
`skills/roadmap/references/roadmap-format.md`, `skills/roadmap/SKILL.md`.

## Implementation Sequence

One batch, strictly ordered, on one branch:

1. **Issue 1** — the validator alias. Land it first so the round-trip
   assertions in issue 2 have something to pass against.
2. **Issue 2** — the renderer. Its round-trip tests are the guard that the
   two halves agree.
3. **Issue 3** — the prose, written against the output issue 2 actually
   produces.

Verification before the PR opens: `cargo test --workspace` green,
`cargo clippy --workspace --all-targets` with no new warnings, `cargo fmt`
clean on the touched files only (the repo carries pre-existing formatting
drift in `crates/shirabe-validate/src/checks.rs` and sibling files, so a
workspace-wide format would bury the change), and the validation script in
tsukumogami/shirabe#263 passing on the branch and failing on `main`.

## References

- `docs/prds/PRD-fc06-index-alias.md` — the requirements this plan
  implements.
- `docs/briefs/BRIEF-fc06-index-alias.md` — the framing.
- `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md` — the
  upstream design whose accepted negative this plan reverses.
- `references/issues-table.md` — the shared roadmap profile.
