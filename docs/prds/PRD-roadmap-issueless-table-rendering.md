---
schema: prd/v1
status: Draft
problem: |
  `shirabe roadmap populate --no-issues` renders an Implementation Issues table
  whose rows can't be identified from the table itself: the key column carries
  `F<n>` instead of the feature label, and the description row is an unbounded
  slice of the feature's prose body. The keying contradicts the shared
  roadmap-profile spec, which `populate --help` and the roadmap format reference
  describe the opposite way.
goals: |
  The issueless Implementation Issues table names each row's feature in its key
  column, bounds every description cell to 200 characters, tells the author when
  a feature body couldn't be summarized or a label couldn't be used as a key, and
  matches what the shared issues-table spec, the roadmap format reference, and
  `populate --help` all say it should look like.
upstream: docs/briefs/BRIEF-roadmap-issueless-table-rendering.md
source_issue: 261
motivating_context: |
  Reported after a 21-feature roadmap was populated in issueless mode and every
  row came back unidentifiable. The report's second finding restates an item
  closed a month earlier, so part of this PRD's job is to record what was
  actually fixed then and what was left.
---

# PRD: Roadmap issueless table rendering

## Status

Draft

## Problem Statement

Repos that declare `## Roadmap Issues: optional` fill a roadmap's two reserved
sections by running `shirabe roadmap populate --no-issues`. Those sections are
tool-generated and carry a "do not fill manually" marker, so whatever the
renderer emits is what every reader of that roadmap sees.

What it emits today can't be read on its own. The key column carries `F1`, `F2`,
`F3` — positional indices whose meaning lives in the Features section further up
the document. The `Issues` column, which in issue-creating mode carries the issue
links that identify a row, carries a `needs-*` label or `None` in issueless mode.
So neither of the two leading columns names the feature. The description row
underneath would be the natural fallback, but it is derived by a heuristic with
no ceiling: the renderer takes the text after `**Functional outcome:**` when a
feature has that line and the body's first sentence otherwise, and "first
sentence" means everything up to the first `.`, `!`, or `?` followed by
whitespace. A body that opens with a bullet list or a semicolon-chained paragraph
has no such terminator early on, so the whole opening block lands in one table
cell. Nothing catches it downstream: `shirabe validate` checks the table's shape,
not its cell lengths, so a roadmap with multi-thousand-character cells reports
clean.

The keying is also a live contradiction between three documents.
`references/issues-table.md` specifies the roadmap profile's key form as the
feature label. `populate --help` and
`skills/roadmap/references/roadmap-format.md` both document `F<n>` as the
intended issueless form. A contributor reading one and an implementer reading
another will build incompatible things, and nothing surfaces the conflict until
someone runs the tool and compares.

Both halves affect the same reader at the same time. An opaque key would be
tolerable if the description named the feature, and a long description would be
tolerable if the key named it. Together they produce a row with no identifier
anywhere.

The same derivation carries a third, smaller failure that surfaced while
investigating the first two: a feature with no prose body renders `| __ | | | |`,
which is a bold marker rather than an italic one, and FC05 rejects it as a
missing description row. A roadmap the tool wrote can therefore fail the tool's
own validator.

## Goals

- A reader can work out what every row of an issueless Implementation Issues
  table refers to without leaving the table.
- A description cell is a summary, bounded at 200 characters.
- An author whose feature body can't be summarized, or whose label can't serve as
  a key, is told so when they populate, and told what to change.
- The shared issues-table spec, the roadmap format reference, and the
  `populate --help` text describe the same table.
- Every roadmap the tool writes passes the tool's own validator with no
  error-level finding.
- The record of what the earlier description-row fix covered, and what it left,
  is written down where the next reader of this subsystem will find it.

## User Stories

- As a roadmap author in a repo that declares `## Roadmap Issues: optional`, I
  want the generated table to name each feature, so that I can review what the
  tool wrote without cross-referencing my own Features section.
- As a reviewer of the pull request that adds a roadmap, I want each row to be
  self-describing, so that I can judge the sequencing without reconstructing
  which feature each index refers to.
- As a roadmap author whose feature bodies open with lists, I want to be told
  which features didn't summarize cleanly, so that I can add a
  `**Functional outcome:**` line where it matters instead of discovering the
  problem months later.
