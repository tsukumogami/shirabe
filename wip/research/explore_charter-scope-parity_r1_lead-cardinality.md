# Lead: What is the real cardinality between artifact types in both chains?

Evidence gathered 2026-08-13 across all repos in the tsukumogami workspace
(`private/vision`, `private/tools`, `public/koto`, `public/niwa`,
`public/shirabe`, `public/tsuku`). Method: extract the `upstream:`
frontmatter edge from every `VISION-*`, `STRATEGY-*`, `COMP-*`,
`ROADMAP-*`, `BRIEF-*`, `PRD-*`, `DESIGN-*`, `PLAN-*` document on disk,
then group by parent to compute observed fan-out. 210 declared edges
total. Git history checked with `--diff-filter=AD` for docs later
deleted or superseded.

## Findings

### Where the real corpus lives

Almost nothing strategic exists under `public/`. Every real VISION,
STRATEGY and COMP lives in **`private/vision/docs/`** — 7 VISIONs,
4 STRATEGYs, 11 ROADMAPs, 1 COMP. `public/` contributes exactly one
real ROADMAP (`public/tsuku/docs/roadmaps/ROADMAP-auto-update.md`).
Every other VISION/STRATEGY/COMP/ROADMAP path under `public/` is a
test or eval fixture under `crates/shirabe/tests/fixtures/` or
`skills/*/evals/fixtures/`. The tactical corpus (BRIEF/PRD/DESIGN/PLAN)
is large and spread across all six repos.

### The observed strategic graph

```
VISION-tsukumogami (scope: org, Accepted)
├── VISION-bunki, VISION-koto, VISION-niwa, VISION-shirabe   [4 child VISIONs]
├── STRATEGY-event-driven-dispatch                            [2 STRATEGYs]
├── STRATEGY-shirabe-evolution
├── ROADMAP-tsukumogami                                       [skips STRATEGY]
└── DESIGN-bunki-koto-data-model                              [skips 2 levels]

VISION-koto    → STRATEGY-koto-agent-surface-legibility, ROADMAP-koto
VISION-shirabe → STRATEGY-shirabe-rust-consolidation,    ROADMAP-shirabe
VISION-niwa    → ROADMAP-niwa
VISION-bunki   → ROADMAP-bunki
VISION-koto-observability-vision (Sunset) → ROADMAP-koto-observability
VISION-niwa-collab-surface (Sunset)       → ROADMAP-niwa-collab-surface

STRATEGY-event-driven-dispatch          → ROADMAP-event-driven-dispatch
STRATEGY-koto-agent-surface-legibility  → ROADMAP-koto-agent-surface-legibility
STRATEGY-shirabe-evolution              → ROADMAP-shirabe-evolution
STRATEGY-shirabe-rust-consolidation     → ROADMAP-shirabe-rust-consolidation

COMP-superpowers-vs-koto: 0 in-edges, 0 out-edges
```

Fan-out by link, counted over distinct parents:

| Link | Parents | Fan-out distribution |
|---|---|---|
| VISION→VISION | 1 | one parent at 4 |
| VISION→STRATEGY | 3 | two at 1, one at **2** |
| VISION→ROADMAP (chain-skipping) | 7 | all at 1 |
| VISION→DESIGN (chain-skipping) | 1 | at 1 |
| STRATEGY→ROADMAP | 4 | all at 1 |
| STRATEGY→COMP | 0 | — |

Git history adds nothing hidden. Every STRATEGY and its single ROADMAP
were **added in the same commit**, four times over — `696ba30`
(2026-07-18), `10473f1` (2026-07-14), `69840ca` (2026-05-24), `ef2891f`
(2026-05-23), all in `private/vision`. No strategic doc has ever been
deleted except `docs/roadmaps/ROADMAP-niwa.md` (removed in `4011cc5`,
re-added later). The observed STRATEGY→ROADMAP 1:1 is therefore not a
survivorship artifact: each pair was authored in one sitting, which is
exactly what one `/charter` run produces.

### The observed tactical graph

