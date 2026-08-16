---
schema: brief/v1
status: Done
problem: |
  `/scope`'s consolidation judgment decides absorbability by comparing type
  schemas, so above BRIEF-to-PRD its verdict is fixed before either document
  is read. Every completed run leaves the same artifact set regardless of what
  the work turned out to be.
outcome: |
  The artifact set a run leaves behind matches what the run actually produced.
  A contested change keeps every altitude it earned; a self-contained fix folds
  down to its code, and the author does not have to reach outside `/scope` to
  get either.
motivating_context: |
  Filed as shirabe#280 after a `/scope` then `/execute` run on #270 left a
  permanent PRD and DESIGN for a two-defect fix, and the author deleted them by
  hand in a follow-up commit that moved 730 lines of document into 56 lines of
  code comments.
---

# BRIEF: Scope Artifact Persistence

## Status

Done

The framing here is settled; the requirements are the downstream PRD's to
articulate. Five decisions that would otherwise be open were settled during
exploration and are carried into the chain as inputs rather than questions.

## Problem Statement

`/scope` walks BRIEF, PRD, DESIGN and PLAN, then decides per hop whether each
document folds into the next. The decision has three stages: whether absorption
is possible, whether it is warranted, and then the move plus its verification.
The second stage is the one that reads the documents, and it is the only one
that can answer differently on different runs.

It never gets to speak. The first stage asks whether the downstream *type's*
required sections have a home for every required section of the upstream
*type* — a comparison between two schemas, with the same answer every time,
reached without opening either document. Against the current formats it is true
for BRIEF-to-PRD and false everywhere else, permanently. So above the first hop
the verdict is `keep` whether the DESIGN in question carries four hundred lines
of contested architecture or restates a decision the PLAN already encodes.

The result is that a run's outcome is fixed rather than decided. Every
completed `/scope` run leaves a permanent PRD and a permanent DESIGN, which is
correct for work that earned them and ceremony for work that didn't. An author
who wants a smaller set has to leave `/scope` and invoke a child skill directly,
which means the judgment isn't encapsulated in the workflow that owns it — it's
made by the author, in advance, from outside, at the moment they have least
information about what the work will turn out to be.

Two things follow that make this worse than a missing feature. The absorb
procedure below the verdict has never once executed in this repository, so
every code path it would take is untested, and four defects are already visible
in it by reading. And because the only reachable outcome is the largest one,
the corpus grows monotonically: documents accumulate because nothing ever asks
whether they should, not because each was judged worth keeping.

## User Outcome

An author running `/scope` gets an artifact set that reflects the work. When a
change turns out to be contested — several live architectural options, a
requirements surface worth citing later — the chain leaves the BRIEF, the PRD
and the DESIGN behind, because at each hop the upstream did work the downstream
does not repeat. When it turns out to be a self-contained fix whose design
value was deciding what order to do things in, that value ends up in the PLAN,
the PLAN dies at implementation, and what remains is the code and its commits.

The author does not choose between those outcomes, and does not have to know
which one they are heading for when they start. They run one command, the
chain runs whole, and each hop's verdict is decided against the two documents
in front of it. A reader who lands on a surviving document later can tell
whether it absorbed something and what happened to what it absorbed. A document
elsewhere that cites an artifact the chain is about to remove keeps resolving,
because the removal is refused rather than performed.

## User Journeys

### An author scopes a self-contained fix and the chain folds to nothing durable

A maintainer runs `/scope` on a bug report describing two defects in a gate
script. The chain writes a BRIEF, a PRD, a DESIGN and a PLAN. At each hop the
judgment reads both bodies and finds the upstream carries nothing the
downstream lacks a home for: the BRIEF's framing is already the PRD's problem
statement, the PRD's requirements are two sentences the DESIGN restates, and
the DESIGN's whole contribution was deciding which of the two defects to fix
first — which is what the PLAN's sequence now says. Each hop folds. `/execute`
implements the PLAN and the cascade deletes it. What survives is the fix, its
tests, and comments in the changed files explaining why the code is shaped that
way. No document in `docs/` describes work that took an afternoon.

### An author scopes a contested change and every altitude survives

An author runs `/scope` on a change with three live architectural options and a
requirements surface later documents will cite by number. The chain writes the
same four artifacts. At PRD-to-DESIGN the judgment finds the PRD holds
acceptance criteria the DESIGN has no home for and does not restate, so the hop
returns `keep`. At DESIGN-to-PLAN it finds the DESIGN records why two of three
options were rejected, which the PLAN's sequence does not carry, so that hop
returns `keep` too. The run ends with a BRIEF, a PRD, a DESIGN and a PLAN, and
the author never saw a prompt about it.

