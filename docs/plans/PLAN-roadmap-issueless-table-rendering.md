---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-roadmap-issueless-table-rendering.md
milestone: "Roadmap issueless table rendering"
issue_count: 6
---

# PLAN: Roadmap issueless table rendering

## Status

Active

## Scope Summary

Implements the accepted design for `shirabe roadmap populate`: label-keyed
issueless Implementation Issues rows resolved through one key table, a sanitized
and bounded description derivation shared by both populate modes, two
author-facing diagnostics, and the documentation corrections that make the four
descriptions of the table agree.

## Decomposition Strategy

**Horizontal**, in the order the design's Implementation Approach sets.

The components have stable interfaces and one is a strict prerequisite for
another: the description derivation is self-contained and touches no signature;
the stability predicate has no consumer until the key table exists; the key table
is what the renderers and the diagnostics both read. There is no integration risk
to surface early — everything is in one process, in two functions of one module,
against a validator that is not changing — so a walking skeleton would buy
nothing that the existing render-then-validate round-trip tests do not already
provide.

The ordering is chosen so the suite stays green at every step. Steps 1 and 2 add
behaviour nothing yet depends on. Step 3 is the only step that changes existing
expectations, and it changes them all at once, so a red suite between steps never
happens.

**Execution mode: single-pr.** No hard constraint forces multiple PRs: one
repository, no cross-repo landing order, no merge gate between steps. The units
are also not independently useful — a key column that changes without its
dependency cells produces a table that fails FC06, and a bounded description
without the empty-body sanitization still fails FC05. The value confirmation
lands on the whole change, not on the steps.

## Issue Outlines

### Issue 1: Sanitize and bound the description derivation

**Goal**: `summarize_description` becomes the single description derivation for
both populate modes, sanitizing the derived text and bounding it at 200
characters.

**Acceptance Criteria**:
- [ ] `summarize_description(desc) -> (String, bool)` prefers the
      `**Functional outcome:**` text and falls back to the body's first sentence,
      preserving today's selection (AC14).
- [ ] The derived text is sanitized before bounding: control characters dropped,
      `|` replaced, `~` removed, leading `_` stripped (AC15a).
- [ ] Text of 200 characters or fewer renders untouched; longer text is cut back
      to the last whitespace at or before character 197 and marked `...`; a single
      over-long word is cut at exactly 197 (AC12, AC13).
- [ ] Counting is by Unicode scalar values, never bytes.
- [ ] An empty body, or text that sanitizes to nothing, yields
      `No description in the feature body.` with the truncation flag `false`
      (AC15).
- [ ] `concise_description` is reduced to `summarize_description(desc).0` and both
      renderers keep calling it (AC16).
- [ ] The existing suite is green with no test edits.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe/src/populate.rs`

### Issue 2: Export a key-stability predicate from the validator crate

**Goal**: `shirabe-validate` exposes the one question the renderer has to ask
before using a label as a table key, answered by the validator's own
normalizers.

**Acceptance Criteria**:
- [ ] `pub fn is_stable_table_key(text: &str) -> bool` lives in
      `crates/shirabe-validate/src/table.rs` and is re-exported from the crate
      root.
- [ ] It returns false for empty or whitespace-only text, for text containing
      `,` or `|`, and for text containing a control character.
- [ ] It returns false unless `extract_entity_key` is the identity on the text
      both bare and wrapped in `~~`, and `extract_deps` returns exactly the text
      as its single token.
- [ ] Unit tests cover a plain label, a label containing `~~`, a label containing
      `#12`, a `[label](target)` form, a comma, a pipe, and a control character
      (AC6a).
