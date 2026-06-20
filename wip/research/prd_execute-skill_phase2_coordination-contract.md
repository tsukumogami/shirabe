# Lead

What does the merged coordinated-execution-mode contract (#196) expose that the
new `/execute` skill must consume? `/execute` is an implementation-altitude
parent skill that owns plan-level execution: single-PR orchestration plus
coordinated multi-repo, delegating each single issue to `/work-on`.

Canonical contract: `references/coordination-strategy.md`.
Consumers today: `skills/scope/SKILL.md`, `skills/work-on/SKILL.md`.
CLI surface: `crates/shirabe/src/main.rs`, `crates/shirabe-validate/src/coordination.rs`, `crates/shirabe-validate/src/merge_gate.rs`.

# Findings

## 1. The coordinated-PLAN structure (shape / fields)

The coordinated effort is the third `execution_mode` value
(`single-pr | multi-pr | coordinated`), defined in
`references/coordination-strategy.md:34`. It is always multi-PR and adds three
things `multi-pr` lacks: a coordination PR that merges last, cross-repo per-repo
grouping, and a two-node merge-order DAG with gates.

The durable home is a **coordination PR** — a docs-only PR on its own branch
(`coordination-strategy.md:25-32`) that holds the planning chain
(BRIEF/PRD/DESIGN), the PLAN, and the coordination state. The PR **body** is the
durable state store (no session file is source of truth; an interrupted effort
reconnects from the branch/PR itself — `:51-55`). The body is authored by the
skill from a fixed template (`:67-101`), not rendered by any CLI subcommand.
There is no `shirabe coordination` create/render verb (`:10-15`).

Body template sections (`:75-101`):
- **Declaration marker** — a verbatim blockquote line carrying
  `This is a **coordination PR**`. Fixed text; `lifecycle.yml` greps for it to
  detect a coordination PR (`:104-107`).
- **Artifact Chain** — list of paths to BRIEF / PRD / DESIGN / PLAN.
- **PR Index** — one line per `(repo, pr_group)` node:
  `<node-id> | <owner/repo:path#number> | <merge-state>`. A **private** node is
  redacted to opaque node id + merge state only (F1, `:108-110`).
- **Merge Order** — a fenced ```` ```merge-order ```` block, one node per line:
  `<node-id> | <merge-state>`, listing each opaque node id once in acyclic order
  (`:96-100`, `:111-113`).

Per-repo grouping rule (Coarsest-Legal-Grouping, `:118-130`): default **one PR
per repository**. A repo splits into more PRs only on a recorded trigger
(independently mergeable, independently rollback-able, exceeds reviewability
ceiling, or needed to break a contraction cycle).

Merge-order model (two-node DAG, `:132-165`):
- **PR nodes** — one per `(repo, pr_group)`; satisfied when its PR merges.
- **Non-PR gate nodes** — a named verifiable condition that is not a PR (e.g. a
  package publish); satisfied only when verified **live** at recompute time; an
  unverifiable gate fails closed and blocks everything ordered after it.
- Edges mean "must merge / be satisfied before." Graph is derived and validated
  acyclic **at authoring time inside the PLAN** (`/plan` collapses the
  issue-level `waits_on` graph into this `(repo, pr_group)`-level graph). Because
  the PLAN is consumed before the coordination PR merges, the validated order is
  authored into the body as the merge-time canon (`:147-150`).
- Cross-repo atomicity (two repos that must merge simultaneously) is **refused at
  planning time**, never planned (`:161-165`).

Code: `IndexedPr { node_id, reference, number }` and `CrossRepoRef`
(`coordination.rs:53,173`); `parse_merge_order_block` extracts node ids from the
fence (`coordination.rs:531`); `parse_cross_repo_ref` is the F2 validator
(`coordination.rs:87`).

## 2. The status surface (metadata-only inspection)

Two surfaces, both metadata-only by construction:

- **Durable index in the PR body** — the PR-Index and merge-order lines carry
  `<node-id> | <merge-state>` per node. This is the *list* of nodes plus a
  last-written merge-state. The body supplies the durable index but is explicitly
  **not authoritative** for live status (F4, `:260-282`).
- **Live status via `shirabe validate --merge-gate`** — the authoritative
  per-PR / per-upstream status surface. It recomputes each node's merged/open
  status from `gh api` at gate time (`merge_gate.rs:191`, `run_merge_gate`). The
  decision core consumes `GatePrStatus { label, merged }` and
  `GateUpstreamStatus { label, terminal }` (`coordination.rs:225,238`).
- **JSON envelope for programmatic consumers** (`--format json`):
  `{"schema":"shirabe-merge-gate/v1","outcome":<pass|violations|notice|refused|...>,"reasons":[...]}`
  (`main.rs:785-804`). The PASS human line reports counts:
  `PASS (N PR(s) merged, M upstream(s) terminal; recomputed live)`
  (`main.rs:643-646`). This is the closest thing to a structured status read
  without reading PR bodies.

Important gap for `/execute`: the merge-gate envelope is a **whole-set
pass/blocked verdict + redacted reason strings**, not a structured per-node
status table. Per-node merge-state for inspection lives in the PR-body index
(non-authoritative) or must be derived by the consumer from `gh` reads it
performs itself. F1 redaction means any private node only ever surfaces as
`pr-<n>` + merge state (`coordination.rs:199-213`, `redacted_label`).

## 3. The done-signal

The single done-signal is **the coordination PR merging**
(`coordination-strategy.md:168-174`). There is no separate "effort complete"
marker — the merged coordination PR is it. It cannot merge until every indexed
PR has merged and finalization is complete.

Enforcement / what `/execute` checks: `shirabe validate --merge-gate`, run by
`lifecycle.yml` under `--mode=ready`, is the non-bypassable CI backstop
(`:64-65`, `:171-173`). It is **posture-aware** (F4, `:260-282`):
- `--mode=ready`: a blocked gate is an **error** (exit 2) — the merge-last
  backstop. Pinned to `draft == false` so it cannot be skipped by toggling draft.
- `--mode=draft` (default): a blocked gate is a **notice** that exits 0 — a
  coordination PR legitimately has unmerged indexed PRs mid-effort.
- Refusals (visibility-rule violation) and input errors are
  posture-independent and exit non-zero in every posture
  (`main.rs:608-617`, `653-677`).

The gate folds in upstream-terminal verification (a cross-repo upstream is at a
terminal status) as part of the same mode (`:273-276`). Fail-closed: any PR the
gate cannot resolve is treated as not-merged (`:281`,
`merge_gate.rs:251-261`).

## 4. The dispatch surface (walk the order, dispatch next unit)

The contract does **not** expose a "give me the next unit to dispatch"
verb. There is no `shirabe coordination next` / scheduler command. What exists:

- The **merge-order block in the PR body** is the authored, validated, acyclic
  order the consumer walks (`:147-150`). Each PR node carries its
  `(repo, pr_group)` identity via the PR-Index reference
  (`owner/repo:path#number`), so reading the index tells the coordinator which
  repo a node belongs to.
- Re-derivation rules with merged nodes (`:152-158`): an already-merged PR is a
  fixed satisfied predecessor; re-derivation orders only the unmerged remainder
  and may not add an edge requiring a merged node to re-merge or move after
  unmerged work.
- `parse_merge_order_block` (`coordination.rs:531`) + `is_acyclic_order` give a
  consumer the node ordering programmatically; live readiness of each node comes
  from the `--merge-gate` recompute (`run_merge_gate`).

So "what to dispatch next" is **computed by the skill**, not the CLI: walk the
merge-order, find the first node whose predecessors are all satisfied (per live
`gh`/merge-gate state) and that is not yet merged, read its `(repo, pr_group)`
from the index, and dispatch that repo's work. `/work-on` today drives each
indexed unit's actual implementation per repo.

## 5. What `/scope` and `/work-on` do today (reuse vs take-over)

**`/scope`** (`skills/scope/SKILL.md`, "Coordination Intent" §, lines 114-173):
- Owns the **create-up-front** phase. When coordination intent is present
  (resolved on `flag > CLAUDE.md-header > default`; `--coordinated` /
  `--no-coordinated`, lines 124-132), `/scope` creates the coordination PR/branch
  before any implementation, authors the body from the contract template, and
  posts with `gh pr create` (`:135-147`).
- Runs `shirabe validate --coordination-body <file>` for offline authoring
  feedback (declaration marker present, refs pass F2, merge-order acyclic).
- Records `plan_execution_mode:` in state (`single-pr | multi-pr`; coordinated is
  the coordinated multi-pr case). State schema refs at lines 315-316, 370-377.
- Handles **coordinated abandonment** (R20, `:545-567`): `gh pr close` without
  merging, force-materializing partial planning artifacts.

**`/work-on`** (`skills/work-on/SKILL.md`, "Coordination Intent" §, lines 43-130):
- Owns the **track / finalize / merge-last** phases as **plan orchestrator
  mode**. When the PLAN's `execution_mode` is `coordinated`, it refreshes the
  coordination PR body on each orchestrator pass — re-authoring the PR-Index and
  merge-order from live `gh` reads, posting with `gh pr edit` (`:58-73`).
- Drives `shirabe validate --merge-gate` as the merge-last check before the
  coordination PR can merge (`:67-68`, `:103-105`).
- **Coordination Failure Halts (R21, `:94-113`)**: any coordination step that
  cannot complete halts loudly; never papers a failed step as success.
- **Coordinated Abandonment (R20, `:116-130`)**: mirrors `/scope` — closes the
  coordination PR unmerged.
- Today, plan-orchestrator mode coordinates per-issue child workflows and
  assembles a combined PR (`:41`); `batch_outcome: all_success` routes to
  `pr_coordination` (`:218`).

# Implications for /execute requirements

- **R-EXEC-1 (consume execution_mode):** `/execute` must read the PLAN's
  `execution_mode` and branch: `single-pr` → single-PR orchestration;
  `coordinated` → multi-repo coordination. It must NOT restate the contract — it
  binds to `references/coordination-strategy.md` and carries only bindings, the
  same single-source discipline `/scope` and `/work-on` follow.
- **R-EXEC-2 (own the track→merge-last lifecycle):** `/execute` takes over what
  `/work-on` plan-orchestrator mode does today for coordinated efforts:
  refreshing the coordination PR body (PR-Index + merge-order) from live `gh`
  reads on each pass via `gh pr edit`, and delegating each single issue/unit to
  `/work-on`. Create-up-front stays with `/scope`; `/execute` consumes the
  already-created coordination PR.
- **R-EXEC-3 (status read = merge-gate, not body):** for done-signal and
  per-node readiness `/execute` must call `shirabe validate --merge-gate`
  (`--mode=ready` for the authoritative verdict, `--format json` for the
  envelope) and treat the PR-body index as the durable *list* only — never trust
  body text for live merge state (F4).
- **R-EXEC-4 (dispatch is skill-computed):** no CLI gives "next unit." `/execute`
  must walk the authored merge-order, resolve each node's `(repo, pr_group)` from
  the PR-Index, check predecessor satisfaction via live state, and dispatch the
  next unblocked, unmerged unit to its repo via `/work-on`.
- **R-EXEC-5 (inherit the hard rules):** F1 (fail-closed private-identifier
  redaction), F2 (`owner/repo:path` component validation), F4 (gate recomputes
  live, posture-aware) are requirements on every consumer that authors,
  validates, or gates. `/execute` re-validates `repo`/`pr_group` on every read
  (`pr_group` `^[a-z][a-z0-9-]*$`), never writes a private repo's identifiers
  into a public coordination body, and routes diagnostics through redaction.
- **R-EXEC-6 (halt + abandonment semantics):** `/execute` must carry R21
  (coordination step that can't complete halts loudly, leaves coordination PR
  unmerged) and R20 (abandonment closes the coordination PR unmerged via
  `gh pr close`, force-materializing partial artifacts) — both currently in
  `/work-on` and `/scope`.
- **R-EXEC-7 (read-only cross-repo boundary):** the cross-repo boundary is a
  read-only verification gate; no coordination step writes across a repo
  boundary. `/execute`'s only writes are to the coordination PR's own body/state
  in its own repo.

# Open questions

- Does `/execute` fully **replace** `/work-on` plan-orchestrator mode for
  coordinated efforts, or wrap it (calling `/work-on` per unit while `/execute`
  owns the coordination-PR refresh loop)? The lead frames `/execute` as
  delegating each single issue to `/work-on`, which implies the latter — but
  `/work-on` SKILL.md still owns the coordinated track/merge-last phases today,
  so the migration boundary needs an explicit decision.
- There is no structured **per-node status** surface (only a whole-set
  pass/blocked envelope + redacted reasons). Does `/execute` need a richer
  per-node status read from the CLI, or is deriving it from its own `gh` reads +
  the merge-gate verdict acceptable?
- Non-PR **gate nodes** (e.g. package publish) are verified live but have no
  authoring/dispatch tooling shown — how does `/execute` know a gate node's
  verifiable condition and trigger/await it?
- For **single-pr** mode there is no coordination PR or merge-gate; confirm
  `/execute` simply runs `/work-on` directly with no coordination surface.

# Summary

The #196 contract (`references/coordination-strategy.md`) exposes a coordinated
`execution_mode` whose durable state is a docs-only coordination PR that merges
last; its skill-authored body carries a verbatim declaration marker, an artifact
chain, a PR-Index of `(repo, pr_group)` nodes (`node-id | owner/repo:path#number
| merge-state`), and a fenced acyclic two-node merge-order DAG (PR nodes + live
gate nodes), with no `shirabe coordination` CLI verb — the only CLI surfaces are
`shirabe validate --coordination-body` (offline authoring check) and `shirabe
validate --merge-gate` (live, posture-aware, fail-closed `gh` recompute that is
both the per-node status read and the non-bypassable done-signal). `/scope` owns
create-up-front and `/work-on` plan-orchestrator mode owns track/finalize/
merge-last today, so `/execute` must take over the coordinated track→merge-last
loop (refresh the body from live `gh`, walk the merge-order, dispatch each
unblocked unit to `/work-on`, gate the done-signal on `--merge-gate
--mode=ready`) while inheriting F1/F2/F4, R20 abandonment, and R21 halt
semantics. The key gaps `/execute` must resolve are the migration boundary with
`/work-on`, the absence of a structured per-node status surface and any
gate-node dispatch tooling, and confirmation that single-pr mode bypasses the
coordination surface entirely.
