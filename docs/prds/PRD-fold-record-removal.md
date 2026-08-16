---
schema: prd/v1
status: Draft
problem: |
  A /scope fold deletes a chain document, and something must record that the
  document was absorbed rather than never written. Today that is docs/folds.md,
  a shared append-only file every parallel chain writes to. The surviving
  document already carries the same fact under error-level enforcement, the
  record's concurrency mitigation does not apply where this repository merges,
  adopting repositories inherit its CI check without ever receiving that
  mitigation, and the check cannot fire on the fold shape the record exists for.
goals: |
  Remove the record and every mechanism that exists only to serve it, replace
  the prose claims that cite it as evidence with claims that hold without it,
  and amend the shipped documents whose requirements and decisions it
  discharges — leaving the survivor-side trace, which is the carrier the
  removal relies on, exactly as it is.
upstream: docs/briefs/BRIEF-fold-record-removal.md
motivating_context: |
  The record landed one day before this PRD and has never held a row. The
  decision to keep it was fixed at BRIEF altitude and never re-examined; the
  design that shipped it chose among surfaces for a record it already assumed,
  in --auto mode without author confirmation, on a pull request with no review.
---

# PRD: Fold-Record Removal

## Status

Draft

Requirements are drafted and awaiting the jury. The downstream DESIGN owns
which replacement claim each prose site gets and what each amendment says.

## Problem Statement

`/scope`'s consolidation judgment deletes a chain document when the document
below it already carries everything it held. That leaves a reader unable to
tell an absorbed artifact from one that was never produced — the two look
identical on disk and mean opposite things — because this repository
squash-merges a whole chain, so a document created and folded away inside one
chain never reaches the default branch at all.

The current answer is `docs/folds.md`: one append-only row per fold, in one
file, in every repository that runs `/scope`. It fails on three counts.

**Its guarantee is already provided elsewhere.** A surviving document declares
what it absorbed in frontmatter, names it in a pinned status line, and carries
its content in a contribution section — all three enforced at error level, and
the declaration accumulates across hops so the document at the end of a chain
names every ancestor folded into it. The record's own justification claims an
absorbed document "leaves no trace otherwise." For every fold whose survivor
stays on disk, that is false.

**Its cost is contention.** The file is a single shared write point for every
chain running in parallel. Its stated mitigation is a merge attribute that the
hosting forge does not consult when it resolves a merge, so concurrent folds
still block the merge button. Repositories that pin the shared validation
workflow inherit the fold check but never receive the attribute, because it is
a repository file rather than a distributed plugin asset — so the mitigation is
absent exactly where the check is present.

**Its verification does not work.** The check is triggered by a two-endpoint
tree comparison, which cannot observe a file created and deleted between those
endpoints — which is precisely the fold shape the record exists for. Where the
check can fire, a guard meant to skip an unrecoverable hash never skips,
because the underlying command emits its unresolved argument on success-shaped
output, so a correct record is reported as a mismatch whenever the base branch
has advanced. On top of that, the record promises duplicate detection in three
separate documents and no code implements it.

The result is a merge attribute, an append-only assertion, a cleanup carve-out,
a citation-search exclusion, and four documents of rationale, all maintaining a
file that has never held a row.

## Goals

- A `/scope` fold completes without writing to any file shared with another
  chain, so parallel chains do not contend, rebase, or fail validation because
  a sibling folded first.
- A reader holding a path that no longer exists still learns what happened to
  it, from the document that absorbed it, in the working tree.
- A repository adopting the shared validation workflow is only asked to satisfy
  checks it has the means to satisfy.
- The reasoning behind the removal, and the carriers measured and rejected, is
  durable — so the mechanism is not reintroduced by a later contributor who
  reads its absence as an oversight.

## User Stories

**As a chain author running `/scope` alongside other agents,** I want a fold to
touch only the documents in my own chain, so that my branch merges regardless
of what a sibling chain folded and when.

**As a contributor following a citation to a path that no longer exists,** I
want the document that absorbed it to tell me so, so that I can distinguish
"absorbed into this" from "never written" without consulting history or a
central index.

**As a maintainer of a repository that pins shirabe's validation workflow,** I
want the checks I inherit to be ones my repository can satisfy, so that adopting
the workflow does not hand me an obligation I was never given the means to meet.

**As a future contributor who notices that folds leave no central ledger,** I
want to find the recorded reasoning for that absence, so that I can evaluate
the decision instead of re-investigating it and re-proposing the mechanism.

