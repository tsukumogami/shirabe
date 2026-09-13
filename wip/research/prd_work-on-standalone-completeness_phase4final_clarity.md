# Clarity Review (final): PRD-work-on-standalone-completeness

## Verdict
FAIL

## The converse criterion

The new bullet reads:

> **Neither document R18 names is modified by this change at all.** A diff
> of each against its pre-change state shows no edit to its routing claims.
> This is the converse of the criterion above and is what makes the
> disposition non-self-serving: without it, a row naming one of those two
> documents could be labelled `edited`, the document rewritten in place, and
> every other criterion still pass — including R18's own, which checks that
> a supersession record exists and not that the superseded text is
> untouched (R16a, R18).

Against the bullet immediately above it —

> Every inventory row with disposition `superseded` names one of the two
> documents R18 covers, and those documents are NOT edited in place — their
> correction is the decision record. A row marked `superseded` that names
> any other document, or a superseded document whose text was rewritten,
> fails this criterion (R16a, R18).

— the two say the same thing, and the "converse" framing is accurate: the
first bullet forbids the *row* from lying about what happened to the
document; the new bullet forbids the *document* from having changed at all,
closing exactly the loophole the testability seat found (label it `edited`,
rewrite the file, and nothing above would have caught it). No daylight
between "NOT edited in place" and "not modified... at all" as applied to
each other. That part of the round's fix is sound.

The bullet does, however, contain its own internal wobble: the bold lead
claims an absolute — "modified by this change **at all**" — while the very
next sentence operationalizes it narrowly: "shows no edit to **its routing
claims**." A literal reading of the bold sentence would fail the criterion
over an unrelated typo fix elsewhere in the same file; the verification
sentence would not. The rationale that follows ("the document rewritten in
place") also only ever discusses the routing claim, not the document as a
whole. This is a minor, self-contained looseness — likely intended as "at
all" for emphasis rather than as a literal broader scope — and would not by
itself be fail-worthy.

## Per-requirement ambiguity scan

The scan surfaced one requirement-breaking contradiction, introduced by the
new bullet's stronger absolute phrasing, against a pre-existing, unchanged
R18 acceptance criterion later in the same list:

> The superseded requirement and the superseded design option each **carry
> a record** of what superseded them, and the validator reports no
> lifecycle or upstream-link violation (R18).

"Carry" is grammatically predicated on the requirement and the design
option themselves — the two spans of prose living *inside* the PRD and the
DESIGN — not on the decision record. Read naturally, "the design option
carries a record" means the record is present in the design option's own
document, the same way R19a's "the change SHALL carry a regression test"
means the change (the PR) includes the test. There is no addressable
artifact for "a requirement" or "a design option" other than the document
they live in, and neither the design-doc nor decision-record conventions in
this workspace give a bare requirement or a chosen option any way to "carry"
something except by the surrounding document being edited (a status line, a
`superseded_by`-style field, an inline note). "The validator reports no
lifecycle or upstream-link violation" reinforces this: a lifecycle/upstream
validator only has something to check if a lifecycle field or link exists on
the document being validated — untouched Accepted/Current documents with no
new field give it nothing to check, making the clause otherwise vacuous.

That reading collides directly with the new converse criterion four lines
above it, which requires that "neither document R18 names is modified by
this change at all." One criterion requires the two documents to gain
something (a record they carry); the other forbids them from gaining
anything. Contrast this with how the PRD phrases the same idea correctly
elsewhere, in R16a's own disposition definition: "`superseded` when the
document carrying [the claim] is corrected **by** a decision record... rather
than rewritten" — there, the record is external and corrects the document
from outside, and the document is explicitly not rewritten. The R18
acceptance criterion at line 398 drops that framing and instead makes the
requirement/option the grammatical holder of the record, reintroducing the
exact ambiguity the round's fix was supposed to close everywhere in this
cluster.

No other requirement in the document produced a comparable contradiction.
R1–R17, R19–R22 read consistently with their acceptance criteria and with
each other; the Decisions and Trade-offs section's "one decision record
amending both... rather than editing either in place" is unambiguous and
consistent with R18 and with the new converse criterion — it is only the
older "carry a record" acceptance-criteria bullet that fails to reflect that
same commitment.

## Required changes

Reword the R18 acceptance criterion at (current) lines 398–400 so it cannot
be read as requiring an edit to the two named documents. For example,
replace "each carry a record of what superseded them" with language that
puts the record on the decision record document, e.g. "each is named by a
decision record documenting what superseded them, and neither document
itself gains any field or note recording this," and clarify what the
"validator reports no lifecycle or upstream-link violation" check is
actually run against (the decision record's own frontmatter/links, given the
two superseded documents are not being touched) so the clause is not
vacuous.

Secondary, non-blocking: tighten the new converse criterion's bold sentence
to match its own verification method — either scope the claim to routing
claims ("is not modified in its routing claims by this change at all") or
scope the verification to the whole file, so the SHALL-equivalent claim and
its test are the same size.

## Observations

This is a case of a targeted fix (the converse criterion) correctly closing
the gap it was aimed at, while an older, untouched sentence three bullets
down turns out to encode the opposite assumption. Nobody edited line 398
this round, so it read as settled; it only becomes a problem once "not
modified at all" is stated in absolute terms right next to it. Worth a
final grep-and-reread of every acceptance criterion sharing a requirement
tag whenever one of them is strengthened, rather than reviewing the new
bullet in isolation.
