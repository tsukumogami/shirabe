---
schema: design/v1
status: Planned
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
  index before anything is deleted, and the absorb re-validates the survivor and
  reverts in full if that fails.
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

Planned

Six decision questions were evaluated before this document was written; two ran
the full adversarial path with five persistent validators each, and all six were
decided in `--auto` mode without author confirmation. Their reports were working
artifacts and do not survive this chain; the reasoning that survived them is
carried in Considered Options and Decision Outcome below, which is the reason
those sections state each losing option's own strongest form rather than
summarizing it.

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
type-level floor, written into the security surface. It gates
`docs/{briefs,prds,designs}/` writes on `abandonment-forced` only, so the
existing `upstream:` re-point's mutation of the survivor is already outside the
enumerated set. And `SKILL.md` and the Phase 3 reference disagree about whether
the PLAN is a Phase 3 write target.

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
  function both the presence and order checks consult, and the abort path already
  downgrades to `keep` and deletes nothing. Where this design borrows a *shape*
  without extending its mechanism, it says so.
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
that *can* return `absorb` and where no ceiling applies. Its advocate held at
0.85 and contributed the round's most useful finding on the floor prohibition,
and its strongest counter — that a type check reads as idiomatic inside a
pre-filter and jarring at the top of a stage contracted to read both bodies — has
enough force that the input restriction below is written at *both* positions
rather than only at the preflight. *The mechanical pre-filter* alternative was
withdrawn as a distinct option by its own advocate, who called it "an ordering
claim wearing a stage's clothes"; its two clauses, the stated ceiling and the
input restriction, are adopted here and are its contribution rather than this
design's. *The eligibility precondition* was withdrawn after conceding its scoping
to the firing condition and then dropping both its preconditions as duplication.

**What surface carries the fold record.** *The survivor's frontmatter*, alone or
hybridized with an index, is genuinely immune to the cross-hop citation problem
and was the closest loser. It fails because the record dies with the document at
the next hop, and because the terminal fold has no survivor at all — so a hybrid
builds the index anyway and is therefore the index plus a second producer, format
and reader location for one requirement. *The PR body's durable half* was not
killed by the three obvious objections, which its advocate explicitly declined to
kill it on, but by fidelity: byte-comparing five real merged PRs, one silently
lost 184 of 622 bytes through the human-editable merge dialog, and the lost
paragraph was a tree-state attestation — exactly this record's genre.

**Who authors a contribution section.** *The child at drafting time* was
eliminated by requirements rather than outscored: the judgment is the last step
of the invocation loop, so a child cannot know the verdict when it drafts, and
every `keep` run would leave an orphan section nothing sanctions. *The parent
authoring from the doomed original* has the same single unreviewed authoring site
but makes omissions unrecoverable after the delete.

**How the validator represents contributions.** *Splice only, no new check code*
was the minimal answer and satisfies the presence and order requirements as
written; it lost because the adjacency contract — contributions immediately after
`## Status` — would go unchecked, since the existing order check compares only
relative order and sits behind a promotion seam that keeps it at notice level. *A
standalone check owning presence, order and adjacency together* has the smallest
blast radius on shared code and lost to the splice because the requirement asks
for the *existing* order check to enforce placement, and because a second presence
checker beside `required_sections_for` is the parallel mechanism this design's
drivers rule out.

**Where the citation guard lives.** *Skill prose alone* leaves the exclusion set
untestable, and the exclusion set is the difference between a guard and a total
fold-blocker. *Wiring the existing referrer map* covers 77 of 271 path-citing
lines, because it indexes only `upstream:` frontmatter edges and is blind to
prose, skill, code and CI citations — the classes that have actually broken.

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
and no verdict.

This is **stricter than R2 as written**, and the design adopts it as a
refinement rather than an interpretation. R2's literal text — "only at a hop where
this run produced both documents" — is a necessary condition that permits
`brief->design`, which a shipped eval produces when re-entry protection holds the
PRD back. The second necessary condition is the edge: the upstream must be the
artifact this run handed the child as its invocation argument. Two validators
independently confirmed this is an addition. Its justification is not caution
about loss but well-posedness: the content question presupposes the downstream
could have incorporated the upstream, and where it never read it, absence is
evidence of nothing. Non-adjacent hops therefore never compose, rather than
composing and being refused, which is what keeps the rule clear of R1.