## Requirements

### Functional

**R1.** The fold record file SHALL be removed from the repository.

**R2.** The absorb procedure SHALL NOT write, stage, or roll back any shared
record. The procedure's step sequence and its rollback table SHALL be
renumbered and rewritten so that no step refers to an append that no longer
happens.

**R3.** The closed write-target set SHALL NOT name an append target. Every
place that enumerates the set — the skill contract and the exit-finalization
read-back — SHALL agree that the set has no append group.

**R4.** The cleanup phase SHALL NOT carry a carve-out exempting the record from
its sweep.

**R5.** The shared validation workflow SHALL NOT contain a step that verifies a
fold record. Because every assertion in that step is about the record itself,
the step SHALL be removed rather than reduced.

**R6.** The citation preflight SHALL NOT carry a flag, a default, a path-shape
assertion, or a search exclusion whose only purpose is to prevent the record
from being read as a citation of the path being folded. Its test suite SHALL
NOT retain a case covering that exclusion.

**R7.** The merge attribute that exists only to serve the record SHALL be
removed, together with the comment block justifying it.

**R8.** Every prose claim that cites the record as evidence SHALL be replaced
with a claim that holds without it, rather than deleted. This binds at minimum:

- the rule explaining how a caller distinguishes a chain that folded every
  artifact away from a chain that never ran;
- the line the implementation cascade writes into a roadmap's downstream cell
  when a chain folds to nothing;
- the public-facing description of the consolidation judgment in the
  repository's README.

**R9.** Adopter-facing documentation SHALL NOT describe a fold-record check.
The removal of a check from a reusable workflow is backward-compatible for
pinning repositories, so no coordinated multi-repository change is required —
but the published contract SHALL be updated in the same change.

**R10.** The shipped documents whose requirements and decisions the record
discharges SHALL each carry a dated amendment recording what no longer holds.
The amendment to the consolidation design SHALL state what now answers the
objection that its design decision was rescued from, because that decision
stays shipped while the argument supporting it loses its premise. A
requirements document has no superseded state, so amendment in place is the
only available mechanism and no status transition is performed.

**R11.** The removal SHALL be recorded durably, naming the carriers that were
measured and rejected, so that a later proposal to reintroduce a fold ledger is
answered from the artifact rather than by re-investigation.

### Non-functional

**R12.** The survivor-side trace SHALL be unchanged. The absorbed-declaration
frontmatter field, the pinned status line, the contribution section, and the
checks enforcing them are the carrier this removal relies on and SHALL NOT be
weakened, renamed, or re-scoped by this work.

**R13.** No compiled behavior SHALL change. The removal touches prose,
workflow configuration, a shell script and its test, and repository metadata;
any source change SHALL be limited to comments that describe the removed
mechanism.

**R14.** The repository's own validation SHALL pass after the change: the
document validator over the corpus, and the scope-scripts test suite.

**R15.** No dangling reference to the record SHALL remain. A search of the
committed tree for the record's path SHALL return no hit outside the amendment
sections that describe its removal.

## Acceptance Criteria

- [ ] **AC1.** `docs/folds.md` does not exist in the working tree.
- [ ] **AC2.** A search of the committed tree for `docs/folds.md` returns hits
      only inside dated amendment sections and this chain's own artifacts —
      no hit in `skills/`, `.github/`, `crates/`, `README.md`, or
      `.gitattributes`.
- [ ] **AC3.** `.gitattributes` contains no `merge=union` entry and no comment
      block describing fold-record concurrency.
- [ ] **AC4.** The shared validation workflow contains no step named for fold-
      record verification, and no `git show`, `grep`, or `rev-parse` invocation
      against the record path.
- [ ] **AC5.** `check-citations.sh` accepts no `--record` flag; invoking it
      with `--record` exits non-zero with an unknown-option error. Its two
      search tiers contain no record exclusion pathspec.
- [ ] **AC6.** `check-citations_test.sh` passes, and contains no case asserting
      that the fold record does not refuse a later hop.
- [ ] **AC7.** The absorb procedure's step list is contiguous and correctly
      numbered, its rollback table has one row per step, and neither mentions
      an append or an un-append.
- [ ] **AC8.** The skill contract's closed write-target set and the exit-
      finalization read-back both enumerate deletions and mutations only, with
      no append group, and do not contradict each other.
- [ ] **AC9.** The cleanup phase contains no carve-out naming the record.
- [ ] **AC10.** The rule for distinguishing a fully-folded chain from an
      unfinalized one states a criterion that can be evaluated without the
      record, and names what a reader consults instead.
