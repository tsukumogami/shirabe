# Phase 4 jury — content quality

Target: `docs/briefs/BRIEF-scope-artifact-persistence.md`
Reviewer: content quality
Contract: `skills/brief/references/brief-format.md` (Quality Guidance, Common
Pitfalls) plus `skills/writing-style/SKILL.md`

PASS

This supersedes an earlier FAIL on one item in the Scope Boundary. That item has
been corrected and re-checked; all five content-quality criteria are met.

## The corrected item

The `/charter` OUT item previously justified the exclusion with "applying this
one there yields no absorbable hops" — a claim resting on the type-level mapping
test this feature removes. It now reads on grounds that survive the change: no
consolidation judgment exists there to change, DESIGN Decision 9 declined to add
one deliberately, no shared reference carries the judgment's logic so it lives
inside `/scope`'s own phase files, and extending it would be new machinery rather
than a follow-on edit. Each of those is supported by the exploration record and
none of them depends on the mapping test. Correct.

### On naming the superseded justification

Keep the last clause. I checked whether it has a real target, and it does, one
hop from this document.

`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:365-372` states
Decision 9 as: "The consolidation half does not generalize, and the mapping test
from Decision 4 says why... Zero strategic hops are absorbable, so porting the
judgment would install a rule that can only ever return `keep`." That is durable,
on `main`, and cited from this BRIEF's own References section. A downstream PRD
author who follows that link lands directly on the falsified reasoning.

So without the clause the BRIEF would state an exclusion whose neighbouring,
referenced DESIGN gives a different and now-unsound reason for the same fence,
with nothing telling the reader which one governs. The retraction is not
historiography — it is the only durable record that the older reason was
superseded, since the exploration files carrying that correction live under
`wip/` and are deleted before merge.

The usual objection to naming a dead argument — you introduce a claim only to
retract it, which is noise for a reader who never held it — does not bind here,
because the reader this OUT item is written for reaches the old claim through
this document's own reference list.

## Everything else

**Problem Statement.** States a problem, not a solution in problem's clothing.
It describes the existing three-stage judgment and why Stage 1 short-circuits
Stage 2; nothing in it describes the feature being built. Stands alone. Every
checkable claim holds against the exploration: BRIEF-to-PRD as the only
absorbable hop under the current formats, the absorb procedure never having
executed in this repository, four defects visible in the untested path. It
correctly omits the corpus-redundancy inference D4 falsified, keeping only the
"nobody ever asked" argument that survived measurement. Contractions now present
("didn't", "isn't", "it's") and the register reads natural.

**User Outcome.** Outcome-shaped, names the author, matches the `outcome`
frontmatter clause for clause — artifact set reflects the work, contested change
keeps its altitudes, self-contained fix folds to code, author does not reach
outside `/scope`. The second paragraph extends to the reader of a survivor and
the holder of a citation that keeps resolving without turning into a parts list.

**User Journeys.** Four, each with a named user, a trigger and an outcome shape.
Journey 4 now leads with the maintainer as actor and carries the consequence
through to them, including which file held the citation and what the alternative
looked like — "a reference that broke a month later in somebody else's unrelated
PR" is accurate to the finding that diff-scoped CI does not notice a stranded
document until an unrelated PR touches a victim. Journeys 1 and 2 share an
invocation surface but walk opposite branches of the judgment at every hop and
reach opposite artifact sets, which for a feature whose whole content is branch
divergence is the defining pair rather than one path retold. Journeys 3 and 4 are
plainly distinct entry points.

**Scope Boundary.** Eight IN items covering every settled decision from the
exploration, correctly saying "implementation" rather than `/execute` for the
rationale-in-code item per the D5 naming correction. Five OUT items, each a real
boundary a downstream author could cross by accident, each carrying its reason.
No filler.

**Writing style.** No banned vocabulary. No preamble, no adverb openers, no
hollow gerunds, no forced rule of three. Sentence length varies sharply. Em
dashes left in place; each is doing appositive work and the density sits within
house norm for this repo's design docs.

## Watch item, not a finding

The contribution-section IN item ("one compact contribution section per ancestor,
in chain order, ahead of its own content") is the most design-shaped clause in
the document. It stays inside the boundary because it bounds what is in scope
rather than specifying a mechanism, and the section is required to carry enough
specificity that a PRD author knows where the feature ends. Noting it as the
place to watch if the document is edited again.
