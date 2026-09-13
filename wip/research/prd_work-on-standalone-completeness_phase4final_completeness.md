# Completeness Review (final): PRD-work-on-standalone-completeness

## Verdict
PASS

## The changed text, judged fresh

**R16a's "What 'the surface' bounds" clause**, current text (lines 238-254):

> **What "the surface" bounds.** It is the live operational corpus — skill
> prose and frontmatter, reference files, routing tables, eval suites, the
> repository `README.md`, and shared references such as the pipeline model —
> plus exactly the two accepted documents R18 names as superseded. It
> excludes durable artifacts that have finished their own lifecycle and
> assert the old routing. Each type's format reference defines that for
> itself: a BRIEF or PRD at `Done`, a DESIGN at `Current` or `Superseded`,
> and any decision record. Those are the audit trail... `Accepted` is NOT
> such a status for any type: an Accepted BRIEF still feeds a PRD and an
> Accepted PRD still feeds a DESIGN, so both remain live operational
> documents inside the surface. A DESIGN has no `Done` state at all. The one
> DESIGN R18 supersedes is `Current`, and R18 names it explicitly rather than
> reaching it through this exclusion.

I checked this against `skills/design/references/lifecycle.md`, which confirms
the DESIGN lifecycle is Proposed -> Accepted -> Planned -> Current -> (or)
Superseded, with no Done state — the clause's "A DESIGN has no `Done` state at
all" is accurate, not a rhetorical flourish. I then checked the two documents
R18 actually names: `docs/prds/PRD-execute-skill.md` is `status: Done` and
`docs/designs/current/DESIGN-execute-skill.md` is `status: Current`. Both are
exactly the per-type terminal statuses the new clause enumerates, and both are
the ones explicitly carved back into the surface ("plus exactly the two
accepted documents R18 names as superseded") rather than reached through the
general exclusion. That is internally consistent: the exclusion states a
default (terminal-status documents are audit trail, left alone), R18 states
the two exceptions to that default by name, and R16a's disposition vocabulary
(below) is what keeps the exception from contradicting R16a's own "after
text" check.

This is a strictly better formulation than the uniform "Done or Accepted"
clause I passed in round 4. That earlier clause would have wrongly excluded
an Accepted BRIEF/PRD (still live, still feeding downstream work) and would
have had no principled answer for a DESIGN, whose terminal states are
`Current`/`Superseded`, not `Done`. The per-type enumeration fixes both: it
correctly keeps Accepted documents inside the surface (rule: "Accepted is NOT
such a status for any type") and correctly names `Current`/`Superseded` as
DESIGN's terminal pair instead of reusing PRD/BRIEF's `Done`.

Re-judging round 4's specific finding against this new clause: I had found
`docs/designs/current/DESIGN-capstone-orchestration.md` (status `Current`) as
a candidate that mentions the old `/work-on` single-pr/multi-pr routing, and
judged it descriptive background rather than a contradicted decision — not a
routing claim R18 needed to name. Under the new clause that document is
*also* excluded from the surface by the general rule (a DESIGN at `Current`
that R18 does not name), reinforcing the same outcome for an independent
reason. My round-4 judgment still holds, on firmer ground than before.

**Disposition per inventory row**, added to R16a (`edited` / `superseded` /
`delegated`, each defined) with four matching Acceptance Criteria: one per
disposition, plus the converse — "Neither document R18 names is modified by
this change at all" — that closes the gap the dispositions would otherwise
open (a row could be mislabeled `edited` on an R18 document and every other
criterion would still pass). The definitions and the four ACs match up
one-to-one; R16a itself calls out why the disposition is needed ("keeps
R16a's completion check from contradicting R18: a `superseded` row is
satisfied by the decision record existing, never by the file changing").

## Per-criterion findings

1. **Sections present/ordered** — Status, Problem Statement, Goals, User
   Stories, Requirements, Acceptance Criteria, Out of Scope, then optional
   Decisions and Trade-offs and Known Limitations. Unchanged, correct.
2. **BRIEF IN/OUT coverage** — unchanged since round 4; all six IN items map
   to requirement clusters (R1-R5/R5a cascade reachability, R6-R10
   enforcement altitude, R5a machinery location, R14-R18 multi-pr migration,
   R11-R12 child signal, R10 child-reachability); all six OUT items appear
   in Out of Scope with matching framing.
3. **BRIEF's three deferred Open Questions** — all three still closed under
   Decisions and Trade-offs with alternatives and reasoning (multi-pr
   refusal-with-pointer; no-anchor pass-through; supersession-by-decision-
   record). Untouched this round.
4. **Goal-to-requirement traceability, including R5a/R7a/R16a/R16b/R19/R19a/
   R19b** — no orphans either direction. R5a and R7a trace to the
   enforcement-altitude goal (obligations enforced where a run can't skip
   them, fields typed to concrete referents); R16a/R16b trace to the
   single-entry-point goal; R19/R19a/R19b trace to the mergeable-PR-or-
   named-stop goal (a terminal tick that destroys its own record undermines
   "stops and names what it could not discharge"). Every requirement R1-R22
   is cited by at least one Acceptance Criterion bullet, including R5a, R21
   (both flagged missing in earlier rounds, both now present).
5. **Exclusion re-judged against the corrected clause** — see above. Holds,
   and is more defensible than the round-4 text.
6. **Content boundaries** — the new disposition vocabulary and exclusion
   clause stay at requirements altitude: they define a classification and a
   scope test, not an implementation. In bounds.
7. **Out of Scope honesty** — unaffected by this round's edits; still
   consistent with current requirements.

## Required changes

None.

## Observations

- R18's prose ("the two accepted documents this feature contradicts") uses
  "accepted" as an ordinary adjective (settled/adopted) right next to the
  clause's technical, capitalized `Accepted` status term. The actual
  statuses of the two documents are `Done` and `Current`, not `Accepted` —
  the capitalization convention the document uses consistently elsewhere
  (`Draft`, `Done`, `Current`, `Superseded` as proper status names vs. lower-
  case ordinary adjectives) disambiguates this on close reading, but a
  skimming reader could momentarily conflate the two. Not a defect worth
  blocking on.
- No sign of the earlier silently-failed edit in the current text: the R16a/
  R18 region reads coherently, the disposition definitions and their four
  Acceptance Criteria line up one-to-one, and the exclusion clause's claims
  about DESIGN's lifecycle check out against
  `skills/design/references/lifecycle.md`.