| Link | Parents | Fan-out distribution |
|---|---|---|
| ROADMAP→BRIEF | 1 | one at 2 |
| ROADMAP→PRD (skips BRIEF) | 2 | one at 1, one at 2 |
| BRIEF→PRD | 58 | **all 58 at exactly 1** |
| PRD→DESIGN | 92 | 89 at 1, one at 2, one at **4**, one at **9** |
| DESIGN→PLAN | 8 | all at 1 |

The 1:N PRD→DESIGN cases by name:

- `public/tsuku/docs/prds/PRD-auto-update.md` → **9** DESIGNs
  (`DESIGN-self-update`, `DESIGN-background-update-checks`,
  `DESIGN-channel-aware-resolution`, `DESIGN-notification-system`,
  `DESIGN-auto-apply-rollback`, `DESIGN-project-level-auto-update`,
  `DESIGN-resilience`, `DESIGN-update-outcome-telemetry`,
  `DESIGN-update-polish`)
- `public/koto/docs/prds/PRD-gate-transition-contract.md` → **4**
  (`DESIGN-gate-backward-compat`,
  `DESIGN-gate-contract-compiler-validation`,
  `DESIGN-gate-override-mechanism`, `DESIGN-structured-gate-output`)
- `public/koto/docs/prds/PRD-session-persistence-storage.md` → **2**
  (`DESIGN-config-and-cloud-sync`, `DESIGN-local-session-storage`)

This is designed behavior, not drift.
`skills/design/references/phases/phase-1-decomposition.md:41-46` scales
on decision-question count: at 8-9 questions the skill "Present[s]
split proposal, require[s] confirmation"; at 10+ it "Refuse[s],
require[s] splitting". One PRD exceeding the decision budget is
*expected* to become several DESIGNs.

There are also off-chain edges the four-link picture does not contain:
4 DESIGN→DESIGN (via the separate `spawned_from` field,
`skills/design/references/design-format.md:65-68`), 4 DESIGN→BRIEF and
2 PLAN→BRIEF (follow-up briefs spawned mid-implementation — e.g.
`DESIGN-roadmap-plan-standardization` → three BRIEFs in
`public/shirabe`), 2 BRIEF→BRIEF, 1 PRD→PRD, 1 PRD→PLAN,
1 ROADMAP→DESIGN.

### What the schema permits

`upstream:` is **optional on every artifact type**:

- VISION — `skills/vision/references/vision-format.md:32`
- STRATEGY — `skills/strategy/references/strategy-format.md:34`
- ROADMAP — `skills/roadmap/references/roadmap-format.md:64-66`
- BRIEF — `skills/brief/references/brief-format.md:42`
- PRD — `skills/prd/references/prd-format.md:38`
- DESIGN — `skills/design/references/design-format.md:45`
- PLAN — `skills/plan/references/quality/plan-doc-structure.md:75`
- COMP — **no `upstream` field at all** (see below)

It is a **single scalar to the validator, but the parser tolerates
lists**. `check_upstream_resolves` reads `field.value` as one path
(`crates/shirabe-validate/src/checks.rs:790`). `extract_upstreams`
(`crates/shirabe-validate/src/lifecycle.rs:396-436`) explicitly handles
both shapes — its doc comment reads "Handles two shapes: scalar
(`upstream: path`) and list-of-lines (the `FieldValue` carries
multi-line content when the YAML is a list)". The chain walk at
`lifecycle.rs:519-542` then discards the extras:

> "Take the first upstream if multiple are present (the additional
> upstreams are typically optional context, e.g. ROADMAP parents)."

A live probe test for exactly this question is already in the tree:
`crates/shirabe-validate/tests/probe_1n.rs`, headed "Temporary probe:
how do multi-upstream and 1:N chain shapes behave?" It exercises block
sequence, flow sequence, block scalar and plain scalar, and notes at
line 43 that the resolution check "reads field.value as ONE path".

**No validation constrains fan-out anywhere.** The seven lifecycle
checks (`lifecycle.rs:11-45`) cover status mismatch, orphans, cycles,
missing parents, parse failures, unticked ACs, and DESIGN directory
placement. None counts children. And the doc index
(`lifecycle.rs:275-282`) walks only `docs/briefs`, `docs/prds`,
`docs/designs`, `docs/designs/current`, `docs/plans`, `docs/roadmaps` —
**`docs/visions/`, `docs/strategies/` and `docs/competitive/` are never
indexed**. Stated deliberately at `lifecycle.rs:530-538`: "The
strategic chain is out of scope here, not absent."

