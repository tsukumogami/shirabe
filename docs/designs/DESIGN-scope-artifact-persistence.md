---
schema: design/v1
status: Proposed
problem: |
  `/scope`'s consolidation judgment decides absorbability by comparing two type
  schemas, so above the first hop its verdict is fixed before either document is
  read. The mechanism below that verdict has never completed a run, and six
  defects in the surrounding machinery — including a state field that is gated on
  but never written, and a write-target set that encodes the very floor being
  removed — mean the feature has no sound ground to build on until they are
  repaired.
decision: |
  The type test and its mapping table are deleted. The position they occupied
  becomes a citation preflight — mechanical, type-blind, able to return only
  `keep` or "proceed" — and the run-ownership scoping moves out to the judgment's
  firing condition. Survivors declare what they absorbed in an `absorbed:`
  frontmatter list, which splices contribution sections into the existing
  required-sections seam and is enforced by one new error-level check. Every
  completed fold appends a mechanically-written row to a shared `docs/folds.md`
  index before anything is deleted.
rationale: |
  Deleting the stage outright was the serious rival and lost on one point: it
  relocates the type-shaped attractor to the head of the content stage, which is
  the only stage that can return `absorb` and where no ceiling applies. Every
  other placement of the record was disqualified by the ruling that it must
  persist on the default branch, because this repository merges a whole chain as
  one squash and any record living inside a chain document leaves with it.
upstream: docs/prds/PRD-scope-artifact-persistence.md
user_visible_surface: true
---

# DESIGN: Scope Artifact Persistence

## Status

Proposed

Six decision questions were settled before this document was written; two ran the
full adversarial path with five persistent validators each. Their reports are the
authority for the reasoning summarized here.

## Context and Problem Statement

`/scope`'s consolidation judgment is the only thing in the tactical chain that
reduces the artifact set, and it runs as three stages at each hop after a child
lands. Stage 1 asks whether absorption is possible, Stage 2 whether it is
warranted, Stage 3 performs the move and verifies it.

Stage 1 is a comparison between two type schemas. It looks the hop up in a
hand-maintained table and asks whether the downstream *type's* required sections
have a home for every required section of the upstream *type*. Neither document
is opened. Against the section lists in `formats.rs` the answer is yes for
BRIEF-to-PRD and no everywhere else, on every run, forever.

The consequence is that Stage 2 — the only stage that reads the documents, and so
the only one whose answer can vary — never runs above the first hop. The verdict
is `keep`, decided before either document exists, regardless of whether the
DESIGN in question carries contested architecture or restates what the PLAN
already encodes.

Six things about the surrounding machinery were verified during the decision
phase, and together they change what this work is.

**The absorb has never completed a run.** No BRIEF has ever been deleted in this
repository's history — `git log --diff-filter=D` over `docs/briefs/` returns
nothing across every commit. The one absorbable hop has been reached twice, on
#260's own dogfood run and on this chain, and refused both times on the same
section. Every code path under the verdict is untested.

**The mapping table's provenance claim is false.** It says the verdicts are
"derived from the per-type required-section contracts in `formats.rs`, not
enumerated by hand." There is no mapping structure anywhere in `crates/`; every
semantic edge in the table is authored prose, and the table silently drops
`Status` from the BRIEF's five required sections. Its re-derivation instruction
has never been runnable.

**Non-adjacent hops are reachable and undefined.** Re-entry protection combined
with four children yields `brief->design`, `prd->plan` and `brief->plan`. A
shipped eval produces `brief->design`, and the table has no row for it — an
absent row is neither total nor not-total, so the procedure has no defined next
action.

**A field the judgment needs is written nowhere.** `chain_ran:` is defined in the
state schema and read in four places by Phase 3: the hard-finalization check
gates on it, the PR-body record copies "every artifact in `chain_ran:`", the bail
tie-break reads per-child start timestamps out of it, and `plan_execution_mode:`
presence is conditioned on it. No instruction in any `/scope` phase file appends
to it.

