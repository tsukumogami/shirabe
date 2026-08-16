---
schema: prd/v1
status: In Progress
problem: |
  A /scope fold deletes a chain document, and something must record that the
  document was absorbed rather than never written. Today that is docs/folds.md,
  a shared append-only file every parallel chain writes to. Wherever the
  survivor stays on disk it already carries the same fact under error-level
  enforcement; the record's concurrency mitigation does not apply where this
  repository merges; adopting repositories inherit its CI check without ever
  receiving that mitigation; and the check cannot fire on the fold shape the
  record exists for.
goals: |
  A fold touches no file shared with another chain, a reader holding a dead
  path still learns what happened to it from the document that absorbed it, an
  adopting repository is asked only for checks it can satisfy, and the reasoning
  behind the removal is durable enough that the mechanism is not reintroduced by
  someone reading its absence as an oversight.
upstream: docs/briefs/BRIEF-fold-record-removal.md
motivating_context: |
  The record has recorded exactly one fold, and that fold demonstrates both
  halves of the case: the survivor carries every fact the row holds, and the
  check meant to verify the row observed nothing. The decision to keep a record
  was fixed at BRIEF altitude and never re-examined; the design that shipped it
  chose among surfaces for a record it already assumed, in --auto mode without
  author confirmation, on a pull request with no review.
---

# PRD: Fold-Record Removal

## Status

In Progress

Three review passes ran against these requirements; the findings converged from
seven blocking items to four localized corrections, and one of those corrected a
premise the repository falsified mid-drafting when the record recorded its first
fold. The downstream DESIGN owns which replacement claim each prose site gets
and what each amendment says.

## Problem Statement

`/scope`'s consolidation judgment deletes a chain document when the document
below it already carries everything it held. That leaves a reader unable to
tell an absorbed artifact from one that was never produced — the two look
identical on disk and mean opposite things — because this repository
squash-merges a whole chain, so a document created and folded away inside one
chain never reaches the default branch at all.

The current answer is `docs/folds.md`: one append-only row per fold, in one
file, in every repository that runs `/scope`. It fails on three counts.

**Its guarantee is already provided elsewhere, wherever a survivor remains.** A
surviving document declares what it absorbed in frontmatter, names it in a
pinned status line, and carries its content in a contribution section — all
three enforced at error level, and the declaration accumulates across hops so
the document at the end of a chain names every ancestor folded into it. The
record's own justification claims an absorbed document "leaves no trace
otherwise." For every fold whose survivor stays on disk, that is false. The
exception is real and is treated as this PRD's central residual: where the last
survivor is itself deleted later by the implementation cascade, the declaration
goes with it.

**Its cost is contention.** The file is a single shared write point for every
chain running in parallel. Its stated mitigation is a `merge=union` attribute in
`.gitattributes`, which GitHub does not consult when it resolves a merge
server-side, so concurrent folds still block the merge button. Repositories that
pin the shared validation workflow inherit the fold check but never receive the
attribute, because `.gitattributes` is a repository file rather than a
distributed plugin asset — so the mitigation is absent exactly where the check
is present.

**Its verification does not work.** The check is triggered by
`git diff --diff-filter=D "$BASE...$HEAD"`, a two-endpoint tree comparison,
which cannot observe a file created and deleted between those endpoints — which
is precisely the fold shape the record exists for. Where the check can fire, the
guard meant to skip an unrecoverable hash never skips: `git rev-parse` on an
unresolvable `<rev>:<path>` prints the literal argument to stdout, so the
emptiness test that guards the comparison always passes and a correct record is
reported as a mismatch whenever the base branch has advanced. On top of that,
the record promises duplicate detection in three separate documents and no code
implements it.

The repository has performed exactly one fold, and it settles all three counts
at once. `#316` absorbed `BRIEF-scope-chain-mandatory-steps.md` into its PRD.
The surviving PRD declares the absorbed path in frontmatter, names it in its
`## Status` line, and carries it in `## Absorbed Brief` — every fact the row
holds, on disk. The absorbed brief was created and deleted inside that same
squashed chain, so it appeared in neither endpoint of the workflow's tree
comparison and the fold-record check exited without asserting anything. The one
row in the record was written by an agent following prose, verified by nothing,
and duplicates a trace that three error-level checks already enforce.