- [ ] No validation check changes behaviour; `shirabe validate` output on the
      existing corpus is unchanged.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe-validate/src/table.rs`, `crates/shirabe-validate/src/lib.rs`

### Issue 3: Resolve keys once and render the issueless table from them

**Goal**: The issueless Implementation Issues table keys its rows on feature
labels, with dependency cells naming the same keys, resolved through one table
that issue-creating mode does not use.

**Acceptance Criteria**:
- [ ] `key_fallback_reason(features, i) -> Option<String>` is the only expression
      of the usability rule: not stable per issue 2, shared with another feature,
      or colliding with a feature's `F<n>` form (AC3, AC4, AC5, AC6, AC6a, AC6b).
- [ ] `feature_keys(features) -> Vec<String>` maps each feature to its stripped
      label or its `F<n>` fallback.
- [ ] `render_deps_cell` takes `keys: &[String]` and resolves a `Feature N` token
      by `position` then `get`, never by arithmetic index; `Feature 0` and a
      stale out-of-range reference are dropped without panicking (AC10).
- [ ] `render_issueless_table` renders the key column from the key table and
      passes it to `render_deps_cell`; `bare_feature_deps` is deleted (AC1, AC7).
- [ ] Delivered rows keep their strikethrough on the key cell, and dependency
      cells name the depended-on key without `~~` (AC2, AC8).
- [ ] Cross-repo tokens survive verbatim, a cell with nothing resolvable reads
      `None`, a mixed cell lists local keys in source order then cross-repo
      tokens, and no cell carries a parenthetical (AC9, AC11).
- [ ] `render_table` passes a plain-stripped-label key table and its existing
      tests pass unmodified (AC16).
- [ ] The two render-then-validate round-trip tests pass, extended with the
      fallback fixtures (AC20).

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>

**Type**: code
**Files**: `crates/shirabe/src/populate.rs`

### Issue 4: Emit the author-facing diagnostics

**Goal**: An author learns at populate time which description was cut and which
label could not serve as a key, without being told about a fallback the run did
not perform.

**Acceptance Criteria**:
- [ ] `truncation_warnings(features)` and `key_fallback_warnings(features)` are
      pure and return lines in feature order (AC18).
- [ ] `diagnostic_label` bounds the label and strips control characters before it
      reaches stderr (AC18a).
- [ ] Truncation lines name the feature and contain the literal
      `**Functional outcome:**` (AC17).
- [ ] `run_issueless` prints both sets; `run_inner` prints only the truncation
      set, so issue-creating mode never reports a fallback (AC18).
- [ ] Lines are prefixed `warning:`, the exit status is unchanged, and they are
      emitted under `--dry-run` on the same terms.
- [ ] CLI-level tests assert the lines on stderr and the exit code.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `crates/shirabe/src/populate.rs`, `crates/shirabe/tests/populate_cli.rs`

### Issue 5: Reconcile the documentation with the shared spec

**Goal**: The four places that describe the issueless table say the same thing.

**Acceptance Criteria**:
- [ ] The `--no-issues` help text states that the key column carries the feature
      label, that dependency cells name those labels, and that descriptions are
      bounded; it no longer says rows are keyed `F1`, `F2` (AC23).
- [ ] The three passages in `skills/roadmap/references/roadmap-format.md` that
      present `F<n>` as the table row key are corrected: the Reserved Sections
      bullet, the FC16 paragraph, and the "Dependencies cells in issueless mode"
      section. The passage about diagram nodes is left alone (AC24).
- [ ] The issueless paragraph in `skills/roadmap/SKILL.md` is corrected.
- [ ] The module's own doc comments no longer assert the `F<n>` key rule, and
      `render_deps_cell`'s heading no longer calls itself issue-creating-only.
- [ ] `references/issues-table.md` is unchanged, because it already specifies the
      behaviour being shipped.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: docs
**Files**: `crates/shirabe/src/populate.rs`, `skills/roadmap/references/roadmap-format.md`, `skills/roadmap/SKILL.md`

### Issue 6: Cover the security invariant on the new path

**Goal**: The verbatim label round-trip is asserted where label text newly
reaches the key column.

**Acceptance Criteria**:
- [ ] A CLI test populates a roadmap in `--no-issues` mode with a label reading
      `Safe; rm -rf /tmp/foo && echo HIJACKED`, asserts the label appears verbatim
      in the key column, and asserts no side effect ran (AC21).
- [ ] The populated output validates with no error-level finding.
- [ ] The existing issue-creating metacharacter test is unchanged.
- [ ] Re-running populate on the already-populated fixture leaves it
      byte-identical (AC22).

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `crates/shirabe/tests/populate_cli.rs`

## Implementation Issues

No GitHub issues are created in single-pr mode; the Issue Outlines section above
carries the decomposition. The canonical table is present but empty, because
FC11 expects the header on every `plan/v1` doc while FC14 sub-check E rejects a
single-pr plan whose table has entity rows.

| Issue | Dependencies | Complexity |
|-------|--------------|------------|

## Dependency Graph

_Empty in single-pr mode; dependencies are declared per outline and narrated in Implementation Sequence._

## Implementation Sequence

The critical path is issues 1 and 2, then 3, then any of 4, 5, and 6 — three
steps deep.

Issues 1 and 2 are independent of each other and of everything else: one adds a
derivation nothing calls yet, the other adds a predicate nothing consumes yet.
Both can land before issue 3 in either order.

Issue 3 is the pivot. It is the only step that changes existing test
expectations, and it changes all of them together: the five issueless unit tests
that encode `F<n>` keys, the direct `render_deps_cell` test that gains a third
argument, and the `bare_feature_deps` test that goes with the function it covers.
That the issue-creating tests do *not* move is the check that the mode boundary
held.

Issues 4, 5, and 6 all depend only on issue 3 and are independent of each other.
