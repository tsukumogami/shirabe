# Lead: Where does `/explore` still route to chain-internal steps, and what would a four-way entry-point router have to replace?

## Findings

### Ground truth: which skill directories actually exist

`ls skills/` returns twenty directories:

```
brief  charter  comp  decision  design  execute  explore  inflight  plan
prd    private-content  public-content  release  review-plan  roadmap
scope  strategy  vision  work-on  writing-style
```

Every `SKILL.md` `name:` field matches its directory name (verified by
`grep -m2 -H '^name:' skills/*/SKILL.md`). So the resolvable command
namespace is exactly that list. Three destination strings that `/explore`
names do **not** resolve:

| Destination named | Resolves? | Note |
|---|---|---|
| `/spike` | **No** | No `skills/spike/`. Nothing in the repo provides it. |
| `/competitive-analysis` | **No** | `skills/comp/` exists and is named `comp`. The string `/competitive-analysis` matches nothing. |
| `/triage` | **No** | Named in `label-reference.md:20` as the label-assigning workflow. |
| `spike-report/SKILL.md` | **No** | `label-reference.md:55` points at a skill directory that does not exist. |
| `decision-record/SKILL.md` | **No** | `label-reference.md:56`. `skills/decision/` exists; `decision-record` does not. |
| `/issue` | **No** | `phase-5-produce-no-artifact.md:34`. No `skills/issue/`. |
| `/cleanup` | **No** | `phase-5-produce.md:57`. No `skills/cleanup/`. |

(The last three plus `/triage` exist as workspace-level `tsukumogami:` skills
outside this repo, so they are cross-plugin references rather than pure
dangling pointers — but from inside shirabe they resolve to nothing.)

Everything else `/explore` names — `/prd`, `/design`, `/plan`, `/vision`,
`/roadmap`, `/decision`, `/brief`, `/work-on` — resolves to a real directory.

**`/scope`, `/charter`, and `/execute` are never named anywhere in
`skills/explore/`.** Confirmed by grep across the whole subtree. The inverse
is nearly as stark: `grep -rn explore skills/scope/ skills/charter/
skills/execute/` returns three hits, all in `/charter`, and all of them cite
`/explore` as a *pattern* to imitate rather than a route in:
`skills/charter/references/phases/phase-1-discovery.md:53,119,122` (borrowed
discover/converge wording) and
`skills/charter/references/phases/phase-2-chain-orchestration.md:425` ("The
handoff causes `/roadmap` to skip its Phase 1, analogous to the existing
`/explore` Phase 5 handoff pattern"). `/scope` does not mention `/explore` at
all.

### Inventory: every destination named in `skills/explore/`

#### `skills/explore/SKILL.md`

*Description frontmatter and preamble*
- L9-10: "use `/prd`, `/design`, or `/plan` directly instead" — all resolve
- L23-24: "`/prd` owns requirements, `/design` owns technical architecture,
  `/plan` owns issue decomposition" — all resolve. This sentence is the
  corpus's clearest statement of the pre-`/scope` ownership model.

*Artifact Type Routing Guide* (L33-42) — eight rows:

| Line | Destination string | Resolves |
|---|---|---|
| L35 | `/explore <topic>` | yes (self) |
| L36 | "Read the decision table below" | n/a |
| L37 | `/design <topic>` | yes |
| L38 | `/brief <topic>` | yes |
| L39 | `/prd <topic>` | yes |
| L40 | `/plan <design-doc-path>` | yes |
| L41 | `/work-on <issue>` | yes |
| L42 | `/explore --strategic <topic>` + "needs VISION or Roadmap before features" | yes / type names |

L38 is notable: `/brief` was added to this table (it is the newest tactical
child) but the row still frames it as a standalone destination an author picks
— "the step between roadmap and PRD" — which is precisely the
choose-before-the-fact model `/scope` replaced.

*Quick Decision Table* (L46-54) — seven rows, each naming a Best Fit and an
Alternative:
- L48 "No artifact, `/work-on` directly" / `/prd`
- L49 PRD / Explore
- L50 Design Doc / Explore
- L51 Plan / Design Doc
- L52 Explore / No artifact
- L53 Explore / No artifact
- L54 "VISION or Roadmap via `/explore --strategic`" / `/explore`

*Complexity-Based Routing* (L58-64) — five levels, five destinations:
- L60 Trivial -> `/work-on` directly (no issue)
- L61 Simple -> `/work-on` or `/prd` then implement
- L62 Medium -> `/design` then `/plan`
- L63 Complex -> `/explore`
- L64 Strategic -> "VISION or `/roadmap` then per-feature pipeline"

L62 and L64 are the two rows that hard-code a chain-internal sequence:
"`/design` then `/plan`" is the back half of the tactical chain with BRIEF and
PRD silently dropped, and "VISION or `/roadmap`" is the strategic chain with
STRATEGY silently dropped.

*Detection Algorithm* (L70-93) — a six-step decision ladder that emits one of
five complexity buckets (Strategic / Complex / Medium / Simple / Trivial). It
names no commands itself; the buckets are the join key into the
Complexity-Based Routing table above. Step 6 defaults to "Simple (create an
issue and proceed)".

