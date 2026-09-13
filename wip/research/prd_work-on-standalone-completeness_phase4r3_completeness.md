# Completeness Review (round 3): PRD-work-on-standalone-completeness

## Verdict

PASS

## The changed text

**R19/R19a/R19b.** R19 is now scoped to root sessions only, with an explicit
prohibition on children ("no child session SHALL ever request that
retention"), and states the failure mechanism as grounding for why the
discipline must be runtime, not textual: the koto template is shared between
root and child, so an unconditional template edit would hand the flag to
every child. This mirrors the document's existing style of embedding causal
justification inside requirement text (R2's cascade-script argument-shape
argument, R12's single-pr-vs-multi-pr routing argument) rather than
introducing a new pattern, and it rules out one class of solution (a static
template edit) without prescribing the actual mechanism — comparable in
altitude to R5a's "not the plan entry point's directory" constraint. R19a
adds the regression test that pins the root-only discipline against a future
unconditional edit. R19b assigns the actual mechanism to a separately-landing
fix and explicitly punts the question of whether that mechanism also serves
R12's discriminator to the design hop. All three have matching, specific
acceptance criteria.

**R5a** now cleanly separates the settled constraint (shared machinery SHALL
NOT leave the single-issue skill depending on the plan entry point) from the
unsettled location, with "left to the design hop" stated outright and an AC
that greps for the forbidden dependency direction.

**R8** now specifies the table's row shape (obligation, class, location) as
part of the requirement text, closing the previous gap.

**R16a** now carries a boundary clause against R17: an eval-suite occurrence
is delegated to R17, not resolved under R16a, but still appears in the
inventory marked as delegated — so the two requirements can't both claim, or
both disclaim, the same line. R16b's re-run check ("every hit is either in
the inventory or is non-routing") still covers delegated rows since they
remain in the inventory.

## Per-criterion findings

1. **Section order/presence** — Status, Problem Statement, Goals, User
   Stories, Requirements, Acceptance Criteria, Out of Scope, Decisions and
   Trade-offs, Known Limitations, in that order. Complete and correctly
   ordered.

2. **BRIEF's six IN items** — all six covered: cascade reachability incl.
   no-chain case (R1-R5), prose obligations becoming gates (R6-R10), shared
   machinery location (R5a), multi-pr migration to the plan entry point with
   routing surface moved (R14-R18), a distinct child-suppression signal
   (R11-R12), obligations reachable by a child (R10).

3. **BRIEF's six OUT items** — all six present in Out of Scope, worded
   consistently with the BRIEF. The terminal-tick exclusion was reworded
   to track the new R19 ("Filed separately and landing before this work. R19
   covers only the states this feature adds.") — see criterion 7.

4. **BRIEF's three deferred Open Questions** — all three closed in
   Decisions and Trade-offs with alternatives and reasoning: multi-pr
   refusal-with-pointer, no-anchor pass-through, and supersession-by-decision-
   record. A fourth decision (shared-machinery dependency direction) is
   additional, closing R5a rather than a BRIEF-deferred question — legitimate
   extra content, not a substitute for the required three.

5. **Goal-requirement traceability** — every requirement traces to one of
   the three goal clauses (reach-mergeable-or-name-the-gap; obligations
   enforced where a child receives them; plan cadence and sole entry point).
   R19/R19a/R19b trace to the third clause: an unsuppressed retention flag on
   a multi-pr child would wedge the parent's completion gate, which would
   break the cadence-and-sole-entry-point goal that R11-R18 exist to satisfy.
   Not orphaned. No requirement found without a goal anchor; no goal clause
   found without an implementing requirement.

6. **Gap from R19b's external dependency** — checked deliberately. R19b
   commits to reusing "the root-only mechanism" a separately-filed, separately-
   landing fix establishes, and explicitly leaves the R12-sharing question to
   design. It does not say what an implementer should do if that fix is late
   or lands with a different shape. This is a real absence, but it reads as
   acceptably delegated rather than a hole: the requirement's actual
   commitment ("root-only at runtime, not textual") is a constraint derivable
   from R10's own reachability fact (shared template), not a guess about the
   other fix's internals, so R19 doesn't depend on the other fix's shape to
   be meaningful today. Cross-team sequencing risk of this kind is
   ordinarily Known-Limitations material rather than a requirements gap, and
   the PRD already uses that section for comparable sequencing costs (R22's
   two-PR order). Its absence here is a minor miss, not one that leaves an
   implementer without a testable requirement — noted below as an
   observation, not a required change.

7. **R19 content boundary** — the mechanism explanation stays at the same
   altitude as the rest of the document's requirement prose (grounding a
   constraint in an observed fact, then ruling out one class of solution)
   rather than prescribing an architecture. Judged in bounds.

8. **Out of Scope consistency with rewritten R19** — the terminal-tick
   exclusion now says "R19 covers only the states this feature adds," which
   correctly narrows the boundary now that R19 itself is root-only and
   scoped to new states. Reads correctly against the rewritten requirement.

9. **Cross-reference integrity** — every requirement number (R1-R22,
   including lettered sub-requirements) appears in Acceptance Criteria; no
   AC references a requirement that doesn't exist; no requirement is left
   without a corresponding criterion (R16 is intentionally covered only
   through R16a/R16b, as the requirement text itself says).

## Required changes

None.

## Observations

- R19b's dependency on a separately-landing fix has no stated fallback if
  that fix is late or shaped differently than assumed. Consider adding one
  sentence to Known Limitations naming this as a sequencing risk, parallel
  to the existing R22 entry — not required for this draft to pass, but cheap
  insurance for a downstream design or plan hop that starts before the other
  fix lands.
- R8's acceptance criterion checks that the classification table exists and
  every row is classified, but doesn't independently verify the three-column
  row shape R8 now specifies. Minor; the "committed with the change" phrasing
  plus R8's own text is probably enough for a reviewer to catch a
  malformed table at implementation time.
