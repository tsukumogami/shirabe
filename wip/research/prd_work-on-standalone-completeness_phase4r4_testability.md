# Testability Review (round 4): PRD-work-on-standalone-completeness

## Verdict

FAIL

## Prior findings — closed or not

**1. R19b ("same mechanism" anchor).** Substantially closed. R19b now names the
referent precisely (the merged fix's PR, not issue #360 as filed), explains why
(I confirmed issue #360 is still OPEN and its own "Suggested scope" text asks
"whether the retention should apply to clean terminals too, or only
`done_blocked`" — an axis that has nothing to do with root-vs-child, and
explicitly models itself on `/scope`'s *unconditional* retention. So the
premise mismatch the round-3 review flagged is real and current, and R19b's
new text correctly refuses to treat the issue-as-filed as authoritative).
The testable definition — "the cascade states call the same named helper or
discriminator that fix introduces, and a search for a second implementation of
the same root-versus-child test returns nothing" — is a two-part mechanical
check (same call-site/symbol; grep for a duplicate conditional), which is the
same style of construction R5a and R16b already use elsewhere in this PRD, not
a restatement of the judgment. The escalation clause ("if that fix has not
landed... or its mechanism differs... that is an escalation rather than a
licence to invent a parallel one") gives a defined action for the premise-failure
case that round 3 found undefined. It does not convert into its own
independently-testable acceptance criterion — nothing verifies that escalation
actually happened — but that is a reasonable thing for a PRD to leave as a
process directive rather than a runtime check, since the branch it covers is
"the dependency isn't in the assumed shape yet," not a behavior of the shipped
feature. Closed, with a minor residual noted below.

**2. R16 (routing files actually edited).** The new acceptance criterion
("For every row in the inventory, the named file at the named location
contains that row's 'after' text and no longer contains its 'before' text...
A correct inventory committed alongside unedited files fails this criterion")
is exactly the fix round 3 asked for, and taken alone it is fully mechanical
and falsifiable. **But it creates a new contradiction with R18** that round 3
did not have in front of it (see Required Changes #1) — so this finding is not
cleanly closed. The gap round 3 named is gone; a different, more serious one
opened in its place.

**3. R8 (classification correctness).** Substantially improved, not fully
closed, and the residual is narrower than round 3's framing. The new
criterion — every gate-enforced row names a gate that exists and fails when
driven to failure; every evidence-carried row names a field the schema marks
required — verifies that the named enforcement mechanism is real, not a
label with nothing behind it. I checked whether "fails when driven to
failure" is constructible for every plausible gate, not just the two R6 names
(closing keyword, merge/rebase cleanliness): the Problem Statement lists six
candidate obligations total, and the two left unnamed by R6/R7 (PR-body
content beyond the mechanical check, commit message convention) are both
naturally gateable — a bad commit message or a PR body missing a required
section can each be produced on demand and checked against a gate. I found no
obligation among the ones this PRD actually names for which a false branch is
not constructible, so the answer to the posed question is "constructible for
every gate this document actually contemplates," not "only some." What the new
criterion still does not catch is a mechanically-observable obligation
deliberately placed in the *weaker* evidence-carried bucket instead of
gate-enforced — round 3's core example. For the two obligations R6/R7 name by
text, that specific dodge is already blocked independently (R6's own
acceptance criterion requires *some* obligation in that class to be gated and
fail on demand, so an implementation that mislabels "closing keyword" as
evidence-carried already violates R6 directly, not just R8). The exposure is
real only for obligations discovered during implementation that neither R6 nor
R7 names — a narrower residue than round 3 described, and one the document's
existing Known Limitations paragraph about classification-as-judgment already
gestures at, even though it doesn't name this specific instance. Treated as
closed-enough; flagged as an observation, not a required change.

## New finding: the R16 fix contradicts R18

R16a's surface definition says the inventory covers "the live operational
corpus... plus exactly the two accepted documents R18 names as superseded,"
and separately excludes "durable artifacts at a terminal status... that assert
the old routing," calling those "the audit trail" that "the repository
corrects... by supersession rather than by editing history. An implementer who
rewrote them would destroy the record." R18 itself, and the Decisions and
Trade-offs section, are explicit that the two documents it names (a
requirement in the plan entry point's PRD, and the chosen option in a Current
design) are **not edited in place**: "Decided: one decision record amending
both the accepted requirement and the chosen design option, rather than
editing either in place," precisely because editing in place "loses the
reasoning: a reader... would find the new option with no trace that another
was chosen first." I confirmed this is also the repository's general
convention for this kind of transition — `skills/design/references/lifecycle.md`
transitions a superseded document via `shirabe transition <path> Superseded
--superseded-by <doc>`, which flips frontmatter and files a link; "the doc
stays where it is." Nothing in that mechanism rewrites the superseded
document's body prose.

R16a already carries a named carve-out for exactly this shape of conflict —
"**Boundary against R17**," which explicitly removes eval-suite rows from
R16a's own resolution duty while keeping them in the inventory "marked as
delegated to R17." No equivalent "Boundary against R18" exists. Because it
doesn't, the two R18 rows are, by R16a's own text, ordinary inventory rows
subject to the new completion criterion added this round: "the named file...
contains that row's 'after' text and no longer contains its 'before' text."
That is the opposite of what R18 and the Decisions section require of those
same two files. As written, a correct implementation of R18 (decision record,
no edit in place) *fails* the new R16 completion criterion for those two rows,
and an implementation that edits the two documents in place to *pass* the new
criterion *violates* R18's explicit decision and destroys the audit trail the
PRD spends a full paragraph explaining it wants to preserve. A tester handed
this PRD cannot mark both criteria satisfied by any single correct
implementation — that is a genuine, not hypothetical, contradiction, and it is
new in this draft: it did not exist before the new R16 completion criterion
was added, because round 3's inventory-only criteria never touched file
content.

## Per-criterion falsifiability table

| Criterion (req) | Constructible check | Verdict |
|---|---|---|
| No-anchor run reaches mergeable PR, no cascade text (R2,R3) | Run on a bare issue; inspect output | Bounded, judgment on "cascade-related text" wording, not blocking |
| Chain pulled to terminal before PR marked mergeable (R1) | Trace call order | Sound |
| No-upstream anchor still commits+pushes deletion, reports skipped (R4) | Existing named regression test | Sound |
| Cascade machinery location recorded; no path-reference into plan entry point dir (R5a) | grep | Sound |
| Both failure shapes handled identically to plan entry point (R5) | Diff handling/recovery guidance | Bounded but soft ("identically" undefined precisely) |
| Classification table complete, one bucket each (R6,R7,R8 presence) | Enumerate table | Sound (presence) |
| Classification correct: named gate exists & fails on demand; named field exists & required (R8 correctness, new) | Drive each gate to failure; check schema for each field | Sound for named-mechanism correctness; does not catch bucket-choice dodge for obligations R6/R7 don't name (see above) |
| Gated obligation blocks advance when omitted (R6) | Drive to failure | Sound |
| Evidence field typed to concrete referent; placeholder/empty fails, per field (R7,R7a) | Submit placeholder/empty per field | Sound for the stated hole |
| No new obligation lives only in SKILL.md (R10) | Diff obligations against koto template | Sound |
| Design-diagram obligation within one hop w/ field, or advisory (R9) | Count hops; check field/note | Sound |
| Child doesn't cascade; chain pulled once per multi-issue run (R11,R13) | Trace multi-issue run | Sound |
| Child-suppression signal distinct; multi-pr child suppressed (R12) | Run multi-pr child to CI monitoring | Sound |
| Plan entry point runs multi-pr plan, one PR/issue, cascades once (R14) | Run fixture, count | Sound |
| Multi-pr plan to single-issue entry point yields recorded disposition (R15) | Invoke, check refusal+pointer | Sound |
| Inventory names every claim's file/line/before/after (R16a) | Read inventory | Sound as a presence check |
| Inventory records candidate-generating command; re-run yields no unlisted hit (R16b) | Re-run command | Bounded, disclosed (recall-dependent) |
| Every inventory row's file has "after" text and lacks "before" text (R16a, new) | Read each named file | **Not sound as written — contradicts R18 for the two R18-named rows (see above)** |
| All three eval scenarios assert new routing and pass (R17) | Run scenarios | Sound |
| Superseded docs each carry a record; validator reports no violation (R18) | Run `shirabe validate` | Sound on its own terms, but see contradiction above |
| Root run retains context on every new terminal tick (R19 bullet 1) | Reach each tick as root, check record | Sound |
| Child doesn't retain; parent gate converges, one new terminal state demonstrated (R19 bullet 2) | Run parent to convergence over one child terminal | Sound but partial-coverage (unchanged from round 3, not re-raised as blocking) |
| Regression test fails if retention made unconditional (R19a) | Invert the guard, confirm new test fails | Constructible, not fully mechanical (which conditional is "the" guard is an interpretive step) |
| Root-only mechanism reused, not reinvented (R19b) | Same named helper/discriminator called; grep for a second implementation | Now sound: concrete two-part check, plus a defined escalation branch for premise failure |
| Execution-mode enum/schema unchanged (R20) | Diff | Sound |
| Three named linter scripts pass (R21) | Run scripts | Sound |
| Two PRs in stated order (R22) | Check merge order via `gh` | Sound |

## Requirement coverage map

R1→AC2, R2→AC1, R3→AC1, R4→AC3, R5a→AC4, R5→AC5, R6→AC6+AC7, R7→AC6+AC8,
R7a→AC8, R8→AC6(presence)+AC6b(correctness, new), R9→AC10, R10→AC9, R11→AC11,
R12→AC12, R13→AC11, R14→AC13, R15→AC14, R16a→AC15+AC16b(new, in
contradiction with R18 — see above), R16b→AC16, R17→AC17, R18→AC18 (also in
tension with AC16b), R19→AC19+AC20, R19a→AC21, R19b→AC22, R20→AC23, R21→AC24,
R22→AC25.

No requirement (including every sub-lettered one: R5a, R7a, R16a, R16b, R19a,
R19b) is an orphan in the presence sense — every one maps to at least one
tagged acceptance criterion. The defect this round is not a coverage gap; it
is two covered requirements (R16a's new completion check and R18) whose
acceptance criteria cannot both be satisfied by one implementation for the two
documents that sit in the overlap.

## Required changes

1. **Add a "Boundary against R18" to R16a**, mirroring the existing "Boundary
   against R17" clause: the two accepted documents R18 names are listed in
   the inventory with their current text and a description of the supersession
   (not a literal replacement text), marked as delegated to R18, and excluded
   from R16a's own resolution duty. Then scope the new completion criterion
   (the "For every row in the inventory, the named file... contains that row's
   'after' text and no longer contains its 'before' text" bullet) to exclude
   rows so marked, and add a matching completion check for the R18 rows that
   verifies what R18 actually requires of them instead — a decision record
   exists, links back, and the original document's routing-claim text is
   unchanged (the opposite polarity of the general check).

## Observations

- R19b and R16's inventory-presence machinery are now the strongest parts of
  this document — both convert what were open judgment calls three rounds ago
  into two-part mechanical checks (name the artifact, then grep for a second
  implementation / absent edit). The new R16 completion criterion is written
  in exactly that style; it just wasn't checked against R18 before landing,
  and the two were drafted to solve different rounds' findings without being
  read against each other.
- R8's residual (bucket-choice gaming for obligations neither R6 nor R7 names)
  is real but narrow, already partially fenced by R6's own gate-driving
  criterion for the two obligations that matter most, and is a defensible
  candidate for a one-line addition to Known Limitations rather than a blocking
  requirement — not required for this verdict, worth doing while R16a is being
  touched anyway.
- Once the R16a/R18 boundary is added, I would expect this PRD to pass a fifth
  round on testability grounds alone; nothing else surfaced in the fresh
  pass that would independently fail it.
