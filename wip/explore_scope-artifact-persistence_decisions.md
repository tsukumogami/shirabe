# Exploration Decisions: scope-artifact-persistence

## Round 1

- **The target is a working judgment, not a shorter chain.** Folding is not
  mandatory on any run. Some runs should end with BRIEF, PRD, DESIGN and PLAN
  all durable, some with a subset, some with none. The defect is that the
  outcome is currently fixed rather than decided, so the fix is to make the
  judgment answer honestly per run, not to bias it toward absorbing.

- **Stage 1's structural test very nearly dissolves.** The shipped test asks
  whether the downstream *type's* required sections have a home for every
  required section of the upstream *type* -- a schema comparison with the same
  answer on every run, which short-circuits Stage 2's content question above
  BRIEF-to-PRD. Under the contribution model a home can always be written, since
  adding a Why section is always possible, so absorbability stops being a
  property of the types at all. The verdict collapses into the content question:
  does this upstream hold anything beyond its contribution that compression would
  lose? That is the answer #280 was reaching for, and it arrives more cleanly
  through contributions than through the document-level mapping test considered
  earlier in this exploration.

- **DESIGN-to-PLAN absorption is in scope and must be supported.** Not every
  activity needs a persistent design. When a DESIGN's value was decomposing
  tasks and ordering them, that value is spent once the PLAN encodes it, and
  the DESIGN has nothing the PLAN lacks a home for. This reverses DESIGN
  Decision 8 Option D from #260.

- **A surviving document owes its ancestors' contributions, not their sections.**
  Superseded an earlier formulation in which the survivor inherited the union of
  its ancestors' required sections. The union rule was rejected because it can
  only be satisfied by copying, producing a survivor that is its ancestors
  stapled together and growing without bound.

  Each type contributes one thing to the chain. As an illustration rather than a
  fixed spec: BRIEF contributes WHY, PRD contributes WHAT, DESIGN contributes
  HOW, PLAN contributes WHEN in the sense of sequence rather than time. A
  document that absorbed an ancestor carries that ancestor's contribution as one
  compact section, placed before its own content in chain order. A PRD that
  absorbed a BRIEF opens with one Why. A DESIGN that absorbed both opens with
  Why, then What, then its own How sections.

  Contributions accumulate transitively: a DESIGN that absorbed a PRD which had
  already absorbed a BRIEF owes both. The count is capped at the number of
  ancestor types, so the survivor grows by a bounded amount rather than by
  concatenation.

- **Contribution sections are owed only where an ancestor actually folded.**
  Under `/scope` a child is never skipped, so every run produces the full chain
  and the only question is which members survive. The existing `chain_skipped:`
  concept fires on re-entry protection, when a settled artifact already exists,
  so the document is present and can still fold or survive -- it never produces a
  missing ancestor. Manual invocation of child skills outside `/scope` can leave
  a genuine gap; that is deferred and out of scope here.

- **Every fold is a distillation, so loss is by design.** This supersedes the
  earlier "reduction is always a content-preserving move" principle.
  Compressing a BRIEF's sections into one Why discards whatever was not the
  essence. That means there is no longer a single special discard at the terminal
  fold: there is one operation, and what varies is whether the distillate lands
  in a durable document or in the PLAN, which dies. The judgment at every hop is
  therefore the same question -- does this upstream hold anything beyond its
  contribution that would be lost under compression.

- **This re-scopes the artifact types, deliberately.** A type is no longer a
  fixed shape -- it is a base shape plus a bounded, ordered set of contribution
  sections for whatever it absorbed. That is the move the consolidation BRIEF
  fenced off as "renaming or re-scoping the artifact types themselves." The fence
  comes down properly, not narrowly, and the design must say so rather than
  present it as a validator tweak.

- **Static validation gets simpler under contributions, and the fidelity gap
  widens.** One known heading per absorbed ancestor type is easier to check than
  a variable inherited section list. But under the union rule a suspiciously
  short carried section was a smell, whereas here compression is the goal, so
  length carries no signal. Presence is the whole of what the machine can assert;
  whether a Why actually carries the BRIEF's why is entirely the judging agent's
  call.

