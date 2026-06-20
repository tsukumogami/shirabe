# Decision 2: orchestrator extraction + PLAN routing

How do we (a) remove the plan-orchestration responsibility from `/work-on`
and (b) route existing PLAN docs so everything keeps working, with `/work-on`
narrowed to single-issue?

## Settled upstream (not relitigated here)

- `/execute` owns **single-pr** + **coordinated** plan execution. `/work-on`
  narrows to single-issue.
- **multi-pr** (single-repo, many PRs) is NOT owned by `/execute`: each issue
  runs independently via `/work-on` against the repo-persisted PLAN (D5 — a
  thin sequential milestone loop inside `/work-on` is allowed but not required;
  no cross-issue state either way).
- Backward-compat is hard: existing PLAN docs run end-to-end with NO rewrite.
  `execution_mode` ∈ {single-pr, multi-pr, coordinated}. The legacy 4-column
  issue table must still parse. The untracked-AC escape hatch
  (`WORK_ON_ALLOW_UNTRACKED_ACS=1`) must keep working.

## What exists today (source survey)

The plan-orchestration responsibility is spread across four assets, all
physically rooted under `skills/work-on/` but logically owned by the
plan-orchestrator path:

| Asset | Path | Role | Owned by |
|-------|------|------|----------|
| Orchestrator prose | `skills/work-on/SKILL.md` lines 39–256 ("Plan Mode" through "Completion Cascade") | Mode detection, plan-orchestrator vs plan-backed-child split, coordination intent, cascade narration | orchestrator |
| Orchestrator koto template | `skills/work-on/koto-templates/work-on-plan.md` (+ `.mermaid.md`) | `orchestrator_setup → spawn_and_await → pr_coordination → pr_finalization → plan_completion → ci_monitor` state machine | orchestrator |
| Per-issue koto template | `skills/work-on/koto-templates/work-on.md` (+ `.mermaid.md`) | Single-issue lifecycle; **also** holds plan-aware states `plan_context_injection`, `plan_validation`, `setup_plan_backed`, and reads `PLAN_DOC`/`SHARED_BRANCH`/`ISSUE_TYPE` vars | shared (issue + child) |
| Cascade script | `skills/work-on/scripts/run-cascade.sh` (+ `_test.sh`) | Upstream-chain lifecycle finalization (PLAN→DELETED, DESIGN→Current, …), `--allow-untracked-acs` env forwarding | orchestrator's `plan_completion` |
| Tasks fan-out script | `skills/plan/scripts/plan-to-tasks.sh` (+ `_test.sh`, `plan-to-tasks-contract.md`) | PLAN→koto task JSON for all three modes (single-pr outlines, multi-pr `#N`, coordinated PR-node contraction) | **already in `/plan`, not `/work-on`** |
| Format/contract refs | `skills/plan/references/plan-format.md`, `.../plan-to-tasks-contract.md`, `.../quality/plan-doc-structure.md` | execution_mode enum incl. `coordinated`, legacy 4-column FC05 hint | `/plan` |

Two structural facts drive the recommendation:

1. **`plan-to-tasks.sh` already lives in `skills/plan/scripts/`**, not in
   `work-on`. The SKILL.md prose calls it via
   `${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/...` for the cascade but
   `plan-to-tasks.sh` is referenced from `skills/plan/`. So part of the
   "shared library" already exists — the fan-out converter is plan-owned and
   any consumer (`/work-on` today, `/execute` tomorrow) calls it by path.
2. **The per-issue `work-on.md` template is dual-purpose.** It is the
   single-issue engine AND the plan-backed-child engine (the orchestrator
   spawns it with `SHARED_BRANCH`/`PLAN_DOC`). Extraction cannot simply "move
   work-on.md to `/work-on` and work-on-plan.md to `/execute`" because the
   orchestrator in `/execute` must keep spawning the child template that lives
   in `/work-on`. The child template is the seam.

## Extraction options

### E1 — Physical move: orchestrator assets into `/execute`, per-issue stays in `/work-on`

Move `work-on-plan.md` (+ mermaid), the "Plan Mode"/"Completion Cascade"
prose, and `run-cascade.sh` (+ test) into `skills/execute/`. Leave `work-on.md`
(per-issue template) and the single-issue prose in `skills/work-on/`. `/execute`
spawns the `/work-on` per-issue child template by cross-skill path; both call
the plan-owned `plan-to-tasks.sh`.