**Stage 1 — citation preflight.** Its sole content is the citation search, moved
here from the end of the absorb. It searches git-tracked files, excluding `wip/`,
the survivor of this fold, and `docs/folds.md`, for citations of the artifact
that would be deleted. A path hit downgrades to `keep` through the existing abort
path; a bare-name hit is carried forward as a finding. It opens neither document.

*Coverage bound, stated because the guard's reach is narrower than its
description suggests.* The preflight protects citers that pre-existed the run,
and structurally cannot protect a deletion target the run created — a document
written before the run cannot cite one created during it. Under the firing
condition every hop the judgment can reach has a run-produced upstream, so the
guard's live coverage is *same-run* citers: `/scope`'s own decision-record
templates, anything a child skill wrote citing the artifact, and the named
retroactive follow-on the PRD gates on this guard. The 15-of-36 measurement in
the decision report is over the pairs already on disk — the retroactive
population — and is not a forecast of live behaviour. The check is required
regardless; this states what it buys.

**Stage 2 — the content question.** Does the upstream hold anything beyond its
contribution that compression would lose? The judging agent's call, at every hop
including the terminal one. No reviewer, no confirmation, no mode-conditional
gate.

**Stage 3 — compose, verify, move, re-validate.**

**Two structural clauses bound the judgment.** A stated ceiling: the preflight
cannot reach any outcome stronger than `keep`. And an input restriction: *no
check in the judgment may read either type's required-section list, or compare
the two types' section sets.* Chain position and provenance are admissible
inputs; a type's content contract is not. The test for a violation — a condition
that refuses one pair while permitting its structural twin under identical
repository state is a type rule. Both clauses come from the withdrawn pre-filter
alternative. The restriction is written at the head of the content stage as well,
because that is the stage that can return `absorb`.

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

**The `## Status` absorption line has a pinned shape and a named owner.** The
shape is modelled on `shirabe transition`'s supersession splice, but the mechanism
is *not* extended: `transition.rs` writes its line in Rust with tests behind a
subcommand, while this line is written by the absorb procedure. Only the shape is
adopted. The new check therefore gains a fifth clause owning the line: when
`absorbed:` is present, a matching `## Status` line SHALL be present and
well-formed for each declared entry. Without that clause the pinned shape is
unenforced and the requirement's criterion has nothing behind it.

### The record

Every completed fold appends one row to `docs/folds.md`, created on first append,
written mechanically. The row carries a date, the absorbed artifact's path, the
survivor or `none` at the terminal fold, the verdict, a serialization of the
carry check's section names and outcomes — never section text — and the blob hash
of the pre-fold original, recomputed at fold time rather than promoted from the
existing snapshot, which is captured post-invocation and can differ from the
bytes actually deleted. The serializer SHALL **reject** rather than escape any
value containing the field separator or a newline, routing to `keep`, so a
crafted path cannot forge a row boundary. Nothing can break a row today, because
every value is drawn from a closed vocabulary or a slug-composed path — but that
safety is inherited from the enum validations rather than stated, and closing the
`absorbed:` prefix gap is what makes it load-bearing.

The checker SHALL also assert that the record's hunk in a pull-request diff is
**additions only**. Union merge resolves silently with no conflict marker, so a
semantically odd file merges clean and rows are mutable in practice; the
pre-deletion append ordering is what makes an additions-only assertion sound.

The record is of the operation, never the distillate. Any destination preserving
absorbed content must assert, every time it fires, that the verdict was partly
wrong.

`docs/folds.md` is this repository's **first** shared append-only durable file and
its merge driver is the repository's first. There is no precedent to inherit, and
union-merge resolves a concurrent duplicate row silently rather than raising a
conflict. Rows are keyed by the pre-fold blob hash, so a cross-branch duplicate is
a duplicate of an identical fact, and the checker flags it — but this is a
residual, not a solved problem, and it is the one genuinely new mechanism in this
design.