- **The terminal fold is where the distillate lands in a doomed document.**
  Folding into the PLAN is an explicit determination that the accumulated
  contributions are not worth persisting in a separate artifact *for this scope*.
  The judgment weight scales with how much the chain already folded: a DESIGN
  that absorbed a BRIEF and a PRD discharges all three at once.

- **The justification for that discard is worth, not survival elsewhere.** The
  load-bearing argument is not that the reasoning survives in code. It is that
  for a large class of work -- bug reports, and coding tasks that turn out to be
  obvious or self-contained -- the content of those sections was never worth a
  separate durable artifact. DESIGN Decision 8 assumed every DESIGN carries
  load-bearing reasoning whose loss costs an audit trail. That assumption is what
  this work rejects.

- **The corpus is the evidence.** Across the workspace: 366 DESIGN docs, 107
  PRDs, 64 BRIEFs (tsuku 147 DESIGNs, shirabe 62, niwa 56, tools 47, koto 40,
  vision 14). They accumulated because the workflow never asked whether they
  should be deleted, not because each was judged worth keeping. Note that
  document *length* does not support a thin-DESIGN reading -- the smallest DESIGN
  in tsuku is 132 lines and in shirabe 227 -- so the terminal-fold judgment cannot
  use size as a proxy for worth. It has to judge content.

- **Agents are trusted to make the terminal-fold call.** The determination of
  whether the accumulated sections are worth persisting is an agent judgment
  against the real bodies, consistent with #260's principle that nothing is
  decided before the artifact it is about exists.

- **The rationale-in-code job is hygiene, not the load-bearer.** `/execute`
  keeping code comments current about why the code works as it does is required
  independently and unconditionally. It raises the floor under the terminal fold,
  but the fold is justified by worth rather than by that capability, so the two
  are decoupled in *justification*. The earlier scope call to sequence it before
  the DESIGN-to-PLAN hop opens still stands; whether it needs to, now that it is
  not the load-bearing argument, is open.

- **Encapsulation is a property to build, not one to preserve.** Because the
  rationale-in-code job is unconditional, the keep-or-fold decision stays inside
  `/scope`'s runtime. But `/execute` does not do that job today (no instruction
  anywhere writes rationale into comments, trailers or docs), and it already
  leaks knowledge of the artifact set in two places -- the R5 finalization guard
  and `run-cascade.sh`'s roadmap `**Downstream:**` rewrite both assume a DESIGN
  survives. Both must be closed for the encapsulation claim to hold.

- ~~**Reduction stays a content-preserving move.**~~ SUPERSEDED by the
  contribution model. Distilling an ancestor to its contribution discards
  whatever was not the essence, so no fold is content-preserving. What survives
  of the original intent: a fold happens only when the judgment holds that
  nothing beyond the contribution would be lost, and where it would, the verdict
  is `keep`.

- **The strategic chain is out of scope.** `/charter` has no consolidation
  judgment at all and DESIGN Decision 9 deliberately left it that way; the
  mapping test yields zero absorbable hops there, so generalizing today would be
  dead code that can only return `keep`. No shared reference carries the mapping
  logic, so a future extension would be new machinery rather than a follow-on
  edit. (Lead: strategic-chain.)

- **Adding the absorbed sections to the base required-section lists is ruled
  out.** It would put error-level FC04 failures on all 48 DESIGN docs and break
  roughly 20 golden fixtures, for no benefit over the two zero-churn
  alternatives. (Lead: format-mapping.)

- ~~**The format fence comes down, but narrowly.**~~ SUPERSEDED. See "This
  re-scopes the artifact types, deliberately" above. The narrow framing was
  written against the union rule and understated the change: a type becomes a
  base shape plus an ordered set of contribution sections, which is genuine
  re-scoping and must be argued as such.

## Round 1 -- Open Question Decisions

Each ran through the `/decision` framework. Reports at
`wip/explore_scope-artifact-persistence_d<N>_report.md`.

### D1: Contribution sections have a two-sided adequacy test

