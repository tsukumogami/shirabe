# Completeness Review

## Verdict: PASS

The PRD is well-structured: requirements R1-R15 map cleanly onto acceptance criteria sub-checks A-E and implementation-level criteria, with minor gaps that are either deliberate non-goals or easy to absorb downstream.

## Issues Found

1. **R2 "malformed dependencies declaration" lacks an acceptance criterion for shape independent of unresolved tokens**: Sub-check B's third AC ("malformed `Dependencies:` declaration produces an FC14 notice") is present, but the line between "malformed shape" (e.g., missing colon, wrong indentation, list with no items) and "unresolved token" (Sub-check C) is not made explicit. An implementer could reasonably read Sub-check B's malformed-shape AC and Sub-check C's unresolved-token AC as overlapping. Suggested fix: add one sentence to R2 or its AC clarifying that "malformed" means structurally unparseable (cannot extract a token list at all), while unresolved tokens are a Sub-check C concern.

2. **Empty-section enforcement under R1 has no dedicated acceptance criterion**: R1 says that on `execution_mode: single-pr`, if `## Implementation Issues` or `## Dependency Graph` is present, it MUST be empty -- and the same in reverse for multi-pr. Sub-check A only checks "populated wrong section produces a notice" via Sub-check E. There is no AC explicitly confirming that an *empty* `## Implementation Issues` section under single-pr (placeholder header + no table) produces no FC14 notice. Suggested fix: add one AC under Sub-check A confirming the empty-placeholder no-notice case for both modes.

3. **R12 "outline parser is total" acceptance is partly implicit**: The implementation-level AC says "the outline parser is total over arbitrary input (no panics)", but R13's "malformed outline block (parser does not panic; per-defect notices fire if applicable)" only loosely cross-references this. An implementer cannot tell from the AC list alone what test fixtures would constitute "arbitrary malformed input" (e.g., unterminated code fences, nested headings, embedded HTML, empty section). Suggested fix: add a sentence to R13 listing 2-3 concrete malformed-input shapes the parser must handle without panic (e.g., "outline header with no body content", "outline body with no recognized fields", "section truncated mid-block").

4. **No AC for the "FC14 must not duplicate FC04" behaviour**: Sub-check A says "A multi-pr plan missing `## Implementation Issues` produces the existing FC04 behaviour unchanged (FC14 does not duplicate the notice)". This is asserted only for the multi-pr direction. The single-pr direction (FC14 fires on missing `## Issue Outlines`; FC04 does not also fire for sections it does not know about) is implied but not explicitly tested. Suggested fix: add one AC confirming that FC04 does not fire for `## Issue Outlines` absence under single-pr (so the single-pr-missing-Issue-Outlines case produces exactly one FC14 notice, not an FC04 + FC14 pair).

5. **`issue_count` absent from frontmatter is not addressed**: R4 and Sub-check D specify behaviour when `issue_count` is *present and mismatched*. What if `issue_count` is absent from frontmatter entirely? The schema may or may not require it. The PRD does not say whether absent `issue_count` triggers a notice, is silently treated as zero, or falls outside FC14's remit. Suggested fix: add one sentence to R4 stating the behaviour for missing `issue_count` (most likely: out of scope, handled by an existing schema check; or, fires an FC14 notice).

## Suggested Improvements

1. **Cross-reference the format spec section anchors in R2/R3**: R2 references `skills/plan/references/quality/plan-doc-structure.md` for the "malformed dependencies declaration" definition. Linking to the specific anchor/heading in that doc (rather than the doc as a whole) would make the implementer's job mechanical -- they would not have to skim the entire format spec to find the contract FC14 enforces.

2. **State the FC14 notice-message format more precisely**: R9 lists the fields each notice must include, but does not specify the wrapper format (e.g., `[FC14] <sub-check-tag>: <specifics>`). Decision D2 hints at it (`[FC14] outline outline-3 missing goal`), but elevating that pattern to R9 would prevent inconsistent wording across the five sub-checks.

3. **Add a worked example of a well-formed single-pr Issue Outlines section**: The PRD references the format spec for the outline structural contract, but inlining a small canonical example (3-4 lines per outline block, 2 sibling outlines with one cross-dep) would make R2/R3/R4 trivially unambiguous for the implementer and the test author.

## Summary

The PRD is complete enough for an implementer to build FC14 without guessing on the core requirements. The five sub-checks map cleanly to R1-R5, the notice-severity ship and one-line promotion seam are explicit (R7-R8), and the parser totality contract is stated (R12). The minor gaps -- empty-section no-notice ACs, malformed-vs-unresolved distinction in R2/R3, absent-`issue_count` behaviour, and FC04-non-duplication for both directions -- are absorbable inline or as design-altitude clarifications, and none of them block a downstream DESIGN/PLAN from starting.
