# Content-Quality Verdict: BRIEF-fold-record-removal (pass 2)

Reviewed against the document as it stands at commit `764c62d` — frontmatter
`status: Accepted`, Open Questions section removed, its single remaining
question relocated into the Status prose. The document changed on disk during
this review (the acceptance commit landed mid-read); every quotation below is
from the current file, not the Draft that preceded it. This file replaces an
earlier pass-2 verdict committed at `764c62d`, which remains recoverable there.

## Verdict

PASS

## Disposition of first-pass findings

### 1. Merge-attribute contradiction — RESOLVED

The Scope IN list keeps its claim:

> - Removing the merge attribute that exists only to serve the record.

and nothing anywhere in the document now reopens it. The Open Questions section
is gone entirely (the acceptance transition removed it, as the lifecycle
requires), so the competing statement is gone with it. There is no second
sentence in the brief that treats the attribute's fate as undecided. The
contradiction is genuinely eliminated rather than papered over.

**Does dropping the question orphan anything the brief still owes a downstream
reader?** No. The residue the first pass identified — documents that cite the
attribute as providing a guarantee it does not provide — has three carriers in
the repository, and all three sit inside the boundary the IN list already draws:

- `docs/folds.md:51-58` ("`.gitattributes` gives this file `merge=union`, so two
  branches each appending…") — deleted by IN item 1.
- `.gitattributes:6-8` — deleted by IN item 3, the comment going with the
  attribute.
- `DESIGN-scope-artifact-persistence.md:329-335` ("its merge driver is the
  repository's first… union-merge resolves a concurrent duplicate row silently")
  — covered by IN item 6, "Amending the four shipped documents whose
  requirements and decisions the record discharges."

One correction to the author's stated reasoning, which does not change the
outcome: the cover is the *amendment* item, not the "replacing the two prose
claims" item. That item enumerates its two claims explicitly — the fully-folded
versus unfinalized rule, and the cascade's roadmap line — and neither is about
the merge attribute. The residue is still inside the boundary; it just enters
through a different door than the author named.

### 2. User Outcome contention claim — RESOLVED

Current first paragraph:

> An author running `/scope` alongside other agents on the same repository
> finishes a fold without writing to a shared bookkeeping file. That write
> surface is gone, so no fold has to be rebased, resolved, or re-run because a
> sibling chain folded first.

Current Journey 1 outcome shape:

> **Outcome shape:** neither branch has written to the shared record, so both
> merge in either order with no rebase, no conflict marker, and no red check on
> a correct record.

Both now scope the claim to the one file. The absolutes the first pass flagged
("without touching any file another chain is also writing," "Nothing about the
run contends," "neither branch touches a file the other wrote") are gone from
both places.

Against the frontmatter, the match is now exact rather than approximate —
frontmatter "Parallel `/scope` runs no longer contend on **a shared bookkeeping
file**" against prose "finishes a fold **without writing to a shared bookkeeping
file**." Same noun, same scope.

I checked the consequent clauses for residual overshoot, since both sentences
still end in a strong claim ("no fold has to be rebased…," "both merge in either
order"). They hold, because each is grammatically bounded by the shared surface
that precedes it ("That write surface is gone, **so**…"; "neither branch has
written to the shared record, **so**…") and because the one other shared write
surface the brief names — "the line the implementation cascade writes into a
roadmap when a chain folds to nothing" — is written by the implementation
cascade, not by a `/scope` fold. It cannot fire in the window either sentence
describes. The narrowed claims are defensible as written.

### 3. Two implementation prescriptions in the IN list — RESOLVED

Both strings are absent. The bullets now read:

> - Removing the citation-search exclusion that exists only to stop the record
>   from poisoning the fold guard.

> - Amending the four shipped documents whose requirements and decisions the
>   record discharges.

"along with its test case" and "in place, following the dated-amendment shape
this corpus already uses" do not appear anywhere in the document.

**No comparable slip remains in the IN list.** I read all seven bullets for
altitude. The closest call is "Removing `docs/folds.md` and the append step that
writes it" — but naming the step identifies *which surface* is inside the
boundary, not how to change it, and a removal brief that named only the file
would leave a downstream author guessing whether the writer stays. The last
bullet is where a slip would have been easiest, and the draft avoids it:
"Recording why a shared fold log was removed and which alternative carriers were
measured and rejected, so the decision survives the branch" commits to the
obligation without naming an artifact type, a location, or a format. That is
brief altitude done correctly.

### 4. Shortened frontmatter `problem` versus the Problem Statement body — MATCHES

Frontmatter, 4 lines:

> A /scope fold deletes a chain document, and the fact that it was absorbed
> rather than never written has to survive. Today that fact is recorded in
> docs/folds.md, a shared append-only file every parallel chain writes to, for a
> guarantee the surviving document already carries.

Every clause traces to the body. "The fact… has to survive" is the body's
opening gap ("a document that was absorbed and a document that was never
produced look identical on disk"). "A shared append-only file every parallel
chain writes to" is the third sub-argument ("The file is one shared write point
for every chain running in parallel"). "For a guarantee the surviving document
already carries" is the second ("A surviving document already declares what it
absorbed…"). Nothing in the summary is absent from the body, and — the check
that matters more — nothing in the summary contradicts it.

The compression drops the body's own carve-out ("What has no other carrier is
narrower: the case where the last survivor is itself deleted after the chain
finishes"), so the summary states flatly what the body states with an exception.
Within a 2-4 line field whose contract is "same content the Problem Statement
elaborates in prose," elaborating an exception is exactly what the body is for.
Passes; noted under Optional.

## Journey 4 ruling

**Journey 4 clears the distinctness bar. It stays.**

The structural reviewer's objection is that its outcome shape — "they find a
durable record" — describes *reading an artifact this work produces* rather than
exercising the feature from a distinct entry point. The objection is precisely
stated, and it is the right question to ask, but it resolves in the journey's
favor for three reasons.

**Reading an artifact the feature produces is exercising the feature.** The
format reference's own examples of distinct entry points include "a downstream
consumer tracing upstream" and "a review-and-accept pass" — both are read paths,
not invocations. A rule that required every journey to be a write path would
fail half the examples the contract offers. What the rule actually forbids is
the same path re-told, and consumption is not a lesser kind of path.

**It is the only journey that exercises an IN-list deliverable no other journey
touches.** The IN list commits to "Recording why a shared fold log was removed
and which alternative carriers were measured and rejected, so the decision
survives the branch," and the OUT list leans on that same artifact to discharge
its own boundary ("A reader who wants to know why will find it in the record
this work produces"). Journey 4 is the only place in the document where that
deliverable is exercised by a person. Delete the journey and the brief commits
to producing an artifact whose consumer it never describes.

**Against each of the other three, the entry point differs in user, in trigger,
and in artifact touched.** Journey 1's user is mid-run and never reads anything.
Journey 3's user is in another repository and meets the feature through CI. The
genuine risk of overlap is with journey 2, and the two come apart cleanly:
journey 2's user holds a specific dead path and wants to know what happened to
*that document*, and resolves it by reading the survivor — which this work does
not produce and explicitly leaves untouched (OUT: "The survivor-side trace").
Journey 4's user holds no path at all; they have noticed a structural absence
and are deciding whether to build something, and they resolve it by reading the
rationale record. Different question, different artifact, opposite direction —
one looks backward at a document, the other forward at a proposal.

Its distinguishing merit is that it is the only journey whose user is not served
by the removal but by the *record of* the removal, and it says out loud what
fails without it: "Without that record the removal reads as an oversight and
invites the mechanism back." That is a real failure mode for a deletion feature,
and no other journey covers it.

One honest weakness, non-blocking: the journey's outcome depends on an artifact
whose form the brief never names. That is correct at this altitude — naming it
would be the altitude slip flagged in finding 3 — but it does mean journey 4 is
the brief's least verifiable until the downstream PRD picks the form.

## Rubric findings

**1. Problem Statement states a problem, not a smuggled solution — PASS.**
Unchanged by the revision and still right. The section opens on the gap ("a
document that was absorbed and a document that was never produced look identical
on disk, and they mean opposite things"), and the three bolded sub-arguments are
diagnoses of the current arrangement — "It was never argued for," "Most of what
it records is recorded twice," "What it costs is contention, not size" — not
descriptions of what gets deleted. The closing enumeration ("a merge driver, an
append-only assertion, a cleanup carve-out, a citation-search exclusion, and
four documents of rationale") maps onto the IN list, but it is framed as the
cost surface being protected, and for a removal the cost surface and the
deletion surface are necessarily the same set. Reading it as a deletion plan
requires ignoring the sentence it sits in.

**Growth check — clean, and actively so.** The brief does not merely omit a
growth argument; it forecloses one, in a bolded sub-heading: "**What it costs is
contention, not size.**" The frontmatter `problem` block, which the revision
rewrote, carries no size claim either — the closest phrase is "a shared
append-only file every parallel chain writes to," which is a sharedness claim.
The revision introduced nothing. Verified by reading the full text, not by
searching for the word.

**2. Problem Statement stands alone — PASS.** A cold reader gets, without
opening anything: what a fold is, why the deletion is ambiguous, why history
does not rescue it (the squash-merge sentence), what the current answer is, and
three specific defects in it. "All six underlying decisions" still leans on a
decision list the reader has not seen; the sentence survives losing the number,
so this stays a polish note.

**3. User Outcome is outcome-shaped and names its user — PASS.** Three
paragraphs, three named users — an author running `/scope` in parallel, a reader
holding a dead path, a maintainer of an adopting repository — and no feature
list. `docs/folds.md` is never named in the section, which is the right
discipline for a removal brief. The second paragraph describes a preserved
rather than a changed outcome and says so honestly ("still learns"); for this
feature, that preservation is the load-bearing claim.

**4. User Outcome matches the `outcome` frontmatter — PASS.** Three frontmatter
clauses against three prose paragraphs: contention → paragraph 1, adopters →
paragraph 3, reader → paragraph 2. Order differs, which the contract does not
constrain. Precision now matches too; see disposition 2.

**5. Each journey names a concrete user, a trigger, and an outcome shape —
PASS.** All four carry all three, and all four are concrete rather than generic
("the grep for that path returns one hit," "no red check on a correct record,"
"their first chain folds a document and opens a pull request").

**6. Journeys are distinct — PASS.** Four entry points: parallel execution, a
consumer tracing a dead path, a downstream adopter meeting the feature through
CI, and future re-litigation. See the journey 4 ruling above for the contested
one.

**7. Scope Boundary IN and OUT are real — PASS.** The IN list bounds seven
surfaces with enough specificity that a PRD author knows where to stop. The OUT
list is the document's strongest section: every one of the six is something a
downstream author could plausibly have taken as inside — the consolidation
judgment (the likeliest over-reach), the survivor-side trace (an implementer
deleting fold bookkeeping could absolutely take `absorbed:` with it),
re-deciding the design-into-plan absorption, building a replacement carrier,
fixing the check's defects as standalone work, and a migration path. None is
filler. "A migration path for existing rows. The record has never held one" is
one line, but a one-line answer to a question every downstream author will ask
is efficiency, not emptiness.

**8. Open Questions genuinely defer framing details — PASS (section removed).**
The section is gone, as `Draft -> Accepted` requires. Its one remaining question
was relocated into the Status prose, where the format explicitly allows
transition context and downstream ownership to live: "One framing question is
deferred to that PRD rather than settled here: what a roadmap's downstream cell
says when a chain folds to nothing… No roadmap carries that text today, so the
choice is unconstrained by existing content." That is a deferred framing detail,
not a blocker, and it stays compatible with the IN list, which commits to
replacing the line without deciding its content.

**9. No drift into requirements, architecture, or implementation — PASS.** With
both prescriptions removed, the document carries no acceptance criteria, no user
stories, no interface shapes, and no file-by-file breakdown. The Problem
Statement's mechanism detail ("a two-endpoint tree comparison cannot see a file
created and deleted between those endpoints") is evidence for why the current
check cannot work, not a design for what replaces it — it explains the gap,
which is the section's job.

## Required changes

None.

## Optional improvements

- **"All six underlying decisions."** Six of what is never established for a
  cold reader. "The underlying decisions were made without author confirmation"
  loses nothing and stops the reader reaching for a list that is not there.

- **"A hosted forge resolves merges without consulting a repository's merge
  drivers."** The exploration verified this on one forge, with one precedent.
  "The forge this repository merges on" would be exactly as strong and exactly
  as short.

- **Frontmatter `problem`, last clause.** "For a guarantee the surviving
  document already carries" states flatly what the body qualifies ("What has no
  other carrier is narrower: the case where the last survivor is itself
  deleted"). Within a 4-line summary this is acceptable compression, but the
  carve-out is the one place a skeptical reader will push, and "in all but one
  shape" costs five words.

- **"That write surface is gone"** (User Outcome, paragraph 1). The section's
  discipline is that it never names what got removed; this clause comes closest
  to breaking it. "No shared file is written, so no fold has to be rebased…"
  keeps the causal link without gesturing at the deletion.

- **Trigger placement in journeys 1 and 2.** Both label a mid-path event as the
  **Trigger:**. Journey 2's actual trigger is following a citation and finding
  nothing; the labeled trigger is the grep that follows. All three required
  elements are present, so this is craft, not compliance.

- **"Four documents of rationale"** in the Problem Statement's closing line
  reads as though it names the four References entries, but one of those
  (`phase-2-chain-orchestration.md`) is a procedure reference rather than a
  rationale document. Two different fours in one document invite a misread.
