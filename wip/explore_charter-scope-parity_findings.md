# Explore Findings: charter-scope-parity

Round 1. Seven leads, all completed. Research files under
`wip/research/explore_charter-scope-parity_r1_lead-*.md`.

**Visibility note.** The strategic corpus lives in a private repo. This file records
shapes, counts and mechanisms only; no private document names appear here, and none
should be added.

---

## The headline

The question as posed — should the `/scope` overhaul be applied to `/charter` — has
a clean answer: **essentially nothing is left to port.** But the cardinality question
underneath it surfaces live defects, and they are mostly not where anyone expected.

## 1. The transplant question is already settled, three times over

PR #260 made three coupled moves. Each has a different status on the strategic side.

**Upstream-path invocation: already shipped in `/charter`.** R6 passes the VISION
path to `/strategy`, which reads it as Input Mode 3 and records it as `upstream:`.
STRATEGY's required Strategic Context section is *defined* as carry-forward of the
essential framing from the upstream VISION. The consumption contract the tactical
chain had to invent in #260 already existed here.

**Always-run: substantially present.** `/strategy` is unconditional and always was;
`/roadmap` became unconditional-with-author-declination in #252. `/comp` is not a
chain member at all (see §3). That leaves `/vision`, and its auto-skip turns out to
be correctly filed — see §4. There is no computed threshold and no altitude
selection left in `/charter` to remove.

**Consolidation: rejected by name, premise verified.**
`DESIGN-scope-consolidation-over-skipping.md` Decision 9 evaluated it as Option B and
rejected it, on the grounds that zero strategic hops are section-mappable. That
premise was independently checked against
`crates/shirabe-validate/src/formats.rs:145-220` and holds: STRATEGY has no home for
a VISION's Audience, Value Proposition, Org Fit or Success Criteria; ROADMAP has no
home for a STRATEGY's Defensibility Thesis, Bet-Specific Falsifiability, Non-Goals or
Downstream Artifacts.

Two caveats on that rejection. It is schema-conditional by construction — Decision 4
derives absorbability from `formats.rs` precisely so the answer re-derives if a
format changes. And its claim that `/charter` "has already taken the run-every-child
half" is true for `/roadmap` alone; it says nothing about `/vision` or `/comp`.
Cardinality is never mentioned in it.

## 2. The chain shapes are not what the notation implies — on both sides

Measured across 210 declared `upstream:` edges in every repo in the workspace.

**Tactical, believed 1:1:1:1, is not.** `PRD -> DESIGN` fans out in three real cases:
one PRD with nine DESIGNs, one with four, one with two. This is produced by a
documented mechanism, not drift — `/design`'s decomposition phase splits on
independent decision-question count, proposes a split at 8-9 and refuses outright at
10+. `BRIEF -> PRD` is uniformly 1:1 at 58 of 58 parents. `DESIGN -> PLAN` is 1:1 at
8 of 8, unconstrained.

**Strategic is 1:N, as suspected.** `VISION -> STRATEGY` is confirmed 1:N in the real
corpus and stated in the format spec: `skills/strategy/references/strategy-format.md:278`
— "Multiple STRATEGYs may operate under one upstream VISION when they make distinct
bets." The lifecycle tables carry the same asymmetry: a VISION is Active when **at
least one** STRATEGY references it; a STRATEGY is Active when **a** ROADMAP does.
`STRATEGY -> ROADMAP` is 1:1 in all four observed cases but unconstrained — and each
of those four pairs was committed in a single commit, i.e. one `/charter` run's
output, so the 1:1 reflects what the tool emits rather than what the model allows.

**Two links exist that appear in no chain notation.** `VISION -> VISION` is real and
in use, an org-scope vision parenting four project-scope ones. And the chain is
skipped more often than followed: seven ROADMAPs point straight at a VISION versus
four at a STRATEGY, plus a VISION -> DESIGN edge jumping two levels.

**The author confirms both strategic links have been hit in real use.** This is not
a specification-only shape.

## 3. COMP is not a chain member

