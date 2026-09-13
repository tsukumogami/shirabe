# Testability Review (final): PRD-work-on-standalone-completeness

## Verdict

FAIL

## The converse criterion — closed, or too strong

The new criterion (lines 387–394) reads:

> "**Neither document R18 names is modified by this change at all.** A diff
> of each against its pre-change state shows no edit to its routing claims.
> This is the converse of the criterion above and is what makes the
> disposition non-self-serving..."

The bold sentence claims an absolute: no modification of any kind. The verification
sentence that follows narrows this to "no edit to its **routing claims**" — a
defined term (line 255–258) that excludes things like a frontmatter status
field, a `superseded_by` link, or a stray typo fix. These are not the same test.
A diff that adds a `superseded_by:` pointer or flips a status field satisfies
"no edit to its routing claims" while failing "modified... at all" outright.
The bullet doesn't say which of the two governs, so two reviewers grading the
same diff would split exactly the way R16a's own boundary text (line 264) warns
against for eval files — except here the PRD author didn't see the seam.

That seam is not hypothetical. `skills/prd/references/prd-format.md` states the
repository's actual, only documented mechanism for superseding a PRD's
requirement:

> "**No "Superseded" state.** If requirements change fundamentally, create a
> new PRD and mark the old one as Done (with a note that it was replaced)."

The established convention is to edit the superseded artifact — flip its status,
add a note. `skills/design/references/lifecycle.md` says the same for DESIGN
via `shirabe transition <path> Superseded --superseded-by <superseding-doc>`,
which "handles status update, file movement (`git mv`), and supersession
links" — again, an edit to the document plus a move.

The PRD under review is aware it's departing from that norm — the Decisions
and Trade-offs section explicitly chooses "one decision record amending both...
rather than editing either in place" and defends it against the in-place
alternative. That's a legitimate call for the author to make. But the
acceptance criteria don't cleanly land it. The very next R18 bullet up
(line 398–400) reads:

> "The superseded requirement and the superseded design option each **carry a
> record** of what superseded them, and the validator reports no lifecycle or
> upstream-link violation (R18)."

"Each carry a record" is naturally read as the requirement and the design
option themselves possessing or referencing that record — which is exactly
the in-place note/link the format references describe, and exactly what the
next bullet then forbids ("modified... at all"). If "carry" instead means
"the decision record carries an entry naming them" (external, no edit), the
bullet needed to say that; as written it contradicts its neighbor. This is
not a hypothetical edge case the reviewer is inventing — it is two adjacent
checkboxes in the same Acceptance Criteria list making incompatible demands
on the same two documents, one of them echoing the repository's own
documented supersession convention that the other bullet overrides without
saying so.

So: the hole from round 5 (a `superseded` row satisfied by nothing changing
about the label) is closed as far as it goes, but the fix introduces a new
one — it isn't reconciled with the criterion immediately preceding it, and it
overrides a documented repository convention (edit + note/link) without the
PRD saying anywhere that this feature is deliberately not following that
convention for these two documents specifically. A reviewer or implementer
has no way to know, from the Acceptance Criteria section alone, whether
adding a `superseded_by`-style pointer to the DESIGN or a "replaced by" note
to the PRD is required (per format convention and the "carry a record"
bullet) or forbidden (per the converse bullet).

## Per-criterion falsifiability table