## Solution Architecture

### The absorb, in order

Step 3 **composes in memory**; the survivor is not written until step 5. That is
what lets an abort at step 4 leave the survivor untouched, and it satisfies R13
because the carry check reads composed text that exists rather than a prediction
that text will be written.

1. **Citation preflight.** Nothing mutated; a refusal is a pure abort.
2. **Content question.** Verdict `keep` or `absorb`.
3. **Compose the contribution** from the survivor's body, in memory.
4. **Carry check** against the text step 3 composed. It itemizes the ancestor's
   required sections *and* each contribution the ancestor carries — its own and
   any it inherited, read from the ancestor's `absorbed:` list and its
   contribution sections. Any non-carry aborts to `keep`.
5. **Snapshot the survivor's bytes, then write it**: capture the pre-fold bytes
   in memory first, because nothing has committed them and `git checkout HEAD --`
   is not guaranteed to resolve to them — `/scope` commits nothing before the
   fold. Then splice `upstream:` preserving sibling and cross-repo parents, write
   the `absorbed:` declaration, the `## Status` line, and the contribution
   section. Rewrite the survivor's own prose citations of the absorbed path,
   which the preflight's survivor exclusion deliberately does not protect and
   which become dangling the moment the fold lands.
6. **Append the row and `git add`** it, before anything is deleted, so a failed
   append aborts with nothing lost.
7. **`git rm`** the absorbed artifact.
8. **Re-validate the survivor.** This is the shipped procedure's step 4, retained
   rather than dropped. A non-zero exit triggers the revert below.
9. **Commit** the deletion, the re-point, the survivor's edits and the record
   together. A failed commit triggers the revert.

Step 6 before step 7 is what makes fail-toward-`keep` structural rather than
procedural at the record.

### Rollback

Every step from 5 onward mutates. Failure at any of them reverts everything
written since step 5, in reverse:

| Failing step | Undo |
|---|---|
| 5 (survivor write) | Restore the survivor from the snapshot step 5 captured before writing |
| 6 (append/stage) | Un-stage and remove the appended row; restore the survivor |
| 7 (`git rm`) | Restore the deleted artifact; un-append; restore the survivor |
| 8 (re-validate) | Restore the deleted artifact; un-append; restore the survivor |
| 9 (commit) | As step 8 |

The verdict is downgraded to `keep`, the revert is recorded in the state file's
judgment entry, and the run routes to bail-handling. The un-append is explicit
because the row is forced to exist before the deletion; without it a revert
strands a durable row asserting a fold that was undone.

### The preflight script's contract

The script's exit codes are **its own contract, not `git grep`'s**, which exits 0
on match and 1 on no-match — the inverse of the obvious reading. It translates
explicitly: `0` clean, `1` path-exact hits, `2` bare-name hits only, `3` search
did not complete. Stage 1's routing default is **any status other than 0 or 2
routes to `keep`**, including statuses the script does not define. Default-deny
rather than enumerate-and-hope, and a fixture pins the did-not-complete case.

### The amended write-target set

Enumerated rather than described, and declared in **both** sites the pattern
requires — `skills/scope/SKILL.md`, which is authoritative, and the Phase 3
reference, which must not diverge from it again.

- **Deletions (Phase 2 absorb):** `docs/briefs/BRIEF-<topic>.md`,
  `docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`. The PLAN is never
  a deletion target of a fold.
- **Mutations (Phase 2 absorb):** `docs/{prds,designs,plans}/{PRD,DESIGN,PLAN}-<topic>.md`
  — the survivor, at whichever hop. This includes `docs/plans/`, because at the
  terminal hop the PLAN *is* the survivor and receives four writes.
- **Append (Phase 2 absorb):** `docs/folds.md`, a fixed constant with nothing
  interpolated.
- **Phase 4:** a carve-out so the record file is enumerated but never swept.
- Force-materialization and Decision-Record entries unchanged.

