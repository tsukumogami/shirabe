# Clarity Review (final confirming): PRD-work-on-standalone-completeness

## Verdict

PASS

## The prior finding — present or gone in the current file

Gone, confirmed directly against the current file. `grep -n -i "accepted"` over
`docs/prds/PRD-work-on-standalone-completeness.md` returns only two hits, both
at lines 250-251 inside R16a's deliberate carve-out ("`Accepted` is NOT such a
status for any type: an Accepted BRIEF still feeds a PRD and an Accepted PRD
still feeds a DESIGN..."). The flagged phrase itself is gone. The Decisions
entry at line 532 now reads: "**Decided:** one decision record amending both
the settled requirement and the chosen design option, rather than editing
either in place." No occurrence of "the accepted requirement" remains anywhere
in the file.

## Terminology consistency

Consistent. `Accepted`, `Done`, `Current`, `Superseded` are used as the
capitalized, reserved lifecycle-status terms only when a status is actually
being named, and R16a's two `Accepted` uses are exactly the deliberate
exception the brief describes — explaining that `Accepted` is terminal for no
type, which is why an Accepted BRIEF/PRD stays inside "the surface" rather than
being excluded from it. Lowercase "settled" is used throughout as an ordinary
adjective/verb ("the two settled documents," "settled by the design that
precedes implementation," "settles the constraint") and never collides with a
capitalized status word. R16a's disposition value `superseded` (lowercase,
code-formatted) and R18's prose "superseded on the record" both point at the
same decision-record mechanism, distinct from the capitalized DESIGN status
`Superseded` — and the new "why neither route fits" passage makes that
distinction explicit rather than leaving it implicit.

Checked against the two format references cited by the testability seat:
- `skills/prd/references/prd-format.md:150-166`: no PRD `Superseded` state;
  the convention is a new PRD plus marking the old one `Done` with a note.
  Matches the PRD's own account verbatim.
- `skills/design/references/design-format.md:222-227`: `any -> Superseded`
  fires only when a successor DESIGN names the predecessor as
  `superseded_by:`. Matches the PRD's own account verbatim.

## Per-requirement ambiguity scan

Read all twenty-nine requirements (R1-R22 including sub-letters), all
acceptance criteria, both User Stories, Out of Scope, Decisions and
Trade-offs, and Known Limitations. No new ambiguity found.

- R18's "terminal status by R16a's own definition" is a self-referential,
  narrower sense of "terminal" than the cascade sense used in R1/R4/goals ("pull
  that chain to its terminal state"). The qualifier "by R16a's own definition"
  is doing exactly the disambiguating work needed, so this reads as precise
  rather than sloppy.
- The "why neither route fits" passage sits directly before its "Decided:"
  paragraph, is scoped to exactly the two documents R18 names, and its claims
  match both format references exactly.
- The narrower prohibition (contradicted text survives verbatim; only a
  pointer may be added) and R18's criterion at lines 390-399 are the same rule
  stated twice at different distances — Decisions gives the reasoning, the
  criterion gives the falsifiable test ("A diff of each against its pre-change
  state shows its routing claim preserved verbatim... The only modification
  permitted to either is the addition of a pointer to the decision record").
  They do not drift from each other on scope, wording, or the two documents
  covered.
- No use of `tier`, `journey`, or `underscore` appears anywhere in the file,
  so the repo's terms-of-art carve-out in CLAUDE.md has nothing to fire on
  (and nothing was incorrectly flagged).
- No AI-writing-pattern words from the repo's quick-reference list
  ("leverage," "robust," "comprehensive," "holistic," "facilitate," "tiered")
  appear in the file.

## Required changes

None.

## Observations

The Decisions entry's new subsection reads as a clean two-beat argument: first
why each type's own supersession route is unavailable (PRD has no Superseded
state at all; DESIGN's Superseded requires a successor DESIGN that doesn't
exist), then why that leaves a decision record plus pointer as the only
option that doesn't assert something false ("Marking either document wholly
superseded would assert something false."). That's a stronger and more
specific justification than the prior draft had room for, and it closes the
gap the testability seat found without reopening the terminology problem this
reviewer flagged last round.
