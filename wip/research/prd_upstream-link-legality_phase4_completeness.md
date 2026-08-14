# Completeness Verdict — PRD-upstream-link-legality

**Verdict:** FAIL

One claim in R5 does not hold against the source it cites, and the consequence
it hides is a scope gap rather than a wording nit. Everything else checked out,
including all eight rows of R20 and the Known Limitations admission.

## Claim verification

### R5's "encodes rather than changes" claim — **DOES NOT HOLD**

Source: `references/pipeline-model.md:120-140`, plus
`skills/vision/references/vision-format.md:28,37-40` for the VISION row.

Row by row:

| R5 row | pipeline-model says | Verdict |
|---|---|---|
| VISION ← VISION | vision-format.md:28: "path to parent VISION when a project-level doc derives from an org-level one" | holds |
| STRATEGY ← VISION | "Strategy (upstream: VISION)"; strategic chain "strict in both directions" | holds |
| ROADMAP ← STRATEGY | "a Roadmap's upstream is the STRATEGY it sequences" | holds |
| BRIEF ← *(none)* | "Brief (upstream: Roadmap, per feature)" and "`/brief` crosses that boundary by taking a Roadmap as its upstream" | **changes** — acknowledged by the PRD in the paragraph below the table |
| PRD ← BRIEF | "A feature framed directly in its PRD has no BRIEF, so that PRD's upstream is the Roadmap" (`pipeline-model.md:132-133`), restated in `skills/prd/references/prd-format.md:27-29` as "a ROADMAP when no BRIEF was written" | **changes — NOT acknowledged** |
| DESIGN ← PRD, BRIEF | nearest-produced admits a ROADMAP when neither a PRD nor a BRIEF was written; `run-cascade_test.sh` Scenario 1 builds exactly `DESIGN → ROADMAP` (consumers research §4a) | **changes — NOT acknowledged** |
| PLAN ← DESIGN, PRD, BRIEF, ROADMAP | "the PLAN's upstream is whatever preceded it"; `/plan` classifies `input_type ∈ {design, prd, roadmap, topic}` (writers §6) | holds; BRIEF is an addition `/plan` has no input mode for — permissive, harmless |
| COMP ← *(none)* | COMP has no `upstream` field at all (`comp-format.md:26-27`, writers §1 row 10) | holds |

The two strictness *readings* the paragraph defends (strategic strict, tactical
any-strictly-higher) are indeed settled in pipeline-model. The *parent sets* are
not: three rows change, and the sentence "R5 encodes it rather than changing it"
asserts otherwise. The PRD names only the BRIEF consequence.

The PRD/DESIGN changes are forced by R4 (ROADMAP is Working, both are Durable),
so they are correct — they are simply unstated. That matters downstream: a
design reading R5 as an encoding job will not know that `prd-format.md:27-29`
and `pipeline-model.md:132-135` both document a shape the PRD is outlawing, and
will not know that `PRD → ROADMAP` and `DESIGN → ROADMAP` join `BRIEF → ROADMAP`
as forbidden.

### R2's lifetime classes — **HOLD**

Verified directly in each skill's `## Artifact Lifecycle` section:
Working — `skills/roadmap/SKILL.md:60-62`, `skills/plan/SKILL.md:25-27`.
Durable — `vision` (:34-36), `strategy` (:52-54), `brief` (:44-46),
`prd` (:25-27), `design` (:24-26), `comp` (:37-39). All eight match R2.

### R20's eight documents — **HOLD, every row, both columns**

Checked against the corpus research's complete edge table (rows 1-8) and its
Step 5 baseline.

| R20 row | corpus evidence | Verdict |
|---|---|---|
| `BRIEF-fc06-index-alias.md` clean → direction (names DESIGN) | edge #2, R6 pass, TP FAIL, LC pass | holds |
| `BRIEF-lifecycle-draft-ready-discipline.md` clean → direction (names BRIEF) | edge #4, R6 pass, TP FAIL | holds |
| `BRIEF-skill-cascade-lifecycle-check.md` clean → direction (names BRIEF) | edge #7, R6 pass, TP FAIL | holds |
| `BRIEF-cascade-outline-ac-completeness.md` R6 → R6 + lifetime | edge #1, BRIEF→PLAN, R6 FAIL-missing, TP FAIL, LC FAIL; R7 suppresses the direction finding | holds |
| `BRIEF-single-pr-plan-validation.md` R6 → R6 + lifetime | edge #6, identical shape | holds |
| `BRIEF-legend-vs-classdef-reconciliation.md` R6 → R6 + direction | edge #3, BRIEF→DESIGN, LC pass | holds |
| `BRIEF-lifecycle-passing-state-validation.md` R6 → R6 + direction | edge #5, same | holds |
| `BRIEF-table-diagram-reconciliation.md` R6 → R6 + direction | edge #8, same | holds |

The corpus research labels rows 4 and 5 "R6 error + type-pair error"; the PRD
says "lifetime violation" for them. That is not a mismatch — it is R7's
precedence rule applied correctly to two edges that violate both properties.

