---
schema: brief/v1
status: Accepted
problem: |
  A /scope fold deletes a chain document, and the fact that it was
  absorbed rather than never written has to survive. Today that fact is
  recorded in docs/folds.md, a shared append-only file every parallel
  chain writes to, for a guarantee the surviving document already carries.
outcome: |
  Parallel /scope runs no longer contend on a shared bookkeeping file,
  adopting repositories stop inheriting a check whose mitigation they
  never received, and a reader can still tell an absorbed document from
  one that never existed by reading the document that absorbed it.
motivating_context: |
  The record landed one day before this brief and has recorded exactly one
  fold. An /explore run across six research leads found its unique
  guarantee is one fact in one fold shape, its concurrency mitigation is
  inert on the platform this repository merges on, and its CI check cannot
  fire on the case it was written for — which the one real fold confirms.
---

# BRIEF: Fold-Record Removal

## Status

Accepted

The framing stops at the boundary of what a fold must leave behind. The
downstream PRD owns the requirements — which files change, what replaces
the two prose claims that cite the record, and what the amended
requirement says.

One framing question is deferred to that PRD rather than settled here:
what a roadmap's downstream cell says when a chain folds to nothing, now
that it cannot point at the record. No roadmap carries that text today,
so the choice is unconstrained by existing content and belongs with the
requirements that decide it.

## Problem Statement

`/scope`'s consolidation judgment deletes a chain document when a
downstream artifact already carries everything it held. That deletion
creates a reader problem the judgment itself cannot solve: a document
that was absorbed and a document that was never produced look identical
on disk, and they mean opposite things. This repository squash-merges a
whole chain, so a document created and folded away inside one chain never
appears on the default branch at all.

The current answer is `docs/folds.md` — one append-only row per fold, in
one file, in every repository that runs `/scope`. Three things are wrong
with it.

**It was never argued for.** The decision to keep a durable record was
fixed at BRIEF altitude as an in-scope item and inherited unchanged by
everything downstream. The design that shipped it evaluated *which
surface* carries a record, never *whether* one is needed. All six
underlying decisions were made without author confirmation, and the pull
request that landed the mechanism carried no review. There is no
cost/benefit for the log to overturn, because none was written.

**Most of what it records is recorded twice.** A surviving document
already declares what it absorbed, in frontmatter and in a pinned status
line, with a contribution section carrying the absorbed content forward —
all three enforced at error level. That declaration accumulates across
hops, so a document at the end of a chain names every ancestor folded
into it. The record's own justification says an absorbed document
"leaves no trace otherwise," and for every fold whose survivor stays on
disk that is false. What has no other carrier is narrower: the case where
the last survivor is itself deleted after the chain finishes.

**What it costs is contention, not size.** The file is one shared write
point for every chain running in parallel. Its stated mitigation is a
`merge=union` attribute, which does not apply where this repository
actually merges — a hosted forge resolves merges without consulting a
repository's merge drivers, so concurrent folds still block the merge
button. Repositories that pin the shared validation workflow inherit the
fold check without ever receiving the attribute, because it is a
repository file rather than something the plugin distributes. And the
check that is supposed to backstop all of this cannot fire on the fold
shape the record exists for, because a two-endpoint tree comparison
cannot see a file created and deleted between those endpoints.

The corpus now contains exactly one executed fold, and it settles the
argument rather than complicating it. The surviving PRD declares the
absorbed brief in its frontmatter, names it in its status line, and
carries it in a contribution section — every fact the row holds, on disk,
where a reader is already looking. The absorbed brief was also created
and deleted inside the same squashed chain, so the check that is supposed
to verify the row observed nothing at all. The one fold this repository
has performed is a demonstration of both halves of the case.

## User Outcome

An author running `/scope` alongside other agents on the same repository
finishes a fold without writing to a shared bookkeeping file. That write
surface is gone, so no fold has to be rebased, resolved, or re-run
because a sibling chain folded first.

A reader who lands on a path that no longer exists still learns what
happened to it, from the document that absorbed it — which names the
absorbed path, says which of its own sections now carries the content,
and is present in the working tree where the reader is already looking.