- **Pro:** Cleanest narrowing of `/work-on` — its SKILL.md drops ~220 lines of
  orchestrator prose and one whole template. The single-issue surface becomes
  legible: one template, one lifecycle, no coordination narration.
- **Pro:** `run-cascade.sh` follows its only caller (`plan_completion` lives in
  `work-on-plan.md`). No script is referenced from a skill that no longer needs
  it.
- **Pro:** Backward-compat is structural, not behavioral: the per-issue child
  template is byte-identical, so plan-backed children, `SHARED_BRANCH`,
  `ISSUE_TYPE`, and the legacy 4-column path all keep working because nothing
  about the child changed.
- **Con:** Introduces a cross-skill template reference: `/execute`'s
  `spawn_and_await` must `koto init` children with
  `--template …/skills/work-on/koto-templates/work-on.md`. That path coupling
  must be explicit and tested. (It already exists in spirit — today the
  orchestrator template and child template live in the same dir but are
  separate koto programs.)
- **Con:** The child template retains plan-aware states (`plan_context_injection`,
  `setup_plan_backed`). Those now serve a sibling skill's orchestrator. That's a
  legible contract, but it means `/work-on` still carries plan-coupled code it
  doesn't drive on its own — a residual, not a clean amputation.

### E2 — Shared library: both skills reference a common `plan-orchestration/` asset set

Create a neutral shared location (e.g. `skills/plan/koto-templates/` or a new
`skills/_shared/`) holding `work-on-plan.md`, `run-cascade.sh`, and the
per-issue child template. Both `/work-on` and `/execute` reference assets by
path; neither "owns" them.

- **Pro:** No skill duplicates the child template; the dual-purpose template
  has a single home that doesn't privilege either consumer.
- **Pro:** `plan-to-tasks.sh` already follows this pattern (plan-owned, called
  by path), so a shared-asset convention is partly precedented.
- **Con:** `/work-on`'s narrowing is muddier — its single-issue engine now
  lives outside the skill, so reading `skills/work-on/` no longer tells you how
  `/work-on` works. The decision context explicitly values "clean single-issue
  narrowing"; a shared template undercuts that legibility.
- **Con:** Introduces a third top-level location (`_shared`) or overloads
  `skills/plan/` with execution-time koto templates that have nothing to do
  with authoring a PLAN. Conceptually muddy: `/plan` authors PLANs, it should
  not host the execution engine.
- **Con:** More moving parts to keep `${CLAUDE_PLUGIN_ROOT}`-relative paths
  correct across three referencing skills.

### E3 — Hybrid: orchestrator to `/execute`, child template stays in `/work-on` as the canonical single-issue engine, cascade to `/execute`

Same as E1 but make the dual-purpose nature explicit and intentional: the
per-issue `work-on.md` template is documented as the canonical single-issue
execution engine, and `/execute` is a declared consumer of it (the plan-backed
states are a published extension point, not residue). `run-cascade.sh` moves to
`/execute` because the cascade is a whole-PLAN completion concern, not a
single-issue one.

- **Pro:** Keeps E1's clean `/work-on` narrowing while reframing the residual
  con of E1 as an intentional contract: `/work-on` owns and publishes the
  single-issue engine; `/execute` composes it. This matches D5 (multi-pr runs
  each issue independently via `/work-on`) — `/work-on` must remain the
  single-issue engine other paths reuse.
- **Pro:** Cascade ownership lands where the responsibility lives: completing a
  PLAN's upstream chain is `/execute`'s job (single-pr) and is never invoked by
  a bare single-issue `/work-on` run.
- **Con:** Requires writing down the child-template contract (vars in,
  evidence out, plan-backed states) so the cross-skill dependency is a
  maintained interface, not an accident. This is documentation work, but it is
  the right kind.

## Routing options

### R1 — `/work-on` keeps PLAN-path input; dispatches by execution_mode

`/work-on PLAN.md` reads `execution_mode` and dispatches: single-pr /
coordinated → redirect/hand off to `/execute`; multi-pr → run per-issue (thin
milestone loop or one-issue selection) in `/work-on` itself.

- **Pro:** Zero break for any caller (human or parent skill) that today types
  `/work-on docs/plans/PLAN-*.md`. The PLAN doc itself is unchanged — the
  dispatcher reads the existing `execution_mode` field.
- **Pro:** multi-pr stays home, matching D5 exactly: each issue runs
  independently via `/work-on`, no cross-issue state required.
