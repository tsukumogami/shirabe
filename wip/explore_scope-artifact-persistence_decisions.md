# Exploration Decisions: scope-artifact-persistence

## Round 1

- **The target is a working judgment, not a shorter chain.** Folding is not
  mandatory on any run. Some runs should end with BRIEF, PRD, DESIGN and PLAN
  all durable, some with a subset, some with none. The defect is that the
  outcome is currently fixed rather than decided, so the fix is to make the
  judgment answer honestly per run, not to bias it toward absorbing.

- **Stage 1's absorbability test moves from the type to the document.** The
  shipped test asks whether the downstream *type's* required sections have a
  home for every required section of the upstream *type* -- a schema comparison
  with the same answer on every run, which short-circuits Stage 2's content
  question above BRIEF-to-PRD. The test must instead ask whether *this* upstream
  document holds content *this* downstream document has no home for.

- **DESIGN-to-PLAN absorption is in scope and must be supported.** Not every
  activity needs a persistent design. When a DESIGN's value was decomposing
  tasks and ordering them, that value is spent once the PLAN encodes it, and
  the DESIGN has nothing the PLAN lacks a home for. This reverses DESIGN
  Decision 8 Option D from #260.

- **A surviving document inherits the required sections of everything folded
  into it.** Each type has a base set of required sections; a document that
  absorbs an upstream is required to carry the union of its own base set and the
  required sections of every document upstream of it that folded in. So a
  surviving DESIGN that absorbed a BRIEF and a PRD must carry sections from both,
  and that is statically validated rather than asserted. The union is additive by
  construction, which is what makes composed absorbs expressible without a
  combinatorial rule per absorbed set.

- **This re-scopes the artifact types, deliberately.** Under the union rule a
  type is no longer a fixed shape -- it is a base shape plus whatever it
  absorbed. That is the move the consolidation BRIEF fenced off as "renaming or
  re-scoping the artifact types themselves." The fence comes down properly, not
  narrowly, and the design must say so rather than present it as a validator
  tweak.

- **The terminal fold is the one discard in the system, and it is deliberate.**
  Every non-terminal fold preserves content by the union rule. Content that
  lands in the PLAN exits the document system when the PLAN is deleted at
  execution. So folding into the terminal artifact is not a move -- it is an
  explicit determination that the accumulated required sections are not worth
  persisting in a separate artifact *for this scope*. The judgment weight scales
  with how much the chain already folded: a DESIGN that absorbed a BRIEF and a
  PRD discharges all three at once.

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

- **Reduction stays a content-preserving move.** No discard verdict. Nothing is
  deleted on a judgment that it was not worth keeping. This constrains the fix:
  where an absorb would lose content, the verdict is `keep`.

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

- **The format fence comes down, but narrowly.** Re-scoping artifact types was
  fenced off by the consolidation BRIEF. What this work actually needs is much
  smaller than that fence implies: no validator change at all, and an editorial
  carve-out to the Content Boundaries rules for the absorbed case only.