The downstream side is a **list** in both strategic formats. VISION's
Downstream Artifacts is "added when the first STRATEGY that
operationalizes this VISION exists. Lists paths to the STRATEGY
documents that carry the thesis forward"
(`skills/vision/references/vision-format.md:65-67`). STRATEGY's is
"populated as downstream ROADMAPs land that reference this STRATEGY as
their upstream"
(`skills/strategy/references/strategy-format.md:425-426`).

### Direct quotes on cardinality

The single most explicit statement,
`skills/strategy/references/strategy-format.md:278-279`:

> "One Active STRATEGY per bet at a time. **Multiple STRATEGYs may
> operate under one upstream VISION when they make distinct bets.**"

The lifecycle-state definitions carry a telling asymmetry.
VISION at `skills/vision/references/vision-format.md:133`:

> "Active | **At least one** STRATEGY references this VISION as its
> upstream."

STRATEGY at `skills/strategy/references/strategy-format.md:230`:

> "Active | **A** ROADMAP references this STRATEGY as its upstream and
> is sequencing its work."

On the tactical side, the roadmap reviewer enforces feature:PRD as 1:1
from above — `skills/roadmap/references/phases/phase-4-validate.md:49-51`:

> "Is each feature independently describable at PRD level? A feature
> that can't stand alone as a PRD is too granular. **A feature that
> would need multiple PRDs is too broad.**"

`/scope`'s consolidation rule assumes one PRD per BRIEF while allowing
the count to go *down*, never up —
`skills/scope/references/phases/phase-2-chain-orchestration.md:428-434`:

> "a BRIEF that fed one PRD and did no independent framing work is a
> redundant document rather than a redundant paragraph."

Its absorbability table at `:402-406` says BRIEF→PRD is absorbable;
PRD→DESIGN and DESIGN→PLAN are not ("have no home").

`/charter` produces exactly one STRATEGY and at most one ROADMAP **per
run** (`skills/charter/references/phases/phase-finalization.md:88-108`) —
per-invocation cardinality, not per-VISION.

### COMP is not a chain link

Four independent lines of evidence:

1. **No `upstream` field exists.**
   `skills/comp/references/comp-format.md:25-26`: "Required fields:
   `status`, `problem`, `scope`. **There are no optional frontmatter
   fields.**" (`skills/comp/SKILL.md:115` accepts a `--upstream <path>`
   argument as scoping context, but nothing lands in frontmatter.)
2. **`/charter`'s own chain declaration excludes it.**
   `skills/charter/SKILL.md:5` and `:21` both say the chain is
   "VISION → STRATEGY → ROADMAP". COMP appears only as a gated feeder.
3. **The gate is conditional and the pattern calls it optional.**
   `references/parent-skill-pattern.md:199-200`: "A parent MAY offer a
   feeder skill (**a side-channel child the chain does not strictly
   require**) conditionally." `/charter` invokes `/comp` only when repo
   visibility is Private *and* `skills/comp/SKILL.md` exists on disk
   (`skills/charter/references/phases/phase-2-chain-orchestration.md:77-93`).
   On a public repo it is skipped conversationally, and the skip is
   deliberately never recorded in any committed file (`:113-129`).
4. **A real STRATEGY says so in prose.**
   `private/vision/docs/strategies/STRATEGY-shirabe-evolution.md:771-774`,
   under a section headed "When a separate COMP would be warranted":

   > "In any of those cases, the COMP analysis would feed forward into a
   > new STRATEGY (or revision of this one) rather than into the
   > upstream VISION — **confirming that competitive analysis is a
   > parallel trigger into the strategic chain, not a step within it.**"

Nothing downstream requires a COMP to exist. The one real COMP is cited
only as inline prose from `STRATEGY-shirabe-evolution.md` and
`ROADMAP-shirabe-evolution.md`, never as an `upstream:`.

### Verdict per link

