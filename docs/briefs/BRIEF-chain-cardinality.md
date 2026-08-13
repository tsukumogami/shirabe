---
schema: brief/v1
status: Accepted
problem: |
  The document formats describe one-to-many lineage and authors work that
  way, but neither the parent skills nor the validator can express or
  check the shape. Reuse of an upstream is unreachable through a parent,
  and a document with several consumers inherits obligations none satisfies.
outcome: |
  An author is never silently handed a shape they did not ask for, and every
  document reaches a state the validator can evaluate -- whether the tools
  support fan-out or refuse it legibly. A lineage walk answers the same from
  any sibling, and nothing is removed while something still points at it.
motivating_context: |
  Surfaced by an exploration that set out to ask whether the /scope
  consolidation overhaul should be applied to /charter. The answer was
  that almost nothing remained to port -- and that the two chains are
  not the same shape, which is the more consequential finding.
---

# BRIEF: Chain Cardinality

## Status

Accepted

Framing only. Whether the answer is to support fan-out, constrain it, or merely
validate it is deferred to the downstream PRD, along with two questions this brief
resolved to defer rather than settle: whether `PRD -> DESIGN` fan-out is intended or
merely tolerated, and where posture should attach when one document belongs to two
chains at once. All three close in the PRD's Decisions and Trade-offs section.

## Problem Statement

The pipeline's document formats describe one-to-many lineage. A VISION's Downstream
Artifacts section lists STRATEGY documents, plural; a STRATEGY's lists the ROADMAPs
that sequence its work; and `strategy-format.md:278` states outright that multiple
STRATEGYs may operate under one upstream VISION when they make distinct bets. The
lifecycle tables carry the same asymmetry — a VISION is Active when *at least one*
STRATEGY references it. Authors work this way in practice, on both strategic links.

Nothing below the formats can represent that shape.

**The parents cannot express it.** `/charter` resolves every path it touches from a
single topic slug. Opening a second bet under a live thesis needs a distinct slug, or
the new STRATEGY would overwrite the first; but with a distinct slug the lookup for the
existing VISION misses, `/charter` reads the run as a cold start, and the cold-start
rule is absolute — it writes a *second* VISION and grounds the new bet in that instead.
Reusing the original slug so the lookup hits collides on the STRATEGY path and routes
the run into the resume ladder as re-entry into the same bet. The two exits are
mutually exclusive, so the intended shape is unreachable through the parent. It is
reachable only by invoking `/strategy` directly, which accepts an arbitrary VISION path
and derives its own slug — the child can express an upstream relationship its parent
cannot.

**The validator cannot check it.** Posture is a property of a chain, and a chain is
identified by its root. A document with several downstream roots therefore belongs to
several chains and inherits several postures, applied as independent obligations on one
mutable `status:` field. For BRIEF and PRD those obligation sets are disjoint, so the
document is unsatisfiable — not by a bug in any one function, but as a consequence of
attaching posture to the chain rather than to the edge. Supporting failures compound it:
the chain walk takes the first upstream and discards the rest, an `upstream:` written as
a YAML list collapses to the empty string before the plural handling ever sees it, and
chain selection turns out to depend on filenames — renaming a plan, with no content
change anywhere, flips a shared BRIEF from zero findings to two.

**This is not a strategic-chain problem.** The tactical chain was believed to be
uniformly one-to-one and is not: one PRD in this workspace has nine DESIGN documents
under it, another has four, a third has two, produced by `/design`'s documented split
heuristic, which proposes a split at eight or nine decision questions and refuses at ten.
`BRIEF -> PRD` is the genuinely uniform link, at 58 of 58 parents. That coincidence is
load-bearing today and unrecorded: `BRIEF -> PRD` is also the only hop `/scope`'s
consolidation judgment can absorb, so absorption is well-defined by accident. The stated
absorbability criterion is section-mapping totality, which says nothing about how many
consumers an upstream has — and the absorb re-validates only the survivor while CI
validates only changed files, so a sibling left pointing at a deleted upstream would
surface only when someone next touches it.

Underneath all of it, nothing anywhere counts children, and three of the strategic
directories are outside the lifecycle document index entirely — a deliberate, documented
exclusion that is currently the only reason the strategic chain cannot fail the same way
the tactical one already can.

## User Outcome

