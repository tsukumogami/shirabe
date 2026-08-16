# Content-Quality Verdict: BRIEF-fold-record-removal

Revision 2 — re-review after the author applied all three required changes from
revision 1. Revision 1's verdict was FAIL with 3 blocking items; all three are
resolved. This revision also rules explicitly on journey 4, which the structural
reviewer declined to judge and referred here, and on the shortened frontmatter
`problem` block.

## Verdict

PASS

## Rubric findings

### 1. Problem Statement states a problem, not a smuggled solution — PASS

Unchanged from revision 1 and still correct. The section opens on the gap —
"a document that was absorbed and a document that was never produced look
identical on disk, and they mean opposite things" — and its three bolded
sub-arguments frame why the current arrangement is wrong rather than what gets
deleted. No solution is stated; the closing line ("machinery ... protecting a
file that has never held a row") implies the conclusion without prescribing it.

**Growth check: still clean.** The third sub-argument is titled "**What it costs
is contention, not size**," which forecloses the growth argument the author
excluded rather than merely omitting it. The "machinery" enumeration is a
complexity cost, a distinct and independently supported claim. Nothing in the
edits reintroduced a size argument.

### 2. Problem Statement stands alone — PASS

Unchanged and still correct. A cold reader gets the fold mechanic, why deletion
is ambiguous, why squash-merge does not rescue it, what the current answer is,
and three specific defects, without opening anything in References.

### 3. User Outcome is outcome-shaped and names its user — PASS

Still three paragraphs, three named users, no feature list. The revision-2
rewording of paragraph 1 preserves the outcome shape rather than sliding into a
description of the removal:

> "An author running `/scope` alongside other agents on the same repository
> finishes a fold without writing to a shared bookkeeping file. That write
> surface is gone, so no fold has to be rebased, resolved, or re-run because a
> sibling chain folded first."

"That write surface is gone" is the closest the section comes to naming a
deletion, and it functions as the *reason* for the outcome rather than as the
outcome itself — the outcome is what the author no longer has to do. Correct
side of the line.

### 4. User Outcome matches the `outcome` frontmatter — PASS (revision-1 blocker resolved)

Resolved. Prose now reads "without writing to a shared bookkeeping file" against
the frontmatter's "no longer contend on a shared bookkeeping file" — the same
claim at the same width. Journey 1's outcome shape was narrowed in step, from
"neither branch touches a file the other wrote" to "neither branch has written to
the shared record," which roots the no-conflict claim in the removed surface
instead of asserting a general absence of shared writes the brief cannot support.
The unsupported absolute is gone from both places.

**On the shortened `problem` block (author asked me to check this pairing).** The
4-line version:

> "A `/scope` fold deletes a chain document, and the fact that it was absorbed
> rather than never written has to survive. Today that fact is recorded in
> `docs/folds.md`, a shared append-only file every parallel chain writes to, for
> a guarantee the surviving document already carries."

It still matches the body: "shared append-only file every parallel chain writes
to" carries the contention sub-argument, and "for a guarantee the surviving
document already carries" carries the recorded-twice sub-argument. The trim
dropped the adopter-obligation clause. That is acceptable — a 4-line field cannot
carry a 40-line section, the body states the adopter cost in full, and the format
treats these fields as summaries with the body as the authority. Two notes, both
non-blocking and recorded under Optional: the frontmatter now promises an adopter
outcome whose corresponding problem it no longer names, and the trailing "for"
clause attaches grammatically to "writes to," which reads as though chains write
to the file *for* the guarantee.

### 5. Each journey names a user, a trigger, and an outcome shape — PASS

All four still carry all three after the journey-1 edit; the narrowing touched
only the outcome-shape wording, not the structure.

### 6. Journeys are distinct — PASS, including journey 4 specifically

**Ruling on journey 4** ("A future contributor notices folds leave no central
trace"), referred here by the structural reviewer. It clears the bar. This is a
considered verdict on that journey, not a pass over the set.

The objection is that its outcome shape — "they find a durable record" — has the
user *reading an artifact this work produces* rather than exercising the feature.
Two things defeat that objection.

First, the format's own examples of distinct entry points include "a downstream
consumer tracing upstream" — a reading journey, where the user consumes an
artifact rather than invoking anything. Read-side journeys are explicitly
sanctioned as distinct entry points. Journey 2 is also a reading journey and
raises no concern; journey 4 is the same species.

Second, and decisively: the record journey 4 consults is **inside the feature's
scope boundary**, not incidental to it. The last IN item reads "Recording why a
shared fold log was removed and which alternative carriers were measured and
rejected, so the decision survives the branch." A journey that exercises an
explicitly in-scope deliverable is exercising the feature by definition. Had the
brief left that record out of scope, journey 4 would be promising an outcome the
feature does not deliver, and that would be a genuine failure — but the brief
scopes it in, and the OUT item on replacement carriers points at the same
deliverable ("A reader who wants to know why will find it in the record this work
produces"). The journey and the boundary agree.

Distinctness against the other three is clean. Journey 4's user intent (evaluate
a proposed change to the corpus) differs from journey 2's (resolve one dangling
reference); the trigger differs; the artifact consulted differs — the decision
record versus the absorbing chain document; and the outcome differs — a proposed
change forestalled versus one document's question answered.

Journey 4 also does work no other journey does: it is the only one that names the
failure mode of *omitting* an in-scope deliverable — "Without that record the
removal reads as an oversight and invites the mechanism back." For a removal
feature, the journey that defends against the removal being silently undone is
arguably the most load-bearing of the four. Keep it.

The set as a whole remains the draft's strongest section: concurrency, consumer
tracing, downstream adopter, future re-litigation — four genuinely different
entry points.

### 7. Scope Boundary has real IN and OUT lists — PASS

The OUT list is unchanged and remains exemplary: six items, every one a boundary a
downstream author could plausibly cross by accident, no filler. The two most
valuable are "**The consolidation judgment itself** ... This work changes what a
fold *records*, never what it *does*" and "**The survivor-side trace** ... They
are the carrier the removal relies on, not collateral" — the second guards against
an implementer deleting `absorbed:` alongside the fold bookkeeping.

The IN list is now free of the two altitude slips (see item 9) and reads as a
boundary rather than a work breakdown.

### 8. Open Questions defer framing details rather than blocking — PASS (revision-1 blocker resolved)

Resolved, and resolved the right way. The merge-attribute question is gone and the
IN bullet stands alone ("Removing the merge attribute that exists only to serve
the record"), so the brief no longer asserts and un-asserts the same decision. The
author's rationale is sound: with the record gone the attribute serves nothing, so
the choice is not genuinely open, and the prose-correction residue is already
carried by the IN item on replacing prose claims.

The single remaining question is a clean deferral:

> "What the roadmap's downstream cell says when a chain folds to nothing, now
> that it cannot point at the record. No roadmap carries that text today, so the
> choice is unconstrained by existing content."

It defers wording, not existence — the IN list commits that the line gets
replaced — and the second sentence tells the PRD author the choice is
unconstrained, which is exactly the kind of context that makes a deferred
question actionable downstream. Not a blocker that should have stopped the brief.

### 9. No drift into requirements, architecture, or implementation — PASS (revision-1 blocker resolved)

Both slips are gone. The citation-search bullet now ends at the exclusion itself
with no mention of a test case, and the amendment bullet now reads "Amending the
four shipped documents whose requirements and decisions the record discharges"
with the "in place, following the dated-amendment shape" prescription removed.
What remains in each is the boundary claim; the mechanism is left to the PRD,
which is where the format's Content Boundaries put it.

Nothing else in the document sits below brief altitude. No acceptance criteria,
no interface shapes, no file-by-file breakdown, and the Problem Statement still
names no line numbers or function names.

## Required changes

None.

## Optional improvements

Carried forward from revision 1, none addressed and none blocking:

- **Problem Statement ordering.** The three sub-arguments run
  provenance → redundancy → cost. "It was never argued for" is a claim about how
  the decision was made rather than about what a user experiences, and it is the
  weakest of the three *as a problem*. Leading with the two user-facing costs and
  closing on provenance would front-load the strongest material without changing
  any content.

- **"All six underlying decisions."** Six of what is never established for a cold
  reader. Either name the decision set briefly or drop the count — "the underlying
  decisions were made without author confirmation" loses nothing.

- **"A hosted forge resolves merges without consulting a repository's merge
  drivers."** The exploration verified this on GitHub specifically, with the
  Kubernetes precedent. Generalizing to "a hosted forge" claims slightly more than
  was measured; "the forge this repository merges on" would be exact.

- **Trigger placement in journeys 1 and 2.** Both label a mid-path event as the
  **Trigger:** — journey 2's actual trigger is following a citation and finding
  nothing, not the grep that follows it. All three required elements are present
  either way.

- **"Four documents of rationale"** in the Problem Statement's closing line reads
  as though it matches the four References entries, but one of those
  (`skills/scope/references/phases/phase-2-chain-orchestration.md`) is a procedure
  reference rather than a rationale document. If the two fours are the same set,
  they are not; if they are different sets, the coincidence invites a misread.

New in revision 2:

- **Frontmatter `problem` dropped the adopter clause.** The `outcome` field still
  promises "adopting repositories stop inheriting a check whose mitigation they
  never received," but the trimmed `problem` field no longer names that cost, so
  a reader scanning frontmatter alone meets an outcome without its problem. The
  body carries it fully, so this is cosmetic. If it can be absorbed inside the
  4-line budget, it would tighten the pairing.

- **Grammar in the trimmed `problem` block.** "a shared append-only file every
  parallel chain writes to, for a guarantee the surviving document already
  carries" attaches the "for" clause to "writes to," reading as though chains
  write to the file *for* the guarantee. The intended sense is that the file is
  maintained for a guarantee the survivor already carries. Recasting the last
  clause would fix it — e.g. "... a shared append-only file every parallel chain
  writes to, kept for a guarantee the surviving document already carries."

- **Journey 4's trigger is the weakest of the four.** "They consider adding one"
  is a mental event rather than an observable one, where the other three triggers
  are observable (branches open PRs, a grep returns a hit, a first chain folds).
  An observable form — drafting the proposal, opening the issue — would match the
  set. Does not affect the distinctness ruling above.