Phase 3 still does not *write* the PLAN; Phase 2's absorb does. Both claims are
true once the phase is named, and the current wording is what makes them look
contradictory.

### Components

| Component | Change |
|---|---|
| `crates/shirabe-validate/src/formats.rs` | Contribution table keyed by filename prefix, beside the required-section lists |
| `crates/shirabe-validate/src/checks.rs` | `required_sections_for` gains the contribution branch; one new error-level check with five clauses; the requirement-citation check scoped to the absorb event |
| `skills/scope/SKILL.md` | Authoritative write-target set amended: deletion set, survivor mutation, append target, Phase 4 carve-out |
| `skills/scope/scripts/` | Citation search as a tested script with a pinned exclusion set and its own exit-code contract, plus its test |
| `.github/workflows/check-scope-scripts.yml` | New merge gate running that test, mirroring the plan and execute script gates |
| `skills/scope/references/phases/phase-1-discovery.md` | Durable-Artifact Floor section removed |
| `skills/scope/references/phases/phase-2-chain-orchestration.md` | Judgment rewritten; mapping table deleted; preflight added; firing condition bound to `chain_ran:`; absorb re-ordered with rollback; `chain_ran:` write site added; `chain_ran:` entries added to enum re-validation; floor prohibition sited here |
| `skills/scope/references/phases/phase-3-exit-finalization.md` | Write-target set amended to match SKILL.md and its three defects corrected |
| `skills/scope/references/phases/phase-4-cleanup.md` | Record-file carve-out |
| `skills/scope/references/state-schema.md` | `absorbable:` dropped; `chain_ran:` entries carry timestamps; `stage:` added (Phase C) |
| `skills/{prd,design,plan}/references/phases/` | Child consumption instructions — one amended, two new |
| `skills/work-on/references/phases/phase-4-implementation.md` | Rationale-in-code instruction |
| `skills/work-on/references/phases/phase-4b-review.md` | Maintainer reviewer's brief names it as blocking |
| `skills/execute/SKILL.md`, `skills/execute/scripts/run-cascade.sh` | Finalization guard and roadmap rewrite stop assuming a surviving DESIGN; `exit_artifacts:` contract for a fully folded chain stated |
| `skills/execute/scripts/run-cascade_test.sh` | No-DESIGN scenario asserting no dangling roadmap reference |
| Four format references | Contribution contract with its two-sided adequacy test; content-boundary carve-out in three of them |
| `.github/workflows/validate-docs.yml` | Record checker, triggered on a fold signature |
| `.gitattributes` | Union merge for the record file |
| `docs/guides/doc-validation.md` | New check family documented |
| `skills/scope/evals/evals.json` | Scenarios 18, 19 and 20 rewritten; absorb and keep coverage added above the first hop. **Scenario 17 is untouched** — it is the tripwire that catches a later maintainer reintroducing an entry-altitude shortcut, and rewriting it alongside its neighbours would remove the guard while the change that makes the shortcut look reasonable lands |
| Two shipped documents | Appended dated amendment sections |

### The contribution table is a mirrored constant, not a single source

Three things must agree: the `formats.rs` constant, the four format references,
and the heading string `/scope`'s Phase 2 composes when it writes the section.
Nothing enforces the agreement, and a drift produces a check failure at fold time
after the mutations. This duplication is house pattern — required-section lists
already live in both `formats.rs` and all eight format references with nothing
tying them — so this design does not fix it, but it names three mirrors rather
than pretending there is one source.

### What `exit_artifacts:` holds under a fully folded chain

Unchanged: the PLAN's path, as on any full-run exit. Folding does not empty the
list, because at the terminal hop the PLAN is the *survivor* rather than a
casualty — it is on disk when `/scope` exits, and only the implementation cascade
deletes it later.

This also forecloses a misreading in which the fully-folded contract is an empty
list. The hard-finalization check fails on an empty `exit_artifacts:` on all three
exit paths, and a fully folded chain never reaches zero at `/scope` finalization
— so that requirement and this contract do not collide.

