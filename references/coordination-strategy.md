# Coordination Strategy: The Coordinated Multi-Repo Contract

This document is the canonical contract for **coordinated** execution — the
multi-repo generalization of shirabe's single-repo tactical chain. It defines
the lifecycle, the per-repo grouping rule, the merge-order model, the
done-signal, and the load-bearing security rules (F1, F2, F4). `/scope`,
`/work-on`, and the `shirabe coordination` subcommand all bind to this contract
and carry only bindings — no consumer restates it. This is the same
single-source discipline `parent-skill-pattern.md` enforces across `/scope` and
`/charter`.

The companion references fill in the details this document points at:

- [`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`](cross-repo-references.md) —
  the `owner/repo:path` reference syntax and the visibility-direction rules the
  coordination index must respect.
- [`${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md`](dependency-diagram.md) —
  the dependency-graph rendering conventions the merge-order block follows.

## The Coordinated Mode

A **coordinated effort** spans more than one repository. A single
**coordination PR** — a docs-only PR on its own branch — holds the durable
planning chain (BRIEF/PRD/DESIGN) and the PLAN, and is the durable home for the
coordination state (the PR-index and the merge-order block). Per-repo
implementation lands as separate PRs. The coordination PR merges **last**, and
that merge is the effort's done-signal.

Coordinated mode is the third `execution_mode` value (`single-pr | multi-pr |
coordinated`). It is always multi-PR, and adds what `multi-pr` lacks: a
coordination PR that merges last, cross-repo per-repo grouping, and a two-node
merge-order DAG with gates.

## Lifecycle

The coordinated lifecycle has four phases, in order:

1. **Create up front.** When coordination intent is present, the coordination
   PR/branch is created at the start — before any implementation work — and its
   body is seeded from the PLAN: a declaration (this is a coordination PR), the
   artifact chain, the PR-index, and a fenced merge-order block. The body is
   *rendered from* the PLAN, never hand-authored.
2. **Track.** As per-repo PRs open and progress, `shirabe coordination
   status`/`sync` reads each indexed PR on the operator's own `gh` credentials,
   rewrites the PR-index, and recomputes the merge-order and the merge-last
   gate. State lives on the coordination branch/PR itself, so an interrupted
   effort reconnects from durable state — no session file is the source of
   truth.
3. **Finalize.** Each repo finalizes its own artifacts in its own PR (writes
   stay repo-local). The cross-repo boundary is a **read-only verification
   gate**: "all upstreams terminal, all per-repo PRs merged." No coordination
   step writes across a repo boundary.
4. **Merge last.** Once every indexed PR has merged and finalization is
   complete, the read-only gate passes, the coordination PR consumes its own
   PLAN, and merges. That merge is the done-signal. A non-bypassable CI check
   (`shirabe validate --merge-gate`, run by `lifecycle.yml` under `--mode=ready`)
   is the backstop that keeps the coordination PR unmerged while any indexed PR
   is open or finalization is incomplete.

## Coarsest-Legal-Grouping Rule

Per-repo implementation is grouped to the **coarsest legal unit**: by default,
**one PR per repository**. A repo splits into more than one PR only on a
recorded trigger:

- the slices are independently mergeable, or
- the slices are independently rollback-able, or
- a single PR would exceed the configured reviewability ceiling, or
- a split is required to break a contraction cycle in the merge-order DAG.

Absent a recorded trigger, do not split: the coarsest grouping minimizes the
number of merge-order nodes and the cross-repo coordination surface.

## Merge-Order Model: A Two-Node DAG

The merge order is a directed acyclic graph with **two kinds of node**:

- **PR nodes** — one per `(repo, pr_group)` unit. A PR node is satisfied when
  its PR has merged.
- **Non-PR gate nodes** — a named, verifiable condition that is not itself a PR
  (for example, a package publish). A gate node is satisfied only when its
  condition verifies **live** at gate-recompute time (a published version
  reachable via `gh`/registry read). An unsatisfiable or unverifiable gate
  fails closed and blocks every node ordered after it.

Edges express "must merge / be satisfied before." The graph is derived and
validated **acyclic at authoring time** inside the PLAN (`/plan` collapses its
issue-level `waits_on` graph into this `(repo, pr_group)`-level graph). An
unschedulable coordinated effort is never committed. Because the PLAN is
consumed before the coordination PR merges, the validated two-node order is
**rendered into the coordination PR body** as a fenced merge-order block, where
it survives the PLAN through merge as the merge-time canon.

### Re-derivation with merged nodes

An already-merged per-repo PR is a fixed, satisfied predecessor. Re-derivation
orders only the unmerged remainder and may not add an edge that would require
re-merging a merged node. A new dependency pointing *into* a merged node is
treated as already-satisfied; a new dependency that would require a merged node
to come *after* unmerged work is rejected as inconsistent with landed history.

### Atomicity is refused, not planned

A cross-repo atomicity requirement — two repos that would have to merge
simultaneously with no compatible-intermediate split — is detected at planning
time and **refused** with guidance to reshape into a compatible-intermediate
sequence. The system never emits a plan that assumes atomic cross-repo merge.

## The Done-Signal

The single done-signal of a coordinated effort is **the coordination PR
merging**. It cannot merge until every indexed per-repo PR has merged and
finalization is complete; `shirabe validate --merge-gate` (run by `lifecycle.yml`
under `--mode=ready`) enforces this and is non-bypassable. There is no separate
"effort complete" marker — the
merged coordination PR is it.

## Coordination-PR Visibility Rule

**A coordination PR lives at the most-restrictive visibility of any repo the
effort touches.** A public-only effort gets a public coordination PR; an effort
that touches any private repo requires a **private** coordination PR. This is
the front-door rule; F1 (below) is its fail-closed backstop, not the mechanism
that makes cross-visibility coordination safe.