**The write-target set is wrong in three ways, and one of them encodes the
defect.** It scopes the judgment's deletion to `docs/briefs/` alone — the
type-level floor, written into the security surface — so an absorb removing a PRD
or DESIGN would fail the hard-finalization check for a reason unrelated to
safety. It gates `docs/{briefs,prds,designs}/` writes on `abandonment-forced`
only, so the existing `upstream:` re-point's mutation of the survivor is already
outside the enumerated set. And `SKILL.md` and the Phase 3 reference disagree
about whether the PLAN is a Phase 3 write target.

**Nothing commits the absorb's output.** `/scope` has no `git add` anywhere, and
its only `git commit` is on the decision-record path. A completed absorb leaves a
staged deletion, an unstaged working-tree edit for the re-point, and nothing that
commits either.

Two further facts bound the solution space. Whether the PLAN ever reaches the
default branch depends on a workflow choice the chain does not control:
`/execute` adopts an existing `docs/<topic>` scoping PR when it finds one, and on
that path the chain, the implementation and the cascade's deletion are one squash
merge; on the older path the chain merges separately and the PLAN does land, as
six have. And the failure mode an absorb can cause is invisible to CI by
construction — `validate-docs.yml` computes its file set with `git diff`, so a
document stranded by a deletion is not a changed file and the reference check can
never fire on it. Fold time is the only catchable point in the system.

## Decision Drivers

- **Nothing may judge an artifact before that artifact exists.** This killed a
  previously-shipped feature and is the constraint every alternative was measured
  against first.
- **One reduction mechanism, not two.** A mechanism whose sole possible effect is
  to force `keep` does not count as a second one. That distinction is what admits
  the preflight and the carry check — and, as the design found, what fails to
  forbid a floor guard.
- **Fail toward `keep` at every added decision point.** A wrong `keep` costs a
  document that stayed; a wrong `absorb` costs content with no recovery path from
  a clone.
- **Existing documents are not this change's business.** Added checks are silent
  on documents declaring no absorption. Where an existing document carries a
  defect this work surfaces, the finding stands and the cleanup is sequenced
  follow-on work; pre-existing breakage is not a reason to narrow a correct check.
- **Prefer the seam that exists.** `required_sections_for` is already the one
  function both the presence and order checks consult; the abort path already
  downgrades to `keep` and deletes nothing; `shirabe transition` already writes a
  lineage key and splices a `## Status` line.
- **The verdict is the agent's; the operation is the machine's.** Whether content
  is worth keeping gets no gate. Whether a section is present, a citation exists,
  or a record was written is checked mechanically and fails closed.

## Considered Options

Six decision questions were evaluated. Each report carries its full alternative
set; what follows is the losing option that came closest, and why it lost.

**What replaces the first stage.** *Full dissolution* — delete the stage, leaving
the content question plus the carry check — was the serious rival and lost on one
argument. Deleting the stage does not remove the attractor that filled it once
already with a hand-authored type table carrying a false provenance claim; it
relocates that attractor to the head of the content stage, which is the stage
that *can* return `absorb` and where no ceiling applies. A type-shaped shortcut
is worse there, not better. Dissolution also drops the recorded first-stage
`keep` that Phase 3's PR-body record and a shipped eval both consume. Two other
alternatives — an eligibility precondition, and a mechanical pre-filter defined
by output algebra — were withdrawn by their own advocates during
cross-examination.

**What surface carries the fold record.** *The survivor's frontmatter*, alone or
hybridized with an index, is genuinely immune to the cross-hop citation problem
and was the closest loser. It fails because the record dies with the document at
the next hop, and because the terminal fold has no survivor at all — so a hybrid
builds the index anyway and is therefore the index plus a second producer, format
and reader location for one requirement. *The PR body's durable half* was not
killed by the three obvious objections but by fidelity: byte-comparing five real
merged PRs, one silently lost 184 of 622 bytes through the human-editable merge
dialog, and the lost paragraph was a tree-state attestation — exactly this
record's genre.

