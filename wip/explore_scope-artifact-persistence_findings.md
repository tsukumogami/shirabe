# Exploration Findings: scope-artifact-persistence

## Core Question

`/scope` is the default front door for tactical work of any size, but every
completed run leaves a permanent PRD and DESIGN in `docs/` regardless of what
the work turned out to be. The floor is structural, not heuristic: the
consolidation judgment can only absorb where the downstream *type's* required
sections have a home for every required section of the upstream *type*, and
against the current formats only BRIEF-to-PRD qualifies. That test is a schema
comparison with the same answer on every run, so above the first hop the
content question never gets to run. What has to change so that each hop's
verdict is decided by what the two documents in front of it actually contain --
letting a run end with all four artifacts, some, or none?

## Round 1

Six leads dispatched, six landed: format-mapping, absorb-blast-radius,
record-survival, child-consumption, strategic-chain, prior-art.

### Key Insights

- **Stage 1 is a type-level test wearing a content-level test's clothes.**
  Its rule -- the downstream type's required sections provide a home for every
  required section of the upstream type -- is evaluated identically for every
  run, so the verdict above BRIEF-to-PRD is fixed at authoring time of
  `formats.rs`, not decided by the documents. Making the home a property of the
  *document* forces Stage 1 to be reworded, and that rewording is the core of
  the work rather than a side effect. (format-mapping)

- **The validator is not the obstacle.** It enforces exactly one thing about
  sections: each name in a format's ordered `required_sections` list appears as
  an H2 (FC04, error) in declared relative order (FC15, notice). Extra H2
  sections are already unconstrained for design, prd and plan, so an absorbed
  content appendix costs zero validator change -- a DESIGN can carry a
  Requirements section today without failing anything. (format-mapping)

- **There is a precedent for making the home *required* only on documents that
  absorbed something.** The Plan profile already swaps its required-section list
  on a frontmatter key (`execution_mode`), and that lookup fails open for docs
  lacking the field. Generalizing it to an absorbed-content key gives absorbing
  docs an enforced home while leaving the other 48 DESIGNs and every existing
  PLAN untouched. Note the fail-open behaviour on unknown values. (format-mapping)

- **The real fence is prose, not schema.** `design-format.md` tells a DESIGN to
  cite requirements by their numbers rather than restate them; `plan-format.md`
  tells a PLAN that drifts into architecture to replace the content with a
  citation. The chain is built on citation-not-duplication above the PRD. That
  is an editorial contract with no machine enforcement, and it is the thing an
  absorbed case has to carve out. (child-consumption, format-mapping)

- **The absorb procedure has never executed.** All 35 PRDs with an `upstream:`
  point at their same-topic BRIEF and no BRIEF has ever been deleted. Even
  #260's own dogfood run failed its carry check on User Journeys and shipped all
  four artifacts. Every code path below the verdict is untested. (child-consumption,
  prior-art)

- **Four concrete breakages sit in that untested path.** The `upstream:` re-point
  is a set rather than a splice, so it silently drops sibling parents now that
  #271 made lineage one-to-many. The `git rm` has no retirement guard, stranding
  any other document that cites the absorbed artifact, and step 4's re-validate
  checks only the survivor so the revert condition never fires. The deletion
  target falls outside the closed write-target set Phase 3 enforces, so an
  upper-hop absorb fails R9. (absorb-blast-radius)

- ~~**The guard the absorb needs already exists and is simply not wired in.**~~
  **CORRECTED during the D4 decision, and the original claim was load-bearing.**
  `lifecycle::build_referrer_map` exists, is a public API, is wired to
  `finalize-chain` and is unreachable from the absorb path -- all true. But it is
  NOT "the single change that turns the reduction back into a move." It indexes
  only `upstream:` frontmatter edges, so it is blind to prose, skill, code, CI and
  script citations, which are the classes that have actually broken here. It would
  have permitted commit `a133581` exactly as it happened. What the absorb needs is
  a point query -- who mentions the one document I am about to delete, in this
  repo, right now -- scanning the repo's text files, with a path-exact hit
  downgrading `absorb` to `keep` through the abort path that already exists.
  (absorb-blast-radius, corrected by D4)