A maintainer of a repository that adopts shirabe's shared validation
workflow no longer inherits an obligation their repository was never
given the means to meet.

## User Journeys

### Two chains fold in parallel

Two agents run `/scope` on the same repository at the same time, on
different topics. Each reaches a hop where the upstream document folds
into its survivor. **Trigger:** both folds complete and both branches
open pull requests. **Outcome shape:** neither branch has written to the
shared record, so both merge in either order with no rebase, no conflict
marker, and no red check on a correct record. Today the second branch
finds the merge button blocked and, once rebased, can still fail
validation for a mismatch that is an artifact of how the check resolves
paths rather than anything wrong with the fold.

### A reader holds a path that no longer exists

A contributor reading a design document follows a citation to a PRD path
and finds nothing there. **Trigger:** the grep for that path returns one
hit — the document that absorbed it. **Outcome shape:** the reader opens
that document, sees the absorbed path declared in its frontmatter and
named in its status line, and reads the section that now carries the
content. The question "was this absorbed or never written?" is answered
in the working tree without consulting history, a forge, or a central
index.

### An adopting repository runs the shared validation workflow

A maintainer of another repository pins shirabe's reusable validation
workflow and starts using `/scope`. **Trigger:** their first chain folds
a document and opens a pull request. **Outcome shape:** the workflow
checks what their repository can actually satisfy. Today it asserts the
presence and integrity of a row in a file whose concurrency mitigation
their repository never received, and no adopter-facing documentation
tells them the attribute exists.

### A future contributor notices folds leave no central trace

A contributor auditing the corpus observes that nothing lists every fold
that has happened. **Trigger:** they consider adding one. **Outcome
shape:** they find a durable record of why that was tried, what it cost,
and which alternatives were measured and rejected — so the question is
answered from the artifact rather than re-investigated. Without that
record the removal reads as an oversight and invites the mechanism back.

## Scope Boundary

**IN**

- Removing `docs/folds.md` and the append step that writes it.
- Removing the fold-record verification step from the shared validation
  workflow, and the adopter-facing documentation describing it.
- Removing the merge attribute that exists only to serve the record.
- Removing the citation-search exclusion that exists only to stop the
  record from poisoning the fold guard.
- Replacing the two prose claims that cite the record as evidence: the
  rule explaining how a caller tells a fully-folded chain from an
  unfinalized one, and the line the implementation cascade writes into a
  roadmap when a chain folds to nothing.
- Amending the four shipped documents whose requirements and decisions
  the record discharges.
- Recording why a shared fold log was removed and which alternative
  carriers were measured and rejected, so the decision survives the
  branch.

**OUT**

- **The consolidation judgment itself.** Whether `/scope` folds, when it
  folds, and what carries into the survivor are settled and untouched.
  This work changes what a fold *records*, never what it *does*.
- **The survivor-side trace.** The `absorbed:` declaration, the pinned
  status line, the contribution section, and the checks enforcing them
  stay exactly as they are. They are the carrier the removal relies on,
  not collateral.
- **Re-deciding whether a design may be absorbed into a plan.** That
  decision stays shipped. Only the supporting argument that cited the
  record needs restating, because the argument loses its premise while
  the decision does not.
- **Building a replacement carrier.** Per-fold files, commit trailers,
  git notes, forge metadata, and rotation schemes were each measured
  during exploration and are not being adopted. A reader who wants to
  know why will find it in the record this work produces.
- **Fixing the defects in the fold-record check as standalone work.**
  They are evidence that the mechanism was never load-bearing, and they
  are deleted along with the step that carries them.
- **A migration path for the one existing row.** The single fold on record is
  already carried by its surviving document, so there is nothing to move.

## References

- `docs/designs/current/DESIGN-scope-artifact-persistence.md` — the
  design that introduced the record and chose its surface.
- `docs/prds/PRD-scope-artifact-persistence.md` — carries the
  requirement the record discharges.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` —
  cites the record as the answer to the objection against absorbing a
  design into a plan.
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — the
  absorb procedure and its rollback table.
