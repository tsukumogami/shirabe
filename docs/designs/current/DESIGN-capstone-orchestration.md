---
status: Current
problem: |
  shirabe's `/scope` and `/work-on` are single-repo. An effort spanning repositories
  has no tool-supported coordination: the author hand-writes the contract each session
  and tracks cross-repo merge state manually. PRD-capstone-orchestration requires the
  workflows to carry that coordination, but the cascade, finalize, and merge-order
  machinery are all hard-bound to a single repository.
decision: |
  Add a "coordinated" capability as a cross-cutting reference contract bound by `/scope`
  and `/work-on`. The coordination PR is a docs-only PR created up front; per-repo
  implementation lands as separate PRs grouped to the coarsest legal unit. The
  coordination PR body is authored by the skill from a template (the same author-by-skill
  discipline every shirabe artifact follows) and posted/refreshed with `gh`; `shirabe
  validate` checks it — `--coordination-body` is the static authoring-feedback check
  (offline) and `--merge-gate` is the posture-aware live merge-last gate that
  `lifecycle.yml` runs under `--mode=ready` as the non-bypassable backstop. Finalize
  writes stay repo-local with a read-only cross-repo verification gate. The merge order is
  derived and validated (acyclic) in the PLAN at authoring time and authored into the
  coordination PR body as merge-time canon.
rationale: |
  Every cross-repo write or always-on service was rejected for cost and for violating
  PRD R19/R21 (no new service; no partial cross-repo state). Keeping writes repo-local
  and coordination pull-based reuses existing seams (`gh.rs`, `is_cross_repo_ref`, the
  `waits_on` DAG, `lifecycle.yml`). Authoring the body in the skill (not a CLI renderer)
  keeps shirabe's author-by-skill / check-by-validate split consistent, so the only
  compiled logic is deterministic validation and the gh-backed live gate. A canonical
  reference with bound consumers matches shirabe's house style (`parent-skill-pattern.md`)
  and prevents drift across consumers.
upstream: docs/prds/PRD-capstone-orchestration.md
---

# DESIGN: Coordinated Multi-Repo Orchestration

## Status

Current

## Context and Problem Statement

shirabe's tactical chain is single-repo by construction. `/scope` produces
BRIEF → PRD → DESIGN → PLAN in the current repository; `/work-on` drives a PLAN onto
one branch and one PR there. PRD-capstone-orchestration requires `/scope` and `/work-on`
to become coordination-aware: a single coordination PR created up front, implementation
grouped to the coarsest legal per-repo PRs, a derived and tracked merge order, and the
coordination PR merging last as the completion signal — generalizing the single-repo machinery
across repositories.

This effort is slugged `capstone-orchestration` (its working name) and introduces the
**coordinated** execution mode and the **coordination PR** — the durable terms used
throughout this document for the mode and the artifact respectively.

The technical obstacle is that the machinery is hard-bound to one repository, by design:

- `finalize.rs` deliberately **stops** the chain walk at any cross-repo `owner/repo:path`
  upstream; `validate_upstream_path` rejects paths outside `$REPO_ROOT`; `run-cascade.sh`
  rejects paths outside one git root and checks issues against a single `origin`.
- `/plan` emits an issue-level `waits_on` dependency DAG with no notion of target repo or
  PR grouping; `/work-on` collapses issues to PRs only via the `single-pr`/`multi-pr`
  binary.
- niwa's mesh/coordination was removed; only `niwa worktree` plus git/`gh` remain, so all
  orchestration must live in shirabe with no new always-on service (PRD R19).

Coordinated mode is the multi-repo generalization of what already works single-repo, not a
new standalone tool.

## Decision Drivers

- **PRD R19 — no new always-on service or state store.** Coordination must use only the
  coordination PR, git/`gh`, and existing niwa worktree creation.
- **PRD R21 — no partial cross-repo state.** A failed coordination step halts; the coordination PR
  never merges on incomplete finalization. This rules out any operation that can leave one
  repo written and another not.
- **PRD R7/R14 — merge-last, gated.** The coordination PR cannot merge until every indexed per-repo
  PR has merged; enforcement must be non-bypassable.
- **PRD R13 — always-executable merge order.** No cyclic order may ever be emitted.
- **PRD R8 — consume-before-merge.** The PLAN is consumed before the coordination PR merges, so the
  canonical merge-order data cannot rely on the PLAN surviving to merge time.
