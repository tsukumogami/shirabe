# Completeness Verdict — PRD-upstream-link-legality

**Verdict:** FAIL

All three of my previous required changes landed and hold up under re-checking.
The revision introduces one new completeness defect of its own: R22's list of
affected eval expectations is four rows, and there is a fifth.

## Claim verification

### R5.2's account of what the references document — **HOLDS, with one loose attribution**

| R5.2 claim | Source | Verdict |
|---|---|---|
| `pipeline-model.md` states a BRIEF's upstream is a ROADMAP | "Brief (upstream: Roadmap, per feature)"; "`/brief` crosses that boundary by taking a Roadmap as its upstream" | accurate |
| ...that a PRD's is a ROADMAP when no BRIEF was written | "A feature framed directly in its PRD has no BRIEF, so that PRD's upstream is the Roadmap" | accurate, near-verbatim |
| ...that a DESIGN's is whatever preceded it | pipeline-model applies the phrase "whatever preceded it" to the **PLAN**, not the DESIGN: "a feature that needs no architectural decision has no DESIGN, so the PLAN's upstream is whatever preceded it" | **substance holds, attribution is loose** |
| `prd-format.md` repeats the PRD case | `prd-format.md:27-29` — "the nearest parent produced above this PRD -- a ROADMAP when no BRIEF was written" | accurate |