- As a roadmap author who names two features the same way, or who writes a label
  containing a comma, I want the tool to produce a valid table anyway and tell me
  which feature it had to fall back on, so that a naming choice can't silently
  produce a roadmap that fails validation.
- As a contributor implementing something that consumes the roadmap profile, I
  want one answer about the table's shape across the spec, the format reference,
  and the tool's help text, so that I don't have to run the tool to find out
  which document is stale.

## Requirements

Every requirement below applies to `shirabe roadmap populate --no-issues` unless
it names issue-creating mode explicitly.

### The key column

- **R1.** A feature's **key text** SHALL be its heading label with trailing
  issue-link decoration stripped, and nothing else: no truncation and no
  character substitution. This is the same transform the issue-creating renderer
  already applies to its own key column, and it is deliberately *not* the
  diagram's node-label transform, which additionally truncates at 40 characters
  and rewrites brackets and backticks.
- **R2.** A feature's key text SHALL be **usable** when, after trimming, it is
  non-empty, contains neither `,` nor `|`, and is not shared with any other
  feature in the same roadmap. When the key text is not usable, that feature's
  key SHALL fall back to `F<n>`, where `n` is the feature's 1-based position in
  the Features section.
- **R3.** The Implementation Issues table's key column SHALL carry each feature's
  key text when usable, and its `F<n>` fallback otherwise.
- **R4.** A delivered feature's row SHALL keep its existing strikethrough
  decoration, applied to the key cell as it is today (`~~<key>~~`). Strikethrough
  is decoration on the row, not part of the key.

### The Dependencies column

- **R5.** A Dependencies cell SHALL name each depended-on feature by that
  feature's key as rendered in its own row's key column, undecorated — no
  strikethrough markers, even when the depended-on feature is delivered.
- **R6.** Cross-repo references (a dependency token containing `/`, such as
  `tsukumogami/koto#65`) SHALL be preserved verbatim.
- **R7.** A local `Feature N` token that names no feature in this roadmap SHALL
  be dropped from the cell, matching the current behaviour of both modes.
- **R8.** A cell that resolves to no reference at all SHALL read `None`.
- **R9.** A mixed cell SHALL list resolved local keys first, in feature order,
  then cross-repo references in source order, comma-and-space separated.
- **R10.** No Dependencies cell SHALL carry a parenthetical annotation. Soft-
  versus-hard and external-dependency nuance stays in the feature prose.

### The description column

- **R11.** The description-cell derivation SHALL continue to prefer the text
  following a feature's `**Functional outcome:**` marker over the body's opening
  prose, and to fall back to the body's first sentence otherwise.
- **R12.** A rendered description cell's text SHALL NOT exceed **200 characters**,
  counted as Unicode scalar values, with the truncation marker counted inside
  that budget.
- **R13.** When the derived text exceeds the ceiling, it SHALL be truncated at
  the last whitespace boundary at or before character 197 and the three-character
  ASCII marker `...` appended. When no whitespace boundary exists in the first
  197 characters, the text SHALL be cut at exactly 197 characters and the marker
  appended.
- **R14.** When a feature yields no description text, the cell SHALL carry the
  fixed placeholder `No description in the feature body.` rather than an empty
  italic marker, so the row satisfies FC05's description-row shape.
- **R15.** R11 through R14 apply to both populate modes. They are properties of
  the shared derivation, not of one renderer.

### Diagnostics

- **R16.** When a description cell is truncated under R13, the run SHALL emit one
  stderr line naming the feature by its heading label and containing the literal
  string `**Functional outcome:**` as the remedy.
- **R17.** When a feature's key falls back to `F<n>` under R2, the run SHALL emit
  one stderr line naming the feature by its heading label and stating which
  condition triggered the fallback (empty, contains `,`, contains `|`, or
  duplicated).
- **R18.** Diagnostics SHALL be emitted in feature order, SHALL be prefixed
  `warning:` to match the existing convention in this crate, SHALL NOT change the
  process exit status, and SHALL be emitted under `--dry-run` on the same terms.

### The diagram

- **R19.** The issueless Dependency Graph SHALL keep `F<n>` node ids and its
  existing node-label transform. The key-column change SHALL NOT propagate into
  the diagram.

### Documentation

- **R20.** The `--no-issues` help text SHALL state that the table's key column
  carries the feature label, that dependency cells name those labels, and that
  descriptions are bounded. It SHALL NOT describe the rows as keyed `F1`, `F2`.
