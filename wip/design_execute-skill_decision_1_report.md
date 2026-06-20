# Decision 1: plan-iteration mechanism

How `/execute` iterates a plan's issues — the execution mechanism and the per-issue session model.

## Context

`/execute` is the new implementation-altitude parent. It owns two plan shapes:

- **single-pr**: many issues, one shared `impl/<slug>` branch + one draft PR, single-repo. This is exactly what the `work-on-plan.md` koto template orchestrates today (lifted out of `/work-on`).
- **coordinated**: independent per-repo PRs across repos, plus a docs-only coordination PR that merges last; the merge order is a two-node `(repo, pr_group)` DAG with gates (`references/coordination-strategy.md`).

Each single issue is delegated to a narrowed `/work-on` — the koto-backed single-issue executor (template `work-on.md`), unchanged.

Two facts about koto bound the space:

1. **koto has no cross-repo session.** A koto session and its child workflows live in one ephemeral home (the session artifacts live in the ephemeral home directory). The `work-on-plan` template's `materialize_children` + `children-complete` gate + `failure_policy: skip_dependents` machinery assumes all children share that home and a shared git branch. A coordinated run spans repos with independent branches/PRs; there is no single git checkout or single ephemeral home that spans them.
2. **koto's plan-level value is real and proven.** The `work-on-plan` template already delivers, declaratively and crash-resumably: the drift gate (`worktree_discipline_check` → `escalate_upstream_drift`), dependency sequencing + skip-dependents (`materialize_children` with `failure_policy: skip_dependents`), batch-completion gating (`children-complete`), CI choreography (`ci_monitor` with DIRTY-merge handling), and the finalization cascade ordered before `gh pr ready` (`plan_completion` → `run-cascade.sh`). Cross-issue carry-forward is layered on top via `koto context add`/`get` (`cross-issue-context.md`), not in the template itself.

The author's directional intent is a **hierarchical koto model**: a parent koto session at the plan level, child koto sessions per issue — but with the explicit caveat that a single plan-level koto session for a coordinated run is hard and may be deferred.

The parity-or-better bar (drift gate, carry-forward, dependency sequencing + skip-dependents, CI choreography, finalization cascade, crash-resume) is a hard guardrail from the PRD, independent of mechanism.

## Options

### Option A — Lift `work-on-plan` into `/execute` as a plan-level koto session with per-issue child sessions (uniform koto for both modes)

`/execute` runs the (renamed) `work-on-plan` template as a single plan-level koto session for *every* plan shape. Per-issue children are koto child workflows materialized from `tasks` via `materialize_children`, each running the `work-on.md` per-issue machine.