| Link | Verdict |
|---|---|
| VISION→VISION | **Confirmed 1:N.** Fan-out 4 from VISION-tsukumogami. Format permits it (`vision-format.md:28`, project-level only). Not part of the declared chain. |
| VISION→STRATEGY | **Confirmed 1:N.** VISION-tsukumogami has 2. Format states it explicitly; lifecycle says "at least one"; downstream side is a list. |
| STRATEGY→COMP | **No such link.** COMP has no `upstream` field, zero observed edges either direction, documented as an orthogonal parallel trigger. |
| STRATEGY→ROADMAP | **Unconstrained but only 1:1 observed.** 4/4 at exactly 1, each pair committed together. Nothing forbids N: Downstream Artifacts is a list of ROADMAPs (plural), no validator counts children, `docs/strategies/` is not indexed. The "A ROADMAP" wording is weaker than VISION's "at least one" but is not a prohibition. |
| ROADMAP→BRIEF | **Confirmed 1:N**, on a weak base. Only 1 parent observed (ROADMAP-koto, fan-out 2); only 2 BRIEFs in the whole corpus declare a ROADMAP upstream. But it is the roadmap's stated purpose — it sequences multiple features, each becoming a BRIEF. |
| BRIEF→PRD | **Confirmed 1:1** across the largest sample in the corpus: 58/58 parents at exactly 1. Reinforced from above by "a feature that would need multiple PRDs is too broad", and from within by `/scope`'s absorb rule, which can only reduce the count to 0. |
| PRD→DESIGN | **Confirmed 1:N.** 3 of 92 parents fan out — to 2, 4 and 9. The design skill has an explicit split mechanism keyed on decision-question count (refuses at 10+). |
| DESIGN→PLAN | **Unconstrained but only 1:1 observed.** 8/8 at exactly 1. `/plan` states a 1:1 document-to-milestone invariant (`skills/plan/references/phases/phase-2-milestone.md:20-24`) and routes overflow to new *documents* via needs-design issues rather than to a second PLAN — that constrains the milestone, not the PLAN count, and no validator enforces either. |

## Implications

The working hypothesis was half right and half wrong, and the wrong
half is the tactical one.

**The strategic chain is genuinely not uniform.** VISION→STRATEGY is
confirmed 1:N both in practice and in the format spec's own words. COMP
is not a chain member by any reading — no upstream field, no edges, a
conditional gate, and prose in a real STRATEGY calling it a parallel
trigger. Two of the three strategic links therefore do not behave like
the 1:1 progression the chain notation "VISION → STRATEGY → ROADMAP"
implies.

**But the tactical chain is not 1:1:1:1 either.** PRD→DESIGN fans out
in three real cases, up to 1:9, and does so through a documented
mechanism in `/design` rather than by accident. Any parity argument
that rests on "tactical is uniform 1:1, strategic is not" is resting on
a premise the corpus contradicts. What is actually uniform is
BRIEF→PRD (58/58) and, on smaller samples, DESIGN→PLAN (8/8) and
STRATEGY→ROADMAP (4/4).

**Nothing enforces any of this.** No validator counts children on any
link in either chain, and `docs/visions/`, `docs/strategies/` and
`docs/competitive/` are not indexed by the lifecycle check at all. So
every "confirmed 1:1" in the table above is a behavioral observation
about what the authoring skills produce per run, not a constraint the
tooling holds. The 1:1 links are 1:1 because `/charter` and `/scope`
each emit one artifact per type per run — not because a second one
would be rejected.

**The list-shaped `upstream:` is a live seam.** The parser accepts
lists, the chain walk silently keeps only the first, the resolution
check treats the whole value as a single path, and a probe test named
`probe_1n.rs` sits in the tree unresolved. Anything that starts relying
on multi-parent edges lands in the gap between those three behaviors.

## Surprises

- **`probe_1n.rs` already exists.** Someone asked this exact question in
  code before it was asked in conversation:
  `crates/shirabe-validate/tests/probe_1n.rs`, "Temporary probe: how do
  multi-upstream and 1:N chain shapes behave?" It is a checked-in test
  with `println!` output and no assertions.