- **The stranding failure mode is already live, independent of #280.** Five
  documents carry dangling `upstream:` refs today -- three stranded by the
  DESIGN Accepted-to-Current directory move, two by PLAN deletion. `shirabe
  validate` exits 2 on them right now and diff-scoped CI does not notice until
  an unrelated PR touches a victim. (absorb-blast-radius)

- **Absorbing a PRD orphans the chain's most-used cross-reference, undetectably.**
  DESIGNs and PLANs both cite requirements as bare `R<n>` numbers. Deleting the
  PRD those resolve against turns every such citation into an orphan, and R6 only
  checks that `upstream:` resolves to a tracked file. Confirmed directly against
  `crates/shirabe-validate/src/`: no rule anywhere validates a requirement
  citation. The rule set is FC01-FC16 plus FC99, L01-L08, and R5-R9; the only
  code matching `requirement` is lifecycle-state machinery in `lifecycle.rs`,
  unrelated to citations. So the failure is silent by construction.
  (child-consumption, confirmed in convergence)

- **BRIEF-to-PRD works because the child carries, not because the parent
  merges.** `/prd` Phase 3.2 reads its upstream BRIEF's body and draws Problem
  Statement, Goals, User Stories and Out of Scope from it, naming the downstream
  carry check as the reason. Stage 3 only verifies and re-points; it never writes
  content into the survivor. The BRIEF's complaint that `/prd` ignores its
  upstream is stale -- #260 fixed it. Any new absorbable hop needs the same
  child-side consumption block, not just a home. (child-consumption)

- **`/execute` does not keep rationale in code today.** Nothing in `/execute` or
  `/work-on` instructs writing design rationale, rejected alternatives or
  decision provenance into code comments, commit trailers or docs. Its one prose
  surface is a factual what-changed Part 1 built from PLAN framing and
  child-outcome metadata, explicitly barred from reading the diff. The one
  structured capture, `koto decisions record` (with `alternatives_considered`),
  writes to `~/.koto/sessions` outside the repo. The rationale-rich comments that
  make this codebase readable are house style, unenforced. (record-survival)

- **PR #278 is evidence about the author, not about `/execute`.** Both koto facts
  do survive into durable code -- but via commit `6e1a22dc`, which hand-deleted
  730 lines of PRD and DESIGN and hand-wrote 56 lines of comments to replace
  them, under a message describing the act as moving reasoning into the code.
  #278 is also still open, so nothing from it is on main. (record-survival)

- **There is a good durable surface nobody is using.** Part 1 of a PR body
  becomes the squash commit message and lands on main in every clone
  permanently (`squash_message: PR_BODY`, squash-only, branch deleted). Part 2 is
  trimmed at merge -- verified against #271 to `9f45603` -- and the trim is a
  human editing the merge dialog, not automation. (record-survival)

- **Phase 3's chain record is documented but unimplemented, and points at the
  wrong half.** `phase-3-exit-finalization.md` says the production and absorption
  record goes into the run's PR body precisely because Phase 4 deletes the state
  file. There is no `gh pr create`/`edit` on the single-pr or multi-pr path,
  SKILL.md's own binding records only the PLAN path, and `/execute`'s
  `pr_finalization` does a full `--body-file` replacement it is forbidden by
  R14/R15 from merging into. (record-survival)

- **`/execute` already knows about the artifact set in two places.** The R5
  finalization guard assumes a DESIGN survives and fails as a false L05
  validation error; `run-cascade.sh`'s roadmap `**Downstream:**` rewrite assumes
  the same and silently no-ops. Encapsulation is a property to establish, not one
  to preserve. (absorb-blast-radius)