Around that single row sit a merge attribute, an append-only assertion, a
cleanup carve-out, a citation-search exclusion, an eval fixture, and seven
shipped documents of rationale.

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

**R1.** The fold record file `docs/folds.md` SHALL be removed from the
repository.

**R2.** The absorb procedure SHALL NOT write, stage, or roll back any shared
record. Its step sequence, the sentence stating how many steps it has, its
rollback table, the standalone paragraph justifying the un-append, its final
commit step, and the partial-absorb resume paragraph that names a step range
SHALL all be rewritten so that nothing refers to an append, an un-append, or a
record committed alongside the deletion. The cross-reference in
`skills/scope/SKILL.md` that states the procedure's step count and enumerates
its parts SHALL be updated to match.

**R3.** The closed write-target set SHALL NOT name an append target. Every
place enumerating the set — the skill contract and the exit-finalization
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

**R7.** The `merge=union` attribute serving the record SHALL be removed from
`.gitattributes`, together with the comment block justifying it.

**R8.** Every prose claim citing the record as evidence SHALL be replaced with a
claim that holds without it, rather than deleted. This binds at minimum:

- the rule in `skills/execute/SKILL.md` explaining how a caller distinguishes a
  chain that folded every artifact away from a chain that never ran;
- the roadmap downstream cell written by `skills/execute/scripts/run-cascade.sh`
  when a chain folds to nothing;
- the description of the consolidation judgment in `README.md`;
- the clause in `skills/scope/SKILL.md` defining the `absorb` verdict, which
  SHALL still state what the verdict ends with rather than trailing off where
  the record used to be.

**R9.** Adopter-facing documentation SHALL NOT describe a fold-record check.
Removing a check from a reusable workflow is backward-compatible for pinning
repositories, so no coordinated multi-repository change is required — but the
published contract in `docs/guides/doc-validation.md` SHALL be updated in the
same change.

**R10.** Each of these seven shipped documents SHALL carry a dated amendment
section recording what no longer holds, and SHALL retain its current status:

1. `docs/briefs/BRIEF-scope-artifact-persistence.md` (Done) — lists a durable
   default-branch record as an in-scope item.
2. `docs/prds/PRD-scope-artifact-persistence.md` (Done) — carries R20, the
   requirement the record discharges.
3. `docs/designs/current/DESIGN-scope-artifact-persistence.md` (Current) —
   chose the record's surface.
4. `docs/prds/PRD-scope-consolidation-over-skipping.md` (Done) — its existing
   amendment names the record as the successor's mechanism.
5. `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`
   (Current) — cites the record in its Option D answer.
6. `docs/prds/PRD-scope-chain-mandatory-steps.md` (Done) — lists the fold
   record among what stays as shipped.
7. `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md` (Current) —
   justifies its clean-cancel carve-out by the shape of the record's carve-out,
   which R4 deletes.

A requirements document has no superseded state, so amendment in place is the
only available mechanism and no status transition is performed.

**R10a.** The amendment to `DESIGN-scope-consolidation-over-skipping.md` SHALL
state affirmatively what now answers the objection that Option D was rescued
from — that absorbing a DESIGN into a PLAN "trades a durable audit trail for a
shorter run and loses the record of why the work happened." The answer had two
halves. The half that survives is that the record of *why* belongs in the code,
which is a standing `/work-on` instruction independent of any chain. The half
that is withdrawn is the record of *what happened*; the amendment SHALL name
what replaces it and SHALL state plainly where nothing does.

**R11.** The removal rationale SHALL be readable in the working tree after this
chain completes, naming each carrier evaluated and why it was not adopted, so a
later proposal to reintroduce a fold ledger is answered from the artifact rather
than by re-investigation. Its home is
`docs/designs/current/DESIGN-fold-record-removal.md`.

This requirement states an outcome, not a verdict. `/scope`'s consolidation
judgment is made against two documents and this PRD does not reach into it. The
expected consequence of that ground is that the design-to-plan hop reaches
`keep`, because the carrier reasoning is content the PLAN does not carry and
folding would lose — but the judgment reaches that on its own terms, and if it
instead finds the reasoning fully carried, R11 is satisfied wherever the
reasoning ends up readable.