- **Con:** `/work-on` retains a PLAN-path mode detector and a dispatch branch —
  it doesn't fully shed plan awareness. The "narrow to single-issue" goal is
  partially compromised: `/work-on` still recognizes PLAN docs, just to bounce
  two of three modes elsewhere.
- **Con:** A single-pr PLAN typed at `/work-on` silently re-routes to
  `/execute`. Convenient, but the redirect must announce itself or it surprises
  the user.

### R2 — `/work-on` drops PLAN mode entirely; author/parent invokes `/execute`

`/work-on` accepts only issue / milestone / free-form. PLAN-path input is
removed; the user or the upstream skill (e.g. `/scope`, `/plan`) invokes
`/execute PLAN.md` for single-pr and coordinated. multi-pr is handled by
`/work-on M<milestone>` (the milestone the PLAN materialized) — i.e. the PLAN
isn't fed to `/work-on`, the milestone is.

- **Pro:** Maximal narrowing — `/work-on` has no PLAN awareness at all. The
  mode detector loses three branches; SKILL.md sheds the entire "Plan Mode"
  section. Cleanest possible single-issue surface.
- **Pro:** Conceptually honest: a PLAN is executed by `/execute`; an issue or
  milestone is executed by `/work-on`. The input type maps 1:1 to the skill.
- **Con (backward-compat break):** Any existing automation, doc, or muscle
  memory that runs `/work-on docs/plans/PLAN-*.md` breaks. The constraint says
  PLAN **docs** need no rewrite — it does not promise the **invocation** is
  unchanged — but a hard removal of the input path is the most disruptive
  option for existing workflows and the `/work-on` SKILL's own evals (which
  assert PLAN-path detection).
- **Con:** multi-pr routing becomes "invoke `/work-on` on the milestone, not
  the PLAN," which is a real behavior shift for multi-pr authors and needs the
  milestone to have been materialized first.

### R3 — execution_mode dispatcher as a thin shared front-door

A small shared resolver (prose or a tiny script) reads `execution_mode` from a
PLAN path and is referenced by both skills. `/work-on PLAN.md` and
`/execute PLAN.md` both route through it: single-pr/coordinated land in
`/execute`'s state machine, multi-pr lands in the per-issue path. The dispatcher
is the one place the enum→path mapping lives.

- **Pro:** Single source of truth for the enum→owner mapping; if a fourth mode
  is ever added, one file changes.
- **Pro:** Preserves the `/work-on PLAN.md` entry point (no invocation break)
  while keeping the dispatch logic out of `/work-on`'s body.
- **Con:** Over-engineered for a three-value enum with a stable owner mapping.
  The mapping (single-pr→execute, coordinated→execute, multi-pr→work-on) is
  unlikely to churn; a shared dispatcher is indirection without payoff.
- **Con:** Still leaves `/work-on` recognizing PLAN paths (same partial-narrow
  con as R1), plus adds a new shared asset to maintain.

## Recommendation

**Extraction: E3 (E1 with the child-template contract made explicit).**

Move the orchestrator prose, `work-on-plan.md` (+ mermaid), and
`run-cascade.sh` (+ test) into `skills/execute/`. Keep the per-issue
`work-on.md` template in `skills/work-on/` as the canonical, published
single-issue engine. `/execute`'s `spawn_and_await` spawns children with
`--template …/skills/work-on/koto-templates/work-on.md`; both skills call the
already-plan-owned `skills/plan/scripts/plan-to-tasks.sh`. Document the child
template's plan-backed contract (vars `PLAN_DOC`/`SHARED_BRANCH`/`ISSUE_TYPE`,
the `plan_context_injection`/`setup_plan_backed` states, the `pr_status: shared`
hand-off) as a maintained interface.

Why over E2: a shared `_shared/` or plan-hosted template muddies the exact
thing the decision prizes — a legible single-issue `/work-on`. E3 keeps the
single-issue engine inside `skills/work-on/` (so reading that directory tells
you how `/work-on` works) while moving every whole-PLAN concern (fan-out
orchestration, cascade) to `/execute`. The one cost — a cross-skill template
reference — is real but bounded, already half-precedented by `plan-to-tasks.sh`,
and turned from a liability into a contract by writing it down.

**Routing: R1 (execution_mode dispatch retained in `/work-on`), with the
single-pr/coordinated hand-off announced.**

