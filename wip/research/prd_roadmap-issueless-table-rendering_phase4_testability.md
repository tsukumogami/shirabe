# Testability Review

## Verdict: FAIL

Most criteria are concrete and assertable, but the central new behaviour — the description-cell ceiling — carries no value anywhere in the document, so its acceptance criterion cannot be written as a test at all, and three criteria conflict with each other or with the Known Limitations section badly enough that a test author would have to ask the author what the expected result is.

## Untestable Criteria

1. **"No description cell in the generated table exceeds the character ceiling"**: the ceiling is never given a number. R5 says "a fixed character ceiling" and the criterion says "the character ceiling" as if it had been defined; it has not been, not in Requirements, not in Decisions, not in Known Limitations. A tester writing `assert!(cell.chars().count() <= N)` has no N. The unit is also unstated — bytes, `char`s, or grapheme clusters — which matters because feature labels and bodies are arbitrary UTF-8 and byte-slicing at a ceiling can split a character. -> State the value and the unit in R5 (e.g. "SHALL NOT exceed 200 characters, counted as Unicode scalar values") and reference that number from the criterion.

2. **"A feature label containing a comma emits a stderr diagnostic naming the feature, and the command still exits 0"** conflicts with its own requirement and with Known Limitations. R8 fires the diagnostic "when a feature label contains a character that prevents the emitted *dependency cell* from reconciling" — conditional on some other feature depending on it. The criterion fires unconditionally on any comma-bearing label. A comma-labeled feature with no dependents is expected to warn under one reading and stay silent under the other. -> Pick one trigger condition and state it in both places; if the trigger is the emitted dependency cell, the criterion's fixture must include a dependent feature.

3. **The comma fixture's rendered output and validation result are undefined.** Criterion 2 requires every dependency token to match an entity row; criterion 9 requires no error-level validate finding; Known Limitations says a comma-bearing label "produces dependency tokens that name no row." A test author building the comma fixture cannot tell whether the resulting roadmap is expected to validate clean (contradicting Known Limitations) or to fail validation (contradicting criterion 9), nor what the dependency cell should actually contain — the raw comma-bearing label, an escaped form, or a fallback to `F<n>`. -> Specify the rendered dependency cell for a comma-bearing label, and scope criterion 9's fixture to exclude it or state the expected finding.

4. **"`shirabe roadmap populate --help` describes the label-keyed table"**: "describes" is a judgment call, not an assertion. The current help text presumably also "describes" a table, just the wrong one. -> Name the substring the help text must contain and the one it must no longer contain (e.g. must not contain `F1, F2`).

5. **"`references/issues-table.md` and `skills/roadmap/references/roadmap-format.md` describe the same key form and the same Dependencies-cell rule"**: sameness of prose across two documents is not machine-checkable and requires a human to decide what counts as "the same." Legitimate as a review gate, but it is not a test. -> Label it a review-checklist item, or reduce it to a mechanical check (neither file contains `F<n>` as the issueless key form).

6. **"Regression tests cover the key column, the dependency cells, the description ceiling, and both diagnostics"**: self-referential — a test plan cannot test that tests exist. It also duplicates criteria 1, 2, 5, 7, and 8, which are the tests in question. -> Drop it, or restate as a coverage checklist owned by review rather than by the suite.

7. **"The pull request states whether the description defect was a regression or an uncovered path, with the evidence"** (and R11 behind it): a property of a PR description, unverifiable by any test and dependent on a reviewer's reading of "with the evidence." Reasonable as a merge gate; it does not belong among acceptance criteria a test plan is written from. -> Move to a PR checklist section.

8. **"every entity row's first cell is that feature's label"** is ambiguous for two row shapes the renderer already emits. Delivered features are struck through, so the cell is `~~label~~`, not `label` — a literal equality assertion fails on a correct implementation. And R1 requires the label with "trailing issue-link decoration stripped," which the criterion omits, so a test author does not know whether a label written `Foundation layer ([#12](...))` should render whole or stripped. -> Say "the feature's label with issue-link decoration stripped, struck through for delivered features."

9. **"The issue-creating mode's existing tests pass unchanged"** is verifiable but hides an undecided question. `concise_description` is shared by both renderers (R14 anticipates exactly this), so applying the ceiling inside it bounds issue-creating descriptions too. R14 protects that mode's key column, dependency resolution, and validation posture — it says nothing about description length. If bounding is intended in both modes, existing tests may legitimately need updating and this criterion blocks a correct implementation; if not, no criterion asserts the issue-creating cell stays unbounded. -> State whether the ceiling applies in issue-creating mode, and give it its own criterion either way.

## Missing Test Coverage

1. **Pipe characters in labels**: R13 requires labels to "round-trip verbatim into the rendered table," but a label containing `|` breaks the markdown table's column structure outright — a sharper failure than the comma case that Known Limitations devotes a paragraph to. No criterion exercises it, and no requirement says what should happen (escape, strip, diagnose, or fall back to `F<n>`).

2. **Duplicate feature labels**: the change replaces a guaranteed-unique key (`F<n>`) with author-supplied text that has no uniqueness constraint. Two features labeled the same produce two rows with the same key, and a dependency naming that label resolves ambiguously — criterion 2 would pass vacuously. Nothing in the PRD acknowledges this.

3. **Delivered (struck-through) features**: the renderer has a distinct branch for terminal features that strikes every cell including the description row. No criterion covers a delivered feature's key cell, its dependency cell, or whether a struck dependency reference still reconciles against a struck entity row.

4. **R4's annotation stripping**: no criterion feeds a feature whose source dependencies read `Feature 1 (soft)` or `None (ext: ...)` and asserts the parenthetical is gone. Criterion 2 catches this only indirectly, and only if the fixture happens to include one.

5. **Mixed dependency cells**: criterion 3 tests cross-repo-only and none-at-all. A feature with both a cross-repo reference and a feature reference is untested, and R3 does not state the ordering or separator for the mixed cell.

6. **Truncation boundary behaviour**: R5's word-boundary rule and ellipsis marker are never asserted. Uncovered: text exactly at the ceiling (truncate or not), a single word longer than the ceiling (where no word boundary exists), and whether the ellipsis counts toward the ceiling.

7. **R12's second half**: "no new notice-level finding relative to the current renderer's output" needs a before/after baseline comparison. Criterion 9 checks only error-level findings, so the notice-level half has no criterion at all.

8. **Empty and degenerate inputs**: a roadmap with zero features, a feature with an empty body (empty description cell — diagnostic or not?), and a feature with an empty label that is also depended upon (does the dependency cell carry `F<n>` per R2, or the empty text?).

9. **Diagnostic behaviour under `--dry-run` and repeat runs**: criterion 10 pins the file to byte-identical output but says nothing about stderr. Whether diagnostics are emitted in dry-run mode, and whether their order is deterministic across runs, is unspecified and untested.

## Summary

The structural criteria — key column, dependency reconciliation, `None` fallback, idempotence, exit status — are concrete enough to write tests against directly, and the fixtures they imply (bullet-list body, semicolon-chained paragraph, cross-repo-only dependency) are well chosen. What blocks a test plan is that the description ceiling, the one genuinely new behaviour in the change, has no stated value or unit, and that the comma-label criterion contradicts both its own requirement and the Known Limitations paragraph about it, leaving three interlocking criteria whose expected results a tester cannot determine without asking the author. Beyond that, the criteria are weighted toward the happy path: pipe-bearing labels, duplicate labels, delivered struck-through rows, and truncation boundary cases are all reachable through normal use and all uncovered.
