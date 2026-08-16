---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-fold-record-removal.md
problem: |
  docs/folds.md records each /scope fold in one shared append-only file. Wherever
  a survivor remains it duplicates a trace three error-level checks already
  enforce; its concurrency mitigation is inert on the forge this repository
  merges on and absent entirely in adopting repositories; and its CI check cannot
  fire on the fold shape it exists for, which the repository's one real fold
  confirms. Removing it means replacing two prose claims that cite it as
  evidence, amending seven shipped documents, and recording why no replacement
  carrier was adopted.
decision: |
  Delete the record and every mechanism serving only it. Point /execute's
  fully-folded disambiguation and the roadmap downstream cell at the same
  surface, so the corpus carries one answer rather than two, and state the
  residual plainly in both places rather than inventing a carrier for it. Amend
  the seven shipped documents in place with dated sections, and record the seven
  evaluated-and-rejected carriers here so the mechanism is not reproposed.
rationale: |
  The residual is structural: any on-branch carrier for a fully-folded chain must
  be a file written outside the chain's own fold set, which is what the record
  was. Eliminating it means reintroducing that shape under another name, so every
  option narrows rather than removes it. Given that, the choice is between
  narrowing honestly on a surface the repository controls and narrowing further
  on forge metadata the corpus does not guarantee. This design takes the first.
---

# DESIGN: Fold-Record Removal

## Status

Planned

Three decision questions were evaluated; two more were mechanical and resolved
inline. The decision reports were working artifacts and do not survive this
chain — the reasoning that survived them is carried in Considered Options below.

## Context and Problem Statement

`/scope`'s consolidation judgment deletes a chain document when the document
below it carries everything it held, and appends a row to `docs/folds.md`
recording the operation. `docs/prds/PRD-fold-record-removal.md` requires that
record removed.

The technical problem is not the deletion. It is that the record is cited as
evidence by two prose claims, justified by seven shipped documents, and coupled
to a CI step, a merge attribute, a citation-search exclusion, an eval fixture,
and a set of comments that name it without spelling its path. Removing the file
without reaching all of those leaves the corpus asserting things that are no
longer true — which is the same defect the record itself was introduced to
prevent, relocated.

Two facts bound every option and were established empirically rather than
assumed.

**The residual is structural.** A chain can fold down to a PLAN, and
`/execute`'s cascade then deletes the PLAN. This repository squash-merges, so a
file created and deleted inside one branch appears in neither endpoint of a
two-endpoint tree comparison. Any on-branch carrier for that case must therefore
be a file the chain wrote *outside* its own fold set — precisely the shape
`docs/folds.md` had. No replacement can eliminate the residual without
reintroducing that shape under another name.

**The record's one real exercise demonstrates the case against it.** `#316`
absorbed `BRIEF-scope-chain-mandatory-steps.md` into its PRD. The surviving PRD
declares the absorbed path in frontmatter, names it in its `## Status` line, and
carries it in `## Absorbed Brief`. The absorbed brief was created and deleted
inside that same squashed chain, so `git diff --diff-filter=D BASE...HEAD` saw
nothing and the fold-record check exited without asserting anything. The row was
written by an agent following prose and verified by nothing.

## Decision Drivers

- **One answer, not two.** `/execute`'s rule and the roadmap cell answer the same
  question. If they name different surfaces the corpus carries two answers, which
  is the failure mode the "replace, do not delete" requirement exists to prevent.
- **Do not invent a carrier.** Seven carriers were evaluated during exploration
  and rejected. Naming any of them in an amendment or a replacement claim
  contradicts this design's own record of why they were rejected.
- **Do not restore a floor.** The prohibition against a guard that forces `keep`
  so a chain leaves something durable is live and independent of this work. A
  replacement that implies a floor collides with it.
- **State the residual where it bites.** The absent case is real. A claim that
  narrows it silently is worse than one that names it.
- **Prefer the shortest claim that holds.** The consumers are a human
  investigator and a soon-deleted table cell. Neither can carry an archive.
- **Shrink the security surface rather than move it.** The closed write-target
  set loses a member; nothing gains one.

## Considered Options