*Reference Files table* (L322-336) — lists seven phase-5 files but **omits
three that exist on disk**: `phase-5-produce-roadmap.md`,
`phase-5-produce-vision.md`, `phase-5-produce-rejection-record.md`. It also
mis-describes `phase-5-produce-deferred.md` as covering
"Roadmap/Spike/Competitive/Prototype" (L335), contradicting
`phase-5-produce.md:47` which routes Roadmap to its own dedicated file. The
table is stale by three files and one row.

*Pathing slip*: L133 references `references/decision-protocol.md` relative to
the skill, but the file lives at repo-root `references/decision-protocol.md`.
Every other citation in the skill uses `${CLAUDE_PLUGIN_ROOT}/references/...`
(L252, and phase-0/3/5-deferred). Minor, but it is in the `--auto` path.

#### `skills/explore/references/quality/crystallize-framework.md`

L21: "**Ten** artifact types can be produced through /explore today. Each has
a dedicated command or a defined action path." The ten, with their declared
routes:

| Line | Type | Declared route | Resolves |
|---|---|---|---|
| L26 | PRD | `/prd` | yes |
| L38 | Design Doc | `/design` | yes |
| L51 | Plan | `/plan` (user runs separately) | yes |
| L60 | No Artifact | none — "suggests direct action" | n/a |
| L74 | Rejection Record | `phase-5-produce-rejection-record.md` (in-skill) | file exists |
| L86 | VISION | `/vision` | yes |
| L101 | Roadmap | `/roadmap` | yes |
| L112 | Spike Report | `/spike` | **no** |
| L123 | Decision Record | `/decision` | yes |
| L134 | Competitive Analysis | `/competitive-analysis`, "Private repos only" | **no** |

L143-157, *Deferred Types*: one entry, Prototype, whose "Closest Available
Alternative" is "No artifact -- start building directly with `/work-on`"
(L151).

L159-172, *Evaluation Procedure* Step 1 re-enumerates all ten by name
(L165-167) and instructs signal-minus-anti-signal scoring per type. Step 2
(L174-181) is the demotion rule. Step 4 (L213-223) is the insufficient-signal
fallback that loops back to Phase 2.

L184-211, *Tiebreakers* — seven pairwise rules, every one of them a question
about which chain-internal artifact to write:
- PRD vs Design Doc (L186-191)
- PRD vs No artifact (L193-196)
- Design Doc vs Plan (L198-200)
- VISION vs PRD (L202)
- VISION vs Roadmap (L204-205)
- VISION vs Rejection Record (L207-208)
- VISION vs No Artifact (L210-211)

L259-293, *Disambiguation Rules* — six rules, of which four are again
intra-chain ordering questions: "requirement gaps AND technical questions ->
favor PRD, the design doc can follow" (L262-266); "deep exploration but user
wants to act fast -> a lean design doc is still required" (L268-273);
"strategic justification AND feature requirements -> VISION comes first,
note that a PRD should follow" (L275-277); "Plan signals but no upstream
artifact -> write PRD or Design Doc first" (L279-285).

**Two types are conspicuously absent from all ten: BRIEF and STRATEGY.** The
framework can route to `/prd` (skipping BRIEF) and to `/roadmap` (skipping
STRATEGY), but has no vocabulary for the two altitudes that sit above them.
That is the mechanical cause of the hazard documented in the next section.

#### `skills/explore/references/phases/phase-4-crystallize.md`

- L70-72: re-enumerates the ten supported types verbatim.
- L80: "Also check the deferred type (Prototype)."
- L97-103: reproduces only **three** of the framework's seven tiebreakers
  (PRD vs Design, PRD vs No artifact, Design vs Plan). The four VISION
  tiebreakers exist only in the framework file. A Phase 4 run that follows the
  phase file literally never applies them.
- L138-149: the worked AskUserQuestion example offers Design Doc / PRD / No
  artifact / None of these.
- L194: quality checklist — "All ten supported types scored with specific
  evidence."

#### `skills/explore/references/phases/phase-5-produce.md`

L38-48, the routing table — nine rows to eight files:

| Line | Chosen Type | File | Handoff |
|---|---|---|---|
| L40 | PRD | `phase-5-produce-prd.md` | Auto-continues into `/prd` |
| L41 | Design Doc | `phase-5-produce-design.md` | Auto-continues into `/design` |
| L42 | Decision Record | `phase-5-produce-decision.md` | Auto-continues into `/decision` |
| L43 | VISION | `phase-5-produce-vision.md` | Auto-continues into `/vision` |
| L44 | Plan | `phase-5-produce-plan.md` | Stops — user runs `/plan` |
| L45 | Rejection Record | `phase-5-produce-rejection-record.md` | Stops — terminal |
| L46 | No artifact | `phase-5-produce-no-artifact.md` | Stops — terminal |
| L47 | Roadmap | `phase-5-produce-roadmap.md` | Auto-continues into `/roadmap` |
| L48 | Spike Report, Competitive Analysis, Prototype | `phase-5-produce-deferred.md` | Stops — terminal |