**Who authors a contribution section.** *The child at drafting time* was
eliminated by requirements rather than outscored: the judgment is the last step
of the invocation loop, so a child cannot know the verdict when it drafts, and
every `keep` run would leave an orphan section nothing sanctions. *The parent
authoring from the doomed original* has the same single unreviewed authoring site
but makes omissions unrecoverable after the delete.

**How the validator represents contributions.** *A keyed map per absorption
combination*, generalizing the existing per-mode precedent, produces a
combinatorial explosion: one key per reachable combination per profile, each a
copy of the base list, drifting from it the first time a required section
changes. *Adding contributions to the base required lists* was ruled out earlier
still — it would put error-level failures on every existing DESIGN.

**Where the citation guard lives.** *Skill prose alone* leaves the exclusion set
untestable, and the exclusion set is the difference between a guard and a total
fold-blocker. *Wiring the existing referrer map* covers 28% of path-citing lines,
because it indexes only `upstream:` frontmatter edges and is blind to prose,
skill, code and CI citations — the classes that have actually broken.

**Whether prior artifacts are amended.** *Leaving them* was rejected because no
mechanism makes recency discoverable, and this chain's own reference list points
a reader directly at the falsified reasoning. *Superseding them* via the
lifecycle overcorrects, discarding real unaffected content across a document
whose other decisions are sound.

## Decision Outcome

### The judgment

The type test and the mapping table are deleted. The position survives, renamed
for what it now does.

**Firing condition (outside the judgment).** The judgment fires only when both
endpoints of the edge the run drew were produced by this run, read from
`chain_ran:` membership. When it does not hold there is no hop, no judgment entry
and no verdict — a held-back artifact was never a party to a judgment, and
`chain_skipped:` already records why it was held back. The justification is not
caution about loss but well-posedness: the content question presupposes the
downstream could have incorporated the upstream, and where it never read it,
absence is evidence of nothing. Non-adjacent hops therefore never compose, rather
than composing and being refused, which is what keeps the rule clear of the
requirement that no hop be unabsorbable because of its types.

**Stage 1 — citation preflight.** Its sole content is the citation search, moved
here from the end of the absorb. It searches git-tracked files, excluding `wip/`,
the survivor of this fold, and `docs/folds.md`, for citations of the artifact
that would be deleted. A path hit downgrades to `keep` through the existing abort
path; a bare-name hit is carried forward as a finding. It returns exactly two
things and opens neither document.

**Stage 2 — the content question.** Does the upstream hold anything beyond its
contribution that compression would lose? The judging agent's call, at every hop
including the terminal one. No reviewer, no confirmation, no mode-conditional
gate.

**Stage 3 — compose, verify, move.**

**Two structural clauses bound the judgment.** A stated ceiling: the preflight
cannot reach any outcome stronger than `keep`. And an input restriction: *no
check in the judgment may read either type's required-section list, or compare
the two types' section sets.* Chain position and provenance are admissible
inputs; a type's content contract is not. The test for a violation — a condition
that refuses one pair while permitting its structural twin under identical
repository state is a type rule. The restriction is written at the head of the
content stage as well, because that is the stage that can return `absorb`.

### Contributions

Each artifact type declares one contribution. A survivor carries each absorbed
ancestor's contribution as one section, immediately after `## Status`, in chain
order, composed by the parent at fold time and **sourced from the survivor's own
body** rather than from the document about to be deleted. That sourcing is what
makes single-site authoring tolerable: the material was already reviewed when it
landed in the survivor's ordinary sections, and an under-distillation leaves the
omitted content still visible in the survivor rather than gone at the delete.

Each child below an absorbable hop carries the instruction that puts the material
into the survivor in the first place.

### Declaration and enforcement

A survivor declares what it absorbed in `absorbed:`, a scalar or sequence of
repo-relative paths read through the same normalizer `upstream:` uses. The
absorbed type is derived from the basename prefix. The list is flat and complete
— a survivor's list is its ancestor's list plus the ancestor — because the
frontmatter parser cannot hold structure, and because flat keeps transitive
accumulation linear.

