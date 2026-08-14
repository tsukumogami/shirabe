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

- **Decision 8's objection is answered, not overridden.** Option D was rejected
  because the PLAN is deleted, so absorbing into it "loses the record of why the
  work happened." The answer is that the record of why belongs in the code, not
  in the DESIGN: `/execute` must keep code comments explaining why the code works
  as it does, current as the code changes, unconditionally and whether or not an
  upstream DESIGN ever existed.

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