- **VISION→VISION is a real, used link that appears in no chain
  notation.** VISION-tsukumogami (org scope) parents four project-level
  VISIONs. The format documents the field
  (`vision-format.md:28`, "optional, project-level only") but every
  chain diagram in the skills reads VISION → STRATEGY → ROADMAP as if
  VISION were a root.
- **The chain is skipped more often than it is followed.** 7 ROADMAPs
  point straight at a VISION, versus 4 that point at a STRATEGY. There
  is also a VISION→DESIGN edge (`DESIGN-bunki-koto-data-model`) that
  jumps two levels. The formats explicitly permit omitting `upstream`
  rather than reaching past a neighbour
  (`roadmap-format.md:85-88`) — but the observed docs reach past it
  anyway.
- **Two real docs violate the one-level-deep rule and nothing catches
  it.** `VISION-shirabe.md:572` lists `ROADMAP-shirabe.md` in Downstream
  Artifacts, though `vision-format.md:122-123` says "that section lists
  STRATEGY documents only". `STRATEGY-shirabe-evolution.md:828` lists a
  DESIGN in the niwa repo, though `strategy-format.md:426-427` says
  "ROADMAPs only". Neither directory is validated.
- **The 1:9 fan-out is in the public tsuku repo**, the repo furthest
  from the shirabe skills work — `PRD-auto-update.md` with nine DESIGNs
  under it. The most extreme counterexample to tactical uniformity was
  sitting in the least-examined corner.

## Open Questions

- Is STRATEGY→ROADMAP 1:1 by intent or by coincidence of authoring? The
  four pairs were each committed together in a single `/charter`-shaped
  act, so the sample cannot distinguish "the link is 1:1" from "each run
  emits one of each". The format's "A ROADMAP references this STRATEGY"
  is the only signal pointing at 1:1, and it is weaker than VISION's
  "at least one" without being a prohibition.
- Same question for DESIGN→PLAN (8/8 at 1). `/plan`'s 1:1
  document-to-milestone invariant constrains milestones, not PLAN count.
  Whether a DESIGN may have two PLANs is undecided by both corpus and
  spec.
- What should happen when `upstream:` is a list? Three components
  currently disagree: the parser accepts it, the chain walk takes only
  the first, the resolution check treats the whole multi-line value as
  one path (and would report it missing). `probe_1n.rs` documents the
  disagreement without resolving it.
- Is the ROADMAP→BRIEF evidence base large enough to call? Only two
  BRIEFs in the entire workspace declare a ROADMAP upstream, both under
  ROADMAP-koto. Every other BRIEF (56 of 58) has no upstream at all,
  so the tactical chain's entry point is almost entirely unrecorded in
  frontmatter.
- Does anything intend to validate the strategic chain? The lifecycle
  check's comment says the strategic chain is "out of scope here, not
  absent" (`lifecycle.rs:530-538`), which reads as a deferral rather
  than a decision.

## Summary

The strategic chain is not uniform: VISION→STRATEGY is confirmed 1:N
(VISION-tsukumogami has two STRATEGYs, and the format says "Multiple
STRATEGYs may operate under one upstream VISION when they make distinct
bets"), and COMP is not a chain link at all — it has no `upstream`
field, zero edges in either direction, and a real STRATEGY describes it
as "a parallel trigger into the strategic chain, not a step within it."
STRATEGY→ROADMAP is 1:1 in all four observed cases, but unconstrained:
nothing forbids N, and each pair was committed in one act, so the sample
cannot separate the link's shape from `/charter`'s per-run output.

The tactical chain is **not** the clean 1:1:1:1 counterpart the
hypothesis assumed. BRIEF→PRD is 1:1 across 58 of 58 parents, and
DESIGN→PLAN across 8 of 8 — but PRD→DESIGN fans out in three real cases,
to 2, 4 and 9 DESIGNs, through a documented split mechanism in `/design`
keyed on decision-question count. There is also a VISION→VISION link in
active use that appears in no chain notation, and seven ROADMAPs that
skip STRATEGY entirely to point straight at a VISION.

Underneath all of it, no validator counts children on any link in either
chain, and `docs/visions/`, `docs/strategies/` and `docs/competitive/`
are never indexed by the lifecycle check. Every observed 1:1 is a fact
about what the authoring skills emit per run, not a constraint the
tooling holds.