`required_sections_for` gains a second branch beside the existing one, splicing
the implied contribution headings in immediately after `Status`. Every format's
required list begins with `Status`, so the splice point is well-defined with no
per-format special case, and a document with no `absorbed:` key gets the base
list unchanged.

One new error-level check, gated entirely on `absorbed:` being present, owns what
the order check structurally cannot say — that check compares only relative order
and permits unrequired sections between, and is notice-level behind a promotion
seam waiting on a corpus cleanup.

### The record

Every completed fold appends one row to `docs/folds.md`, created on first append,
written mechanically. The row carries a date, the absorbed artifact's path, the
survivor or `none` at the terminal fold, the verdict, a serialization of the
carry check's section names and outcomes — never section text — and the blob hash
of the pre-fold original, recomputed at fold time rather than promoted from the
existing snapshot, which is captured post-invocation and can differ from the
bytes actually deleted.

The record is of the operation, never the distillate. Any destination preserving
absorbed content must assert, every time it fires, that the verdict was partly
wrong.

## Solution Architecture

### The absorb, in order

1. **Citation preflight.** Nothing mutated; a refusal is a pure abort.
2. **Content question.** Verdict `keep` or `absorb`.
3. **Compose the contribution** from the survivor's body.
4. **Carry check** against the text step 3 wrote, never a prediction. Any
   non-carry aborts to `keep` and deletes nothing.
5. **Splice `upstream:`**, preserving sibling and cross-repo parents, and write
   the survivor's `absorbed:` declaration and `## Status` line.
6. **Append the row and `git add`** it, before anything is deleted, so a failed
   append aborts with nothing lost.
7. **`git rm`** the absorbed artifact.
8. **Commit** the deletion, the re-point, the survivor's edits and the record
   together.

Step 6 before step 7 is what makes fail-toward-`keep` structural rather than
procedural at the record.

### Components

| Component | Change |
|---|---|
| `crates/shirabe-validate/src/formats.rs` | A contribution table keyed by filename prefix, declared beside the required-section lists |
| `crates/shirabe-validate/src/checks.rs` | `required_sections_for` gains the contribution branch; one new error-level check with four clauses; the requirement-citation check scoped to the absorb event |
| `skills/scope/scripts/` | The citation search as a tested script with a pinned exclusion set, plus its co-located test |
| `skills/scope/references/phases/phase-1-discovery.md` | The Durable-Artifact Floor section replaced and relocated |
| `skills/scope/references/phases/phase-2-chain-orchestration.md` | The judgment rewritten: mapping table deleted, preflight added, firing condition bound to `chain_ran:`, absorb steps re-ordered, `chain_ran:` write site added, floor prohibition sited here |
| `skills/scope/references/phases/phase-3-exit-finalization.md` | Write-target set amended and its three defects corrected |
| `skills/scope/references/phases/phase-4-cleanup.md` | Carve-out so the record file is enumerated but never swept |
| `skills/scope/references/state-schema.md` | `absorbable:` retired for a stage discriminator; `chain_ran:` entries carry timestamps |
| `skills/{prd,design,plan}/references/phases/` | Child consumption instructions — one amended, two new |
| Four format references | Contribution contract with its two-sided adequacy test; content-boundary carve-out for the absorbed case in three of them |
| `.github/workflows/validate-docs.yml` | Deletion-driven record checker, triggered on a fold signature |
| `.gitattributes` | One line so concurrent appends merge cleanly |
| `docs/guides/doc-validation.md` | The new check family documented |
| `skills/scope/evals/evals.json` | Three scenarios rewritten; absorb and keep coverage added above the first hop |
| Two shipped documents | Appended dated amendment sections |

### What `/execute` needs

Its finalization guard must stop assuming a surviving DESIGN, and the cascade's
roadmap downstream rewrite must handle the no-DESIGN case rather than falling
through to a bare print that leaves a dangling reference. The record surface
requires no `/execute` change at all.

## Implementation Approach