The state the guard must handle therefore arises after `/scope`, not within it:
the cascade has removed the PLAN and no DESIGN survives to seed on. The contract
is that `/execute`'s finalization guard seeds on the chain's surviving durable
anchor where one exists, and where none does treats a fully folded chain as
*complete* rather than as a missing seed — which is the condition it reports today
as a false validation error. The record row is what a reader consults for such a
chain; it is not a seed.

### The record checker's trigger

The checker cannot fire on deletion alone: a real merged commit in this history
removes superseded roadmaps with no fold involved, and a naive check would fail
ordinary housekeeping in every repository pinning the reusable workflow. The
trigger is a **fold signature** — a chain-document deletion *plus* an absorption
declaration added in the same diff naming that path. That couples the record
check's trigger to the declaration, which is a dependency the plan must sequence.

What the checker proves is narrow and worth stating: that a row exists for a
deletion carrying a fold signature, and that the row's hash matches the pre-fold
blob. It does not prove the fold was correct, that the contribution carries, or
that the row was written by the procedure rather than by hand.

## Implementation Approach

Four phases. Two repairs are provisional by necessity and are marked as such.

**Phase A — repair the ground.** The `chain_ran:` write site and its timestamps;
the write-target set's three pre-existing errors in both declaration sites; the
unspecified commit; and dropping `absorbable:`. Two of these are **provisional**:
the write-target amendment is reopened in Phase C to add the record's append
target, and Phase A can only establish *that* a commit happens, since three of the
four things step 9 commits do not exist until B and C. The `stage:` discriminator
that replaces `absorbable:` is deferred to Phase C, because its values name stages
Phase C creates.

**Phase B — the validator.** Contribution table, required-sections branch, the new
check's five clauses, and the scoped citation check, with fixtures updated in the
same commits.

**Phase C — the procedure.** Judgment rewrite, preflight script and its merge
gate, the absorb re-ordering with its rollback, the record and its checker, the
floor prohibition, `stage:`, and the child consumption instructions.

**Phase D — surrounding.** `/execute`'s two assumptions and its `exit_artifacts:`
contract, the `/work-on` rationale instruction, eval rewrites, the guide, and the
two amendments.

## Security Considerations

The change touches an enumerated security surface. The amended set is enumerated
above rather than described, and is declared in `skills/scope/SKILL.md` — the site
the pattern contract names as authoritative — with the Phase 3 reference kept in
sync. The record's path is a fixed constant with nothing interpolated, which is
stronger against injection than the slug-composed paths already in the set.

**The firing condition now gates a deletion.** `chain_ran:` was bookkeeping and
is now the only thing standing between the judgment and a document the run did not
produce; a tampered entry puts a pre-existing document on the deletion path with
neither the preflight nor the firing condition covering it. Phase 2's existing
paragraph declining to re-validate chain-shape fields reasons entirely about
invocation redirection and does not extend to this, so it is rewritten rather than
left standing — as written it reads as a considered exemption. `chain_ran:` entry
names join the pre-interpolation re-validation list, validated against
`{brief, prd, design, plan}`; an out-of-enum or unparseable entry fails the firing
condition closed.

**The preflight is the new execution surface, and `--` is not the mitigation it
looks like.** Its two arguments are the deletion target's path and the survivor's
path. Both are composed from the validated topic slug rather than from author
input — verified across all four routes a path can take, and correct today — but
that safety is a property of the caller, not of the surface. Passing them after
`--` protects against a leading dash being read as an option; it does **not**
disable pathspec globbing, and these arguments are interpolated into the search's
exclusions. An exclusion of `docs/*` would blind the search across the tree, the
script would exit clean, and the fold would proceed. `-F` neutralizes regex in the
pattern, not globbing in the pathspec.

The script therefore asserts both arguments against
`^docs/(briefs|prds|designs|plans)/(BRIEF|PRD|DESIGN|PLAN)-[a-z0-9-]+\.md$` and
exits `3` — did-not-complete, routing to `keep` — otherwise. Its merge gate makes
this nearly free: the same fixture file, one more case. The script cannot write.