### What surface replaces the record as the fully-folded-chain evidence

**Named: the roadmap feature's downstream cell, with its limits stated.**
The cascade already writes that cell, the repository controls it, and it is the
only surviving on-branch surface that distinguishes a folded chain from one that
never ran. Its limits are stated in the same passage rather than elided: a chain
that came through no roadmap feature has no cell, and the cascade deletes the
roadmap once its features land.

*The merged pull request's body* was the closest loser and would have narrowed
the residual furthest, because a forge retains PR refs and bodies indefinitely.
It was rejected on a chain of three findings. `/scope` Phase 3 writes
`chain_ran`, `chain_skipped` and `consolidation_judgments` into an unspecified
part of the body; the merge dialog is human-editable and one of five sampled
merged PRs silently lost 184 of 622 bytes through it; and `/execute` re-authors
the body at finalization with no preservation clause. Naming it honestly would
require pinning the section in `/scope` and adding a preservation clause to
`/execute` — a real change to two skills, beyond replacing a prose claim, and a
conscious call rather than a side effect. It also names forge metadata, which
this design records as a rejected carrier.

*Asserting nothing* — stating that the two cases are indistinguishable on disk
and treating both as complete — is what the guard already does behaviorally, and
it narrows the residual by zero. It was rejected as under-informative rather than
wrong: the roadmap cell genuinely does distinguish the cases while it exists, and
declining to say so discards real information.

### What the roadmap downstream cell says

**Chosen: `**Downstream:** _none (chain folded)_`.** The pointer is deleted and
nothing else changes. It satisfies both halves of the governing criterion — no
record reference, and "chain folded" is a phrase no author writes into a
never-ran cell, where the corpus forms are a named in-flight PLAN or `Needs PRD`.

*Naming the folded artifact* (`chain folded into PLAN-<slug>.md, deleted`) was
rejected twice over. The emitting branch fires precisely when the artifact path
variable is empty, so the name is not in scope at emit time; and the existing
test asserts a negative `PLAN-|DESIGN-` regex on this cell, so naming an artifact
is a decision to weaken the guard that exists to stop this cell from carrying a
dangling pointer — the exact defect the record's removal is correcting.

*Pointing at the PR or squash commit* is not reachable at emit time and inherits
the same forge-metadata objection.

### What the Option D amendment states

**Chosen: name what carries the withdrawn half, and state where nothing does.**
The original objection to absorbing a DESIGN into a PLAN was that it "trades a
durable audit trail for a shorter run and loses the record of why the work
happened," and the design records it as *answered rather than overruled*. The
answer had two halves. The half recording *why* — kept in the code, as a standing
`/work-on` instruction — survives untouched and is stronger than its one-line
summary suggests: `skills/work-on/references/phases/phase-4-implementation.md`
states it unconditionally and says it holds "regardless of what documents the
work leaves behind." The half recording *what happened* is withdrawn with the
record, and the amendment says what replaces it: the survivor's `absorbed:`
declaration for every hop that leaves one, the roadmap cell conditionally and
temporarily, and nothing at all for a PLAN the cascade deletes.

*Withdrawing without restating* fails the requirement and makes the design's own
"answered rather than overruled" sentence false about itself.

*Re-justifying Option D on new ground* exceeds scope. Option D's reversal stays
shipped; only its supporting argument loses a premise.

### Carriers evaluated and rejected

Recorded here so a later proposal to reintroduce a fold ledger is answered from
this document rather than by re-investigation.