Four phases, ordered so nothing depends on something unbuilt.

**Phase A — repair the ground.** The six pre-existing defects: the `chain_ran:`
write site, the write-target set's three errors, the unspecified commit, and the
`absorbable:` field's retirement. None of these depend on the feature, and the
feature is unsound without them.

**Phase B — the validator.** The contribution table, the required-sections
branch, the new check, and the scoped citation check, with fixtures updated in
the same commits. This is the half with mechanical tests.

**Phase C — the procedure.** The judgment rewrite, the preflight script and its
test, the absorb re-ordering, the record and its checker, the floor prohibition,
and the child consumption instructions.

**Phase D — surrounding.** `/execute`'s two assumptions, the implementation
rationale instruction, the eval rewrites, the guide, and the two amendments.

## Security Considerations

The change touches an enumerated security surface, and the amendment is explicit
rather than a quiet widening. `/scope`'s closed write-target set gains one append
target and one corrected deletion target; the record's path is a fixed constant
with nothing interpolated, which is stronger against injection than the
slug-composed paths already in the set.

Three surfaces are strengthened rather than weakened. The deletion target was
previously scoped to a single directory by an assumption rather than a
constraint; naming the real set makes the enumeration honest. The existing
survivor mutation was already outside the set and is now inside it. And the
citation preflight is a new refusal path with no override and no outcome stronger
than `keep`, so its failure mode is a document that stayed.

The preflight's search is the one new execution surface. It runs over
git-tracked files with a pinned exclusion set and a composed repo-relative path;
the path is derived from the validated topic slug rather than from author input,
and the search cannot write. Its fail-safe is to abort to `keep` when the search
cannot complete, which is observable rather than inferred.

The record contains no document content by construction — section names and
outcomes, never section text — so it cannot become a channel for content a
visibility rule would otherwise govern. Cross-repo absorbed paths are rejected by
the new check rather than resolved.

No new runtime dependency, no external URL, no credential, and no untrusted input
reaches an emitted command.

## Consequences

**Positive.** A run's artifact set reflects what the run produced. The mechanism
this feature extends stops being untested in its repairs, which is a
precondition for trusting any of it. Six latent defects are fixed, including one
where the hard-finalization check gates on a field nothing writes. And the
deletion failure mode that CI structurally cannot see acquires the only guard
that can catch it, at the only point where it is catchable.

**Negative, and accepted.** The guard bites hard on today's corpus: a substantial
share of candidate pairs carry a genuine third-party citation and will fold to
`keep`. `/scope` can block itself, because its own decision-record templates
write durable files citing artifact paths into a tracked directory. Both are
correct under fail-toward-`keep` and both are designed outcomes rather than
accidents.

**The central behaviour is graded, not gated.** The fold-versus-keep
discrimination is verified by an eval that is LLM-graded, grades a stated plan
rather than an executed fold, and runs on a weekly cron. The honest upgrade
exists and is deliberately out of scope.

**Static validation buys presence, not fidelity.** An empty contribution section
satisfies the check. The residual gaming vector is omission, which the folding
agent cannot see because it created the absence.

**One contested point, recorded as contested.** Whether a reverted absorb removes
its record row or marks it went 3-2, with the two principals swapping sides. This
design takes removal, on the grounds that the record's own criterion is scoped to
a completed fold and the row is uncommitted at that point. The cost is a checker
assertion that removal forecloses. Either way the un-append must be specified,
because the row is forced to exist before the deletion.

**A coupling the plan inherits.** The record checker triggers on a fold signature
rather than on deletion, because a real merged commit in this history removes
superseded roadmaps with no fold involved, and a naive check would fail ordinary
housekeeping in every repository pinning the reusable workflow.

## References

- `docs/prds/PRD-scope-artifact-persistence.md` — the requirements this design
  implements.
- `docs/briefs/BRIEF-scope-artifact-persistence.md` — the framing.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — Decision 8
  rejected the terminal fold and Decision 9 rests on the deleted test; both are
  amended by this work.