### The promoted-field category, closed by rule rather than by enumeration

This work takes several fields that previously only *recorded* and makes them
*decide*. Closing them one at a time invites a seventh argument for the next one,
because the re-validation list's scope sentence today reaches only path
interpolation. It is rewritten rather than extended:

> Every enum-typed or closed-domain field is re-validated against its domain at
> the read that precedes its use, where a use is: interpolation into an emitted
> command, construction of a write or delete path, a decision that gates a
> destructive operation, or serialization into a durable artifact.

That subsumes every member below, and the general rule behind the strictest of
them: **a gate that reads a list fails closed on a list it cannot fully parse,
because a partially-parsed list silently weakens the gate.**

**`absorbed:` is the strictest member, and the only one with a
fail-toward-`absorb` path.** This design gives it three load-bearing jobs: its
basename prefix selects a contribution heading spliced into
`required_sections_for`'s output; the carry check derives its itemization set from
the list; and the record checker's fold signature keys on it. A list that is
short — truncated, mis-parsed, or hand-corrected — makes the carry check itemize
*fewer* contributions and therefore pass *more* easily. That is under-declaration
weakening a gate, in the forbidden direction, on a hand-editable frontmatter key
of a tracked document that survives cleanup and merges to the default branch, and
it needs no adversary: a scalar written where a sequence was meant produces it.

Every entry is therefore validated at every read against
`^docs/(briefs|prds|designs)/(BRIEF|PRD|DESIGN)-[a-z0-9-]+\.md$` — in the absorb,
where an unparseable or unknown-prefix entry fails the carry check closed to
`keep` and never silently skips the item, and in the new error-level check as a
sixth clause.

**The sites are not equal, and the design ranks them.** The absorb is the
**gate** — the only site that can stop a deletion, running at fold time against
on-disk frontmatter. The error-level check is the **backstop** — it validates
document conformance, fires on documents nobody is folding including one
hand-edited long after a fold, and cannot see the fold at all. The record
checker's fold signature is the **trigger** — it pattern-matches a diff to decide
whether to demand a row, and validates nothing in a meaningful sense. None
substitutes for another; collapsing them loses coverage rather than duplication.
The ranking is written down so a later maintainer cannot relax the absorb's
validation to match the validator's without noticing they are relaxing the only
site that can prevent a deletion.

**Drift between the sites is contained, and this states the containment rather
than relying on it.** A stricter absorb than validator means some documents
validate but cannot be folded — fails toward `keep`, harmless. A looser absorb
means the fold proceeds on a list the validator rejects, the survivor is written,
and **step 8's post-absorb re-validation catches it and triggers the revert**.
That containment exists for other reasons and is what makes the duplication
tolerable; without saying so it is an accident of the ordering.

**One owner for the string, not for the behaviour.** The path shape is a named
constant declared beside the contribution table in `formats.rs`; the skill prose
and the workflow cite it by name rather than re-typing it, and a grep-based CI
assertion checks that each site's literal matches the constant. This is strictly
better than the contribution table's position, which cannot have such a test
because a table of headings is not a single string. A shared CLI surface is
explicitly *not* built: the citation-check decision already priced a new
subcommand and rejected it, because it enters a versioned multi-consumer contract
with cross-repo consumers pinning tags — a heavy price for a regex.

**A fourth reader lives inside the crate.** `required_sections_for`'s contribution
branch also reads `absorbed:`, to derive headings. If the splice runs against an
unvalidated entry the author gets two diagnostics for one cause, and the
misleading one — a missing required section — is the louder. The splice branch and
the new check share one parse, and an invalid entry produces only the entry
diagnostic.

**`hop:`, `verdict:` and the `carry_check:` map** are promoted by a different
route: from scratch state that cleanup deletes into columns of a durable file on
the default branch. Domains: `verdict:` against `{absorb, keep}`, `hop:` against
the composed type-pair form, `carry_check:` outcomes against `{true, false}` with
keys drawn from the ancestor's required sections plus its contribution headings.
`stage:` joins them when Phase C introduces it.