- **The floor was seen and deliberately built.** DESIGN Decision 8 weighed four
  options; Option D was absorbing a DESIGN into the PLAN, rejected because the
  PLAN is deleted so the move "trades a durable audit trail for a shorter run and
  loses the record of why the work happened." PRD R14 requires the floor, and
  `phase-1-discovery.md`'s "do not add a guard for this" is that decision's
  enforcement. The DESIGN did not conclude the type boundary was the real
  problem. (prior-art)

- **The single-mechanism constraint is the sharper trap.** The entry-altitude
  removal rests on two claims, the load-bearing one being that only one reduction
  mechanism may exist. Any per-hop roll-forward must *replace* the consolidation
  judgment rather than sit beside it, or it reinstates the failure that killed the
  entry altitude. (prior-art)

- **The strategic chain has no equivalent floor to fix.** `/charter` has no
  consolidation judgment; DESIGN Decision 9 declined to add one, and the mapping
  test yields zero absorbable hops there (STRATEGY has no home for VISION's
  Audience, Value Proposition, Org Fit or Success Criteria; ROADMAP none for
  STRATEGY's Defensibility Thesis or Building Blocks). ROADMAP is already deleted
  on completion. No shared reference carries the mapping logic. (strategic-chain)

### Tensions

- **Decision 8 versus the author's direction on DESIGN-to-PLAN.** Prior-art found
  the exact proposed move considered and rejected on audit-trail grounds.
  Resolved during convergence: the objection assumed the record of why lives in
  the DESIGN. The author's position is that it belongs in code, kept current by
  `/execute` unconditionally, which answers the objection rather than overriding
  it -- but it converts a documented `/execute` non-capability into required work.

- **Encapsulation asserted versus encapsulation available.** The direction is
  that the keep-or-fold decision is `/scope`'s alone and `/execute` need not
  know. Blast-radius found `/execute` already assumes a DESIGN survives in two
  places, and record-survival found the rationale-in-code job it is being relied
  on for does not exist. Both must be built before the encapsulation claim is
  true.

- **Zero-churn homes versus enforced homes.** The appendix convention costs
  nothing but makes the home merely *available*; the frontmatter-keyed variant
  makes it *required* on absorbing docs at the price of a small validator change
  and a fail-open edge. Stage 1's current wording implies required; the
  content-preserving-move framing does not settle it.

- **Total mapping versus no-loss.** If the PLAN is deleted at execution anyway,
  it is unclear whether DESIGN-to-PLAN needs a *total* mapping or merely one
  good enough that nothing is lost between the DESIGN's deletion and the PLAN's.
  The format-contract cost differs sharply between those readings.

- **Composition.** If a DESIGN absorbs a PRD and a PLAN then absorbs that DESIGN,
  the PLAN must carry both. Under the frontmatter-variant approach that is a
  third combinatorial list rather than a composition of two; `execution_mode` has
  no additive semantics to borrow.

### Gaps

- No worked example of an absorb exists anywhere in the repo's history, so every
  claim about what an absorb does downstream is read from instructions rather
  than observed.
- Prose citations are the largest unexamined surface: 73 files cite a PRD path
  and nothing validates them.
- `/design`'s freeform mode (a PRD-less DESIGN) was not examined and interacts
  with any change to the absorb model.
- Whether `shirabe validate` has any check that would catch an orphaned `R<n>`
  citation was not confirmed against `crates/shirabe-validate/src/`.
- Who actually trims PR body Part 2 at merge. If it is a human, "Part 2 is
  deleted at merge" is a discipline rather than a guarantee.
- No evidence base was found for the claim that framing overlap between adjacent
  artifacts is constant; #260's PRD flags that its corpus was generated by the
  same pipeline it was measuring.

### Decisions

Recorded in full in `wip/explore_scope-artifact-persistence_decisions.md`. In
brief: the target is a working per-run judgment rather than a shorter chain;
Stage 1's test moves from type to document; DESIGN-to-PLAN absorption is
supported and Decision 8 Option D is reversed on the ground that rationale
belongs in code; `/execute` gains an unconditional rationale-in-code job and
loses its two DESIGN-survives assumptions; reduction stays a content-preserving
move with no discard verdict; the strategic chain is out of scope; adding
sections to the base required lists is ruled out; the format fence comes down
narrowly.

### User Focus

The author's clarification reframed the problem from the one the issue implies.
The goal is not that content rolls forward on every run -- it is that the
workflow *permits* folding at every hop and lets the run's own content decide.
Runs ending with every durable doc, with a subset, and with none are all correct
outcomes; the defect is that only one of those is currently reachable. The
mechanics of absorption were believed built; the bug is in how absorbability is
judged.

The author then supplied the model for what a survivor owes -- first as a union
of ancestors' required sections, then replaced by the contribution model above.

Folding into the PLAN is where the distillate lands in a doomed document, and the
author's justification for it is worth rather than survival-elsewhere. The
expected common case is a `/scope` run over a bug report or a coding task that
turns out to be obvious or self-contained, where the content was never worth a
separate durable artifact. Agents should be able to make that call against the
real bodies.

**Corpus figures, corrected by the D4 decision.** The convergence-time counts
(366 DESIGN, 107 PRD, 64 BRIEF) included 44 golden test fixtures. The real corpus
is 516 documents: 352 DESIGN, 103 PRD, 61 BRIEF. The redundancy reading those
numbers seemed to support does not survive measurement -- among DESIGNs actually
in a PRD chain the ratio is **1.03**, 94 of 103 PRDs have exactly one child, and
only 12% of DESIGNs share even a two-token topic prefix with a sibling. The 3.42
headline comes almost entirely from tsuku (21.0) and private/tools (23.5), repos
that predate the PRD-first workflow. The corpus is independent design work, not a
pile of duplicates.

The author's "nobody ever asked" argument stands on its own terms and is
untouched by this. What falls is the separate redundancy inference.

Document length is likewise useless as a proxy, and more so than first reported:
the smallest DESIGN figures cited during convergence were test fixtures. The real
floor is 81 lines and the median is 544. The terminal-fold judgment has to judge
content, which is the harder call and the one being delegated.

## Accumulated Understanding

#280 is a bug report about a judgment that cannot answer, sitting on top of a
mechanism that has never run.

The judgment has three stages per hop: whether absorption is possible, whether
it is warranted, and then the move plus verification. Stage 2 is the content
question and the only one that can vary between runs. Stage 1 short-circuits it
by comparing type schemas, which produces the same verdict every time and makes
`keep` unconditional above BRIEF-to-PRD. Repointing Stage 1 at the documents
rather than the types is the central fix, and it is cheap: the validator already
permits extra sections on design, prd and plan, so a thin DESIGN whose substance
is decomposition has nothing the PLAN lacks a home for and absorbs honestly,
while a DESIGN carrying live architectural reasoning fails the same test and
stays. Same question, different answers, decided per run.

Two things sit beside that fix and are not optional. First, the floor has a
second, independent cause: Decision 8 rejected DESIGN-to-PLAN on its own
audit-trail grounds, and PRD R14 plus the "do not add a guard" instruction encode
that rejection. Reversing it is a deliberate act, and it is grounded rather than
asserted -- the objection presumed the record of why lives in the DESIGN, and the
author's position is that it lives in code, maintained by `/execute` as a standing
unconditional job. That grounding converts the reversal into scoped work, because
`/execute` does none of that today. Second, the absorb procedure itself is buggy
in four ways that would make a fold lossy even when the verdict was right, and
the stranding failure is already live in the tree on five documents. Those are
what "content-preserving move" means in practice, and the guard they need already
exists unwired from #271.

The shape settled during convergence, in two passes. The first formulation had a
survivor inherit the union of its ancestors' required sections; it was rejected
because a section list can be satisfied by copying, which produces a survivor
that is its ancestors stapled together and grows without bound.

What replaced it: each type contributes one thing to the chain -- illustratively
BRIEF/WHY, PRD/WHAT, DESIGN/HOW, PLAN/WHEN-as-sequence -- and a survivor carries
each absorbed ancestor's *contribution* as one compact section, ahead of its own
content in chain order. A DESIGN that absorbed a BRIEF and a PRD opens with Why,
then What, then its own How sections. Contributions accumulate transitively and
are capped at the number of ancestor types, so growth is bounded and the operation
is compression rather than concatenation.

Three consequences. Static validation gets simpler -- one known heading per
absorbed ancestor type -- but the fidelity gap widens, because compression is the
goal so section length carries no signal at all; presence is the whole of the
machine's assertion. Every fold is now lossy by design, which supersedes the
content-preserving-move principle: distilling four BRIEF sections into one Why
discards whatever was not the essence. And Stage 1's structural test very nearly
dissolves, since a home can always be written, leaving the verdict to the content
question alone -- does this upstream hold anything beyond its contribution that
compression would lose.

Folding into the terminal artifact is therefore not a different operation, only
the case where the distillate lands in a document that dies. It is justified by
worth rather than by the reasoning surviving elsewhere. For the class of work
where it fires -- bug reports, and tasks that turn out to be obvious or
self-contained -- the content was never worth a separate durable artifact. The
judgment scales with how much already folded, and cannot key off document size.

**The reversibility picture, corrected by D2 and D4.** The asymmetry this
exploration assumed -- durable-survivor folds bounded, terminal fold irreversible
-- is false on both halves. Nothing is reversible from a clone: an absorbed
BRIEF's bytes are as unrecoverable as a folded-away DESIGN's, because both are
created and `git rm`-ed on one branch that squash-merges and is deleted, and only
one chain-document deletion exists in all of `main`'s history. Nothing is wholly
lost either: `refs/pull/<N>/head` survives branch deletion and a `git clone
--mirror` captures all 141, so a deleted PLAN is recoverable byte-exact offline
(best-effort platform retention, not a git guarantee, and nobody runs a mirror).
The premise is also backwards in the retroactive direction: deleting a document
already on `main` is recoverable in two commands, while forward absorption is
not. What differs between hops is not reversibility but where the distillate
lands.

All five open questions were then run through the `/decision` framework and
settled; see the `## Round 1 -- Open Question Decisions` section of
`explore_scope-artifact-persistence_decisions.md` and the five `_d<N>_report.md`
files. In brief: contribution sections carry a two-sided standing-alone test
lifted from the strategic chain; the verdict itself gets no gate while the
*operation* gets a hardened carry check plus a bounded durable record; a survivor
records what it absorbed in frontmatter plus one `## Status` line; the existing
corpus is out of scope with the boundary rewritten to carry its reason and the
retirement guard pulled in as a point query; and everything ships in one PR with
rationale-in-code bounded to two diff-checkable edits in `/work-on`.

The constraint that held across all five: the result must replace the
consolidation judgment rather than sit beside it -- the single-mechanism rule is
what killed the entry altitude and it still binds. Note that every statement of
that rule is scoped by a removal verb, so a mechanism that can only force `keep`
sits outside it, which is what admits both the carry check and the guard.

Deferred by the author: manual invocation of child skills outside `/scope`, which
is the only way to reach a chain with a genuinely missing ancestor.

Still open for the DESIGN rather than for this exploration: the surface of the
durable operation record (leading candidate a single shared append-only index);
whether the contribution section is authored by the child at drafting time or the
parent at fold time; and the rollout call for the `R<n>` citation-resolution rule,
which will fire on documents already on disk.
