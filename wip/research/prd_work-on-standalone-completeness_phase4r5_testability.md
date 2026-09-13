# Testability Review (round 5): PRD-work-on-standalone-completeness

## Verdict

FAIL

## The disposition split — resolved or relabeled

The direct logical contradiction round 4 found is gone for any correctly-labeled
inventory. The universal "every row's file must show the after-text and lose
the before-text" check from round 4 is now scoped to rows whose disposition is
literally `edited` (the bullet reads "For every inventory row with disposition
`edited`..."), and a separate bullet requires `superseded` rows to name one of
the two R18-covered documents and to be **not** edited in place ("or a
superseded document whose text was rewritten, fails this criterion"). Those two
bullets can both be satisfied by one implementation as long as the two R18
documents are labeled `superseded` and everything else is labeled `edited`. So
the impossibility round 4 found — no implementation could satisfy both R16a's
completion check and R18 at once — is gone.

But the split is checkable in only one direction. The `superseded` bullet
verifies "rows labeled `superseded` must name one of the two R18 documents and
must not be edited," which blocks the dodge the task asked me to check for
directly: relabeling an ordinary live-corpus row as `superseded` to skip
editing it fails immediately, because that row does not name one of the two
closed-set documents. The `delegated` bullet is symmetric and closed the same
way (must name a file inside an eval suite). Good — the forward direction,
"claim a weaker disposition than you deserve," is mechanically blocked for
both alternate dispositions.

Nothing checks the reverse: that the two documents R18 covers are actually
labeled `superseded` rather than something else. The `superseded` bullet's
condition is one-directional ("a row marked `superseded` that names any other
document... fails this criterion") — it never asserts "a row naming one of the
two R18 documents that is *not* marked `superseded` fails this criterion." So
an inventory can list a routing claim inside one of the two R18-named documents
with disposition `edited`, edit that document's text in place to make the
`edited` bullet pass (after-text present, before-text gone), and — since R18's
own acceptance criterion is anchored to the two documents by name rather than
routed through the inventory's self-reported labels — *also* attach a
supersession record to satisfy "each carry a record of what superseded them."
Every literal acceptance criterion in the document would then read as
satisfied, while the actual artifact is exactly the outcome R18 and the
Decisions section spend a paragraph forbidding: the document was rewritten in
place, destroying "the trace of the reasoning" the decision record was
supposed to be the sole means of preserving. This is not a hypothetical
laziness-driven dodge (skipping the record is still caught, since R18's
"each carry a record" check does not depend on any disposition label and fails
outright if no record exists) — it is a *labeling* error: a bulk edit pass
across "the surface" that fails to carve the two R18 documents out and tags
them `edited` like everything else, which is a plausible way to get this wrong
by omission, not malice, and is the same two documents round 4 already flagged
once.

The hole has moved, not closed. Round 4's version made every implementation
impossible; round 5's version makes the two special rows' correctness depend
on an unchecked self-report rather than on a fact any reviewer could verify
independently of the inventory's own claims.

## Per-criterion falsifiability table

| Criterion (req) | Constructible check | Verdict |
|---|---|---|
| No-anchor run reaches mergeable PR, no cascade text (R2,R3) | Run on a bare issue; inspect output | Sound |
| Chain pulled to terminal before PR marked mergeable (R1) | Trace call order | Sound |
| No-upstream anchor still commits+pushes deletion, reports skipped (R4) | Existing named regression test | Sound |
| Cascade machinery location recorded; no path-reference into plan entry point dir (R5a) | grep | Sound |
| Both failure shapes handled identically to plan entry point (R5) | Diff handling/recovery guidance | Bounded but soft, not blocking (unchanged from round 4) |
| Classification table complete, one bucket each (R6,R7,R8 presence) | Enumerate table | Sound |
| Classification correct: named gate exists & fails on demand; named field exists & required (R8) | Drive each gate to failure; check schema | Sound for named-mechanism correctness (unchanged from round 4, not reopened) |
| Gated obligation blocks advance when omitted (R6) | Drive to failure | Sound |
| Evidence field typed to concrete referent; placeholder/empty fails, per field (R7,R7a) | Submit placeholder/empty per field | Sound |
| No new obligation lives only in SKILL.md (R10) | Diff obligations against koto template | Sound |
| Design-diagram obligation within one hop w/ field, or advisory (R9) | Count hops; check field/note | Sound |
| Child doesn't cascade; chain pulled once per multi-issue run (R11,R13) | Trace multi-issue run | Sound |
| Child-suppression signal distinct; multi-pr child suppressed (R12) | Run multi-pr child to CI monitoring | Sound |
| Plan entry point runs multi-pr plan, one PR/issue, cascades once (R14) | Run fixture, count | Sound |
| Multi-pr plan to single-issue entry point yields recorded disposition (R15) | Invoke, check refusal+pointer | Sound |
| Inventory names every claim's file/line/before/after/disposition (R16a) | Read inventory | Sound as a presence check |
| Inventory records candidate-generating command; re-run yields no unlisted hit (R16b) | Re-run command | Bounded, disclosed (recall-dependent, unchanged) |
| `edited`-disposition rows: file shows after-text, lacks before-text (R16a) | Read each named file | Sound, now correctly scoped |
| `superseded`-disposition rows: name one of the two R18 docs, not edited in place (R16a, R18) | Read each named row + diff document text | Sound in the forward direction only — does not verify the two R18 documents are *actually* labeled `superseded` rather than mislabeled `edited` (see above) |
| `delegated`-disposition rows: name a file inside an eval suite, resolved under R17 (R16a, R17) | Check path is under eval suite dir | Sound, closed-membership |
| All three eval scenarios assert new routing and pass (R17) | Run scenarios (anchored to three named scenarios, independent of inventory labels) | Sound |
| Superseded docs each carry a record; validator reports no violation (R18) | Run `shirabe validate`; check record exists | Sound for "a record exists," but does not check that the two documents' routing-claim text is unchanged — see the gap above |
| Root run retains context on every new terminal tick (R19) | Reach each tick as root, check record | Sound |
| Child doesn't retain; parent gate converges (R19) | Run parent to convergence over one child terminal | Sound but partial-coverage (unchanged, not blocking) |
| Regression test fails if retention made unconditional (R19a) | Invert the guard, confirm new test fails | Constructible (unchanged) |
| Root-only mechanism reused, not reinvented (R19b) | Same named helper/discriminator called; grep for a second implementation | Sound (closed in round 4, not reopened) |
| Execution-mode enum/schema unchanged (R20) | Diff | Sound |
| Three named linter scripts pass (R21) | Run scripts | Sound |
| Two PRs in stated order (R22) | Check merge order via `gh` | Sound |

## Requirement coverage map

R1->AC2, R2->AC1, R3->AC1, R4->AC3, R5a->AC4, R5->AC5, R6->AC6+AC7,
R7->AC6+AC8, R7a->AC8, R8->AC6(presence)+AC7(correctness), R9->AC10,
R10->AC9, R11->AC11, R12->AC12, R13->AC11, R14->AC13, R15->AC14,
R16a->AC15+AC16+AC(edited)+AC(superseded)+AC(delegated), R16b->AC16,
R17->AC(delegated)+AC(eval scenarios pass), R18->AC(superseded)+AC(validator),
R19->AC19+AC20, R19a->AC21, R19b->AC22, R20->AC23, R21->AC24, R22->AC25.

Every requirement, including every sub-lettered one (R5a, R7a, R16a, R16b,
R19a, R19b), still maps to at least one tagged acceptance criterion. No
orphaned requirement. The defect this round, as in round 4, is not a coverage
gap — it is that the criteria covering R16a and R18 together do not close the
loop in both directions for the two documents where the two requirements
overlap.

## Required changes

1. **Close the reverse direction of the disposition check for the two
   R18-named documents.** Add a criterion (or extend the `superseded` bullet)
   that is independent of the inventory's own self-reported disposition: for
   the two documents R18 names, verify directly — by document identity, not by
   trusting the row's disposition field — that (a) their inventory row(s) are
   labeled `superseded`, and (b) their routing-claim text is unchanged from
   its pre-change state (a diff against the pre-change document, not merely
   "a record exists"). As written, a row for either R18 document can be
   mislabeled `edited`, have its text rewritten in place, and still pass every
   literal acceptance criterion in the document, including R18's own ("each
   carry a record of what superseded them") which checks for the record's
   existence but not for the absence of an in-place edit. This is the same
   pairing round 4 flagged; the disposition field resolved the case where the
   inventory is labeled correctly but left the correctness of that labeling,
   for exactly these two documents, unchecked.

## Observations

- The `superseded` and `delegated` dispositions are otherwise well-built:
  both are pinned to an externally verifiable fact (is this one of exactly
  two named documents; is this path inside an eval suite) rather than to an
  arbitrary label, which is why the primary "relabel to dodge work" attack the
  task asked me to check for is closed for both. The one gap is specific to
  the two-document overlap with R18, not a general property of the
  three-way split.
- R17 and R18's own acceptance criteria are anchored to fixed, named artifacts
  (three specific eval scenarios; two specific documents) independent of
  inventory labeling, which is why mislabeling `delegated` or `superseded`
  rows as `edited` does not let an implementation skip the underlying
  eval-scenario or decision-record work outright — it only lets the two R18
  documents additionally be edited in place without that edit being caught,
  which is a narrower defect than the round 4 impossibility but is the same
  shape of hole.
- Round 3's closed findings (R19b's anchor, the R16 inventory-presence check,
  R8's classification correctness) were not reopened; nothing new surfaced
  against them in this pass.