The rule follows directly from the workspace's directional visibility rule in
[`cross-repo-references.md`](cross-repo-references.md) (the "Visibility rule"
table): **a public artifact must not reference a private repo's artifact**
(Public → Private is forbidden; Private → Public is allowed). Two independent
consequences make a public coordination PR coordinating a private repo
incoherent, not merely risky:

1. The coordination PR is a public artifact that *references* the private
   repo's PR (it indexes it). That is a Public → Private reference, which the
   directional rule forbids outright.
2. The coordination PR holds the PLAN (R5/R8), and the PLAN describes the
   per-repo work by tagging each issue with its `repo`. A public coordination
   PR coordinating a private repo would therefore **name that private repo in
   plaintext in the PLAN**, regardless of any render-layer redaction — making
   redaction theater rather than protection.

Because Private → Public references *are* allowed, a private coordination PR
can legally describe and index everything — public and private repos alike. The
direction only fails one way, so the most-restrictive-visibility rule resolves
it cleanly: any private repo in the effort pulls the coordination PR to private.

**Consequence (enforced at the front door):** a public coordination PR MUST NOT
index or reference a private repo. When a coordination verb is rendering,
creating, or syncing a coordination PR whose own repo is public and any indexed
(or to-be-indexed) repo resolves as private — including the fail-closed
unresolvable case (treated as private) — the verb **refuses fail-closed** with a
diagnostic naming the violation. Every identifier in that diagnostic is routed
through the F1 redaction so the refusal itself does not leak. A public
coordination PR therefore only ever coordinates public repos.

## Hard Rules (Load-Bearing Security)

The following three rules are load-bearing for visibility (R15) and the
merge-last gate (R7/R14/R21). They are requirements, not guidance: every
consumer that renders, validates, or gates MUST satisfy them.

### F1 — Fail-closed private-identifier redaction (defense-in-depth backstop)

Front-door enforcement of visibility is the **Coordination-PR Visibility Rule**
above: a public coordination PR refuses to index a private repo, so a public
coordination PR never coordinates a private one. F1 is **not** the mechanism
that enables cross-visibility coordination — that is forbidden. F1 is the
**fail-closed backstop** for the residual edges the front-door rule cannot
pre-empt: a repo flips visibility mid-effort, a moved/renamed reference, or a
reference whose visibility is unresolvable. In each of those cases the
redaction still happens; it is the second line of defense, not the first.

A private repo's **name, path, branch, PR title, and number are themselves
private**. The render path MUST resolve each indexed PR's repo visibility and,
for any private repo, render a redacted placeholder carrying **only an opaque
node id and merge state** — never the private owner, repo, path, branch, title,
or number.

**Fail closed:** if a repo's visibility cannot be resolved, treat it as
private. Private identifiers MUST be routed through this redaction before they
reach any rendered body, diagnostic, or log. So even where the front-door rule
would already have refused (e.g. an edge it could not see), no private content
leaks: the redaction is the backstop that holds.

### F2 — `owner/repo:path` component validation

Every cross-repo `owner/repo:path` reference MUST be parsed into components and
each component validated **before use**:

- `owner` and `repo` against the GitHub charset regex
  (`^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$`);
- the `path` against in-root, no-symlink, lexical confinement: reject absolute
  paths, `..` traversal segments, and any newline or NUL byte.

Reuse the existing validators. A reference that fails validation **halts with a
diagnostic** (R21) — it is never silently skipped. This blocks path-traversal
and injection via a crafted reference.

### F4 — The merge-last gate recomputes from live `gh`, never PR-body text

The merge-last gate is the `shirabe validate --merge-gate` mode — a
posture-aware validate mode like every other merge-gating check, not a separate
subcommand. It MUST recompute merge state from authoritative `gh api` queries
**at gate time**, never by parsing the editable PR body. The body may supply the
*list* of indexed PRs (the durable index), but each PR's merged/open status and
the order's acyclicity are verified **live**.

**Posture-aware:** the mode honors the same `--mode=draft|ready` posture every
other validate check uses. Under `--mode=ready` a blocked gate is an error (the
merge-last backstop). Under `--mode=draft` (the default) a blocked gate is a
**notice** that exits 0 — a coordination PR legitimately has unmerged indexed
PRs mid-effort, symmetric with how the draft-tolerable lifecycle codes resolve
under draft. The upstream-terminal verification that the gate folds in (a
cross-repo upstream is at a terminal status) is part of the same mode; both the
gate and the upstream-terminal check are validate modes, not coordination verbs.

**Fail closed:** any PR the gate cannot resolve is treated as not-merged. The
gate is pinned to the `draft == false` trigger (CI passes
`--mode=ready` there) so it cannot be skipped by toggling draft. A stale
rendered body can mislead a human reader but cannot cause a wrong merge, because
the gate never trusts it.

## Inherited Controls (must not regress)

- All coordination `gh` use is **read-only**; no coordination verb writes
  across a repo boundary.
- `gh` arguments are passed as an argv array (`Command::arg`), never through a
  shell; the validator process never holds the token bytes.
- `gh`-sourced strings (PR titles, branch names) are treated as untrusted on
  render: escape/strip markdown/HTML control characters (F3). The authoritative
  fields of the merge-order block derive from validated PLAN/`gh` state, never
  from free-text titles.
- `repo`/`pr_group` tags are re-validated on **every read** (not only at
  authoring time), because the coordination PR re-derives state from the
  editable body on resume; `pr_group` is constrained to `^[a-z][a-z0-9-]*$` and
  the repo tag to the owner/repo regex before interpolation.