L8-9 and L69-70 both carry stale prose: "either continue in the same session
(for /prd and /design) or tell the user what to run next (for /plan and no
artifact)" and "If the session continues into /prd or /design, the target
skill's orchestrator takes over." Four types auto-continue, not two.

#### The nine `phase-5-produce-*.md` files

**`phase-5-produce-prd.md`** — writes `wip/prd_<topic>_scope.md` matching
`/prd` Phase 1's output format (L3), then L37-43: commit, "Invoke the PRD
skill: `/shirabe:prd <topic>`", "The PRD skill detects the handoff artifact
and resumes at Phase 2". Enters the tactical chain at its **second** step.

**`phase-5-produce-design.md`** — writes a real durable artifact directly:
`docs/designs/DESIGN-<topic>.md` with `status: Proposed` (L5-38), plus
`wip/design_<topic>_summary.md` (L40-53). L55-61: `/shirabe:design <topic>`,
resuming at Phase 1. Enters the tactical chain at its **third** step, and
`/explore` authors a chain artifact skeleton itself — the exact behavior the
author has decided `/explore` should stop doing.

**`phase-5-produce-vision.md`** — writes `wip/vision_<topic>_scope.md`
(L3-37), then `/shirabe:vision <topic>` resuming at Phase 2 (L39-45). Enters
the strategic chain at its **first** step, which is the one handoff that is
altitude-correct today.

**`phase-5-produce-roadmap.md`** — writes `wip/roadmap_<topic>_scope.md`
(L3-38), then L40-63 hands to `/shirabe:roadmap`. This file is the single
best piece of evidence for the lead. L43-57 is a paragraph that exists only
because `/explore` enters the strategic chain at its **last** step:

> **Do not pass a VISION.** A ROADMAP's only legal upstream is the STRATEGY
> it sequences, and `/roadmap`'s own contract already says a VISION must not
> be substituted for one — it would skip an altitude and leave the strategic
> reasoning at that altitude unreachable from the path a reader walks.
> `/roadmap` enforces no basename on the flag, so nothing downstream catches
> the substitution; `shirabe validate` reports it as an `R10` direction
> violation once the roadmap is written.