- **PRD R15 — visibility-aware; cross-repo refs use `owner/repo:path`.**
- **PRD R17 — single source of truth across `/scope`, `/work-on`, CLI.**
- **Reuse over reinvention.** Prefer existing seams (`gh.rs`, `is_cross_repo_ref`, the
  `waits_on` DAG, `lifecycle.yml`, the `/work-on` plan orchestrator) to minimize new,
  drift-prone surface.

## Considered Options

### Decision A — Integration shape

- **Chosen: canonical reference + coordination-aware consumers.** A cross-cutting
  `references/coordination-strategy.md` defines the coordination contract (lifecycle, grouping
  rule, two-node merge-order model, done-signal). `/scope`, `/work-on`, and the `shirabe`
  CLI bind to it, carrying only bindings, never a restated copy.
- *Alternative — embed the contract in each consumer.* Rejected: three consumers would
  drift; this is exactly the failure `parent-skill-pattern.md` avoids by being shared by
  `/scope` and `/charter`.
- *Alternative — a standalone coordination tool/skill alongside the chain.* Rejected by the
  brief: coordinated mode is the generalization of `/scope` + `/work-on`, not a bolt-on; a
  separate tool re-implements their machinery.

### Decision B — Cross-repo PR-state tracking (PRD R6, R14)

- **Chosen: skill-authored body + `shirabe validate` checks.** The coordination PR body
  is authored by the skill from a template (declaration marker, artifact chain,
  `owner/repo:path#number` PR-index, fenced merge-order block) and posted/refreshed with
  `gh pr create` / `gh pr edit` — the same author-by-skill discipline every other shirabe
  artifact follows. Correctness lives in `shirabe validate`: `--coordination-body <file>`
  is the static authoring-feedback check (offline — declaration marker present, every ref
  passes F2, merge-order acyclic) and `--merge-gate` is the gh-backed live merge-last gate
  (F4). Both reuse the existing `gh api` client (`crates/shirabe-validate/src/gh.rs`) and
  the `owner/repo:path` parser (`coordination.rs::parse_cross_repo_ref`).
- *Alternative — a `shirabe coordination create/status/sync` subcommand that renders the
  body (an earlier iteration of this design; see Revision below).* Rejected on a second
  pass: rendering an artifact body is authoring, and shirabe authors every other artifact
  in a skill, not a CLI subcommand. A renderer subcommand was the only place in the CLI
  that produced an artifact body — an inconsistency. The deterministic parts (ref
  validation, acyclicity) belong in `shirabe validate` as checks; the body belongs in the
  skill.
- *Alternative — on-demand polling embedded in skill prose with ad-hoc inline `gh`
  parsing.* Rejected for the *validation* logic: `owner/repo:path` parsing and acyclicity
  as shell/markdown is untestable and drift-prone — that class of logic lives in the Rust
  validator (`--coordination-body`). Authoring the body text from a template, however, is
  exactly what the skill should own.
- *Alternative — webhook / GitHub Actions push from each repo.* Rejected: standing
  per-repo infrastructure, cross-repo write-auth, a visibility-boundary risk, and it can't
  attach to forward-declared PRs that don't exist yet. Violates R19.

> **Revision.** An earlier iteration of this design introduced a pull-model `shirabe
> coordination` subcommand with `create`/`status`/`sync` verbs that *rendered* the
> coordination PR body. It was removed for consistency with shirabe's author-by-skill /
> check-by-validate pattern: rendering a body is authoring (a skill job), and the body is
> now authored from the template in `references/coordination-strategy.md` and checked by
> `shirabe validate` (`--coordination-body` static, `--merge-gate` live). No coordination
> subcommand exists.

### Decision C — Cross-repo finalize / consume cascade (PRD R8, R21)

- **Chosen: repo-local writes + read-only cross-repo verification gate.** Each repo
  finalizes its own artifacts in its own PR; the coordination PR consumes only its own PLAN (R8,
  unchanged). The cross-repo boundary becomes a read-only gate — "all upstreams terminal,
  all per-repo PRs merged" — that blocks the coordination PR from merging (R21). The Rust change
  is small: the `finalize.rs` `Stop` wall persists for *writes*, a new `gh`-backed read
  pass is added alongside it, and `run-cascade.sh`'s `check_issue_closed` single-`origin`
  assumption is relaxed.