- [ ] **AC11.** The cascade writes a roadmap downstream cell that contains no
      pointer to the record, and `run-cascade_test.sh` passes.
- [ ] **AC12.** `README.md` describes the consolidation judgment without naming
      the record.
- [ ] **AC13.** Adopter-facing validation documentation describes no fold-record
      check.
- [ ] **AC14.** Each of the four shipped documents carries a dated amendment
      section stating what no longer holds; each retains its prior status; and
      the consolidation design's amendment contains an affirmative statement of
      what now answers the objection, not only that the prior answer is
      withdrawn.
- [ ] **AC15.** A durable artifact records the removal rationale and names at
      least the carriers evaluated during exploration — survivor frontmatter
      alone, commit trailer, git notes, per-chain file, forge metadata,
      rotation, and per-fold file — with the reason each was not adopted.
- [ ] **AC16.** `shirabe validate` reports a clean outcome over the changed
      document set.
- [ ] **AC17.** The absorbed-declaration field, its pinned status line, its
      contribution section, and their enforcing checks are byte-identical to
      their pre-change state except where a comment names the removed checker.

## Out of Scope

- **The consolidation judgment itself.** Whether `/scope` folds, at which hops,
  and what carries into the survivor are settled. This work changes what a fold
  records, never what it does.
- **Replacing the record with another carrier.** Per-fold files, commit
  trailers, git notes, forge metadata, per-chain files, and rotation schemes
  were each measured during exploration and none is adopted. R11 records why so
  the question is not reopened by default.
- **Re-deciding whether a design may be absorbed into a plan.** That decision
  stays shipped; only the argument that cited the record needs restating.
- **Fixing the defects in the fold-record check as standalone work.** The
  trigger that cannot fire, the dead skip-guard, the column-blind row lookup,
  and the absent duplicate detection are evidence that the mechanism was never
  load-bearing. They are deleted with the step that carries them and are not
  separately repaired.
- **Migrating existing rows.** The record has never held one.
- **Auditing adopting repositories for rows.** Whether any pinning repository
  has a populated record is not verifiable from here and does not gate this
  change; removing a check from a reusable workflow cannot break a caller.

## Decisions and Trade-offs

**The roadmap's downstream cell says nothing about a record.** The BRIEF
deferred what that cell should say once it cannot point at the record. It
states that the chain folded and stops there. The alternatives were to point at
the surviving artifact — but in this case there is none, which is what makes
the cell fire — or to say nothing at all, which loses the distinction between a
chain that folded and a feature never started. No roadmap carries the current
text today, so the change is unconstrained by existing content.

**The merge attribute is removed rather than left inert.** It costs nothing
where it sits, but three documents cite it as providing a guarantee it does not
provide, and leaving it would require correcting that prose while keeping a
mechanism with nothing left to protect. Removing it makes the prose correction
a deletion instead of a rewrite.

**The record's absence is itself documented, rather than left silent.** The
cheaper option is to delete and move on. It was rejected because the original
decision was never argued: a later contributor finding no ledger and no
reasoning has the same information the original author had, and reaches the
same conclusion. R11 exists to break that loop.

**Amendment in place, not supersession.** A requirements document has no
superseded state, so the mechanism is not available for the document that
carries the binding requirement. The design documents could be superseded, but
that discards sound unaffected decisions across documents whose other content
is untouched. Amendment in place is both the only universally available
mechanism and the one this corpus already used on these same documents.

**Growth is not a reason.** A row costs roughly a hundredth of what the fold
that writes it reclaims, and nothing reads the record into an agent's context.
The case rests on contention, on redundancy with the survivor-side trace, and
on verification that does not work. Any argument from file size is unsupported
and is deliberately absent from this document.

## Known Limitations

- **One fold shape loses its only carrier.** Where a chain folds down to a
  single surviving artifact and that artifact is later deleted by the
  implementation cascade, nothing on the default branch records that the chain
  ran. R8's replacement claim narrows this but does not eliminate it: a reader
  gets "no downstream artifact" rather than "a chain ran and folded to
  nothing." This is accepted as the cost of the removal, and it is the residual
  the durable record in R11 exists to explain.
- **The removal is verified against a mechanism that has never executed.** No
  fold has ever run, so the behavior being removed is specified rather than
  observed, and the acceptance criteria test the absence of machinery rather
  than a change in observed fold behavior.
