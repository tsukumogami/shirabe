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
  reviews the prose and the fold-time reviewer becomes the right answer.