- *Alternative — full cross-repo write walk (finalize resolves and writes sibling repos).*
  Rejected: the only option needing push access to sibling repos and the only one that can
  leave cross-repo partial state (violates R21), for the largest change to the shared
  binary — to provide an atomicity plain PRs cannot.

### Decision D — Coordination PR + merge-order representation (PRD R12, R13)

- **Chosen: phase-split canon.** The merge order is a two-node DAG (PR nodes + non-PR gate
  nodes) derived and validated at authoring time inside the PLAN, by `/plan` collapsing its
  existing issue-level `waits_on` graph into a `(repo, pr_group)`-level graph. The
  post-contraction acyclicity check (R13) and the split-at-seam → re-sequence → stack
  resolution live at that collapse step, so an unschedulable coordinated effort is never committed.
  Because R8 deletes the PLAN before the coordination PR merges, the coordination PR body carries the
  merge-time canonical PR-index + fenced merge-order block, authored by the skill from the PLAN at
  creation and surviving it through merge.
- *Alternative — canonical only in the PR body.* Rejected: loses authoring-time
  validatability and the rich `waits_on`-derived representation; the body becomes
  hand-maintained prose.
- *Alternative — canonical only in the PLAN.* Rejected: R8 consumes the PLAN before merge,
  so the canonical merge-order data would vanish exactly when the merge-last gate needs it.

### Decision E — Decomposition / per-repo grouping (PRD R10, R11)

- **Chosen: tag-and-collapse in `/plan`.** `/plan` tags each issue with `repo` and a
  `pr_group` key, then collapses the issue DAG to a `(repo, pr_group)`-level PR DAG
  (Decision D's contraction). Default grouping is one PR per repo (coarsest legal); a repo
  splits only on a recorded trigger (independently mergeable, independently rollback-able,
  exceeds the configured reviewability ceiling, or to break a contraction cycle). Reuses
  `plan-to-tasks.sh`'s existing per-issue-attribute-to-derived-edge precedent.
- *Alternative — a separate post-`/plan` grouping layer.* Rejected: duplicates the DAG
  machinery `/plan` already owns and splits sequencing ownership across two steps.

### Decision F — Intent and preference surface (PRD R1, R2, R18)

- **Chosen: the existing `flag > CLAUDE.md-header > default` stack.** Coordination intent is a
  per-invocation flag on `/scope` and `/work-on` plus a workspace default header. The
  PR-grouping policy and the reviewability ceiling are durable workspace preferences;
  coordination-PR creation, artifact persistence, sequencing, and merge-order tracking are smart
  defaults that announce on activation and accept a per-invocation override.
- *Alternative — all per-invocation flags.* Rejected: defeats the "express once" goal.
- *Alternative — all workspace preferences.* Rejected: forces configuration before first
  use and can't carry per-effort intent.

### Decision G — PLAN execution_mode for coordinated efforts

- **Chosen: a third `execution_mode` value — `coordinated`** (`single-pr | multi-pr |
  coordinated`). A coordinated PLAN is always multi-PR but adds what `multi-pr` lacks: a
  coordination PR that merges last, cross-repo per-repo grouping, and the two-node
  merge-order DAG with gates. `/plan`, `/work-on`, the validator (an FC14-style branch),
  and the CLI all branch on this one field; a `coordinated`-mode PLAN carries the
  Implementation Issues table plus the two-node Dependency Graph and names its coordination
  PR.
- *Alternative — an orthogonal `coordinated: true` flag over `multi-pr`.* Rejected: splits the
  coordinated effort's identity across two fields and permits invalid combinations (`single-pr` +
  coordinated); a single enum has no invalid state and gives the validator one branch.
- *Alternative — no schema change (intent-driven behavior only).* Rejected: the PLAN could
  not declare or validate its own coordinated shape — the exact gap that surfaced while
  planning this very effort, where a coordinated PLAN fit neither `single-pr` nor `multi-pr`.