| Carrier | Why not adopted |
|---|---|
| Survivor frontmatter alone | Already adopted and unchanged — it is the carrier this removal relies on. It is listed here because it does not cover the case where the last survivor is itself deleted, which is the residual, and no variant of it can. |
| Commit trailer on the squash commit | Verified to survive squash-merge and parse. Rejected because the squash commit does not exist until the merge button is pressed, so a pull-request-triggered check cannot assert the trailer will be there, and the merge dialog is human-editable. |
| git notes | Verified not fetched by `git clone`, rendered nowhere by the forge, separately mutable from the commit they annotate, and requiring an explicit refspec. Every cost is paid before anything is delivered. |
| Per-chain file retired at finalization | Inverts the requirement. Retiring the file at finalization destroys the evidence at exactly the moment the fully-folded case needs it, because finalization is when the chain folds to nothing. |
| Forge metadata (PR body, labels, comments) | Not in the tree, so absent from a clone; freely editable after the fact; unavailable to a non-forge-hosted adopter; and measured to lose content silently through the merge dialog. |
| Rotation or pruning | Needs an escape hatch in the append-only assertion, and any exemption a rotation commit can claim a row-deleting commit can also claim. Union merge preserves no row order, so positional truncation is not implementable. |
| Per-fold file (`docs/folds/<date>-<slug>.md`) | Structurally the strongest: conflict-free, no merge driver, simpler append-only assertion, and it dissolves the adopter gap. Rejected because it preserves a guarantee this work concluded is not worth its cost, not on its mechanics. If a future author reopens this question, this is the option to reopen it with. |

## Decision Outcome

Delete `docs/folds.md` and every mechanism that exists only to serve it: the
append step in the absorb procedure, the fold-record verification step in the
shared validation workflow, the `merge=union` attribute, the citation-search
exclusion, and the cleanup carve-out.

Replace rather than delete the two prose claims that cite the record, pointing
both at the roadmap downstream cell and stating its limits in the same passage,
so `/execute`'s rule and the cell itself give one answer. Correct the comments
that name the record without spelling its path, reducing the stated reader count
from three to two. Rewrite the eval fixture to describe the procedure that then
exists. Amend seven shipped documents in place with dated sections.

The residual — a chain that folds to a PLAN the cascade later deletes leaves
nothing on the default branch — is accepted and stated in three places: this
design, the PRD's Known Limitations, and the amendment to the consolidation
design. It is not carried by any invented surface.

## Solution Architecture

The change has five groups. They are independent except where noted.

**Group 1 — delete the record and its dedicated machinery.** `docs/folds.md`;
the `merge=union` line and its comment block in `.gitattributes`; the
`Verify the fold record` step in `.github/workflows/validate-docs.yml`; the
`--record` flag, its default, its path-shape assertion and both grep-tier
exclusions in `skills/scope/scripts/check-citations.sh`, with the matching case
in `check-citations_test.sh`; and the carve-out in
`skills/scope/references/phases/phase-4-cleanup.md`.

**Group 2 — renumber the absorb procedure.** In
`skills/scope/references/phases/phase-2-chain-orchestration.md`: remove the
append step, taking nine steps to eight; drop the append row and the two
un-append cells from the rollback table; drop the standalone paragraph
justifying the un-append; remove `and the record` from the final commit step's
object list; and correct the partial-absorb resume paragraph's step range. In
`skills/scope/SKILL.md`: correct the cross-reference that states the step count
and enumerates the procedure's parts, and the `absorb` verdict definition, which
must still state what the verdict ends with. In
`skills/scope/references/phases/phase-3-exit-finalization.md`: drop the append
group from the read-back and correct the sentence stating how many groups the
absorb adds.

**Group 3 — replace the two prose claims.** `skills/execute/SKILL.md`'s
fully-folded rule names the roadmap cell and states what a reader observes when
there is no roadmap feature or the roadmap has been deleted.
`skills/execute/scripts/run-cascade.sh` emits `_none (chain folded)_`.
`README.md` describes the consolidation judgment without naming the record.
`docs/guides/doc-validation.md` drops the fold-record section. Group 3's two
`/execute` edits must land together — they are the one-answer constraint.

**Group 4 — correct the non-path references.** The `ABSORBED_ENTRY_PATTERN` doc
comment in `crates/shirabe-validate/src/formats.rs` and the matching comments in
`.github/workflows/check-scope-scripts.yml` and `check-citations.sh` describe two
readers rather than three: the absorb procedure as the gate, and the crate's
absorbed-declaration check as the backstop. The record checker's fold signature
was the third and is deleted with the workflow step.
`contribution_heading`'s doc comment drops the durable record column, leaving the
required-section splice as its sole consumer. `skills/scope/evals/evals.json` is
rewritten to describe the eight-step procedure, retaining its assertions that the
deletion precedes re-validation, that re-validation precedes the commit, and that
the deletion, splice and survivor edits land together.