- **R21.** `skills/roadmap/references/roadmap-format.md` SHALL describe the same
  key form and the same Dependencies-cell rule as `references/issues-table.md`.
  Neither file SHALL present `F<n>` as the issueless table's key form.

### Non-functional

- **R22.** A roadmap populated in issueless mode SHALL produce no error-level
  finding from `shirabe validate`, and no notice-level finding from FC05, FC06,
  FC07, or FC08. This holds unconditionally, including for roadmaps whose labels
  triggered the R2 fallback.
- **R23.** Feature label text SHALL NOT be transformed beyond R1's decoration
  stripping when it reaches the table. Labels carrying shell metacharacters
  SHALL round-trip verbatim, preserving the populate module's existing invariant
  that no shell is invoked on label content.
- **R24.** Issue-creating mode's key column, Dependencies-cell resolution, and
  Issues-column contents SHALL be unchanged. Its description cells change only as
  R15 requires.
- **R25.** Rendering SHALL stay deterministic: populating the same roadmap twice
  SHALL leave the file byte-identical.

### Worked example

Given this Features section:

```markdown
### Feature 1: Baseline — [#12](https://github.com/o/r/issues/12)
**Dependencies:** None
**Status:** Done

**Functional outcome:** the pipeline reads a manifest once and emits a
normalized record set.

### Feature 2: Resolver cache
**Dependencies:** Feature 1, tsukumogami/koto#65
**Status:** Not started

The stages this adds, end to end:

- discovery, which walks the configured roots
- normalization, which folds each candidate into the record shape
- validation, which rejects records that cannot be resolved later
- emission, which hands the survivors to the resolver
```

the renderer produces:

```markdown
| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|
| ~~Baseline~~ | ~~None~~ | ~~None~~ | ~~Done~~ |
| ~~_the pipeline reads a manifest once and emits a normalized record set._~~ | | | |
| Resolver cache | None | Baseline, tsukumogami/koto#65 | Not started |
| _The stages this adds, end to end: - discovery, which walks the configured roots - normalization, which folds each candidate into the record shape - validation, which rejects records that cannot be..._ | | | |
```

Feature 1's key is `Baseline`: the `— [#12](...)` decoration is stripped (R1) and
the whole row is struck through because the feature is delivered (R4). Its
description is the `**Functional outcome:**` text at 69 characters, well inside
the ceiling, so nothing is truncated (R11, R12).

Feature 2's Dependencies cell names `Baseline` undecorated (R5) and preserves the
cross-repo token verbatim after it (R6, R9). Its body carries no sentence
terminator at all, so the derived text is the whole 265-character block; it is
cut at the last whitespace at or before character 197 and marked, giving a
199-character cell (R13). The run emits a `warning:` line naming the feature and
the `**Functional outcome:**` remedy (R16).

## Acceptance Criteria

Each criterion is numbered so a test can cite it.

- [ ] **AC1 (R1, R3).** A feature headed `### Feature 1: Baseline — [#12](url)`
      renders `Baseline` in the key column: decoration stripped, not truncated,
      brackets and backticks in a label left as written.
- [ ] **AC2 (R4).** A feature whose Status is `Done` renders `~~<key>~~` in the
      key column and `~~_<description>_~~` in its description row.
- [ ] **AC3 (R2).** A feature whose label is empty or whitespace-only after
      stripping renders `F<n>` in the key column, `n` being its 1-based position
      in the Features section.
- [ ] **AC4 (R2).** Two features sharing a label both render `F<n>` keys, and a
      dependency on either names the corresponding `F<n>`.
- [ ] **AC5 (R2).** A feature whose label contains a comma renders `F<n>`, and so
      does every dependency reference to it.
- [ ] **AC6 (R2).** A feature whose label contains a pipe renders `F<n>`, and the
      rendered table row still has exactly four cells.
- [ ] **AC7 (R5).** Every Dependencies token in the rendered table matches an
      entity row's key cell in the same table, after strikethrough is stripped.
- [ ] **AC8 (R5).** A dependency on a delivered feature renders that feature's
      key without `~~` markers.
- [ ] **AC9 (R6, R8, R9).** A feature depending only on `tsukumogami/koto#65`
      renders that token verbatim; a feature with no dependencies renders `None`;
      a feature depending on both a local feature and a cross-repo reference
      renders the local key first, then the cross-repo token, separated by
      `, `.