- *Bootstrapping note:* `coordinated` mode does not exist until this effort builds it, so this
  effort's own PLAN runs in `single-pr` mode — all issues land in the one coordination PR
  (PR #196), which is created up front and merged-last by hand.

## Decision Outcome

The coordination PR is a docs-only PR on its own branch, created up front by `/scope`
(or `/work-on`) when coordination intent is present, holding the PLAN and the durable
BRIEF/PRD/DESIGN. Implementation lands as per-repo PRs grouped by `/plan` to the coarsest
legal unit, with a two-node merge-order DAG validated acyclic at authoring time and authored
into the coordination PR body. The skill authors the body from the contract's template and
posts/refreshes it with `gh`; `shirabe validate --coordination-body` checks the authored body
offline and `shirabe validate --merge-gate` is the posture-aware live merge-last gate that
`lifecycle.yml` runs under `--mode=ready` as the non-bypassable backstop; finalize stays
repo-local with a read-only cross-repo verification gate. The whole contract is defined once in
`references/coordination-strategy.md` and bound by the two consumers.

This holds together because every piece is pull-based and repo-local: no component writes
across a repo boundary, nothing runs always-on, and the only genuinely new compiled logic is
two `shirabe validate` modes (`--coordination-body`, `--merge-gate`) plus a `/plan` collapse
step. State lives on the coordination branch/PR itself (R9), so an interrupted effort is
re-discoverable without a session store.

### State home and discovery (PRD R9)

"A coordinated effort is active" is encoded by the coordination PR/branch itself (a `docs(...)` PR
carrying the declaration marker and the index/order block). The skill re-derives the live picture
by reading the PR body + querying indexed PRs on each pass and re-authoring the body; no `wip/`
session file is the source of truth, so context resets reconnect from durable state.

### Abandonment and failure (PRD R20, R21)

Abandonment closes the coordination PR without merging and force-materializes/marks the in-flight
planning artifacts as Draft (mirroring `/scope`'s `abandonment-forced` exit), never silently
orphaning them. Any coordination step that cannot complete (index update, finalize, gate
recompute) surfaces the error and halts; the `lifecycle.yml` gate keeps the coordination PR unmerged
while finalization is incomplete, so no partial cross-repo state can land.

### Visibility and atomicity (PRD R15, R16)

Cross-repo references use `owner/repo:path`. The load-bearing visibility rule is the
**Coordination-PR Visibility Rule** (canon: `references/coordination-strategy.md`): a
coordination PR lives at the most-restrictive visibility of any repo the effort touches.
A public-only effort gets a public coordination PR; an effort touching any private repo
requires a private coordination PR. This follows from the workspace's directional rule
(`references/cross-repo-references.md`): Public → Private references are forbidden, and the
coordination PR holds the PLAN, which names each indexed repo in plaintext — so a public
coordination PR coordinating a private repo would both make a forbidden reference and name the
private repo regardless of redaction. A public coordination PR therefore never coordinates a
private repo; the front-door check (a public coordination PR refuses to index a private node,
fail-closed) enforces this, and F1 redaction is the fail-closed backstop for residual edges
(see the F1 finding below). A cross-repo atomicity requirement is detected at planning time
(a dependency that would require two repos to merge simultaneously) and refused with guidance
to reshape into a compatible-intermediate sequence — the system never emits a plan that assumes
atomic cross-repo merge.

### Decomposition edge rules (R13, R16, R22)

- **Non-PR gate satisfaction.** A gate node (e.g. a package publish) carries a named,
  verifiable condition (a published version reachable via `gh`/registry read). At
  gate-recompute time, a gate is satisfied only when its condition verifies live; an
  unsatisfiable or unverifiable gate fails closed and blocks the PRs ordered after it.
  Default enforcement is hard; whether a given gate can be a hard CI block depends on the
  repo's CI/branch protection (a Known Limitation carried from the PRD).
- **R16 (refuse) vs R13 (auto-resolve) discriminator.** Both surface as a contraction
  cycle. The discriminator is whether a *legal acyclic ordering exists after splitting*:
  if splitting a repo at the seam (or re-sequencing/stacking) yields an acyclic order, it
  is an R13 case and the collapse step resolves it; if no acyclic ordering exists because
  two repos genuinely must change simultaneously (no compatible-intermediate split), it is
  an R16 atomicity case and the step refuses with reshaping guidance.
- **R22 re-derivation with merged nodes.** An already-merged per-repo PR is a fixed,
  satisfied predecessor; re-derivation orders only the unmerged remainder and may not add
  an edge that would require re-merging a merged node. A new PLAN dependency pointing *into*
  a merged node is treated as already-satisfied; a new dependency that would require a
  merged node to come *after* unmerged work is rejected as inconsistent with landed history.

## Solution Architecture

Components:

- **`references/coordination-strategy.md`** — the canonical contract: lifecycle (create up front
  → track → finalize → merge last), the coarsest-legal-grouping rule, the two-node
  merge-order DAG model, the done-signal, the body template, and the `owner/repo:path`
  reference rules. Bound by `/scope` and `/work-on`; no consumer restates it.
- **Skill-authored coordination PR body** — `/scope` and `/work-on` author the body from the
  template in `references/coordination-strategy.md` (declaration marker, artifact chain,
  `owner/repo:path#number` PR-index, fenced merge-order block) and post/refresh it with `gh pr
  create` / `gh pr edit`. There is no `shirabe coordination` subcommand: rendering a body is
  authoring, which belongs in a skill, as with every other shirabe artifact.
- **`shirabe validate --coordination-body <file>`** — the static authoring-feedback check (in the
  existing CLI crate), the static analog of `shirabe validate <brief-file>`. Reads an authored body
  and checks it **offline** (no `gh`): the declaration marker is present, every `owner/repo:path#number`
  cross-repo ref parses and passes F2, and the fenced merge-order block is acyclic. Reports findings
  in the existing `annotation`/`human`/`json` shapes and exits non-zero on any violation. The
  visibility rule and live merge state stay in `--merge-gate` (they need `gh`).
- **`shirabe validate --merge-gate`** — the merge-last gate (F4 / R14), a posture-aware `validate`
  mode like every other merge-gating check. Recompute "all indexed PRs merged + all upstreams
  terminal" from authoritative live `gh api` queries at gate time, never by parsing the editable PR
  body; fails closed on any unresolvable PR/upstream. Validates each `owner/repo:path` component
  before use (F2); resolves each repo's visibility and redacts private identifiers to opaque node ids
  in diagnostics (F1, the fail-closed backstop — a public coordination PR over a private indexed repo
  is refused). Under `--mode=ready` a blocked gate is an error (the merge-last backstop); under
  `--mode=draft` it is a notice (exit 0). The upstream-terminal read pass is part of this mode.
  Drives the `lifecycle.yml` non-bypassable backstop.
- **`/plan` collapse step** — tags issues with `repo` + `pr_group`, contracts the `waits_on`
  issue DAG to a `(repo, pr_group)` PR DAG, runs the acyclicity check (R13) and the
  split→re-sequence→stack resolution, and emits the two-node order into the PLAN. A
  `plan-to-tasks.sh` sibling serializes it.
- **`finalize.rs` extension** — keep the `Stop`-on-cross-repo wall for writes; add a `gh`-backed
  read pass that verifies cross-repo upstreams are terminal. Separately, relax
  `run-cascade.sh`'s `check_issue_closed` single-`origin` assumption.
- **`lifecycle.yml` merge-last step** — on a coordination PR, run `shirabe validate --merge-gate
  --mode=ready`, failing the "ready" check while any indexed PR is unmerged or finalization is
  incomplete (the merge-last backstop).
- **`/scope` + `/work-on` bindings** — detect coordination intent (flag/header/default), author
  the coordination PR body up front from the template and post it with `gh pr create`, re-author and
  `gh pr edit` it as per-repo PRs progress, run `shirabe validate --coordination-body` for authoring
  feedback, and announce smart-default activations (R18).

Data flow: `/scope` (coordination intent) → skill authors the PR body from the PLAN's two-node
order and posts it (`gh pr create`), checked by `shirabe validate --coordination-body` → per-repo
work via `/work-on` opens per-repo PRs → skill re-authors the index from `gh` and refreshes the body
(`gh pr edit`) → each repo's PR finalizes its own artifacts → all merged → `shirabe validate
--merge-gate` (ready posture), the read-only merge-last gate, passes → coordination PR consumes its
PLAN and merges last.

## Implementation Approach

A walking skeleton first, then the cross-repo machinery (sequenced by `/plan`):

1. **Contract reference** — author `references/coordination-strategy.md`, including the F1
   (fail-closed private-identifier redaction), F2 (`owner/repo:path` component validation),
   and F4 (gate recomputes from live `gh`, not PR body) hard rules (cheap; unblocks the rest).
2. **`/plan` collapse + two-node order** — `repo`/`pr_group` tagging, DAG contraction,
   acyclicity check + resolution, serialized order. (Most of R10–R13.)
3. **Coordination PR body template** — add the copy-pasteable body template to
   `references/coordination-strategy.md` (declaration marker, artifact chain, PR-index, fenced
   merge-order block) that the skill authors from.
4. **`shirabe validate --coordination-body`** — the static authoring-feedback check (declaration
   marker, F2 on every ref, merge-order acyclicity), the static analog of `shirabe validate
   <brief-file>`.
5. **`shirabe validate --merge-gate` + `finalize.rs` read pass + `lifecycle.yml`** — the merge-last
   backstop and repo-local cascade verification.
6. **`/scope` + `/work-on` bindings** — intent surface, announce/override, author-and-post the body
   with `gh`, run `--coordination-body` for feedback.
7. **Abandonment + failure paths** — force-materialize on bail; halt-on-failure.

## Security Considerations

The architecture is pull-based and repo-local — no cross-repo write path and no always-on
service — which removes the highest-severity classes up front. The remaining surface is the
`gh`-backed read pass, the rendering of cross-repo metadata into a **public** coordination PR
body, and the `lifecycle.yml` merge-last gate. Three findings are load-bearing and are
hard rules in `references/coordination-strategy.md` (below); the rest are standard hardening.

### Threat surface

- **Cross-repo read pass** (the skill's `gh` reads when authoring the body, `shirabe validate
  --merge-gate`, the `finalize.rs` read pass): reads each indexed PR / upstream on the operator's
  own `gh` credentials across
  public and private repos — data from *other* repos now flows into a rendered artifact and
  a CI gate.
- **Public coordination PR body:** the rendered PR-index + merge-order block. The
  Coordination-PR Visibility Rule keeps this from being a cross-visibility egress point —
  a public coordination PR only coordinates public repos (front-door refusal), with F1
  redaction as the fail-closed backstop for residual edges (R15).
- **Untrusted `owner/repo:path` and PR metadata** interpolated into markdown, `gh` argument
  positions, and gate logic.
- **`/plan` collapse step:** new `repo`/`pr_group` tags become node identity and feed the
  acyclicity logic.
- **`shirabe validate --merge-gate` (run by `lifecycle.yml` under `--mode=ready`):** the
  merge-last backstop reads influenceable data to decide "ready."

Inherited controls that must not regress: `gh.rs` uses `Command`/`.args()` (no shell
string), validates owner/repo against `^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$`, caps output at
4 MiB, and never holds the token; `finalize.rs` confines paths lexically and rejects
symlinks; `run-cascade.sh` quotes paths and validates issue URLs; `plan-to-tasks.sh`
validates task names against `^[a-z][a-z0-9-]*$` and builds JSON with `jq --arg`.

### Findings and mitigations

- **F1 — Private content leak through a public coordination PR body (High, R15) — fail-closed
  backstop.** Front-door enforcement is the **Coordination-PR Visibility Rule** (canon:
  `references/coordination-strategy.md`): a public coordination PR refuses to index a private
  repo, because Public → Private references are forbidden and the PLAN would name the private
  repo regardless. So a public coordination PR never coordinates a private one in the first
  place. F1 is **not** the cross-visibility egress mechanism — it is the fail-closed backstop
  for the residual edges the front-door rule cannot pre-empt (a repo flips visibility
  mid-effort, a moved/renamed/unresolvable ref). For those, a private repo's name, path,
  branch, PR title, and number are themselves private: the skill must not author a private
  ref into a public body, and `shirabe validate --merge-gate` enforces it — it resolves each
  indexed PR's repo visibility and, for any private repo, routes diagnostics through an opaque
  node id + merge state only (no private owner/repo/path/branch/title/number) and refuses a
  public coordination PR over a private indexed repo. Fail closed: if visibility can't be
  resolved, treat as private. Covered by unit tests on the front-door decision (public PR +
  private node → refuse; private PR + mixed → allow; unresolvable → refuse) and by the F1
  redaction tests feeding a private-repo node into a diagnostic label.
- **F2 — Path traversal / injection via crafted `owner/repo:path` (High).** Both validate
  modes (`--coordination-body` statically, `--merge-gate` live) MUST parse the reference into
  components and validate each before use: owner/repo against the existing GitHub charset
  regex; path against in-root, no-symlink, lexical confinement (reject newline/NUL). Reuse the
  existing validators; a failing reference halts with a diagnostic (R21), never silently skipped.
- **F3 — Markdown/metadata injection from PR titles and branch names (Medium).** Treat all
  `gh`-sourced strings as untrusted when the skill authors them into the body: escape/strip
  markdown/HTML control chars; the
  authoritative fields of the fenced merge-order block derive from validated PLAN/`gh`
  state, never from free-text titles (which are escaped, non-load-bearing annotations).
- **F4 — Merge-last gate must not trust PR-body text (High, R7/R14/R21).** The
  `shirabe validate --merge-gate` mode MUST recompute merge state from authoritative `gh api`
  queries at gate time, never by parsing the editable PR body. The body may supply the *list*
  of indexed PRs (the durable index), but each PR's merged/open status and the order's
  acyclicity are verified live. Fail closed: any PR it cannot resolve is treated as not-merged.
  The mode is posture-aware (enforce under `--mode=ready`, notice under `--mode=draft`); CI
  pins it to the `draft == false` trigger and passes `--mode=ready` so it cannot
  be skipped.
- **F5 — Privilege scope / token exposure (Medium).** The validate modes' `gh` use is
  read-only; no coordination step writes cross-repo (the skill's `gh pr` calls write only the
  coordination PR's own body in its own repo). Inherit `gh.rs`'s no-token-in-process property;
  do not log raw `gh` responses; route private identifiers through F1 redaction before any
  diagnostic, log, or body; apply the 4 MiB cap to the read pass.
- **F6 — `repo`/`pr_group` tags re-validated on every read (Medium).** Constrain `pr_group`
  to `^[a-z][a-z0-9-]*$` and the repo tag to the owner/repo regex before interpolation.
  Because the coordination PR re-derives state from the editable PR body on resume (R9, R22),
  re-validate these on every read, not only at authoring time (matching the
  re-validation-on-resume rule); build serialized JSON with `jq --arg`.
- **F7 — Acyclicity / scheduling integrity (Low, integrity).** Treat the acyclicity check
  as a correctness gate with explicit test coverage for contraction-induced cycles and
  self-loops; refuse to emit on any unresolved cycle; verify R22 re-derivation (merged PRs
  as fixed nodes) cannot reintroduce a cycle among the unmerged remainder.

### Residual risks

- **Staleness window** between body refreshes: the authored body can misstate merge state, but
  F4 makes the gate recompute live at merge time, so a stale body misleads a human reader
  but cannot cause a wrong merge.
- **Operator-credential blast radius:** the read pass is only as confined as the operator's
  `gh` token; a compromised workstation is out of scope. Read-only use reduces exposure.
- **Human edits to the durable index:** bounded by F4 live recompute and F1 redaction; a
  non-load-bearing annotation could still mislead a reviewer. Accepted given gate independence.
- **Moved cross-repo references** degrade to a fail-closed gate (blocks merge) — the safe
  direction.

### Verdict

No blocking security issues, conditional on F1, F2, and F4 being adopted as explicit,
testable rules in `references/coordination-strategy.md` (they are load-bearing for R15 and
R7/R14/R21). The architecture supports all three with existing seams, so they are hardening
requirements, not architectural blockers.

## Consequences

Positive:

- No new always-on service, no cross-repo write access, no partial-state failure mode — the
  architecture is pull-based and repo-local throughout.
- Reuses proven seams (`gh.rs`, `is_cross_repo_ref`, `waits_on`, `lifecycle.yml`), so the new,
  drift-prone compiled surface is two `shirabe validate` modes plus a `/plan` collapse step;
  the body is authored by the skill, like every other shirabe artifact.
- A single canonical contract prevents the consumers from drifting.
- The merge-last gate is enforced by CI, not discipline.

Negative / mitigations:

- Cross-repo PR state is only as fresh as the last body refresh; mitigation: `/work-on`
  re-authors the body each pass and the CI gate re-checks at merge time, so staleness can't
  cause a wrong merge.
- The phase-split canon (PLAN authoring-time, PR body merge-time) means two representations;
  mitigation: the skill authors the PR body *from* the PLAN against a fixed template, so there
  is one source at each phase.
- Already-merged per-repo PRs constrain mid-effort re-derivation (R22) and abandonment (R20);
  mitigation: re-derivation treats merged PRs as fixed nodes and only re-orders the unmerged
  remainder; abandonment leaves merged work in place and documents the partial state.
