# Round-2 Jury Disposition

**Verdict:** PASS

Note on provenance: the round-2 re-review was dispatched to an independent agent
and that agent terminated on a session usage limit before writing a verdict. The
disposition below was done by the orchestrator against the three round-1 review
files, which are the authority for what had to close. It is not an independent
third opinion, and the honest reading is that round 2 is a self-check rather than
a jury pass.

## Completeness findings

| # | Finding | Disposition | Closed by |
|---|---------|-------------|-----------|
| 1 | Ceiling never given a value | CLOSED | R12 (200, Unicode scalar values), cited by AC12 |
| 2 | R1 key text defined by the diagram helper, contradicting the verbatim rule | CLOSED | R1 names the transform and rules the diagram's out; R23 scoped to post-stripping text |
| 3 | Ceiling's applicability to issue-creating mode undecided | CLOSED | R15, R24, AC16 |
| 4 | Comma-label requirement contradicts the clean-validate requirement | CLOSED | R2's fallback makes the cell valid; R22 holds unconditionally; D3 records why |
| 5 | Annotation-stripping and verbatim-round-trip had no criterion | CLOSED | AC11, AC21 |
| 6 | Duplicate labels unaddressed | CLOSED | R2's uniqueness clause, AC4 |
| 7 | Done-row strikethrough not carried into a requirement | CLOSED | R4, R5, AC2, AC8 |
| 8 | Diagram node ids only asserted in prose | CLOSED | R19, AC19 |
| 9 | Already-populated roadmaps unaddressed | CLOSED | Out of Scope entry |
| 10 | Truncation marker and counting unit unspecified | CLOSED | R12, R13 |

## Clarity findings

1-2 (ceiling, unit, marker, no-boundary case): CLOSED by R12 and R13.
3 (diagnostic trigger mismatch): CLOSED — R2's predicate is a property of the
label alone, not of whether something depends on it, and AC3 through AC6 test it
that way.
4 (partial dependency resolution): CLOSED — R7 states the drop explicitly, AC10
tests it, Known Limitations records that no diagnostic fires and why.
5 (cross-repo form never shown): CLOSED — R6 gives the token form, the worked
example shows it rendered.
6-7 (strikethrough, two competing key definitions): CLOSED by R1, R4, R5.
8 (`n` basis, whitespace-only labels): CLOSED by R2.
9 (diagnostic content untested): CLOSED — R16 requires a literal substring, AC17
asserts it.
10 (help text "describes"): CLOSED — R20 lists the facts, AC23 is a substring
test.
11 (process requirement among functional ones): CLOSED — removed; D4 carries the
obligation.
12 (moving baseline): CLOSED — R22 names FC05, FC06, FC07, FC08.
13 ("assessed" is an activity): CLOSED — R24 states the outcome.
14 (verbatim round-trip unscoped and untested): CLOSED — R23, AC21.
15 ("regression tests cover"): CLOSED — replaced by the per-criterion mapping.
16-17 (subjective goals): CLOSED by reference to R12 and R16.

## Testability findings

1-3 (ceiling, comma trigger, comma fixture's expected output): CLOSED as above.
4-7 (help text, cross-document sameness, self-referential coverage criterion, PR
body criterion): CLOSED — AC23 is mechanical, AC24 is labelled a review item,
the coverage criterion is gone, the PR obligation moved to D4.
8-9 (delivered-row ambiguity, issue-creating ceiling): CLOSED by AC1/AC2 and
R15/R24/AC16.

Missing-coverage list: pipe-in-label CLOSED (R2, AC6) with pipe-in-body recorded
as a limitation; duplicate labels CLOSED (AC4); delivered rows CLOSED (AC2, AC8);
annotation stripping CLOSED (AC11); mixed cells CLOSED (R9, AC9); truncation
boundaries CLOSED (AC13); notice-level validation CLOSED (R22, AC20); empty body
CLOSED (R14, AC15); dry-run and ordering CLOSED (R18). A zero-feature roadmap is
already rejected before rendering and is covered by the existing
`empty_features_section_fails_cleanly` test.

## Corrections made during this pass

1. **The worked example's table was wrong.** Feature 2's body as originally
   written came to 144 characters, under the 200 ceiling, so the example showed
   a truncation that the stated requirements would not produce. The example's
   body was extended to 265 characters and the rendered cell recomputed to the
   199 characters R13 actually yields.
2. **`## Worked Example` was a top-level section the PRD format does not list.**
   It is now `### Worked example` under Requirements, so the document's
   top-level section list stays exactly the required set plus the listed
   optional ones.

## New problems

None found. Requirements R1-R25 each have at least one criterion (AC1-AC24), and
every criterion cites the requirement it exercises.