Positive evidence of absence, not missing evidence. COMP has no `upstream` frontmatter
field at all (`skills/comp/references/comp-format.md:25-26` — "There are no optional
frontmatter fields"). It has zero edges in either direction. `/charter`'s own chain
declaration reads "VISION → STRATEGY → ROADMAP"; COMP appears only as a gated feeder,
and its skip is deliberately never recorded anywhere. A real STRATEGY in the corpus
says it outright, calling competitive analysis a parallel trigger into the strategic
chain rather than a step within it.

So `VISION -> STRATEGY -> COMP -> ROADMAP` has one confirmed fan-out, one member that
is not a member, and a third link that is 1:1 only because nobody has written a second
roadmap under one strategy yet.

## 4. `/charter` cannot express the shape its own formats describe

This is the sharpest finding, and it is a structural gap rather than a mislabelled one.

`/charter` keys everything on a single validated `<topic>` slug and looks up exactly
one canonical path per child. Trace a second bet under a live VISION:

- Author runs `/charter <topic2>`; the existing vision is at `VISION-<topic1>.md`.
- The lookup for `docs/visions/VISION-<topic2>.md` misses, so `/charter` reads a cold
  start — and the cold-start rule is absolute: `/vision` runs and "nothing the author
  says about the thesis changes that."
- A **second VISION** is written, and `/strategy` is grounded in it rather than in the
  existing thesis.

The reverse horn closes the other exit: reuse `<topic1>` so the vision lookup hits,
and `/strategy`'s output path collides with the first STRATEGY, routing the run into
the resume ladder as re-entry into the same bet. Slug-sharing and slug-distinctness
are mutually exclusive under one key, so **the intended shape is not reachable through
`/charter` at all.**

Three schema fields independently forbid repeats within a run (`chain_ran` as a
sub-list of child names, `child_snapshots` keyed one-per-child, `exit_artifacts` fixed
at two entries on a full run) — but relaxing them would change nothing, because two
STRATEGYs in one run still resolve to one filename. The naming convention forces 1:1
before any schema field is consulted.

**Consequence for the skip vocabulary.** Charter's `/vision` auto-skip is *correctly*
filed as re-entry protection: slug-keying means the only runs reaching it are ones
where re-running would rewrite the file in place. The missing thing is not a wrong
reason string but an absent case. There is no vocabulary for "this upstream is being
reused by a new downstream," and no state field records that a run consumed an
upstream it did not produce.

**How the author does it today: by bypassing the parent.** `/strategy` Input Mode 3
accepts an arbitrary VISION path and derives its own slug. The child is strictly more
capable than the parent here — `/charter` rejects paths by construction. That is the
workaround the live fan-out was built with.

**A coincidence hides all of this.** On a same-slug run where the `/vision` skip does
fire, `/charter` hands that same VISION to `/strategy` as its upstream. So reuse of an
unwritten-this-run upstream is *already happening* on every skipped-`/vision` run — it
just rides on slug identity and is recorded only as protection. No state field says
this run's STRATEGY hangs off an upstream the run did not produce.

Charter's own requirements gesture at the missing concept and lose it in
implementation: `PRD-shirabe-charter-skill.md:290-294` scopes the skip to a VISION
"matching the chain's scope," a scope-match notion the implementation renders as an
exact-slug path check and nothing more. SKILL.md similarly promises upstream references
are "detected during Phase 1 discovery by inspecting the topic-related child docs that
exist in the repo" — a phrase never operationalized beyond that same slug check.

## 5. Where 1:N actually breaks the CLI — and it is the tactical chain

Six concentrated sites, not a diffuse assumption.

The load-bearing one is conceptual: **posture is a property of a chain, and a chain is
identified by its root.** A document with N downstream roots belongs to N chains and
inherits N postures, which the passing-state table applies as N independent
obligations on one mutable `status:` field. For BRIEF and PRD those obligation sets
are disjoint, so the document is unsatisfiable. That is a consequence of putting
posture on the chain rather than on the edge — not a bug a patch to one function
fixes. And it bites *today*, because `PRD -> DESIGN` fan-out is real in three places.

Supporting findings:

- `--lifecycle-chain` results depend on filenames. Renaming a plan with no content
  change anywhere flipped a shared BRIEF from 0 findings to 2. Nothing in the CLI
  surface hints that chain selection is order-dependent.
- Multi-upstream YAML lists are unreachable from idiomatic syntax: the frontmatter
  parser collapses every YAML sequence to `""` before the plural handling sees it. The
  `Vec<PathBuf>` and its multi-value contract have never been reachable except via a
  block scalar, and the doc comment claiming otherwise is factually wrong. The failure
  message an author gets is `upstream "" does not exist on disk`.
- **Correction (Phase 2 of the downstream PRD).** An earlier round of this exploration
  reported a checked-in assertion-free probe at `crates/shirabe-validate/tests/probe_1n.rs`
  asking exactly this question. **That file does not exist and never has** — the crate has
  no `tests/` directory, and `git log --all --diff-filter=A` finds no such path on any
  branch. The substantive claims about list-shaped `upstream:` behavior were independently
  re-derived and hold; only the artifact attribution was wrong. Nothing downstream should
  lean on "a probe already documents this."
- Fan-out *discovery* is already correct — the breakage is entirely downstream of it,
  in how per-chain postures are applied to shared members.

**The strategic chain, by contrast, cannot break because nothing looks at it.**
`docs/visions/`, `docs/strategies/` and `docs/competitive/` are not in the lifecycle
doc index at all, and the exclusion is deliberate and documented. The strategic chain
has zero chain-level validation. `STRATEGY` is not even a recognized prefix in the
upstream walk. There is no rollup at the strategy level to get wrong: `populate` reads
one roadmap's own Features section and never opens a STRATEGY. And `Downstream
Artifacts` — the one section whose name suggests it records fan-out — is a required
STRATEGY section with no content validation whatsoever. It could name two roadmaps or
none and nothing would notice.

## 6. Absorption is safe today by coincidence

The only hop `/scope` can absorb is `BRIEF -> PRD`, which is the one uniformly-1:1 hop
in the corpus. But nothing ties absorbability to single-successor-ness: the stated
Stage 1 criterion is section-mapping totality alone, which would license an absorb on
a fanned-out hop just as readily if two formats happened to line up.

The mechanics have no guard either. Stage 3 re-points the survivor's `upstream:` and
`git rm`s the absorbed artifact, then re-validates **the survivor**. The R6 check is
per-document — it flags a dangling `upstream:` in the document under test, not other
documents pointing at a deleted file — and CI validates only the PR's changed files. A
sibling still pointing at an absorbed upstream would survive both the absorb-time
re-validation and that PR's CI, surfacing only when the sibling is next touched.
Nothing anywhere counts consumers.

## 7. Adjacent defects surfaced, not pursued

Recorded so they are not lost: `/charter` never writes the `parent_orchestration:`
block, yet `/vision` and `/strategy` both open their resume ladders by reading that
sentinel out of charter's state file. `chain_skipped` entries are `{child, reason}` in
`/charter` and `{name, reason}` in `/scope` (issue #254). Unresolved `<<ISSUE:5>>`
placeholders still ship in two charter phase files. Charter's `--max-rounds` default
is documented as unbounded in its own SKILL.md and as 3 in `/scope`'s. Whether a
skipped `/vision` belongs in `planned_chain` is left unsettled by three passages that
disagree. Two real strategic documents violate the one-level-deep downstream rule with
nothing catching it, because those directories are not validated.

## Gaps and open questions

- Is `PRD -> DESIGN` fan-out intended, tolerated, or forbidden? No document says. It
  happens three times and has a documented producing mechanism, which reads as
  intended — but the CLI's posture model has no answer for it.
- Where does a split DESIGN's second document land in `/scope`'s state? The fan-out is
  created by the child mid-run — `/design`'s split heuristic — which `/scope` cannot
  see at Phase 1. `/scope` has one `design` slot with one canonical path, and the
  hand-back R20 check tests one canonical artifact path. Undefined today.
- If a document legitimately belongs to two chains at different postures, what *is*
  the intended passing state? This is a product question about whether posture belongs
  to the chain or the edge.
- Should the strategic chain enter the lifecycle doc index at all? Today its exclusion
  is what keeps it from breaking.
- Should Stage 1 absorbability test consumer count as well as mapping totality?
- Would letting `/charter` accept a VISION path conflict with its path-rejection rule,
  or is that rule aimed only at the topic-slug argument slot?

## Decision: Crystallize