- [ ] **AC10 (R7).** A feature depending on `Feature 99` in a five-feature
      roadmap renders a cell without that token.
- [ ] **AC11 (R10).** A feature whose source reads
      `**Dependencies:** Feature 1 (soft)` renders a cell with no parenthetical.
- [ ] **AC12 (R12).** No description cell in a populated roadmap exceeds 200
      Unicode scalar values, including for a body that is a bullet list with no
      sentence terminator and for a body that is one long semicolon-chained
      paragraph.
- [ ] **AC13 (R13).** A derived text of exactly 200 characters renders untouched;
      a text of 201 characters renders truncated at a whitespace boundary and
      ending in `...`; a single 400-character word renders as 197 characters plus
      `...`.
- [ ] **AC14 (R11).** A feature carrying a `**Functional outcome:**` line renders
      that text, bounded, rather than the body's opening prose.
- [ ] **AC15 (R14).** A feature with no prose body renders
      `| _No description in the feature body._ | | | |`, and the populated
      roadmap validates with no error-level finding.
- [ ] **AC16 (R15, R24).** The issue-creating renderer applies the same ceiling:
      a feature with an over-long body renders a bounded cell in that mode too,
      and the issue-creating mode's existing tests pass unchanged.
- [ ] **AC17 (R16).** Truncating a description emits a stderr line naming the
      feature and containing `**Functional outcome:**`, and the command exits 0.
- [ ] **AC18 (R17, R18).** An R2 fallback emits a stderr line naming the feature
      and its trigger, the command exits 0, and the lines appear in feature
      order.
- [ ] **AC19 (R19).** The rendered diagram's node ids are `F1`..`F<n>` and its
      node labels are unchanged from the current renderer's output.
- [ ] **AC20 (R22).** `shirabe validate --visibility=public` on each populated
      fixture — the ordinary one, the empty-body one, the duplicate-label one,
      and the comma-label one — reports no error-level finding and no FC05, FC06,
      FC07, or FC08 notice.
- [ ] **AC21 (R23).** A label reading `Safe; rm -rf /tmp/foo && echo HIJACKED`
      appears verbatim in the rendered key column and no shell runs.
- [ ] **AC22 (R25).** Re-running populate on an already-populated roadmap leaves
      the file byte-identical.
- [ ] **AC23 (R20).** `shirabe roadmap populate --help` contains the words
      naming the feature label as the key and does not contain the string
      `F1`.
- [ ] **AC24 (R21).** Neither `references/issues-table.md` nor
      `skills/roadmap/references/roadmap-format.md` presents `F<n>` as the
      issueless key form. Verified by review, not by the test suite.

AC1 through AC22 each have a corresponding test. AC23 is a CLI-level assertion.
AC24 is a review checklist item.

## Decisions and Trade-offs

### D1 — The spec wins: the key column carries the feature label

The upstream brief left open which side of the contradiction changes. The spec
wins, and the two documents describing `F<n>` are corrected.

The alternative was to affirm `F<n>` as correct for issueless mode and add a
carve-out to `references/issues-table.md`, on the reading that the rows are
feature-keyed rather than issue-keyed and an index is the honest key. Three
things decided it against that reading.

First, the spec's key form is not an accident of wording: it says the key is
free text identifying the feature and may even carry a link to the per-feature
body section, which is a deliberate accommodation of exactly the "help the reader
find the feature" concern that motivates the report. Second, the `F<n>` form has
no recorded rationale. The design that introduced issueless mode decides the
dependency-cell *annotation* question, not the key form; the index came in with
a fixture that mirrored one adopter's hand-written table. Third, the argument
that `F<n>` is needed for the validator does not hold: the issue-creating
renderer already keys rows on the label and satisfies FC06 by resolving each
`Feature N` reference to the depended-on feature's label, and a probe of a
label-keyed issueless roadmap validates clean.

The cost is that Dependencies cells become longer and repeat label text. The
`F<n>` handle survives in the two places it was load-bearing: the diagram's node
ids (R19), and the fallback key for a feature whose label can't serve (R2).

### D2 — Bound the description at render, and say so

The brief left open whether an over-long description is bounded by the renderer
or left alone with the author told to fix the feature body. Both, in that order:
the renderer bounds the cell it emits, and it also tells the author when it had
to.

