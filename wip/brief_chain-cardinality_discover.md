# Brief Discover: chain-cardinality

## Grounding

Upstream is an `/explore` run on topic `charter-scope-parity`, whose findings are at
`wip/explore_charter-scope-parity_findings.md` with seven research files under
`wip/research/`. That exploration started from a different question — whether PR #260's
`/scope` overhaul should be ported to `/charter` — established that essentially nothing
remains to port, and surfaced this problem underneath it.

No durable upstream artifact exists: the exploration's outputs are all `wip/`. The BRIEF
therefore omits `upstream:` rather than pointing at a non-durable path.

## Framing decision

The author chose the widest of three framings: one problem spanning both chains and both
layers, rather than isolating the strategic expressibility gap or the CLI model. The
justification is that the two faces share a cause — lineage that fans out is describable
in the formats and unrepresentable everywhere else — and splitting them would produce two
briefs that each have to restate the same shape.

## Problem/outcome pair

**Problem.** The document formats describe one-to-many lineage and authors use it, but
neither the parent skills nor the validator can express or check that shape. Reuse of an
existing upstream is unreachable through the parent, and a document with several
downstream roots inherits obligations no single status can satisfy.

**Outcome.** An author with one thesis and several bets under it works through the tools
rather than around them, and a document with more than one consumer stays in a state the
validator accepts.

## Evidence carried forward

- `strategy-format.md:278` sanctions multiple STRATEGYs under one VISION; the lifecycle
  table reads "at least one" on the VISION side and "a" on the STRATEGY side.
- Both strategic links confirmed live in real use by the author. Artifacts are private,
  so no public instance exists to cite.
- Tactical fan-out is public and real: `PRD -> DESIGN` at 1:9, 1:4 and 1:2, produced by
  `/design`'s split heuristic, which proposes at 8-9 decision questions and refuses at 10+.
  `BRIEF -> PRD` is 58/58 exactly 1:1.
- `/charter` resolves every path from one topic slug; the second-bet trace writes a
  duplicate VISION, and the same-slug alternative collides on the STRATEGY path.
- `/strategy` Input Mode 3 accepts an arbitrary VISION path — the child can express what
  the parent cannot.
- Posture attaches to a chain identified by its root; N downstream roots means N postures
  on one mutable `status:` field, disjoint for BRIEF and PRD.
- `docs/visions/`, `docs/strategies/` and `docs/competitive/` are outside the lifecycle
  doc index by deliberate, documented choice.
- Nothing anywhere counts consumers; the absorb re-validates only the survivor and CI
  validates only changed files.

## Deferred to the PRD

Whether the answer is to support fan-out, constrain it, or only validate it. The brief
frames the gap; the requirements contract picks the posture.
