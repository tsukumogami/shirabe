# Structural Format Review

**Verdict:** PASS

Every validated rule passes — frontmatter fields, status value, the FC03 bare-word contract, section presence and canonical order, public-visibility cleanliness, banned-word screening, and altitude boundaries — with two soft format deviations and a handful of prose-level suggestions that do not block acceptance.

## Issues Found

1. **`problem` and `outcome` frontmatter blocks exceed the documented 2-4 line shape**: `brief-format.md` describes both fields as "a 2-4 line YAML literal block scalar". The `problem` block runs seven lines (frontmatter lines 5-10) and `outcome` runs six (lines 11-16). The validator does not check block length, and nothing downstream misparses, so this does not move the verdict off PASS. Suggested fix: compress `problem` to the two-defect core (opaque `F<n>` key plus unbounded description slice, and the three-document contradiction) and drop the trailing "which three documents describe two different ways" clause into the Problem Statement prose where it already lives; compress `outcome` similarly by folding the documentation-agreement sentence into a single clause.

2. **One Scope Boundary IN item edges toward PLAN altitude**: "Regression coverage for both defects in the existing test style" (line 137). Naming test coverage as in-bounds is legitimate brief-altitude scoping; "in the existing test style" is an implementation instruction that belongs to the downstream PLAN. Suggested fix: trim to "Regression coverage for both defects." Non-blocking — one qualifying phrase, not a drifted section.

## Suggested Improvements

1. **Reduce em-dash density**: 14 em dashes across 179 lines, roughly 10 of them in body prose (lines 42, 51, 67-68, 80-81, 112, 119-120, 150), including two paired-parenthetical uses inside a single paragraph. The writing-style skill lists em-dash overuse as a formatting tell. The four in the References list are conventional list-item separators and should stay. Rationale: paragraph three of the Problem Statement and the second User Outcome paragraph would both read cleaner with a comma or a period in place of the dash.

2. **Introduce contractions**: the document contains zero. Grep for `don't|it's|doesn't|isn't|can't|that's|they're` returns nothing across all 179 lines, while the prose repeatedly uses "does not", "do not", "is not", "was not". The workspace writing guidance says to use contractions, and the writing-style skill lists their total absence as a tell. Rationale: a few well-placed contractions ("the two documents don't agree", "it's tolerable when the description names the feature") would break the uniform formality without loosening the register.

3. **Fix the mixed-locale spelling**: frontmatter line 9 has British "behaviour" while the body consistently uses American forms ("summarize", "summarized", "summaries"). Rationale: one-word fix; internal consistency in a document three other documents will be reconciled against.

4. **Vary sentence rhythm in the Problem Statement**: paragraph one runs five sentences of broadly similar length and clause structure. Rationale: the writing-style skill's burstiness target is a short sentence adjacent to a long one. The strongest short sentence in the document — "The two defects compound." — shows the effect and could be echoed once earlier.

## Summary

The BRIEF is structurally clean: `shirabe validate docs/briefs/BRIEF-roadmap-issueless-table-rendering.md --visibility=public` exits 0 with no diagnostics, and a control probe confirmed the validator does report on `BRIEF-`-prefixed inputs rather than silently skipping, so the clean run is a genuine pass rather than a no-op. All five required sections appear in canonical order (Status, Problem Statement, User Outcome, User Journeys, Scope Boundary) followed by the two optional sections in listed order (Open Questions, References); Open Questions is correctly present given `status: Draft`, and every one of the four References paths resolves to a real file in this repo. Public-visibility cleanliness holds — no `private/` paths, no private-repo issue numbers, no `wip/` references, no emojis, and no banned words, with the only hit on the ban list being "Journey" inside the mandated `## User Journeys` heading. The remaining notes are two soft format deviations (over-long frontmatter block scalars, one implementation-flavored qualifier in the Scope Boundary IN list) and four prose-level suggestions, none of which block acceptance.