**R12.** References to the record that do not spell its path SHALL be corrected,
not left standing. This binds at minimum:

- `crates/shirabe-validate/src/formats.rs` — the `ABSORBED_ENTRY_PATTERN` doc
  comment naming three readers, one of them the record checker's fold signature;
  and the `contribution_heading` doc comment naming a durable record column.
- `.github/workflows/check-scope-scripts.yml` — the same three-reader model.
- `skills/scope/scripts/check-citations.sh` — the comment stating the path shape
  has three readers.

In each, the stated reader count SHALL match the number that remains. These
sites are source and workflow rather than amended-document bodies, so R18's
exemption does not reach them.

**R13.** The scope eval fixture SHALL be rewritten rather than scrubbed. It
currently specifies the append and its ordering relative to the `git rm`; after
the change it SHALL specify the absorb procedure as it then exists, so the eval
asserts a step sequence that is real.

### Non-functional

**R14.** The survivor-side trace SHALL be unchanged. The `absorbed:` frontmatter
field, the pinned `## Status` absorption line, the contribution section, and the
checks enforcing them are the carrier this removal relies on and SHALL NOT be
weakened, renamed, or re-scoped.

**R15.** No compiled behavior SHALL change. Any change under `crates/` SHALL be
confined to comment lines.

**R16.** The change SHALL introduce no new validator error relative to the merge
base. The corpus carries five pre-existing errors at the time of writing, so a
clean corpus is not an available bar; the bar is that this change adds none.

**R17.** The test suites covering the changed scripts SHALL pass:
`skills/scope/scripts/check-citations_test.sh` and
`skills/execute/scripts/run-cascade_test.sh`.

**R18.** No dangling reference to the record SHALL remain in any executable or
adopter-facing surface. Body prose inside the seven amended documents is
deliberately exempt: R10 preserves those bodies unedited and records the change
in an appended section, so the historical text stays as written.

## Acceptance Criteria

- [ ] **AC1.** `docs/folds.md` does not exist in the working tree.
- [ ] **AC2.** `git grep -n 'docs/folds\.md' HEAD -- ':!wip/'
      ':!docs/briefs/BRIEF-scope-artifact-persistence.md'
      ':!docs/prds/PRD-scope-artifact-persistence.md'
      ':!docs/designs/current/DESIGN-scope-artifact-persistence.md'
      ':!docs/prds/PRD-scope-consolidation-over-skipping.md'
      ':!docs/designs/current/DESIGN-scope-consolidation-over-skipping.md'
      ':!docs/prds/PRD-scope-chain-mandatory-steps.md'
      ':!docs/designs/current/DESIGN-scope-chain-mandatory-steps.md'
      ':!docs/briefs/BRIEF-fold-record-removal.md'
      ':!docs/prds/PRD-fold-record-removal.md'
      ':!docs/designs/current/DESIGN-fold-record-removal.md'` returns no output.
- [ ] **AC3.** `git grep -in 'fold record\|fold-record\|record checker\|fold
      signature' HEAD` with the same exclusion set returns no output.
- [ ] **AC4.** `.gitattributes` contains no `merge=union` entry and no comment
      block describing fold-record concurrency.
- [ ] **AC5.** `.github/workflows/validate-docs.yml` contains no step named for
      fold-record verification, and no `git show`, `grep`, or `rev-parse`
      invocation against the record path.
- [ ] **AC6.** `check-citations.sh --record x` exits non-zero with an
      unknown-option error, and the script contains no record exclusion
      pathspec in either search tier.
- [ ] **AC7.** `bash skills/scope/scripts/check-citations_test.sh` exits 0 and
      contains no case asserting that the fold record does not refuse a later
      hop.
- [ ] **AC8.** The absorb procedure's step list is contiguously numbered; the
      sentences stating its step count — in `phase-2-chain-orchestration.md` and
      in `skills/scope/SKILL.md`'s cross-reference — both match the list length;
      the rollback table has one row per writing step with step numbers matching
      the renumbered list; every prose reference to a step number inside the
      Consolidation Judgment section, including the partial-absorb resume
      paragraph, matches the renumbered list; and no step, row, paragraph, or
      cross-reference mentions an append, an un-append, or a record committed
      alongside the deletion.
