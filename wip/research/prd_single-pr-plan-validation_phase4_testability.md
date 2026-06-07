# Testability Review

## Verdict: PASS

The acceptance criteria are concretely testable: each AC names a specific input shape (single-pr or multi-pr plan with a specific defect), an expected validator output (FC14 notice or absence thereof), and a verifiable substring requirement (outline key, missing field name, declared vs observed counts, unresolved token verbatim).

## Untestable Criteria

1. "The Roadmap arm of `validate_file` is unchanged by inspection." -> The phrase "by inspection" makes this a code-review check rather than a runtime assertion. It is verifiable by reading the diff, but a black-box test plan cannot exercise it directly. To make it runtime-testable, add an AC such as "running `shirabe validate` on a representative Roadmap fixture produces the same notice set before and after the FC14 change" (a snapshot/golden test).

2. Sub-check B AC3: "An outline block with a malformed `Dependencies:` declaration produces an FC14 notice naming the outline key and the malformed shape." -> "Malformed dependencies declaration" is delegated to "per the format reference at `skills/plan/references/quality/plan-doc-structure.md`" in R2. A test author cannot enumerate the malformed shapes from the AC alone without reading the format reference. To make this self-contained, list 2-3 representative malformed shapes (e.g., "missing colon", "unparseable token list", "trailing comma") inline in the AC or in a referenced fixture table.

3. R2/Sub-check B uses "outline block" without defining the exact heading shape. The AC refers to "outline key" and the example in Decision D2 shows `### Outline 1:`, but the AC doesn't pin the parser's heading recognition rule. To make this testable without reading the format reference, the AC should name the heading pattern (e.g., "an `### Outline <N>:` heading or equivalent per the format reference, fixture in `tests/fixtures/...`").

## Missing Test Coverage

1. R12 (outline parser is total over arbitrary input): the Implementation-level AC says "no panics on malformed headers, missing fields, or unterminated blocks" but no AC supplies a specific input shape (e.g., an unterminated outline at EOF, an outline with only a heading and no body, binary or non-UTF-8 bytes within an outline body) that must be exercised. Add explicit fuzz/edge-case AC entries naming at least: empty `## Issue Outlines` section, outline heading with no body, file truncated mid-outline.

2. Sub-check C duplicate-key behaviour: the Known Limitations section says "either fail-on-duplicate or first-wins is acceptable" but there is no AC pinning the chosen behaviour. A reviewer cannot test which path was taken. Either add an AC ("duplicate outline keys resolve to first occurrence and produce no additional notice" OR "duplicate outline keys produce an FC14 notice") or explicitly mark the behaviour as unspecified-and-not-asserted in tests.

3. R7 ("validator MUST exit with code 0 on a doc that produces only FC14 notices") and the Implementation-level AC about CI staying green both depend on exit code, but no AC says "the validator process exits with code 0 when only FC14 notices are emitted." Add an explicit exit-code AC so a CI-shaped integration test can verify it.

4. R9 (notice message specificity): the requirement enumerates five message-content rules (outline key, missing field name, unresolved dep token, declared/observed counts, declared mode + wrong section name) but the matching ACs only check three of these substrings (outline key, missing field, declared vs observed). Add explicit ACs requiring the unresolved-dep-token substring and the declared-mode + wrong-section substring in their respective notice messages.

5. R1 third bullet ("Implementation Issues and Dependency Graph optional in single-pr; if present, MUST be empty"): no AC tests the "present but populated" boundary cleanly except via Sub-check E for Implementation Issues. Dependency Graph populated under single-pr has no AC at all. Add an AC: "a single-pr plan with a non-empty `## Dependency Graph` (nodes/edges present) produces an FC14 notice naming the section."

6. Sub-check D coverage of zero-count edge: no AC tests `issue_count: 0` with zero outline blocks (well-formed empty plan) vs `issue_count: 0` with one outline (mismatch at the lower boundary). Add a boundary-case AC.

7. Interaction with FC04: AC for Sub-check A says "a multi-pr plan missing `## Implementation Issues` produces the existing FC04 behaviour unchanged (FC14 does not duplicate the notice)" -- but there is no AC for the reverse direction: a single-pr plan missing `## Issue Outlines` should produce FC14 *and* not produce FC04 (or whatever the new dispatch picks). Add an AC pinning which check fires for single-pr missing-section so duplicate-notice regressions are catchable.

## Summary

The PRD is testable as written. The ACs map cleanly to table-driven test cases per sub-check, each with a named input defect and a named expected substring in the FC14 notice. The gaps are non-blocking: a few cases delegate to the format reference (malformed dependencies shape, outline heading recognition), the duplicate-key behaviour is deliberately left unspecified, and a handful of edge cases (exit-code assertion, populated Dependency Graph under single-pr, unresolved-dep substring AC) could be sharpened to make the test plan fully self-contained from the AC list alone.