### A reader lands on a survivor and can tell what happened to what it replaced

Months later a contributor opens a PRD that opens with a Why section reading
unlike the rest of the document. The `## Status` section tells them a BRIEF was
folded into it and which section now carries that framing. A second contributor,
chasing a path from an old issue that no longer resolves, greps the dead slug
and finds it named in the surviving document rather than only in the rotted
citation — so the trail continues instead of ending.

### A maintainer's absorb is refused because something else still cites the artifact

A maintainer's chain reaches a hop where the judgment says `absorb` and the
content genuinely carries. Before anything is deleted, the procedure asks what
else in the repository mentions the document it's about to remove, and finds a
skill file citing it by path. The verdict is downgraded to `keep`, both
documents stay, and the run tells the maintainer which file held the citation.
Nothing is stranded, and what they see is a document that survived rather than a
reference that broke a month later in somebody else's unrelated PR.

## Scope Boundary

### In

- The absorbability judgment: moving it off type schemas and onto the two
  documents in front of it, so each hop's verdict is decided per run.
- What a surviving document owes its absorbed ancestors — one compact
  contribution section per ancestor, in chain order, ahead of its own content —
  and the adequacy expectation that contribution carries.
- The artifact format contracts, to the extent contribution sections need a
  home and the content-boundary rules need a carve-out for the absorbed case.
- The absorb procedure's known defects: the `upstream:` re-point that replaces
  rather than splices, the missing retirement guard before deletion, the
  post-absorb re-validation that checks only the survivor, and the write-target
  set that does not name the paths an upper-hop absorb writes.
- A durable record, on the default branch, of what folded into what and on what
  verdict.
- A trace on the surviving document recording what it absorbed.
- The two places `/execute` assumes a DESIGN survives, which are the only
  reason the fold decision is not already encapsulated in `/scope`.
- A standing instruction that implementation keeps code comments current about
  why the code is shaped as it is — unconditional, and independent of whatever
  the chain decided.

### Out

- **Retroactive application to documents already on disk.** The judgment runs
  against two bodies that exist, at the moment a child lands. For most DESIGNs
  in the corpus the downstream PLAN was deleted at finalization by design, so
  there is no second body and no landing event — `keep` there is the absence of
  a runnable judgment, not a verdict that the document earned its place.
  Whether a settled document is live guidance or the historical record of
  shipped work is a lifecycle question with its own criterion and its own
  disposal, and it is deferred as named follow-on work.
- **The strategic chain under `/charter`.** There is no consolidation judgment
  there to change — DESIGN Decision 9 declined to add one deliberately — and no
  shared reference carries the judgment's logic, so it lives entirely inside
  `/scope`'s own phase files. Extending it to the strategic chain would be new
  machinery rather than a follow-on edit, which is work of a different size and
  belongs in its own change. That reason holds before and after this feature
  lands; the older justification, that the strategic chain has no absorbable
  hops, rested on the type-level mapping test this feature removes.
- **Manual invocation of child skills outside `/scope`.** It is the only route
  to a chain with a genuinely missing ancestor, and it is deferred.
- **A repository-wide citation index, and a validator rule for unresolvable
  citations generally.** Both are repair campaigns against references that are
  already broken, not guards on the operation this feature adds.
- **Any judgment that runs before the artifact it is about exists.** Including
  an author-chosen entry altitude. This is the constraint the whole mechanism
  is built to respect, and nothing here relaxes it.

## References

- `docs/briefs/BRIEF-scope-consolidation-over-skipping.md` — the framing that
  introduced the consolidation judgment, and the fence around re-scoping the
  artifact types that this feature takes down.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — Decision
  8 weighed absorbing a DESIGN into the PLAN and rejected it; this feature
  reverses that on the ground that the record of why belongs in the code.
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — the
  consolidation judgment's three stages and the mapping table this feature
  replaces.
- `skills/scope/references/phases/phase-1-discovery.md` — the Durable-Artifact
  Floor section, whose condition this feature makes reachable.

## Amendment — 2026-08-16

`BRIEF-fold-record-removal.md` removes `docs/folds.md`. The original text above is left unedited; this section records what no longer holds.

**"A durable record, on the default branch, of what folded into what and on what
verdict" is withdrawn from the in-scope list.** It was the framing decision this
brief made, and it was never re-examined downstream: the PRD assumed it, and the
design chose only which surface would carry it. The surviving half of the pair
holds unchanged — the trace on the surviving document, which is the carrier the
removal relies on.