| Criterion (abbreviated) | Falsifiable? | Note |
|---|---|---|
| No-anchor run has no cascade output (R2/R3) | Yes | |
| Chain pulled to terminal state before PR mergeable (R1) | Yes | |
| No-upstream-chain case unchanged, existing test passes (R4) | Yes | |
| Cascade location recorded, no cross-skill path reference (R5a) | Yes | grep-verifiable |
| Both failure shapes handled identically to plan entry point (R5) | Yes | |
| Classification table committed, every obligation classified (R6/R7/R8) | Yes | |
| Each classification correct (gate exists and fails; field required) (R8) | Yes | |
| Gated obligation blocks advance when driven to failure (R6) | Yes | |
| Evidence field typed to concrete referent, placeholder fails (R7/R7a) | Yes | |
| No obligation only in SKILL.md (R10) | Yes | |
| Diagram obligation within one hop + evidence, or recorded advisory (R9) | Yes | |
| Child doesn't cascade; multi-issue chain pulled once (R11/R13) | Yes | |
| Suppression signal distinct from shared-branch signal; multi-pr child suppressed (R12) | Yes | |
| Plan entry point runs multi-pr end to end, one cascade (R14) | Yes | |
| Single-issue entry point refuses multi-pr with pointer (R15) | Yes | |
| Inventory committed, all fields present (R16a) | Yes | |
| Inventory records reproducible command (R16b) | Yes | |
| `edited` rows: after-text present, before-text absent (R16a) | Yes | |
| `superseded` rows: name one of the two R18 docs, docs not edited in place (R16a/R18) | Yes | |
| **Converse: neither R18 doc modified "at all"** (R16a/R18) | **No — see above** | contradicts the "carry a record" bullet and the diff-scope sentence beneath its own bold claim; not self-consistent |
| `delegated` rows: eval-suite file, resolved under R17 (R16a/R17) | Yes | |
| Three eval scenarios pass on new routing (R17) | Yes | |
| Superseded requirement/option "carry a record"; validator clean (R18) | **Ambiguous** | "carry a record" undefined as to where the record lives; collides with converse bullet above it |
| Root session retains context on new terminal ticks (R19) | Yes | |
| Child does not retain; parent gate converges (R19) | Yes | |
| Regression test fails if retention made unconditional (R19a) | Yes | |
| Reused mechanism, not a second implementation (R19b) | Yes | grep-for-second-implementation is concrete |
| Enum/schema unchanged (R20) | Yes | |
| Three validator scripts pass (R21) | Yes | |
| Two PRs, stated order (R22) | Yes | |

## Requirement coverage map

R1–R22 (including R5a, R7a, R16a, R16b, R19a, R19b) each have at least one
mapped acceptance-criterion bullet; on this pass coverage is complete and
unchanged from prior rounds. The defect found here is not a coverage gap —
it's a self-consistency gap between two criteria both tagged to R18.

## Required changes

1. Resolve the collision between the "carry a record" bullet (line 398–400)
   and the converse bullet (line 387–394). State explicitly, in one place,
   whether the two R18 documents get any in-document trace of their
   supersession (a status note or `superseded_by`-style link, matching
   `prd-format.md`'s and `lifecycle.md`'s documented conventions) or genuinely
   none at all (all trace lives only in the decision record and the
   inventory). Pick one and make both bullets say the same thing.
2. If the answer is "no trace in the documents at all" (the converse
   bullet's literal claim), say explicitly that this feature deliberately
   departs from `prd-format.md`'s "mark the old one as Done (with a note)"
   convention and from `lifecycle.md`'s `--superseded-by` convention for
   these two documents, and why a reader landing on either original document
   directly (not via the inventory) is expected to have no signal it was
   superseded. Currently the PRD's Decisions section defends "don't rewrite
   the routing claim" but never confronts that it's also skipping the
   record-carrying step the format references call the standard mechanism.
3. Once resolved, restate the converse bullet's testable clause to match
   the decision: either "diff shows zero changes" (if truly untouched) or
   "diff shows only a status/frontmatter/backlink change, never a change to
   the routing-claim text" (if a note/link is allowed) — not both, and not
   the current bold claim paired with a narrower diff test that doesn't
   match it.

## Observations

The round-5 hole itself is closed: the `edited`/`superseded` pairing (lines
378–394) does now foreclose the "label it edited, rewrite it anyway" escape,
and the R16a/R18 boundary language elsewhere in the document is otherwise
careful and internally cross-referenced. The defect found here is narrow and
local to two adjacent bullets, not a sign of sloppier drafting throughout —
which is exactly why it's worth fixing rather than waiving: it's a five-line
change to make the two bullets agree, not a rethink of the mechanism.