Bounding alone would silently drop content an author might have wanted. Warning
alone would leave the tool capable of writing a roadmap nobody can read, and the
reserved sections carry a "do not fill manually" contract, so the author's only
remedy would be to rewrite the feature body and re-run — with no guarantee they
ever notice. The renderer is the only producer of these cells, so bounding there
is sufficient in practice; the diagnostic is what makes the loss visible.

200 characters is roughly two sentences of ordinary prose, against the "1-3
sentences" the shared spec asks for. It is a deliberate compromise: high enough
that a normal `**Functional outcome:**` sentence is never touched (the longest
in the reproduction fixture was 194), low enough that a truncated cell still
reads as a table cell.

### D3 — One rule for every unusable key, not three special cases

Three separate conditions make a label unfit to key a row: it can be empty, it
can contain a character the table or the validator's dependency-cell parser
treats as a delimiter (`|` breaks the markdown row; `,` splits into tokens that
name no row and trip FC06 at error level), or it can collide with another
feature's label and make dependency references ambiguous. Rather than a distinct
behaviour per condition, R2 defines one usability predicate and one fallback.

The alternative — emitting the label anyway and warning — was rejected because it
lets the tool knowingly write a document that fails its own validator, which is
exactly the failure mode the reserved-section contract is supposed to prevent.
The alternative of escaping or rewriting the offending characters was rejected
because it breaks R23's verbatim round-trip, which is a security invariant of
this module rather than a stylistic preference.

The cost is that a roadmap with a comma in one label gets one opaque row back.
The diagnostic names it, and the fix is in the author's hands.

### D4 — The earlier fix covered this path; the defect that survives is narrower

The report treats its second finding as a closed item that still reproduces. The
investigation says something more specific, and the pull request that lands this
work records it: the earlier fix does cover issueless mode — the issueless
renderer calls the same `concise_description` helper the issue-creating renderer
does — and it remains in place. What it never did was bound the result, so a body
whose first sentence terminator arrives late still yields an unbounded cell. The
reported magnitude is consistent with a build predating that fix, and the version
string in the report cannot distinguish the two eras because it is a floating
development sentinel that has been unchanged since before the fix landed.

This matters for scope: the work here is not restoring lost behaviour, so nothing
about the earlier fix needs reverting or re-deriving.

### D5 — No new validator check

Adding a cell-length check to `shirabe validate` was considered and rejected. The
reserved sections are tool-generated and must not be hand-edited, so after R12 the
renderer cannot produce an over-long cell; a validator check would only catch
documents that violated the no-hand-editing contract. It stays a separate
question about the validation surface.

## Known Limitations

- **A pipe inside a feature body still breaks its description cell.** R2 handles
  a pipe in a *label*; the description text comes from the body, and a `|` there
  splits the markdown row. This is unchanged by this work and is not covered by
  R23, whose verbatim guarantee is about label text reaching the key column.
- **Truncation is lossy.** A bounded cell for a feature whose body has no early
  sentence terminator is a fragment of that body, not a written summary. The
  author's remedy is a `**Functional outcome:**` line, which is what R16's
  diagnostic names.
- **A dropped dependency token is silent.** R7 keeps the current behaviour of
  discarding a `Feature N` token that names no feature. Adding a diagnostic for
  it would be an improvement, but dependency-edge loss is the subject of a
  separate report against this subsystem and is out of scope here.
- **Longer cells.** Label-keyed dependency cells repeat feature labels, so a
  feature with several dependencies gets a visibly wider cell than the `F1, F2`
  form produced.

## Out of Scope

- The three other findings reported alongside the description-row defect (plural
  dependency forms dropping edges, `Status:` mangling, diagram node ids versus
  the shared bijection convention). They are separate reports against the same
  subsystem.
- Issue-creating populate mode's key column, Dependencies-cell resolution, and
  Issues-column contents (R24). Only the shared description derivation changes
  for that mode.
- What the `Issues` column carries in issueless mode. A `needs-*` label in a
  column the spec describes as an issue fan-out is a third divergence, and it is
  a different question from the key column's.
- New or widened validator checks (D5).
- Re-populating roadmaps that were already written with `F<n>` keys. This repo
  carries no roadmap under `docs/`, so there is nothing here to migrate;
  downstream adopters re-run populate when they next touch their roadmap.
- Whether issueless mode should exist. Settled in
  `docs/designs/current/DESIGN-roadmap-issueless-preference.md`.