Since crystallize has no STRATEGY type, an exploration that scores Roadmap
highest is instructed to hand off with **no upstream at all** ("When the
exploration found a VISION but no STRATEGY, omit the flag and name the VISION
in the handoff artifact's prose instead", L55-57). The skill knowingly
produces an orphan ROADMAP because it cannot route to the altitude in between.

**`phase-5-produce-plan.md`** — the only "specify upstream first" handler.
L5-13 splits on whether open decisions remain: no decisions -> "run `/plan
<topic>`"; decisions remain -> "complete the upstream artifact first... Suggest
/prd if requirements need capturing, /design if the technical approach is
open." Terminal; the user runs `/plan` themselves (L35).

**`phase-5-produce-decision.md`** — writes `wip/explore_<topic>_decision-brief.md`
(L8-32), then L38-46: "Read the decision skill: `skills/decision/SKILL.md`" and
invoke it with question/prefix/options/constraints/background/complexity. Off-chain
destination; resolves.

**`phase-5-produce-rejection-record.md`** — authors
`docs/decisions/REJECTED-<topic>.md` inline (L13-59), commits it (L63), and is
terminal ("No handoff to another skill — this is the final produce step", L82).
L72-75 optionally offers `/decision` for a formal ADR. Off-chain; no parent
chain owns `REJECTED-*.md`.

**`phase-5-produce-no-artifact.md`** — terminal, no artifacts. L26-34 presents
findings and suggests "Create a focused issue with `/issue`" or "Start
implementing directly with `/work-on`". L10-20 is a guard that bounces back to
Phase 4 if `wip/explore_<topic>_decisions.md` has entries.

**`phase-5-produce-deferred.md`** — three sections (L7-12 table of contents).
Despite the file name, it does **not** defer: it authors artifacts inline.
- Prototype (L15-38): AskUserQuestion offering spike report or design doc; if
  design doc, read `phase-5-produce-design.md`.
- Spike Report (L42-105): writes `docs/spikes/SPIKE-<topic>.md` with a full
  frontmatter+section template, commits `docs(explore): produce spike report
  for <topic>`, and runs `gh issue edit <N> --remove-label needs-spike`.
- Competitive Analysis (L109-186): checks visibility, refuses on public repos
  with three named alternatives (L115-124), and on private repos writes
  `docs/competitive/COMP-<topic>.md` inline and commits it.

So `/explore` today is not purely a router: it directly authors DESIGN
skeletons, SPIKE reports, COMP analyses, and REJECTED records.

#### `skills/explore/references/label-reference.md`

- L9-14: the label vocabulary — `needs-triage`, `needs-design`, `needs-prd`,
  `needs-spike`, `needs-decision`, `tracks-plan`.
- L20-24: lifecycle — "`/triage` or `/plan` (roadmap decomposition) assigns a
  `needs-*` label" (L20, `/triage` unresolved), "The appropriate upstream
  workflow produces the artifact (`/explore`, `/prd`, `/design`)" (L21),
  "If `/plan` creates a PLAN document, `tracks-plan` is applied" (L23).
- L36: "'Ready' (atomic, clear AC) -> ready for `/work-on`".
- L38-42: Stage 2 four-way label split — `needs-prd` / `needs-design` /
  `needs-spike` / `needs-decision`.
- L44-45: the primary gap heuristic — "when both requirements AND approach are
  unclear, route to the earlier-stage artifact (PRD before design)."
- L51-56: the skill-lookup table, with two of four rows dangling
  (`spike-report/SKILL.md`, `decision-record/SKILL.md`).

This whole file encodes "pick the one artifact this issue needs" as a label
applied *before* any work happens — the purest expression of the
steps-are-choosable model.

#### `skills/explore/references/phases/phase-0-setup.md`

Two-stage triage, reached when an issue carries `needs-triage`:
- Stage 1 (L130-158): investigation / breakdown / ready. Breakdown -> create
  sub-issues, "suggest the user run `/work-on` on individual sub-issues"
  (L155-156). Ready -> remove label, "suggest the user run `/work-on
  <issue-number>`" (L157-158).
- Stage 2 (L160-249): **three agents each argue for one artifact type** —
  Agent 1 `needs-prd`, Agent 2 `needs-design`, Agent 3 `needs-spike` /
  `needs-decision` (L165-179). The agent prompt template (L185-212) lists the
  four types with their distinguishing questions and states the primary-gap
  heuristic (L204-206). Synthesis (L214-221) applies "needs-prd before
  needs-design, needs-design before needs-spike" on a three-way split.
- The routing AskUserQuestion (L227-232) offers Explore (Recommended) /
  Different type / Implement directly (`/work-on`).
- L242-246: on confirm, apply the `needs-*` label and proceed to Phase 1 —
  "/explore will crystallize to the appropriate artifact type."

Phase 0 therefore makes a four-way artifact-type commitment *before* Phase 1
even starts, and then Phase 4 makes a ten-way one again at the end.

#### `skills/explore/evals/evals.json`

Sixteen evals. Nine of them assert artifact-type or child-skill destinations:

| Eval | Line | Destination asserted |
|---|---|---|
| 1 open-ended-no-direction | L8 | "Should NOT jump directly to `/design` or `/prd`" |
| 3 routing-advisor-prd-vs-design | L22 | Consults Quick Decision Table + Complexity-Based Routing; PRD vs Design Doc |
| 4 crystallize-to-design-doc | L29 | "should score Design Doc highest... Phase 5 hands off to `/design`" |
| 5 crystallize-to-prd | L36 | "should score PRD highest... recommending `/prd` handoff" |
| 8 simple-task-routes-away | L57 | "Routes to `/work-on` or direct implementation" |
| 12 roadmap-handoff-upstream-propagation | L109, L112-115 | Roadmap scores highest; routes to `phase-5-produce-roadmap.md`; writes `wip/roadmap_*_scope.md`; "invoking or handing off to `/roadmap` or `/shirabe:roadmap`" |
| 13 trivial-classification | L122, L126 | "Recommends `/work-on` directly"; "rather than `/explore`, `/prd`, or `/design`" |
| 14 strategic-classification | L135, L139-140 | "Recommends `/explore --strategic` or VISION"; "does NOT recommend `/prd` or `/design` as the first step" |
| 16 triage-stage-2 | L162-168 | three-way `needs-prd` / `needs-design` / `needs-spike` split, primary-gap tiebreaker, recommends `needs-prd` |

Eval 15 (L147-157) tests Stage 1 triage recommendation quality. Evals 2, 6, 7
test input detection, `--auto`, and cross-repo handling — destination-neutral.
Evals 9, 10, 11 (L60-104) are the adversarial demand-validation fixtures; they
test the *research agent*, not routing, and would survive any router rewrite
untouched — **except** that eval 10's whole point is producing a "demand
validated as absent" finding, whose only current destination is the Rejection
Record.

#### Outside `skills/explore/`: `references/pipeline-model.md`

Not in the lead's list, but it mirrors the same routing model corpus-wide and
explicitly defers to `/explore` as the owner:
- L11: "`/explore` (diverge) -> crystallize (converge) -> artifact type"
- L38-39: the Complex and Strategic rows, "Explore -> crystallize -> specify ->
  implement" and "VISION -> STRATEGY -> Roadmap -> per-feature pipeline"
- L42-43, L247-249: "the algorithm and tiebreaker rules live in `/explore
  SKILL.md`... /explore owns the detection algorithm"
- L240-245: four situation rows — "/explore -> (crystallize) -> /prd or /design
  -> /plan -> /work-on", "-> /vision -> /strategy -> /roadmap", "-> spike
  report", "-> /decision"
- L255, L262: the `needs-*` label vocabulary including `needs-spike`

Any rewrite of `/explore`'s routing surface has to land here too, or the
corpus keeps stating the old model in a file that claims `/explore` is
authoritative.

### The four-way router: delete / repurpose / homeless

Taking the four outcomes as (a) file a GitHub issue, (b) `/charter`,
(c) `/scope`, (d) `/execute`.

**Deleted outright**

- SKILL.md *Artifact Type Routing Guide* (L33-42). Six of its eight rows name
  a chain-internal child (`/design`, `/brief`, `/prd`, `/plan`) as a
  destination an author picks up front. Under the router, "I know what to
  build, not how" and "I have a feature named but haven't framed it" are the
  same answer: `/scope`.
- SKILL.md *Quick Decision Table* (L46-54). Every row is a
  PRD-vs-design-vs-plan discrimination that `/scope` now performs internally
  by running all four children and consolidating afterward.
- SKILL.md *Complexity-Based Routing* (L58-64). Five levels mapping to five
  destinations, of which only Trivial (-> file an issue) survives; "`/design`
  then `/plan`" and "VISION or `/roadmap`" are chain fragments that no longer
  exist as author-selectable paths.
- SKILL.md *Detection Algorithm* (L70-93) as written. It emits five complexity
  buckets, not four entry points, and its steps 2-5 discriminate on
  requirements-clarity vs approach-clarity — a question that only mattered
  when PRD and DESIGN were separately choosable. It would be rewritten, not
  kept: the surviving discriminations are altitude (project direction vs one
  feature) and readiness (is there already a PLAN).
- crystallize-framework.md's ten signal/anti-signal tables (L24-141), the
  ten-type enumeration (L21, L165-167), the demotion rule (L174-181), and
  five of the seven tiebreakers (PRD vs Design Doc, PRD vs No artifact, Design
  Doc vs Plan, VISION vs PRD, VISION vs Roadmap). Each of these five is now a
  question `/scope` or `/charter` answers inside its own run, not a question
  that gates entry.
- crystallize-framework.md's four intra-chain disambiguation rules (L262-266,
  L268-273, L275-277, L279-285). "Requirements come first -- you can't design
  a solution without knowing the problem. The design doc can follow the PRD"
  is a statement of the chain, now enforced by `/scope` running the chain.
- phase-4-crystallize.md L70-72, L80, L97-103, L194 — the ten-type scoring
  loop and the three-tiebreaker subset.
- The five child-specific handoff files: `phase-5-produce-prd.md`,
  `phase-5-produce-design.md`, `phase-5-produce-vision.md`,
  `phase-5-produce-roadmap.md`, `phase-5-produce-plan.md`. Each writes a
  scope artifact shaped to one child's Phase 1 schema and invokes that child
  mid-chain. Two handoff files replace all five: one that pre-populates
  `/charter`'s discovery input and one that pre-populates `/scope`'s.
- `phase-5-produce-design.md`'s `docs/designs/DESIGN-<topic>.md` skeleton
  (L5-38) specifically — `/explore` authoring a chain artifact is the thing
  the decision forbids.
- `phase-5-produce-deferred.md`'s Spike (L42-105) and Competitive Analysis
  (L109-186) sections, both of which author durable docs inline.
- phase-0-setup.md Stage 2 (L160-249) in its current four-label form. Three
  agents arguing `needs-prd` vs `needs-design` vs `needs-spike` vs
  `needs-decision` is a pre-commitment to a chain step, made before Phase 1.
- label-reference.md L38-45 (the Stage 2 label split and primary-gap
  heuristic) and L51-56 (two of whose four rows already dangle). The
  `needs-spike` and `needs-decision` labels lose their producer entirely.
- The `/spike` and `/competitive-analysis` strings
  (crystallize-framework.md L112, L134) go away with their types — which
  incidentally fixes two of the seven dangling destinations for free.
- Evals 3, 4, 5, 13, 14, 16 as written; eval 1's L8 assertion and eval 12's
  L112-115 expectations.

**Repurposed**

- Phases 0-3 (setup, scope, discover, converge) are untouched. The
  discover-converge research loop is `/explore`'s actual value and is
  orthogonal to where it hands off. `/charter` already borrows its wording
  (charter phase-1-discovery.md L119-122).
- Phase 4 crystallize survives as a **four-way altitude scorer** instead of a
  ten-way artifact scorer. The signal vocabulary largely re-buckets rather
  than dies: VISION's signals (L88-97: "project doesn't exist yet", "should we
  build this?", "org fit was the core question") plus Roadmap's (L104-108:
  "multiple features need ordering", "dependencies affect delivery order")
  collapse into one `/charter` bucket. PRD's (L28-33), Design Doc's (L41-47)
  and Plan's (L53-58) collapse into one `/scope` bucket. No Artifact's
  (L65-70: "simple enough to act on directly", "one person can implement
  without coordination") becomes the file-an-issue bucket. The two VISION
  tiebreakers that survive are the ones that discriminate *between* the four:
  VISION vs PRD ("does the project exist yet?", L202) becomes charter-vs-scope,
  and PRD vs No artifact ("can one person act on this without a written
  contract?", L193-196) becomes scope-vs-issue.
- The Documentation Purpose preamble (crystallize-framework.md L6-17) and its
  echo in phase-4-crystallize.md L64-68 survive intact — "wip/ is cleaned
  before every PR merges... did we decide something a future contributor needs
  to know?" is still the right pressure, and under the router it argues for
  `/scope` over file-an-issue rather than for design-doc over no-artifact.
- The insufficient-signal fallback (crystallize-framework.md L213-223,
  phase-4-crystallize.md L105-116) survives verbatim — "don't force a choice
  when the evidence isn't there" applies to four options as well as ten.
- `phase-5-produce.md`'s routing table shrinks from nine rows to four.
- `phase-5-produce-no-artifact.md` becomes the **file-an-issue** handler. It
  already suggests `/issue` and `/work-on` (L34) and already carries the
  decisions-file guard (L10-20) that bounces back to Phase 4 when the
  exploration decided something durable. Under the router that guard becomes
  "if decisions were made, this is `/scope`, not an issue."
- `phase-5-produce-plan.md` becomes the `/execute` handler, or is folded into
  the `/scope` handler. Its existing split (L5-13) is already the right
  question in the wrong vocabulary: "no open decisions, work is decomposable"
  -> a PLAN exists or can be produced -> `/execute`; "open decisions remain"
  -> `/scope`.
- phase-0-setup.md Stage 1 (L130-158) survives largely as-is — investigation
  vs breakdown vs ready maps cleanly onto explore-further vs file-issues vs
  hand off. Stage 2 would be rewritten from four labels to the same four-way
  altitude question Phase 4 asks, or dropped entirely in favor of letting
  Phase 1-4 do it.
- `references/pipeline-model.md` L11, L38-39, L240-249, L255, L262 need the
  same rewrite; it defers to `/explore` as the owner of the algorithm, so it
  cannot be left stating the old one.
- Evals 9, 10, 11 survive as research-agent tests; evals 2, 6, 7 survive
  untouched; evals 8 and 15 need only vocabulary updates.

**No home under the four-way model**

These are the outcomes `/explore` produces today that map to none of (a)-(d),
and — as the lead anticipated — no parent chain owns any of them:

1. **Rejection Record** (`docs/decisions/REJECTED-<topic>.md`). The strongest
   case. An exploration that concludes "don't build this" cannot file an issue
   (there is no work to track), cannot enter `/charter` or `/scope` (there is
   nothing to specify), and cannot enter `/execute`. The artifact is terminal
   by construction (`phase-5-produce-rejection-record.md:82`, "No handoff to
   another skill"). Its signal table (crystallize-framework.md L76-82) is the
   payoff of the adversarial demand-validation lead, and eval 10 asserts that
   the agent must reach "demand validated as absent" — a finding whose only
   destination is this record. Deleting the outcome would make eval 10's
   result unroutable; keeping it means the router has a fifth outcome.
2. **Spike Report**. "Can we do this?" is answered by investigation, not by
   any of the four. `/execute` needs a PLAN; `/scope` produces a PLAN for work
   already believed feasible. The `needs-spike` label (label-reference.md L12)
   and the Stage 2 agent that argues for it (phase-0-setup.md L175-179) both
   lose their terminus. Note `/spike` never existed as a skill anyway —
   `phase-5-produce-deferred.md` L46-90 authors `docs/spikes/SPIKE-*.md`
   directly — so this outcome is already half-orphaned today.
3. **Competitive Analysis / COMP**. `docs/competitive/COMP-<topic>.md`,
   private-repo-only. `skills/comp/` exists as a skill, but `/comp` is not one
   of the four and no chain owns a COMP. The public-repo refusal path
   (`phase-5-produce-deferred.md` L115-126) offers three alternatives, two of
   which (design doc, spike report) also stop existing as `/explore` outcomes.
4. **Decision Record**. `/decision` is a real, working skill and
   `phase-5-produce-decision.md` hands to it cleanly, but it is not one of the
   four. There is a partial overlap worth flagging: `/scope` writes a Decision
   Record on its `re-evaluation` exit (`skills/scope/SKILL.md` L26-28), but
   only "at a settled-upstream boundary (PRD or DESIGN)" *inside a running
   chain* — that does not cover "exploration surfaced one contested choice and
   nothing else." Routing such an exploration into `/scope` to obtain an ADR
   would mean running BRIEF -> PRD -> DESIGN -> PLAN to produce one decision.
5. **"Just do it" / `/work-on` directly**. Filing an issue is outcome (a), but
   nothing in the four drives that issue to code: `/execute` takes a PLAN doc
   path (`skills/execute/SKILL.md` description: "Takes a finished PLAN doc"),
   not an issue number. Today Trivial and Simple both route to `/work-on`
   (SKILL.md L60-61, phase-0-setup.md L156-158, L232, L249, eval 13). Under a
   strict four-way router that path terminates at a filed issue with no
   named next step.
6. **Prototype** (deferred). Already homeless today; stays homeless.

## Implications

The lead's premise holds and is stronger than expected. `/explore` does not
merely *name* chain-internal children — it enters the tactical chain at three
different depths (`/prd` at step 2, `/design` at step 3, `/plan` at step 4)
and the strategic chain at two (`/vision` at step 1, `/roadmap` at step 3),
and in the `/design` case it writes the chain artifact itself before handing
off. Because its type vocabulary has no BRIEF and no STRATEGY, two of those
five entries structurally skip an altitude. The roadmap handler already had to
grow a five-sentence warning (`phase-5-produce-roadmap.md` L48-57) explaining
that the skipped altitude produces an `R10` direction violation that nothing
downstream catches. That paragraph is a workaround for the exact defect the
four-way router removes.

The volume of deletion is large but concentrated. Four tables in SKILL.md, the
ten-type core of the crystallize framework, five of nine phase-5 files, the
inline-authoring half of the deferred file, and Stage 2 of triage. What
survives is more than it looks: Phases 0-3 are untouched, the crystallize
*procedure* (score, rank, tiebreak, insufficient-signal fallback) is
type-count-agnostic, and the Documentation-Purpose framing gets sharper, not
weaker.

The load-bearing decision this informs is whether the router really has four
outcomes or six. Four of the ten current types are off-chain and terminal by
construction — Rejection Record, Spike Report, COMP, Decision Record — and
three of them are backed by real machinery: a signal table, a produce handler,
an eval fixture (Rejection Record); a label plus a triage agent plus a produce
handler (Spike); a working skill plus a visibility gate (COMP, `/decision`).
Deleting them silently would strand `needs-spike` and `needs-decision` in
`label-reference.md`, orphan the `adversarial-absent-demand` eval fixture's
payoff, and remove the only way `/explore` records a "we investigated and
decided not to" conclusion. The cleanest reading of "router only" that
preserves those is a **four-way handoff plus a small terminal set** —
`/explore` still *records* an off-chain finding (rejection, spike, ADR, COMP)
because no chain will ever own one, but it stops *authoring chain artifacts*
(the DESIGN skeleton) and stops *entering chains mid-way*. That is a materially
different scope than "four outcomes, delete everything else," and it changes
how much of `phase-5-produce-deferred.md` and
`phase-5-produce-rejection-record.md` survives.

A second implication: `references/pipeline-model.md` is a corpus-wide file that
explicitly names `/explore SKILL.md` as the owner of the detection algorithm
and tiebreakers (L42-43, L247-249) while restating the old model itself
(L11, L38-39, L240-245, L255, L262). Rewriting `/explore` without rewriting it
leaves the corpus stating both models, with the stale one pointing at the
rewritten one as its authority.

## Surprises

- **`/explore` authors durable artifacts today.** The lead framed the question
  as routing, but `phase-5-produce-design.md` L5-38 writes
  `docs/designs/DESIGN-<topic>.md` with `status: Proposed`,
  `phase-5-produce-deferred.md` writes `docs/spikes/SPIKE-*.md` and
  `docs/competitive/COMP-*.md`, and `phase-5-produce-rejection-record.md`
  writes `docs/decisions/REJECTED-*.md`. Four of the nine produce handlers
  create committed documents. "Router only" is a bigger behavioral change than
  "stop naming children."
- **`phase-5-produce-deferred.md` does not defer.** Its name and the
  framework's "Deferred Types" section (L143-157, one entry: Prototype)
  disagree with its contents (three sections, two of which produce artifacts
  inline). Spike Report and Competitive Analysis are listed as *supported*
  types in the framework (L110-141) but routed to the *deferred* file
  (`phase-5-produce.md` L48).
- **SKILL.md's Reference Files table is stale by three files.** It omits
  `phase-5-produce-roadmap.md`, `phase-5-produce-vision.md`, and
  `phase-5-produce-rejection-record.md`, and its `phase-5-produce-deferred.md`
  row (L335) claims Roadmap goes there, contradicting `phase-5-produce.md:47`.
  Any rewrite touching this table is fixing a pre-existing inconsistency, not
  just adapting to the router.
- **Phase 4 reproduces only three of seven tiebreakers.** The four VISION
  tiebreakers (crystallize-framework.md L202-211) appear nowhere in
  `phase-4-crystallize.md`. A Phase 4 run following the phase file gets no
  guidance on VISION-vs-Roadmap or VISION-vs-Rejection-Record — precisely the
  strategic-altitude discriminations the router most needs to get right.
- **`/explore` commits to an artifact type twice.** Phase 0 Stage 2 picks one
  of four `needs-*` labels *before* Phase 1 runs, then Phase 4 scores ten types
  *after* Phases 2-3. Nothing reconciles the two; `phase-0-setup.md` L244-246
  just says "proceed to Phase 1 as well -- /explore will crystallize to the
  appropriate artifact type," which quietly makes the Stage 2 label
  non-binding. The label is applied to the GitHub issue regardless.
- **Seven destination strings in `skills/explore/` do not resolve to anything
  in this repo**: `/spike`, `/competitive-analysis`, `/triage`, `/issue`,
  `/cleanup`, `spike-report/SKILL.md`, `decision-record/SKILL.md`. The first
  two are named as the routes for two of the ten *supported* types.
- **`/scope` has no awareness of `/explore` whatsoever.** Not a mention, not a
  handoff-artifact detection clause. `/charter` mentions it three times, all as
  a pattern to copy. The handoff mechanism `/explore` relies on — write a
  `wip/<child>_<topic>_scope.md` and let the child skip Phase 1 — is
  documented in `/charter` as "the existing `/explore` Phase 5 handoff
  pattern" (charter phase-2-chain-orchestration.md L425), so the mechanism to
  build `/explore` -> `/scope` already exists and is already in use
  parent-to-child. Nobody has pointed it at the parents.

## Open Questions

1. **Is the router strictly four-way, or four handoffs plus a terminal
   recording set?** Rejection Record, Spike Report, COMP, and Decision Record
   have no chain owner by construction. Deleting them removes `/explore`'s
   only way to record "we investigated and concluded X" — and strands eval 10's
   fixture. Needs an explicit author decision, because it determines whether
   `phase-5-produce-rejection-record.md` and `phase-5-produce-deferred.md`
   survive.
2. **What drives a filed issue to code?** `/execute` takes a PLAN doc path, not
   an issue. Today Trivial/Simple explorations route to `/work-on`. If
   `/work-on` is not a router outcome, outcome (a) terminates at a filed issue
   — is that intended, or should the router's (d) accept an issue as well as a
   PLAN?
3. **What happens to `needs-spike` and `needs-decision`?** Both labels
   (`label-reference.md` L12-13), the Stage 2 agent that argues for them
   (`phase-0-setup.md` L175-179), and the `gh issue edit --remove-label
   needs-spike` call (`phase-5-produce-deferred.md` L95-97) presume a producer
   that the router removes. Retire the labels, or keep them pointed at
   something?
4. **Does `/scope` need to detect an `/explore` handoff artifact?** It has no
   such clause today. `/charter` documents the pattern but for its own
   children. Someone must add a Phase-1-skip path to `/scope` (and `/charter`)
   or `/explore`'s handoff re-asks everything the exploration already settled.
5. **Does `/explore --strategic` survive?** The flag currently selects
   Strategic scope, which biases crystallize toward VISION/Roadmap
   (`SKILL.md` L160-168, L42, L54, L64; evals 12 and 14). If the router asks
   the altitude question directly in Phase 4, the flag becomes a pre-answer to
   the question the router exists to answer.
6. **Who owns `references/pipeline-model.md`'s rewrite?** It restates
   `/explore`'s model while naming `/explore` as the authority for it. In or
   out of this change's scope?
7. **Should Phase 0 Stage 2 be dropped rather than rewritten?** It commits to
   an artifact type before any research happens, and Phase 4 overrides it
   anyway. Its only durable effect is the GitHub label.

## Summary

`/explore` names a chain-internal child or artifact type as a destination in
roughly 60 places across nine files, entering the tactical chain at three
different depths (`/prd`, `/design`, `/plan`) and the strategic chain at two
(`/vision`, `/roadmap`), with no vocabulary at all for BRIEF or STRATEGY — and
it does not merely route, it authors `DESIGN-*.md`, `SPIKE-*.md`, `COMP-*.md`,
and `REJECTED-*.md` directly, while `/scope`, `/charter`, and `/execute` appear
nowhere in the skill. A four-way router would delete four SKILL.md tables, the
ten-type core of the crystallize framework with five of its seven tiebreakers,
five of the nine phase-5 handoff files, and Stage 2 of triage, while keeping
Phases 0-3, the crystallize procedure, and the wip-is-ephemeral framing intact.
The biggest open question is whether the router is strictly four-way: Rejection
Record, Spike Report, COMP, and Decision Record are terminal off-chain outcomes
that no parent chain owns, three of them backed by real machinery (labels,
produce handlers, an eval fixture asserting a "demand validated as absent"
finding), so deleting them silently would strand `needs-spike`/`needs-decision`
and remove `/explore`'s only way to record a "don't build this" conclusion.