**Group 5 — amend seven shipped documents.** Each gains a
`## Amendment — <date>` section, with the separator being U+2014 EM DASH, the
pinned opening formula, and the fixed sentence "The original text above is left
unedited; this section records what no longer holds." Each retains its current
status; no lifecycle transition is performed, and a requirements document has no
superseded state in any case. The amendment to
`DESIGN-scope-consolidation-over-skipping.md` carries the Option D restatement
and is the only one whose body is not a straightforward withdrawal.

## Implementation Approach

Groups 1, 2, 4 and 5 are independent and can land in any order. Group 3 has an
internal ordering constraint only.

1. **Group 1** first, because deleting the record is what makes every other
   group's correction true rather than anticipatory.
2. **Group 2** and **Group 4** next, in either order.
3. **Group 3**, with the two `/execute` edits in one change.
4. **Group 5** last, so each amendment describes a change that has landed.
5. Verification: the two shell test suites, `cargo test`, the document validator
   over the changed set, and the two inventory sweeps.

The whole change is one pull request. Nothing here is independently shippable —
a partial landing leaves the corpus asserting a record that is gone, or a record
that is present with its machinery half removed.

## Security Considerations

**The closed write-target set shrinks.** `/scope`'s enumerated write targets lose
their only append member. Every remaining path is composed from the validated
topic slug or is a fixed constant, so the set stays closed and enumerable and is
strictly smaller. No new write target is introduced.

**The citation preflight's argument validation must survive the flag removal.**
`check-citations.sh`'s `--record` handling sits inside a security-reviewed
argument-validation block, and the path-shape assertion being removed guards a
value that reaches a git pathspec. Removing the flag must not disturb the
validation applied to `--target` and `--survivor`, which reach the same
machinery. This is the only place in the change where a deletion could weaken a
control by accident, and it is the reason Group 1 is not purely subtractive.

**An enum re-validation loses its stated reason and must keep the control.**
`phase-2-chain-orchestration.md` justifies re-validating `verdict:` and `stage:`
against their enums on the ground that both are serialized into the durable fold
record. That justification goes with the record. The control must not: the values
still reach the survivor's `## Status` absorption line, which is a durable
committed surface, so the re-validation is re-justified rather than removed.
Deleting the clause without replacing it would leave a security control with no
stated reason, which is how controls get removed later by someone tidying.

**No new interpolation site and no new untrusted input.** The change removes a
file, a workflow step, a flag and prose. It introduces no new argument, no new
path composition, and no new value reaching a shell command.

**The removal cannot break an adopting repository.** Removing a check from a
reusable workflow is backward-compatible for pinning callers — it can only stop
failures, never start them. Adopters currently inherit the fold check without the
merge attribute that mitigates its concurrency cost, so the removal strictly
improves their position.

## Consequences

**Positive.** The shared write point is gone, so parallel chains no longer
contend, rebase, or fail validation because a sibling folded first. Adopting
repositories stop inheriting a check they were never given the means to satisfy.
Four defects in the fold-record checker — a trigger that cannot fire on the fold
shape it exists for, a skip-guard that never skips, a column-blind row lookup,
and duplicate detection promised in three documents and implemented in none — are
deleted rather than repaired. The corpus stops asserting seven documents' worth
of rationale for a mechanism that is gone.

**Negative, and accepted.** A chain that folds to a PLAN the implementation
cascade later deletes leaves nothing on the default branch recording that it ran.
The roadmap cell narrows this to chains with no roadmap feature, and narrows
further to a window rather than a permanent record, because the same cascade
deletes the roadmap once its features land. This is the residual named in three
places and carried by none.

**Negative, and accepted.** Two of the seven amended documents will carry two
dated amendment sections, which is correct and reads oddly on first encounter.

**Mitigation.** The rejected-carrier table above is the mitigation for the
residual's re-proposal risk: a later author who notices that folds leave no
central ledger finds the reasoning and the measurements here rather than
re-deriving them. The per-fold-file row is written to be the entry point if the
question is genuinely reopened.