- [ ] **AC9.** The closed write-target set in `skills/scope/SKILL.md` and the
      read-back in `phase-3-exit-finalization.md` both enumerate deletions and
      mutations only, with no append group, do not contradict each other, and
      the sentence stating how many groups Phase 2's absorb adds matches the
      number of groups listed.
- [ ] **AC10.** `phase-4-cleanup.md` contains no carve-out naming the record.
- [ ] **AC11.** `skills/execute/SKILL.md`'s rule for distinguishing a
      fully-folded chain from an unfinalized one does not cite the record. It
      names a concrete artifact or signal a reader consults, and states in the
      same passage what a reader observes when even that is absent — the case
      Known Limitations concedes.
- [ ] **AC12.** `bash skills/execute/scripts/run-cascade_test.sh` exits 0, and
      the roadmap downstream cell the script emits contains no pointer to the
      record while still distinguishing a chain that folded from one that never
      ran.
- [ ] **AC13.** `README.md` describes the consolidation judgment without naming
      the record.
- [ ] **AC14.** `docs/guides/doc-validation.md` describes no fold-record check.
- [ ] **AC15.** Each of the seven documents named in R10 contains a section
      heading matching `## Amendment — <date>` where `<date>` is on or after
      the date this change lands, and the text under that heading contains the
      string `folds.md`. Each document's `status:` is unchanged from the merge
      base.
- [ ] **AC16.** `DESIGN-scope-consolidation-over-skipping.md`'s new amendment
      contains both the phrase naming the surviving half of the answer (the
      record of *why*, in the code) and an explicit statement of what carries
      the record of *what happened*, including the case where nothing does.
- [ ] **AC17.** The document carrying the removal rationale —
      `docs/designs/current/DESIGN-fold-record-removal.md`, or the surviving
      document that absorbed it — exists in the working tree and names, each
      with a reason for rejection: survivor frontmatter alone, commit trailer,
      git notes, per-chain file, forge metadata, rotation, and per-fold file.
- [ ] **AC18.** `git diff <merge-base>..HEAD -- crates/` touches comment lines
      only, and `cargo test` passes.
- [ ] **AC19.** `git diff <merge-base>..HEAD --` over
      `crates/shirabe-validate/src/checks.rs`,
      `crates/shirabe-validate/src/formats.rs`,
      `crates/shirabe/tests/absorption_corpus.rs`, and
      `.github/workflows/check-scope-scripts.yml` touches comment lines only.
      These are the survivor-trace enforcement surfaces; the prose and eval
      surfaces that AC8 and AC21 mandate changing are deliberately excluded.
- [ ] **AC20.** `shirabe validate --visibility=public` over the changed document
      set exits 0, and
      `shirabe validate --visibility=public $(git ls-files 'docs/*.md'
      'docs/**/*.md')` yields no more than five error-severity findings, which
      is the merge base's count.
- [ ] **AC21.** `skills/scope/evals/evals.json` describes the absorb procedure
      as it exists after the change: no expected output or rubric criterion
      mentions appending a row, its ordering relative to the deletion, or a
      record committed alongside it. The scenario still asserts that the `git
      rm` precedes the re-validation, that the re-validation precedes the
      commit, and that the deletion, the splice and the survivor's edits land in
      one commit.
- [ ] **AC22.** `crates/shirabe-validate/src/formats.rs`,
      `.github/workflows/check-scope-scripts.yml`, and
      `skills/scope/scripts/check-citations.sh` each describe the
      absorbed-path shape's readers without naming a record checker or a fold
      signature, and the reader count stated in each matches the number that
      remains. `formats.rs`'s `contribution_heading` doc comment names no
      durable record column.

## Out of Scope

- **The consolidation judgment itself.** Whether `/scope` folds, at which hops,
  and what carries into the survivor are settled. This work changes what a fold
  records, never what it does.
- **Replacing the record with another carrier.** Survivor frontmatter alone,
  commit trailers, git notes, per-chain files, forge metadata, rotation
  schemes, and per-fold files were each measured during exploration and none is
  adopted. R11 records why so the question is not reopened by default.
- **Re-deciding whether a design may be absorbed into a plan.** That decision
  stays shipped; only the argument that cited the record needs restating.
