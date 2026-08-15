# Draft sections for DESIGN-scope-artifact-persistence

Scratch. Assembled into the DESIGN once decisions 1 and 4 land.

## Context and Problem Statement

`/scope`'s consolidation judgment is the only thing in the tactical chain that
reduces the artifact set, and it runs as three stages at each hop after a child
lands. Stage 1 asks whether absorption is possible, Stage 2 whether it is
warranted, Stage 3 performs the move and verifies it.

Stage 1 is a comparison between two type schemas. It looks the hop up in a
hand-maintained table in `phase-2-chain-orchestration.md` and asks whether the
downstream *type's* required sections have a home for every required section of
the upstream *type*. Neither document is opened. Against the section lists in
`formats.rs` the answer is yes for BRIEF-to-PRD and no everywhere else, on every
run, forever — a DESIGN has no home for a PRD's Goals, User Stories,
Requirements, Acceptance Criteria or Out of Scope, and a single-pr PLAN has no
home for any of a DESIGN's reasoning sections.

The consequence is that Stage 2 — the only stage that reads the documents, and
so the only one whose answer can vary — never runs above the first hop. The
verdict is `keep`, decided before either document exists, regardless of whether
the DESIGN in question carries contested architecture or restates what the PLAN
already encodes.

Three things make this worse than a missing capability.

The procedure below the verdict has never completed a run. All PRDs with an
`upstream:` in this repository point at their same-topic BRIEF and no BRIEF has
ever been deleted. The one absorbable hop has been reached twice — on #260's own
dogfood run and on this chain — and refused both times, on the same section.
Every code path under the verdict is therefore untested, and four defects in it
are visible by reading.

The absorb writes into documents the enumerated write-target set does not name.
The existing `upstream:` re-point already writes the survivor and is not listed,
so the set understates the parent's reach today, before this change adds to it.

A field this work depends on is specified, consumed, and never written.
`chain_ran:` is defined in `state-schema.md` and read in three places by Phase 3
— R9's chain-membership-gated extension gates on it, the PR-body record copies
"every artifact in `chain_ran:`", and `plan_execution_mode:` is required present
if and only if `/plan` appears in it. Phase 2 records `child_snapshots:` and
clears its sentinel, but no instruction anywhere appends to `chain_ran:`. So the
hard-finalization check gates on a field nobody populates. That matters here
because the scoping this work needs — the judgment fires only at a hop where
*this run* produced both documents — is exactly what `chain_ran:` is for, and
because telling an absorbed artifact from one that was never produced is the
thing the fold record exists to make possible.

And the failure mode the absorb can cause is invisible to CI by construction.
`validate-docs.yml` computes its file set with `git diff`, so a document
stranded by a deletion is not a changed file — its bytes are untouched, only its
target vanished. The reference check can never fire on it. Fold time is the only
point in the system at which that breakage is catchable.

## Decision Drivers

- **Nothing may judge an artifact before that artifact exists.** This killed a
  previously-shipped feature and is the constraint every alternative here is
  measured against first.
- **One reduction mechanism, not two.** The consolidation judgment must remain
  the only thing that removes a document. A mechanism whose sole possible effect
  is to force `keep` does not count as a second one — that distinction is what
  admits the guard and the carry check.
- **Fail toward `keep` at every added decision point.** A wrong `keep` costs a
  document that stayed; a wrong `absorb` costs content with no recovery path
  from a clone, because squash-merge with branch deletion means an absorbed
  document never existed on the default branch.
- **Existing documents are not this change's business.** The added checks must
  be silent on documents that declare no absorption. Where an existing document
  carries a defect this work happens to surface, the finding stands and the
  cleanup is sequenced follow-on work — pre-existing breakage is not a reason to
  narrow a check that is otherwise correct.
- **Prefer the seam that exists.** `required_sections_for` is already the single
  function both the presence and order checks consult; the abort path already
  downgrades a verdict to `keep` and deletes nothing; `shirabe transition`
  already writes a lineage key and splices a `## Status` line. Each of those is a
  pattern to extend rather than a mechanism to invent.
- **The verdict is the agent's; the operation is the machine's.** What an agent
  decides — whether content is worth keeping — gets no gate. What a machine can
  decide — whether a section is present, whether a citation exists, whether a
  record was written — is checked mechanically and fails closed.