On the DESIGN row: the conclusion is right and the citation is not. DESIGN can
legally name a ROADMAP today under the general nearest-produced sentence ("Each
artifact's `upstream` field points to the nearest artifact actually produced
above it"), and the shape is exercised in the tree —
`skills/execute/evals/fixtures/designs/DESIGN-cascade-test-short.md:3` names a
ROADMAP directly, and `run-cascade_test.sh` Scenario 1 builds `PLAN → DESIGN →
ROADMAP`. But the sentence R5.2 borrows to support it is about the PLAN. Cite
the nearest-produced rule instead of the PLAN sentence.

The consequence R5.2 states — no durable tactical document may name a ROADMAP,
so the strategic-to-tactical crossing lands on the PLAN alone — is correct and
is what R4 forces. That was my first required change and it is discharged.

### R24's eight rows — **HOLD, every row, both columns**

Re-verified against the corpus research's complete edge table. Rows 1-3
(`BRIEF-fc06-index-alias`, `BRIEF-lifecycle-draft-ready-discipline`,
`BRIEF-skill-cascade-lifecycle-check`) are the three clean-today edges, R6 pass
and TP FAIL. Rows 4-5 (`BRIEF-cascade-outline-ac-completeness`,
`BRIEF-single-pr-plan-validation`) are the two BRIEF→PLAN edges that fail both
properties, correctly reported as lifetime under R7's precedence. Rows 6-8 are
the three BRIEF→DESIGN edges with LC pass. The trailing counts (73 legal edges,
68 no-field documents) match corpus Steps 1 and 3.

Scoping R24 to "every document under `docs/`" is an improvement: it makes the
count exact and makes R23's fixture carve-out coherent.

### R22's four eval entries — **ALL FOUR ACCURATE, BUT THE LIST IS INCOMPLETE**

Each of the four names a real scenario asserting what the table says:

| Eval | Verified |
|---|---|
| `brief` / `upstream-roadmap-grounding` (id 2) | expectation: "Plan declares the ROADMAP path as the BRIEF frontmatter upstream field" |
| `brief` / `upstream-flag` (id 12) | expected_output: "Phase 2 writes upstream: docs/roadmaps/ROADMAP-editor.md into docs/briefs/BRIEF-inline-diff.md" |
| `scope` / `upstream-flag-consumed` (id 23) | expected_output: "the produced docs/briefs/BRIEF-inline-diff.md carries upstream: docs/roadmaps/ROADMAP-editor.md in its frontmatter" |
| `execute` / full-chain cascade (id at `evals.json:328`) | expected_output: "The chain is PLAN -> DESIGN -> PRD -> BRIEF -> ROADMAP" |

**The fifth:** `skills/scope/evals/evals.json:373`,
`pre-authoring-notice-cold-start` (id 25), asserts an author-facing notice
**verbatim**, including the clause:

> "re-invoke as `/scope inline-diff --upstream <path-to-the-ROADMAP>` and this
> chain will attach the BRIEF to it"

Under R13 the chain no longer attaches the BRIEF to the roadmap — R14 attaches
the PLAN. The notice becomes false as written, and the same string is committed
in the skill itself at `skills/scope/references/phases/phase-1-discovery.md:304`
and `:341`, so the prose has to change and the eval's verbatim assertion changes
with it. This is precisely the failure R22 exists to prevent ("named here so the
change is visible in review rather than discovered in a diff"), and the
acceptance criterion "no eval outside that list changes" would be violated by a
correct implementation.

### R23's two fixtures — **BOTH CARRY FORBIDDEN EDGES, AS DESCRIBED**

- `skills/execute/evals/fixtures/briefs/BRIEF-cascade-test-full.md:4` —
  `upstream: skills/execute/evals/fixtures/roadmaps/ROADMAP-cascade-test.md`.
  Durable BRIEF naming a Working ROADMAP: forbidden on both properties.
- `skills/execute/evals/fixtures/designs/DESIGN-cascade-test-short.md:3` — the
  same ROADMAP path. R23's wording "names one directly" is exact: this is the
  DESIGN→ROADMAP shape, not a transitive reach.

Keeping them as frozen regression evidence for R18 is coherent. Minor: R23
exempts them from "R24's no-other-changes clause," but R24 is now scoped to
`docs/` and these live under `skills/`, so the exemption is a no-op. Harmless.

### R21's golden-corpus claim — **HOLDS** (checked because it looked fragile)

Four golden fixtures carry `upstream:`. Three are unaffected:
`PLAN-roadmap-plan-standardization.md` (PLAN→DESIGN, legal),
`DESIGN-gha-doc-validation.md` (DESIGN→PRD, legal), and
`PLAN-r6-broken-upstream.md` (`synthetic/this-upstream-does-not-exist.md`, no
artifact prefix, unchecked under R9).

The fourth looked like a counterexample:
`crates/shirabe/tests/fixtures/golden/corpus/real/PRD-roadmap-skill.md:12`
carries `upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md` — a Durable PRD
naming a Working ROADMAP, forbidden under R5. Its frozen expected output is
`expected/real/PRD-roadmap-skill.md.stdout`, which contains exactly
`::notice ...::schema field missing, skipping`. The document is skipped before
any check runs, so no new finding lands and the frozen output stays
byte-identical. R21 and its acceptance criterion survive — by one line of
fixture accident rather than by design, which is worth knowing but not worth
requiring anything about.

### Previously verified, unchanged and re-confirmed

R2's lifetime classes against all eight `## Artifact Lifecycle` sections; R8's
no-indexing claim; R9/R10 against `upstream.rs` and `checks.rs`; R25's exit-0
baseline; Known Limitations' three-versus-zero corpus yield.

## Coverage

Every brief IN item still has a requirement, and the two previously thin spots
are now covered: the `/explore` → `/roadmap` VISION handoff is R15 with its own
acceptance criterion (my second required change, discharged), and the roadmap
link's new home is R14 with `/plan` accepting it on the flag rather than the
positional slot (which also avoids the slug-collision failure the writers
research documents).

R16/R16.1 resolve the tension I flagged: the absorb re-point is placed after
both children return, as a statement about the corpus rather than an override of
what a child recorded, and R13 makes the absorbed brief upstream-less so the
existing "remove the field" branch does the right thing. That reasoning holds
against `scope/phase-2-chain-orchestration.md:485-501`.

Both brief Open Questions remain closed in Decisions and Trade-offs.

Acceptance-criteria coverage is materially better than the previous draft: R15,
R14, R22 and R23 each have a criterion. R11 is still only exercised through the
`/brief`, `/scope`, `/plan` and `/explore` criteria rather than in general,
which I consider acceptable now that the specific producers are named.

## Gaps / scope creep

1. **R22 names four eval expectations; there are five.** See above. This is the
   only FAIL driver.
2. **R5.2's DESIGN citation.** Substance right, attributed sentence wrong.
3. No scope creep. Nothing from the brief's OUT list has been absorbed, and the
   new requirements (R14, R15, R21-R23) all trace to the brief's IN item about
   keeping consumers whole or to the change-visibility discipline R24 owns.
4. Note, not a required change: no eval covers R14's new `/plan --upstream`
   surface. Adding one is not "changing an eval outside the list," so it does
   not conflict with R22's acceptance criterion, but the flag ships ungraded
   unless a scenario is added.

## Required changes

1. Add the fifth row to R22: `skills/scope/evals/evals.json` /
   `pre-authoring-notice-cold-start`, which asserts verbatim that supplying
   `--upstream <ROADMAP>` means "this chain will attach the BRIEF to it."
   Disposition: reworded, because R14 attaches the PLAN. Note that the same
   string is committed at `skills/scope/references/phases/phase-1-discovery.md:304`
   and `:341`, so the skill prose changes with it.

2. Fix R5.2's DESIGN attribution. `pipeline-model.md` applies "whatever preceded
   it" to the PLAN. The sentence that makes DESIGN→ROADMAP legal today is the
   nearest-produced rule — "Each artifact's `upstream` field points to the
   nearest artifact actually produced above it" — and the shape is exercised by
   `DESIGN-cascade-test-short.md` and `run-cascade_test.sh` Scenario 1. Cite
   those instead.