- **Parity**: free and verbatim for single-pr — every capability already lives in the template. Drift gate, dependency sequencing/skip, CI choreography, cascade, crash-resume are the template's existing states; carry-forward is the existing `koto context` layer.
- **single-pr**: native. This is the template's home ground; no change beyond ownership migration and variable renaming.
- **coordinated**: this is where A breaks. A single koto session cannot span repos — children would need independent git checkouts, branches, and PRs in different repos, but koto materializes children into one ephemeral home tied to one working tree. To force coordinated mode into one koto session you would have to either (i) drive cross-repo `gh`/git from a single checkout (fragile, and violates the coordination contract's "no coordination step writes across a repo boundary"), or (ii) invent a cross-repo session primitive koto does not have. The coordination contract's state is explicitly **durable on the coordination PR/branch itself, not a session file** ("no session file is the source of truth") — a plan-level koto session would be a *second*, competing source of truth for merge-order/PR-index state.
- **Feasibility**: high for single-pr, low for coordinated given koto's cross-repo limit. Shipping A alone would either block coordinated mode or force an unsound cross-repo koto hack.

### Option B — Plain (non-koto) orchestration loop in `/execute`, koto only per-issue inside `/work-on`

`/execute` itself runs no koto session. It implements a plain orchestration loop (the parent-skill-pattern Team-Lead sleep-check-nudge discipline, I-7 Active Orchestration) that: classifies drift, walks the issue/merge-order graph, dispatches each issue to `/work-on`, and each `/work-on` invocation runs its *own* per-issue koto session (template `work-on.md`, unchanged). Carry-forward, CI choreography, and the cascade become parent-loop responsibilities re-implemented in prose/scripts.

- **Parity**: achievable but expensive and risky. Every capability the `work-on-plan` template gives declaratively — the drift gate, skip-dependents sequencing, the children-complete batch gate, the cascade-before-ready ordering, crash-resume — must be **re-implemented by hand** in the parent loop. Crash-resume is the worst regression risk: koto's session state machine gives free resumability (`koto workflows` → `koto next`), whereas a plain loop must reconstruct progress from durable artifacts (PR state, branch commits, `wip/` state) — feasible (the coordination contract already reconnects from durable PR state) but a lot of net-new resume logic.
- **single-pr**: works but throws away a proven, tested template and rebuilds its guarantees less safely.
- **coordinated**: this is B's natural fit. Coordinated state is already durable-on-PR, the merge-order walk is a graph traversal the parent loop owns, and per-repo PRs are independent `/work-on` invocations. No cross-repo koto session is needed because there is no plan-level koto session at all.
- **Feasibility**: high for coordinated, but imposes a parity-regression risk on single-pr by discarding the template that currently *is* the parity bar.

### Option C — Hybrid: koto-backed plan session for single-pr; plain durable-state orchestration for coordinated

`/execute` branches on `execution_mode` at entry:

- **single-pr** → run the lifted `work-on-plan` koto session verbatim (Option A's strength), single-repo, single shared branch, child koto workflows per issue. Parity is inherited, not rebuilt.
- **coordinated** → run a plain orchestration loop over the merge-order DAG (Option B's strength). No plan-level koto session; state is durable on the coordination PR per the contract; each per-repo PR group is dispatched to `/work-on` (which still uses its own per-issue koto session internally). The cross-repo merge-last gate is `shirabe validate --merge-gate`, owned by the CLI, not by koto.

Per-issue session model is uniform across both modes: **every single issue is a `/work-on` invocation backed by its own per-issue koto session.** The modes differ only in the *parent* layer — koto session (single-pr) vs. plain durable-state loop (coordinated).

- **Parity**: single-pr inherits all capabilities verbatim from the template (zero regression risk). Coordinated re-implements only the subset that the cross-repo shape actually needs (merge-order walk, per-PR-group dispatch, merge-last gate) — and most of that is *already specified* in the coordination contract, which deliberately does not assume a koto session.
- **single-pr vs coordinated**: each mode uses the mechanism that fits it. The single-repo nesting koto supports is used exactly where it works; the cross-repo case that koto cannot express is handled by durable-PR state, which the contract already mandates.
- **Feasibility**: highest overall. It does not ask koto to do the one thing it cannot (cross-repo sessions), and it does not throw away the proven single-pr template. The cost is two parent-layer code paths in `/execute` instead of one — but they share the per-issue delegation surface and the parent-skill-pattern state schema/resume ladder, so the divergence is confined to the plan-walk layer.

## Recommendation

**Adopt Option C — the hybrid.** single-pr runs the lifted `work-on-plan` koto session verbatim (a plan-level koto session with per-issue child koto sessions, exactly the author's hierarchical intent where it is sound); coordinated runs a plain durable-state orchestration loop over the merge-order DAG with no plan-level koto session, because koto has no cross-repo session and the coordination contract already makes the coordination PR/branch the durable source of truth.

This is the only option that honors all three forces simultaneously: (1) the author's hierarchical-koto intent is realized for single-pr, where single-repo child nesting works; (2) koto's cross-repo limit is respected rather than worked around unsafely; (3) the parity bar is met with **zero regression for single-pr** (the template that *defines* the bar is reused, not reimplemented) and met for coordinated by binding to the contract's already-durable state plus the CLI-owned merge gate.

The per-issue session model is uniform and unchanged: one `/work-on` invocation per issue, each backed by its own per-issue koto session (`work-on.md`). `/execute` never reaches into a child's koto session — it inspects only durable artifacts (child workflow outcome, PR state, branch commits), preserving parent-skill-pattern R14 child-isolation (I-3 child-isolated resume).

Capability mapping under C:

| Parity capability | single-pr (koto session) | coordinated (plain loop) |
|---|---|---|
| Drift gate | `worktree_discipline_check` state | parent-loop classify before dispatch (same `worktree-discipline.md`) |
| Carry-forward | `koto context add/get` layer | parent-loop assembles from child summaries / durable state |
| Dependency seq + skip | `materialize_children` + `skip_dependents` | merge-order DAG walk; skip dependents on PR-group failure |
| CI choreography | `ci_monitor` (incl. DIRTY) | per-PR-group `/work-on` owns its CI; merge-last gate gates the coordination PR |
| Finalization cascade | `plan_completion` → `run-cascade.sh` (before `gh pr ready`) | repo-local cascade per PR; coordination PR consumes its own PLAN, merges last |
| Crash-resume | koto session (`koto workflows` → `koto next`) | reconnect from durable coordination-PR/branch state |

## What defers

- **A unified plan-level koto session spanning both modes is deferred**, not chosen-against permanently. It is blocked on a koto capability that does not exist today: a cross-repo (or cross-checkout) session/child-materialization primitive. If koto later grows that primitive, coordinated mode could migrate from the plain loop to a koto session under the same `team_primitive` amplifier-layer substitution the parent-skill-pattern already names — without changing `/execute`'s public contract or the per-issue delegation surface. The hybrid is explicitly structured so that this is a later substitution, not a redesign: the coordinated plain loop and the single-pr koto session both sit behind the same parent-skill-pattern state schema and resume ladder.
- **Coordinated-mode crash-resume via koto session** defers with it; v1 coordinated resume reconnects from durable PR/branch state (which the coordination contract already specifies as the source of truth), not from a koto session file.
- **I-6 cross-branch resume** remains the parent-skill-pattern's named-but-unsatisfied v1 invariant for both modes (state lives where the run originated); this decision does not close it and is not expected to.

## Open dependencies

- **Narrowing `/work-on`** (PRD in-scope): the `work-on-plan.md` template and its plan-orchestrator prose move from `/work-on` to `/execute`. `/work-on` keeps only `work-on.md` (per-issue) plus plan-backed *child* mode. This decision assumes that migration lands; the per-issue delegation surface (`-- plan-backed`, `SHARED_BRANCH` injection, `ISSUE_TYPE` hint, `pr_status: shared`) is the contract both modes call and must survive the move unchanged.
- **Coordination contract ownership** (`references/coordination-strategy.md`, merged #196): the coordinated plain loop binds to it — PR-index, merge-order DAG, F1/F2/F4 security rules, and `shirabe validate --merge-gate`/`--coordination-body`. The plain loop authors and refreshes the coordination PR body; it does not re-specify the contract. Confirms the contract's "no session file is the source of truth" stance is compatible with C (it is — C deliberately uses no plan-level session for coordinated).
- **CLI merge-gate** (`shirabe validate --merge-gate`, run by `lifecycle.yml` under `--mode=ready`): the coordinated done-signal backstop. Owned by the CLI, not `/execute`; this decision depends on it existing as the non-bypassable merge-last gate.
- **Cross-issue carry-forward placement**: in single-pr it stays the `koto context` layer; in coordinated `/execute`'s loop must assemble carry-forward from child durable summaries. Whether carry-forward crosses repo boundaries in coordinated mode (and how, given F1 redaction) is a follow-on detail this decision flags but does not resolve.