**`consolidation_judgments[].absorbed:` and `.into:`** are closed by prohibition
rather than validation: no path is ever read back from `consolidation_judgments:`
for interpolation, which is what the resume rule below enforces.

**`visibility:` is pre-existing, and it falsifies a claim an earlier draft of this
section made.** It is an enum read back from the state file and interpolated into
an emitted command — `shirabe validate --format json --visibility=<value>` — so
"no untrusted input reaches an emitted command" was not true of `/scope` before
this change. A tampered value crosses the interpolation surface and the visibility
surface at once. The rewritten scope sentence catches it.

**The visibility boundary is crossed at the splice, not at the record.** The
record holds paths, section names and outcomes — never section text — so it cannot
become a content channel. The exposure is the `upstream:` splice, which inherits
the absorbed artifact's parents into a surviving document, and a private
cross-repo parent would ride in that way.

The rule, stated rather than gestured at, and run by step 5 rather than assumed:
**when this repository is public and a spliced parent resolves to a private
artifact, the entry is dropped and the omission reported, not written.** That is
the existing `--upstream` check's third ordered condition applied at a second
site; the check is reused rather than reinvented, because a public document
naming a private one is the same violation whichever field carries it. Cross-repo
`absorbed:` values are rejected outright by the new check rather than resolved.

**What the record checker is trusted for.** It runs in a reusable workflow other
repositories pin, and it proves a row exists and its hash matches. It does not
prove the row was machine-written: the file is hand-editable, and a forged row
would pass. That is acceptable because the record is an audit aid rather than an
authorization, and nothing reads it to decide anything — but it should not be
described as proof that a fold was legitimate.

**A partial absorb is never resumed across sessions.** The absorb now has a
durable staged write before the deletion, so a chain interrupted between them is
a reachable state. The natural implementation would read the absorbed and
survivor paths back out of the state file into a `git rm` — precisely the surface
the re-validation contract exists to close. Instead: the row is un-appended, the
survivor is restored, nothing is deleted, and the hop is re-derived from scratch
or left at `keep`. **No path is ever read back from `consolidation_judgments:`
for interpolation.** This is also the guard against a double append through the
resume ladder's re-run path.

No new runtime dependency, no external URL, and no credential. With the
`visibility:` fix above, no untrusted input reaches an emitted command.

## Consequences

**Positive.** A run's artifact set reflects what the run produced. Six latent
defects are fixed, including one where the hard-finalization check gates on a
field nothing writes. The deletion failure mode CI structurally cannot see
acquires a guard at the only point where it is catchable. And the shipped
procedure's post-absorb re-validation, which an earlier draft of this design
dropped, is retained and given the explicit revert it never had.

**Negative, and accepted.** `/scope` can block itself, because its own
decision-record templates write durable files citing artifact paths into a tracked
directory — correct under fail-toward-`keep`, and a designed outcome. The record
file is a new mechanism with no precedent in this repository and a silent
duplicate-row case under union merge.

**The central behaviour is graded, not gated.** The fold-versus-keep
discrimination is verified by an eval that is LLM-graded, grades a stated plan
rather than an executed fold, and runs on a weekly cron. The honest upgrade exists
and is deliberately out of scope.

**Static validation buys presence, not fidelity.** An empty contribution section
satisfies the check. The residual gaming vector is omission, which the folding
agent cannot see because it created the absence.

**One contested point, recorded as contested.** Whether a reverted absorb removes
its record row or marks it went 3-2, with the two principals swapping sides. This
design takes removal, on the grounds that the record's own criterion is scoped to
a completed fold and the row is uncommitted at that point. The cost is a checker
assertion that removal forecloses.

## References

- `docs/prds/PRD-scope-artifact-persistence.md` — the requirements this design
  implements.
- `docs/briefs/BRIEF-scope-artifact-persistence.md` — the framing.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — Decision 8
  rejected the terminal fold and Decision 9 rests on the deleted test; both are
  amended by this work.
