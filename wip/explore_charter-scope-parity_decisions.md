# Exploration Decisions: charter-scope-parity

## Round 1

- Scope narrowed to `/charter` only: `/execute` and any future parent skill are out,
  though findings that generalize get flagged. Author's call — keeps the question
  answerable rather than turning it into a parent-skill contract rewrite.
- Topic classified directional under the Phase 1.1a gate: additive phrasing, no
  concrete failure behind it, hedged intent ("not certain there is any work to be
  done"). The adversarial demand lead fired as a result.
- The consolidation half of the `/scope` overhaul is treated as already-decided, not
  re-litigated. `DESIGN-scope-consolidation-over-skipping.md` Decision 9 evaluated it
  by name, rejected it as Option B, and the mapping premise was independently verified
  against `crates/shirabe-validate/src/formats.rs:145-220`: zero strategic hops are
  absorbable. What remains open is whether its *reasoning* is the durable one.
- The upstream-path-invocation half is also treated as settled: `/charter` R6 already
  passes the VISION path to `/strategy`, and STRATEGY's Strategic Context section is
  defined as carry-forward from the upstream VISION. The consumption contract the
  tactical chain had to add in #260 already exists on the strategic side.
- **Strategic-chain fan-out confirmed live by the author.** Both links have been hit in
  real use: multiple STRATEGYs under one VISION, and more than one ROADMAP under a
  single STRATEGY. This is the fact the public repo structurally cannot hold — PR #242
  moved every strategic artifact to the private vision repo, so no VISION or STRATEGY
  has ever been committed here. The documented 1:N rule at
  `skills/strategy/references/strategy-format.md:278` is describing practice, not
  aspiration.
- Consequence accepted: the two chains are not symmetrical, and the asymmetry is
  structural rather than a matter of cost-per-step. The tactical chain is 1:1 by
  construction; the strategic chain is 1:N at VISION->STRATEGY and STRATEGY->ROADMAP.
  The exploration's centre of gravity moves from "should the overhaul be transplanted"
  to "is the machinery prepared for the shape it already has."
- Fan-out located across runs, not within one: a single `/charter` invocation calls
  `/strategy` once and `/roadmap` once. Per-hop reasoning stays well-defined inside a
  run; what is undefined is what a second STRATEGY's hop compares against when the
  VISION above it already has a sibling.