An author who holds one thesis and several bets beneath it is never silently handed a
shape they did not ask for. Opening a new bet under an existing thesis either picks that
thesis up or says plainly why it cannot — what it does not do is write a second thesis
document nobody requested, leaving the author to discover that reaching past the parent
to a child skill was the only way to get what they wanted.

Every document reaches a state the validator can actually evaluate. A document with more
than one consumer is either given a status that satisfies all of them or reported as a
named conflict; what it is not is left in a state no value can satisfy and no message
explains. A maintainer walking a lineage gets the same answer whichever sibling they
start from, and the same answer tomorrow after an unrelated file is renamed. When a
document really is redundant, whoever removes it knows who was still pointing at it.

Underneath all of that, one thing changes for everyone: the shape the format
specification describes, the shape the tools produce, and the shape the validator checks
agree with each other. Today those three disagree, and the author is the one absorbing
the difference — quietly, and usually without being told.

## User Journeys

### A second bet under a live thesis

An author has an Active VISION and a running STRATEGY beneath it. A distinct second bet
emerges under the same thesis. They open the parent skill for the new bet and expect the
existing thesis to be picked up as the new bet's upstream. The run either reuses the
VISION or tells them plainly why it cannot, and in no case does it write a second
thesis document the author did not ask for.

### A maintainer tracing what a finished plan belongs to

A maintainer picks up a PLAN whose work has just shipped and needs to know what it sits
under before retiring it. Its DESIGN shares a PRD with eight sibling designs. The walk
they run resolves to a definite answer about which chain the PLAN belongs to and what
posture that implies — and gives them the same answer tomorrow, after a colleague renames
an unrelated sibling.

### Validating a corpus that already fans out

A maintainer runs the validator across a repository where one PRD has nine designs
beneath it. Every document reports a state it can actually reach. A document sitting
under two chains at different postures is either given a status that satisfies both or
reported as a specific, nameable conflict — not left in a state no value can satisfy and
no message explains.

### An author mid-chain whose upstream has other consumers

An author is partway through a chain run when it reaches a hop where the upstream looks
absorbable — and something outside this run still points at that upstream. The run tells
them the document has another consumer and keeps it, rather than deleting it on their
behalf and leaving a dangling reference for whoever next opens the sibling to find.

## Scope Boundary

**In:**

- The cardinality of every link in both chains: what the formats permit, what the tools
  produce, and what the validator checks — and closing the gaps between those three.
- Whether and how a parent skill can consume an upstream it did not produce, given that
  every path it resolves is currently derived from one topic slug.
- The validator's posture and passing-state model when a document has more than one
  downstream document, including whether posture belongs to the chain or to the edge.
- The `upstream:` field's list handling end to end — parsing, resolution, and the chain
  walk that currently keeps only the first value.
- Whether the consolidation judgment's absorbability test should account for how many
  consumers an upstream has, alongside section-mapping totality.
- Whether the strategic document directories should enter the lifecycle index at all,
  since their exclusion is what currently keeps the problem theoretical on that side.

**Out:**

- Porting `/scope`'s consolidation judgment to `/charter`. Evaluated and declined on the
  record in `DESIGN-scope-consolidation-over-skipping.md` Decision 9; zero strategic hops
  are section-mappable. This work may refine *why* that holds without reopening it.
- The other parent skills. `/execute` walks a chain too and several findings would apply
  to it, but the author scoped this to the two chains named above.
- Redesigning where competitive analysis sits. The exploration established that it is a
  parallel input rather than a chain member; recording that is in scope, restructuring it
  is not.
- The adjacent defects the exploration turned up and set aside: the `chain_skipped` entry
  shape divergence between the two parents (#254), the orchestration sentinel that
  `/charter` never writes but its children read, and the unresolved placeholders still
  shipping in two of its phase files.
- Retrofitting existing documents. Whatever shape is chosen applies going forward; a
  migration of the current corpus is separate work.

## References

- `skills/strategy/references/strategy-format.md` — the explicit multiple-STRATEGYs rule
  and the Downstream Artifacts contract.
- `skills/vision/references/vision-format.md` — the plural downstream list and the
  at-least-one lifecycle condition.
- `crates/shirabe-validate/src/lifecycle.rs` — the chain walk, the document index, and
  the documented exclusion of the strategic directories.
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — the consolidation
  judgment's absorbability test and absorb mechanics.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — Decision 9, which
  settles the consolidation half on the strategic chain.