"One section, essence only" is the shape, not the whole specification. The
criterion is lifted from `strategy-format.md`'s Strategic Context contract,
which is a contribution section in all but name and already ships: if the
section reads like a rewrite of the upstream, fold it back; if a reader cannot
follow *this document's* argument without first reading the upstream, expand.

The second clause is the load-bearing one, because it is phrased against the
survivor's own content rather than abstract sufficiency -- a one-line
restatement fails the moment the survivor's later sections lean on something the
contribution never established. It is anchored to two named consumers rather
than an abstract reader: the `R<n>` citations DESIGNs and PLANs resolve against
the PRD, and `/execute` seeding CI lifecycle validation on the surviving DESIGN.

Stated in three places (format reference, drafting instruction, the authoring
artifact's jury), mirroring how STRATEGY states its version. Rides Stage 3's
existing carry check: a failure keeps `carried: false` semantics, downgrading the
verdict to `keep` and deleting nothing.

Rejected: presence-only, because it contradicts #260's D5 principle head-on and
hollows out the carry check while keeping its shape. A scored rubric, because
this repo has no scored rubric anywhere and functional tests demonstrably work.
An independent fold-time reviewer as a standing requirement, because that
independence already exists one phase earlier *if* the child authors the
contribution. No word count or length floor -- under a model whose point is
compression, a floor inverts the incentive and padding satisfies it free.

Riders:
- **A citation-resolution rule belongs in `shirabe validate`**: fail when an
  `R<n>` cited in a document resolves nowhere in that document or its surviving
  upstream. The only depth expectation in this problem with a machine check
  available. It will fire on documents already on disk, so it needs a rollout
  call.
- **Correction to a prior artifact.** #260's PRD states "the commit history is
  the recovery path" for an absorbed document. That holds only while the feature
  branch lives. This org squash-merges with branch deletion, so after merge an
  absorbed original never existed on main. There is no recovery path, which
  raises the price of every inadequate contribution.
- **Open fork, deliberately not settled here:** whether the contribution section
  is authored by the child at drafting time or by the parent at fold time. If the
  child, the criterion rides an existing jury. If the parent, nobody independent
  reviews the prose and the fold-time reviewer becomes the right answer. Note D2
  partially answers this: Stage 3 is reordered so the contribution is authored
  first and the carry table built against authored text.

### D2: No gate on the verdict; a structural backstop on the operation

The fold verdict is the judging agent's call at every hop including the terminal
one -- no independent reviewer, no human confirmation, in any mode. Both
advocates withdrew their own alternatives: human confirmation is self-refuting
against the recorded ruling that agents make this call, and a reviewer agent is
structurally unavailable because `/scope` owns no team at its own layer, has zero
sub-agent spawn sites across all seven of its files, and has no row in the
dispatch binding table. Five of five validators converged.

What gets a structural backstop is the *operation*, in two parts.

**The carry check, hardened.** Stage 3 is reordered so the contribution section is
authored first and the carry table is built against authored text -- making the
verdict the mechanical consequence of the table rather than a prediction the table
is later fitted to. The check becomes per-contribution and runs at every hop
including the terminal one; any contribution that does not carry aborts to `keep`.
Step 4's post-absorb re-validation widens from the survivor alone to the survivor
plus every referrer of the absorbed artifact.

**A bounded, durable record of the operation.** Each completed fold leaves a short
entry on `main`: what folded into what, on what verdict, the finding, the
per-contribution carry table, and a content-addressed (blob SHA) pointer to the
pre-fold original. Written mechanically (`git hash-object` plus `printf`), not
authored by an agent -- it is the one part of the design that cannot fail by
misjudgement. Presence at a canonical path is what static validation can assert,
and it fails in the established direction: no record, no fold.

The record persists no contributions. That distinction is the sharpest argument
the bakeoff produced: **any destination that preserves the distillate must assert,
every time it fires, that the verdict was partly wrong** -- the fold's meaning is
that this content did not warrant a durable artifact, so a mechanism durably
preserving it contradicts the judgment it backs up. A record that a judgment
happened, about what, with what carried, asserts nothing the fold denies.

Surface left to the DESIGN. Leading candidate is a single shared append-only index
(one `docs/deletions.md`, one row per deletion), because it is the only shape that
is not a per-run artifact and so cannot read as a floor. Note **three deletion
sites, not one**: BRIEF-to-PRD has a durable survivor and can record in the
survivor's frontmatter; `/execute`'s cascade deletion and the terminal fold have
no survivor and need the shared file.

Riders:
- **Urgent independently of this decision.** `validate-docs.yml` computes its file
  set with `git diff`, and a document stranded by an absorb is not a changed file
  -- its bytes are untouched, only its target vanished. R6 can never fire on it, in
  CI or the pre-commit hook. **Fold time is the only catchable point in the
  system**, and sixteen documents already point at two nonexistent paths.
- **Eval 18 must be rewritten under every alternative.** Its `expected_output`
  asserts "no hop above BRIEF-to-PRD is absorbable" -- the sentence #280 exists to
  falsify -- and grounds its refusal to add a guard on a condition #280 flips.
- **The worth judgment ships ungraded and ungradeable.** A fixture eval can grade
  whether content was lost, because the fixture retains both bodies. It cannot
  grade whether reasoning deserved to persist; after the fold the comparison object
  is gone. This belongs in the DESIGN's Consequences so nobody mistakes a green
  eval for a check on the whole judgment.

### D3: A survivor records what it absorbed, in two paired places

An `absorbed:` frontmatter key listing each folded ancestor's repo-relative path,
taking the same scalar-or-sequence shape `upstream:` takes after the one-to-many
change -- and **explicitly excluded from path resolution**. R6 is the only rule
that resolves a frontmatter value to a tracked file; wiring `absorbed:` into it
would guarantee a dangling reference on every fold, because the target is deleted
by construction. The design must write that exclusion down, since adding the
resolution is exactly the helpful-looking change a future contributor makes.

Plus one sentence per absorbed ancestor spliced into the survivor's `## Status`
section, naming what was folded *and* which contribution section now carries it.
Placement and direction do the work: `## Status` is the lifecycle section, so a
reader who came for content never walks past the trace; and the line points
forward to the contribution rather than backward at a corpse, which turns
bookkeeping into navigation.

This is house pattern, not invention: `shirabe transition` already writes a
`superseded_by:` frontmatter key *and* splices a `Superseded by [name](path)` line
into `## Status`. Supersession is the nearest existing analogue of absorption.

The beneficiary it serves is the one absorption actually harms -- the reader of
some third document citing the dead path. There are roughly ninety such citations
under `docs/` today, none validated by any rule or CI job. That reader is not
holding the survivor and does not know it exists; a visible line puts the dead
slug back in the working tree as a grep-reachable string.

Rejected: no trace, which concedes Decision 8's objection in full for zero saving.
Frontmatter-only, whose sole beneficiary is tooling nobody has written -- it costs
the same as the recommendation and is that recommendation minus the half that
pays. A tombstone stub, strongest on the merits and the only option that keeps all
~90 citations resolving, but it leaves one durable file per fold in the corpus
that motivated #280, and needs a new format plus a new validator posture.

Note this does not fix the ~90 orphaned prose citations -- it gives them a lead,
not a resolution. It also does not make the fold lossless; nothing on the list
would.

### D4: The corpus is out of scope, and the boundary carries its reason

No retroactive pass of any kind in this work -- no deletions, archive moves, pilot
repo, or corpus report. The `Out of Scope` line is rewritten (see `scope.md`) to
record the corpus as *unreached* rather than *vindicated*.

The decisive finding is structural, not evidential: for 338 of the 352 DESIGNs
there is no question to ask. The judgment compares an artifact that just landed
against a surviving durable artifact above it, and for those the PLAN was deleted
at finalization by design -- one body, not two, and no landing event. `keep` there
is the absence of a runnable judgment, not a verdict. A sweep would be inventing a
discard verdict the mechanism refuses, against 201 surviving files holding broken
references (111 outside `docs/`), behind CI whose `--diff-filter=ACMR` excludes
deletions outright. The one precedent, `a133581`, stranded five references that
have been broken for 64 days and still are. The validator assigned to argue for
the sweep voted against it after reading the trigger condition.

**The retirement guard comes INTO scope**, respecified as a point query rather
than the frontmatter index this exploration had committed to (see the corrected
finding). It runs inside Stage 3 between the `upstream:` re-point and the `git rm`,
scanning the same repo's text files. Two tiers: a path-exact hit downgrades
`absorb` to `keep` through the abort path that already exists verbatim; bare-name
hits route into the judging agent's findings rather than acting mechanically. No
new severity, no new error code, no override -- a guard whose only power is
refusing to delete has no unsafe failure mode, and it must never grow an action
stronger than `keep`.

Fenced OUT: the corpus-wide citation index; a notice-severity validator rule for
unresolvable citations (it would fire on ~374 pre-existing unresolvable names --
a repair campaign, not a guard); and the CI deletion blindness, which is not a
one-line diff-filter fix since it would pass deleted paths to a validator that
cannot open them.

**Two named follow-ons, both specified:**
1. *The BRIEF-to-PRD retroactive fold* -- the one coherent retroactive operation.
   Deferred on ordering, not merit: a validator pre-committed to conceding at 80%
   carry and the measurement cleared it decisively (53 of 58 pairs at >=0.70, all
   58 at >=0.61, no low tail, predicted bimodality falsified). So it is
   verification of a carry that already happened, not authoring into settled
   artifacts. ~55 candidates after exclusions; population, filters and
   R-citation carve-outs are recorded in the D4 report.
2. *A lifecycle criterion for settled documents* -- "live guidance or historical
   record?" is a lifecycle question with its own criterion and its own disposal
   (archive, not delete). Needs an `Archived` status (~3 lines) because the
   existing `Superseded` transition requires a pointer an orphan DESIGN cannot
   honestly supply. Most defensibly scoped to the 141 DESIGNs cited by nothing.

Recorded honestly: without either follow-on, 240 chainless and 141 uncited
DESIGNs will never be judged by any current or planned mechanism. That is a
curation gap, not a pipeline gap -- the instrument already exists and nobody has
spent an afternoon with it.

### D5: One PR, with rationale-in-code scoped to a diff-checkable deliverable

No ordering constraint. The judgment rewrite, the Durable-Artifact Floor rewrite,
the absorb repairs, the `/execute` R5 fix, the `run-cascade.sh` roadmap fix and
the rationale instruction all ship in a single-pr plan and one squash merge, so no
window exists in which the fold lives without the instruction. The repo's own plan
rule makes one PR the default and permits a split only on a *named* hard
constraint; #280 is ~6-10 files in one repo with no landing-order constraint.

Rationale-in-code is bounded to two diff-checkable edits: a subsection under
`### A. Write Code` in `skills/work-on/references/phases/phase-4-implementation.md`
(record why the code is shaped this way -- the decision the diff cannot show), and
one line extending the **maintainer reviewer**'s brief in `phase-4b-review.md`.
The second is what makes it enforcement rather than aspiration: that phase already
has a blocking path that collects findings, respawns the coder and re-enters
implementation. Roughly 15-25 lines of prose across two existing files.

Explicitly not a gate: any mechanical comment-content check, and the long-tail
effort of raising rationale coverage across the existing codebase.

**Naming correction that propagates into the design:** the rationale-in-code work
is `/work-on` work, not `/execute` work. R14/R15 bars `/execute` from reading
diffs, and the only agent in the chain holding the diff is `/work-on`'s
implementation phase. Only the R5 finalization guard and the `run-cascade.sh`
roadmap rewrite are genuinely `/execute`-side. Any design or plan should say
`/work-on` where it currently says `/execute`.

Accepted trade-off, stated plainly: this ships the fold alongside an instruction
whose effect nobody can measure. There is no check that will tell anyone whether
`/work-on` actually started writing why-comments. The judgment is that an
unmeasurable instruction plus a blocking agent reviewer is the honest ceiling for
a qualitative property, and that holding an atomic change hostage to a property
nobody can certify buys nothing.