- **Fixing the defects in the fold-record check as standalone work.** The
  trigger that cannot fire, the dead skip-guard, and the absent duplicate
  detection are evidence that the mechanism was never load-bearing. They are
  deleted with the step that carries them and are not separately repaired.
- **Migrating the one existing row.** The record holds a single row, for the
  `#316` brief-to-PRD fold. It is deleted with the file and nothing is carried
  anywhere, because the surviving PRD already declares the absorbed path in
  frontmatter, names it in its `## Status` line, and carries it in
  `## Absorbed Brief`. Every field of the row except the pre-fold blob hash is
  recoverable from that survivor, and the hash fingerprints bytes no plain clone
  can reach now that the branch is gone. Migration would move a fact that is
  already in a better place.
- **Auditing adopting repositories for rows.** Not verifiable from here, and it
  does not gate this change; removing a check from a reusable workflow cannot
  break a caller.
- **The five pre-existing corpus validation errors.** They predate this work and
  are not repaired by it; R16 only forbids adding more.

## Decisions and Trade-offs

**The roadmap's downstream cell says the chain folded, and stops there.** The
BRIEF deferred what that cell should say once it cannot point at the record. It
keeps the folded-versus-never-started distinction, which is the whole reason the
cell fires, and drops only the pointer. It cannot point at a surviving artifact,
because the case where it fires is the case where there is none. This carrier is
narrower than the record in one specific way, recorded under Known Limitations:
a chain with no roadmap feature entry has no cell to write, and the roadmap
itself is eventually deleted by the same cascade.

**The merge attribute is removed rather than left inert.** It costs nothing
where it sits, but three documents cite it as providing a guarantee it does not
provide, and leaving it would require correcting that prose while keeping a
mechanism with nothing left to protect. Removing it makes the prose correction a
deletion instead of a rewrite.

**Seven documents are amended, not four.** An earlier draft named only the two
persistence documents and the two consolidation documents. Three more assert
things this change falsifies: the BRIEF that put a durable record in scope at
the altitude where the decision was actually made, and the two mandatory-steps
documents that either list the record as staying shipped or justify their own
carve-out by the shape of the one R4 deletes. Leaving any of them unamended
leaves a reader a contradiction to find.

**The removal's rationale lives in a DESIGN that this chain must keep.** The
cheaper option is to delete and move on. It was rejected because the original
decision was never argued: a later contributor finding no ledger and no
reasoning has exactly the information the original author had and reaches the
same conclusion. Siting the rationale in the DESIGN rather than the PRD is
deliberate — a PRD reaches Done and stops being consulted. The expectation is
that the design-to-plan hop reaches `keep` on its own terms, because the carrier
reasoning is content the PLAN does not carry; R11 requires the outcome, not the
verdict.

**Amendment in place, not supersession.** A requirements document has no
superseded state, so the mechanism is unavailable for the document carrying the
binding requirement. The designs could be superseded, but that discards sound
unaffected decisions across documents whose other content is untouched.
Amendment in place is both the only universally available mechanism and the one
this corpus already used on two of these same documents.

**Growth is not a reason.** A row costs roughly a hundredth of what the fold
that writes it reclaims, and nothing reads the record into an agent's context.
The case rests on contention, on redundancy with the survivor-side trace, and on
verification that does not work. Any argument from file size is unsupported and
is deliberately absent from this document.

## Known Limitations

- **One fold shape loses its only carrier.** Where a chain folds down to a
  single surviving artifact and the implementation cascade later deletes it,
  nothing on the default branch records that the chain ran. R8's roadmap cell
  narrows this to chains with no roadmap feature entry — and even there the
  cascade eventually deletes the roadmap. This is the accepted cost of the
  removal and the residual R11's record exists to explain.
- **The removal is specified against a mechanism that has executed once.** One
  fold has run, which is enough to confirm the argument and not enough to
  characterize the mechanism's behavior across fold shapes. The
  design-to-plan hop, the multi-hop chain, and the concurrent-fold case remain
  documented rather than observed, and the acceptance criteria test the absence
  of machinery rather than a change in observed fold behavior.
- **Two of the seven amended documents already carry a dated amendment.** The
  new sections are appended alongside, so those documents will carry two, which
  is correct but reads oddly on first encounter.