Also verified: "the other 73 edges stay legal" (corpus Step 3: pass 73, fail 8)
and "the 68 documents with no `upstream:` field are untouched" (Step 1: 68).
R5's table does not change either count, since the corpus contains zero
`BRIEF → ROADMAP`, `PRD → ROADMAP` or `DESIGN → ROADMAP` edges.

### R21's baseline — **HOLDS**

Corpus Step 5: `shirabe validate --lifecycle . --mode=draft` exits 0 today with
two notice-level L02 findings.

### R8's no-indexing claim — **HOLDS**

Consumers §2: `docs/strategies/` and `docs/visions/` are never indexed
(`lifecycle.rs:678-686`), and the direction/lifetime decision needs only two
basenames.

### R9 and R10 — **HOLD**

Placeholder skip and blank-entry-is-already-R6's-finding match consumers §1
(`upstream.rs:103`, `checks.rs:806/826/829`). Cross-repo values keep the
file-component basename rule, matching `brief/phase-0-setup.md:188-197`.

### R18's framing of the L02 orphan exemption — **ACCURATE**

Consumers §2b: `lifecycle.rs:1276-1282` is "the *only* place in the codebase
where the type and status of a BRIEF's upstream is consulted," and the loss is
narrow — branch 3 covers the brief the moment a PRD names it. R18 describes
exactly that state ("correctly the head of its own lineage and has no downstream
document yet") and requires the change to state the outcome. One imprecision,
not a defect: R18 credits R13 alone with making the exemption unreachable, but
R13 only stops `/brief` from producing the edge — it is R5's empty BRIEF parent
set that forbids a hand-authored one. Both are needed.

### Known Limitations honesty — **HONEST**

"The direction check finds three documents on its own and the lifetime check
finds zero" matches corpus Step 4 exactly ("its marginal yield is zero
documents"; both lifecycle failures already fail R6). The limitation also names
the absent-ROADMAP corpus caveat the research asked for.

## Coverage

Every brief IN item has a requirement:

| Brief IN item | Requirements |
|---|---|
| Stated definition covering both properties | R1, R2, R3, R5 |
| Decision on one-rule-vs-two for unrecordable upstreams | Decisions §1 |
| Enforcement by `shirabe validate` | R6-R10 |
| Skills' recording behaviour, changed in each skill's own contract | R11-R14 (see gap below) |
| Named ahead-of-time list of changed validation results | R20 |
| Keeping the automated consumer whole | R16, R17, Decisions §5 |

Both brief Open Questions are closed in Decisions and Trade-offs: the
mechanism question in "The mechanism is to record nothing, not to navigate
further up," and the "absorb the context" question in "'Absorb the context' is
the self-containment each format already requires" (plus R15).

Every brief OUT item is preserved in Out of Scope, none absorbed.

No requirement lacks grounding. R19 and R21 are compatibility constraints not
named in the brief, but they are measurement discipline for R20 rather than new
scope.

## Gaps / scope creep

1. **R5's unacknowledged rows** (see above). The claim is wrong and the two
   consequences it hides are load-bearing.

2. **`/explore` → `/roadmap` produces an illegal link and nothing names it.**
   Writers §7 gap 1: `explore/phase-5-produce-roadmap.md:43-49` passes a VISION
   in `--upstream` to `/roadmap`, which enforces no basename and writes it
   straight to frontmatter. Under R5 (ROADMAP's only legal parent is STRATEGY)
   that is a direction violation, produced by a documented, live code path. R11
   covers it generically; no requirement or acceptance criterion names it, and
   `/brief` is the only skill R13 changes by name.

3. **No acceptance criterion exercises R11 beyond `/brief`.** The AC list has a
   `/brief` criterion and a `/scope` criterion; R11's "no skill records a
   forbidden value" has no criterion covering `/prd`'s or `/roadmap`'s
   unenforced flags. Nor does any criterion cover R18's orphan outcome.

4. **Minor tension between R14 and `/scope`'s absorb re-point.** R14 says a
   parent skill "does not reach into a child to suppress or rewrite what the
   child records," but `scope/phase-2-chain-orchestration.md:485-501` has
   `/scope` rewriting a survivor PRD's `upstream:` after the child produced it —
   and that re-point is the documented mechanism that produces `PRD → ROADMAP`,
   a pair R5 now forbids. Worth one clause; not a FAIL driver on its own.

## Required changes

1. Replace R5's closing sentence. The strictness *readings* are settled in
   `pipeline-model.md`; the parent *sets* are not. State that three rows change
   what the references currently document — BRIEF (already stated), PRD (which
   `pipeline-model.md:132-133` and `prd-format.md:27-29` both say may name a
   ROADMAP when no BRIEF was written), and DESIGN — and that all three follow
   from R4 rather than from a new judgment.

2. Add the consequence sentence alongside the existing BRIEF/PLAN one: no
   durable tactical node may name a ROADMAP, so the boundary crossing that
   `pipeline-model.md` currently lets a BRIEF, PRD or DESIGN record now lives
   only on the PLAN. This is what Decisions §5 already argues; R5 should say it.

3. Name the `/explore` → `/roadmap` VISION handoff as a producer the definition
   forbids, either as a requirement beside R13 or as an explicit Out of Scope
   deferral. Leaving it to R11's general phrasing means the one live
   strategic-chain violation in the repo ships unnamed.