`/work-on PLAN.md` keeps working: it reads `execution_mode` and (a) hands
single-pr and coordinated PLANs to `/execute` with an explicit announce
("this PLAN is single-pr; handing off to /execute"), and (b) runs multi-pr
in-place via per-issue selection (the optional D5 thin milestone loop). This
keeps every existing `/work-on PLAN.md` invocation functional with no PLAN
rewrite, satisfies D5's "multi-pr runs each issue via `/work-on`" exactly, and
confines the only behavior change to a visible redirect.

Why over R2: R2's hard removal of the PLAN-path input is the single biggest
backward-compat hazard in this decision — it breaks existing invocations and
the skill's own PLAN-detection evals, for a narrowing benefit that R1 mostly
delivers anyway. Why over R3: the enum→owner mapping is stable and tiny; a
shared dispatcher is indirection the three-value enum doesn't earn.

Net: `/work-on` sheds the orchestrator template, the cascade, and ~220 lines
of orchestrator prose (the real narrowing), while retaining a thin PLAN-path
front door that dispatches multi-pr locally and bounces single-pr/coordinated
to `/execute`. The dispatcher is prose in `/work-on`'s SKILL.md, not a new
asset.

## Backward-compat verification

| Hard constraint | How the recommendation preserves it |
|-----------------|--------------------------------------|
| **No PLAN rewrite** | Neither extraction nor routing touches PLAN doc content. `execution_mode`, the issue table, frontmatter, and upstream chains are read, never rewritten. R1 dispatches on the existing field. |
| **`execution_mode` ∈ {single-pr, multi-pr, coordinated}** | `plan-to-tasks.sh` (unchanged, plan-owned) keeps its three-way `case` (verified at `plan-to-tasks.sh:1040–1075`). R1's dispatcher maps the same three values; coordinated → `/execute` (which owns coordination per upstream), multi-pr → `/work-on` per-issue, single-pr → `/execute`. |
| **Legacy 4-column issue table parses** | The legacy shape is handled inside `plan-to-tasks.sh`'s multi-pr reader (`| Issue | Title | Complexity | Dependencies |`, contract §multi-pr) and the FC05 migration hint in `plan-format.md`. Both stay in `/plan`; extraction doesn't touch them. multi-pr routing stays in `/work-on`, which already drives that reader. |
| **Untracked-AC escape hatch** | `WORK_ON_ALLOW_UNTRACKED_ACS=1` is read by `run-cascade.sh` (lines 52–60, 649–650) and forwarded as `--allow-untracked-acs`. The cascade script moves to `/execute` **as-is**; the env var name and forwarding are unchanged, so the hatch works identically. Its `_test.sh` scenarios (9b: env-forwarded, default-off) move with it and keep asserting the contract. |
| **Plan-backed children keep running** | The per-issue `work-on.md` template — including `plan_context_injection`, `plan_validation`, `setup_plan_backed`, `SHARED_BRANCH`/`PLAN_DOC`/`ISSUE_TYPE` handling, and `pr_status: shared` — stays byte-identical in `/work-on`. `/execute` spawns it by path, exactly as `work-on-plan.md` does today. |
| **Cascade lifecycle behavior** | `run-cascade.sh` (delete PLAN, DESIGN→Current, PRD/BRIEF→Done, ROADMAP update; `--lifecycle-chain … --mode=ready` pre-probe/post-verify) is moved unmodified; only its containing directory changes. The `plan_completion` state that calls it moves with `work-on-plan.md` into `/execute`. |

### Main residual risk

The one load-bearing new coupling is the **cross-skill koto template
reference**: `/execute` must `koto init` per-issue children against
`…/skills/work-on/koto-templates/work-on.md`. If that path is hard-coded
incorrectly, or `${CLAUDE_PLUGIN_ROOT}` resolves differently for `/execute`
than for `/work-on`, plan-backed children fail to spawn — and this is exactly
the path that existing single-pr/coordinated PLANs depend on, so a path error
is a silent backward-compat break. Mitigation: make the child-template path an
explicit, tested contract (an eval that runs a single-pr PLAN end-to-end
through `/execute` and asserts a child workflow initializes), and assert
`run-cascade.sh`'s relocated path in `plan_completion` the same way. Secondary
risk: `/work-on`'s own PLAN-detection evals (which currently assert
plan-orchestrator behavior in `skills/work-on/evals/evals.json:643,678`) must
be repointed — the single-pr/coordinated cases move to `/execute`'s eval suite,
and `/work-on` keeps only the multi-pr and the "announce-and-hand-off" cases.
