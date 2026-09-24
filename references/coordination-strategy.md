# Coordination Strategy: The Coordinated Contract

This document is the canonical contract for **coordinated** execution: a split
PLAN whose PRs land in one or more repositories and are tied together by a
coordination PR that merges last. It defines how the mode is resolved, the
lifecycle, the grouping rule, branches, the merge-order model, the merge step
and its pause, the done-signal, and the load-bearing security rules (F1, F2,
F4). `/plan`, `/scope`, `/execute`, and `/work-on` bind to this contract and
carry only bindings — no consumer restates it. This is the same single-source
discipline `parent-skill-pattern.md` enforces across `/scope` and `/charter`.

The coordination PR body is **authored by the skill** from the template below,
the same author-by-skill discipline every other shirabe artifact follows; there
is no `shirabe coordination` create/render subcommand. `shirabe validate` checks
the authored body: `--coordination-body <file>` is the static authoring-feedback
check (offline), and `--merge-gate` is the live merge-last gate.

The companion references fill in the details this document points at:

- [`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`](cross-repo-references.md) —
  the `owner/repo:path` reference syntax and the visibility-direction rules the
  coordination index must respect.
- [`${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md`](dependency-diagram.md) —
  the dependency-graph rendering conventions the merge-order block follows.

## The Coordinated Mode

A **coordinated effort** spans one or more repositories. Its PRs may all sit in
one repository, one per split unit, or spread across several; the contract is
the same either way. A single **coordination PR** — a docs-only PR on its own
branch — holds the durable planning chain (BRIEF/PRD/DESIGN) and the PLAN, and
is the durable home for the coordination state (the PR-index and the
merge-order block). Implementation lands as separate PRs, one per PR node (a
`(repo, pr_group)` unit). The coordination PR merges **last**, and that merge
is the effort's done-signal.

Because it is gated on every indexed PR merging first, the coordination PR
**stays draft until every indexed PR has merged** — draft is its correct resting
state throughout review, not an oversight. This is the standing exception to the
[DRAFT-vs-READY discipline](../docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md):
the implementation PRs each flip to ready-for-review at their own review
handoff once their work is verified, while the coordination PR alone stays
draft. Once every indexed PR has merged, `/execute` marks the coordination PR
ready, and it merges last.

Coordinated mode is the third `execution_mode` value (`single-pr | multi-pr |
coordinated`). It is always multi-PR, and adds what `multi-pr` lacks: a
coordination PR that merges last, grouping by `(repo, pr_group)` node, and a
two-node merge-order DAG with gates.

## Mode Resolution

A PLAN's mode is settled in two questions, in order. The first is whether the
work splits at all (recorded in the PLAN's `split_branch` and
`split_rationale`). That question never reads the coordination flags, the
intent, or the headers below, so none of them can change whether the work
splits. **An unsplit PLAN is `single-pr` regardless of flags or intent.**

Only when the work splits does the second question pick between `coordinated`
and `multi-pr`. The first level that gives an answer wins:

1. **An explicit flag.** `--coordinated` gives `coordinated`;
   `--no-coordinated` gives `multi-pr`.
2. **Intent.** `--intent=continue` gives `coordinated`; `--intent=stop` gives
   `multi-pr`. No intent (`none`) gives no answer at this level.
3. **A coordinated-by-default header** in the repository's `CLAUDE.md`, from
   the closed list below, gives `coordinated`.
4. **The default**, `multi-pr`.

The PLAN records which level decided as `split_mode_source`, next to the mode:

| `split_mode_source` | Meaning | Mode it accompanies |
|---|---|---|
| `none` | The work didn't split. | `single-pr` |
| `flag` | Level 1 decided. | `coordinated` or `multi-pr` |
| `intent` | Level 2 decided. | `coordinated` or `multi-pr` |
| `header` | Level 3 decided. | `coordinated` |
| `default` | No level above gave an answer. | `multi-pr` |

`none` is recorded only when the work doesn't split, and the mode is then
`single-pr`; `flag`, `intent`, `header`, and `default` appear only on a split.
`/plan` computes both values with `skills/plan/scripts/resolve-split-mode.sh`
rather than by judgment, and `/scope` re-runs the same script to check what its
`/plan` hop produced.

### Coordinated-by-default header values

This table is the single definition of which `CLAUDE.md` header values mean
"coordinated by default". It's mirrored as a constant in
`skills/plan/scripts/resolve-split-mode.sh`; **the two must change together**,
and that script's test fails when they differ.

| Header | Values that mean coordinated by default |
|---|---|
| `## PR Grouping Policy:` | `coordinated` |
| `## Reviewability Ceiling:` | none (no value of this header turns coordinated mode on) |

Matching rules:

- The header name is matched exactly and case-sensitively as a level-2
  heading at the start of a line, and the value is the rest of that line after
  the colon. The first matching heading in the file is the one read.
- The value is trimmed of leading and trailing whitespace, then compared
  case-sensitively against the table. `Coordinated` doesn't match.
- Any other value is not a coordinated-by-default signal. That includes the
  `coarsest-legal` grouping policy and every `## Reviewability Ceiling:` value
  (`default` or a concrete ceiling). An unrecognized value isn't an error
  either: the header keeps whatever meaning it has as a grouping or size
  preference, and resolution falls through to level 4. A missing header or a
  missing `CLAUDE.md` falls through the same way.

`coordinated` is a grouping policy as well as a signal: it groups work by the
Coarsest-Legal-Grouping Rule below, exactly as `coarsest-legal` does. The
values repositories already set stay non-signals so that a repository which
sets them keeps the modes it gets today.

## Tracking Level

A coordinated PLAN follows the resolved tracking level the way `multi-pr`
does, on the `flag > CLAUDE.md ## Tracking Level: > mode default` stack, with
**`none` as coordinated's default**. At `none` the work items are outlines with
local IDs under `## Issue Outlines`, each carrying `**Repo**: <owner/repo>` and
`**Group**: <pr_group>`, and nothing is filed. Only when the tracking level asks
for issues (`issues` or `issues-and-milestone`) does `/plan` file them, each
with a `_Repo: <owner/repo> | Group: <pr_group>_` row, behind an explicit
filing approval.

## Lifecycle

The coordinated lifecycle has four phases, in order:

1. **Create up front.** When coordination intent is present, the coordination
   PR/branch is created at the start — before any implementation work — and the
   skill **authors** its body from the template below: a declaration (this is a
   coordination PR), the artifact chain, the PR-index, and a fenced merge-order
   block, all derived from the PLAN. The skill posts the body with `gh pr
   create`. `shirabe validate --coordination-body <file>` gives authoring
   feedback before the post. A `/scope` run under `--intent` is the one
   exception to "up front": the PLAN's mode isn't known until its `/plan` hop
   returns, so it opens the coordination PR when it publishes at exit.
2. **Track.** As node PRs open and progress, the skill re-authors the body
   from the same template — reading each indexed PR on the operator's own `gh`
   credentials, rewriting the PR-index, and recomputing the merge-order — and
   posts the refreshed body with `gh pr edit`. State lives on the coordination
   branch/PR itself, so an interrupted effort reconnects from durable state — no
   session file is the source of truth.
3. **Finalize.** Each repo finalizes its own artifacts in its own PR (writes
   stay repo-local). The boundary between node PRs is a **read-only
   verification gate**: "all upstreams terminal, all indexed PRs merged." No
   coordination step writes across a repo boundary.
4. **Merge last.** Once every indexed PR has merged and finalization is
   complete, the read-only gate passes, the coordination PR consumes its own
   PLAN, and merges. That merge is the done-signal. A non-bypassable CI check
   (`shirabe validate --merge-gate`, run by `lifecycle.yml` under `--mode=ready`)
   is the backstop that keeps the coordination PR unmerged while any indexed PR
   is open or finalization is incomplete.

## Coordination PR Body Template

The skill authors the coordination PR body from this template (it is not
rendered by a CLI subcommand). Fill the bracketed slots from the PLAN and from
live `gh` reads, keep the literal declaration marker line **verbatim** (the
merge-last gate detects a coordination PR by grepping for it), and post with `gh
pr create` / refresh with `gh pr edit`:

````markdown
# Coordination PR: <effort-slug>

> This is a **coordination PR** for a coordinated effort. It is docs-only and
> merges **last**, once every indexed PR has merged and finalization is
> complete. See `references/coordination-strategy.md`.

## Artifact Chain

- <path/to/BRIEF>
- <path/to/PRD>
- <path/to/DESIGN>
- <path/to/PLAN>

## PR Index

- <node-id> | <owner/repo:path#number> | <merge-state>
- <node-id> | <owner/repo:path#number> | <merge-state>

## Merge Order

```merge-order
# Two-node merge-order DAG (PR nodes + non-PR gate nodes), one node per line.
<node-id> | <merge-state>
<node-id> | <merge-state>
```
````

Slot rules:

- **Declaration marker** — the blockquote line carrying `This is a
  **coordination PR**` is fixed text; do not paraphrase it (`lifecycle.yml`
  greps for it).
- **PR Index** — one line per `(repo, pr_group)` node. Each cross-repo
  reference uses `owner/repo:path#number` and MUST satisfy F2 (below). A
  **private** node is redacted to its opaque node id + merge state only (F1).
- **Merge Order** — the fenced ```` ```merge-order ```` block lists each node id
  once, in an acyclic order, carrying only opaque node ids + merge state.
- **Checks** — run `shirabe validate --coordination-body <file>` before posting
  (declaration marker present, every ref passes F2, merge-order acyclic);
  `shirabe validate --merge-gate` is the live merge-last gate at merge time. The
  static check is offline; the gate is the only authority on live merge state.

## Coarsest-Legal-Grouping Rule

Implementation is grouped to the **coarsest legal unit**: by default,
**one PR per repository**. A repo splits into more than one PR only on a named
branch from the coordinated profile of
[`${CLAUDE_PLUGIN_ROOT}/references/split-triggers.md`](split-triggers.md): the
three shared branches (Hard Constraint, Incremental Value, Stated Preference)
plus this altitude's own **Merge-Order Necessity** — a split required to break a
contraction cycle in the merge-order DAG.

That file is the single source; this rule cites it rather than enumerating, so
the two cannot drift. Three triggers this rule used to carry as free-standing
bullets are retired into the shared branches there; see its Retired Triggers
section for which and why.

Absent a named branch, do not split: the coarsest grouping minimizes the
number of merge-order nodes and the cross-repo coordination surface.

A coordinated PLAN whose work sits in one repository exists only because the
work split, so the PLAN's recorded split branch is the named branch that
splits that repository: each split unit is its own `pr_group`, and the PLAN
has at least two. A multi-repo PLAN whose items all carry `Group: default`
keeps one node per repository, as before.

## Branches

The unit of branching is the PR node, not the repository. `/execute` cuts one
branch per PR node, named `impl/<slug>-<node-id>`, from the repository's
default branch, in its own worktree. A node branch is **never** cut from the
coordination branch, so no node PR carries the PLAN or the planning chain to
the default branch ahead of the coordination PR. Two groups in one repository
therefore get two branches and two PRs, and never share a branch. A multi-repo
PLAN with `Group: default` on every item gets one node, and one branch, per
repository, which is the shape it had before nodes were the unit.

Because a node branch doesn't contain the PLAN, a work item on it reads its
outline from the coordination checkout (the checkout holding the coordination
branch), or from its GitHub issue when the tracking level filed one. On resume,
a node with no indexed PR is adopted by looking up its branch
(`impl/<slug>-<node-id>`) rather than by title, keeping only a PR whose head is
in the same repository, whose author is the authenticated user, and whose base
is the default branch. More than one match is an error, never a pick.

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
consumed before the coordination PR merges, the skill **authors the validated
two-node order into the coordination PR body** as a fenced merge-order block,
where it survives the PLAN through merge as the merge-time canon.

### Re-derivation with merged nodes

An already-merged node PR is a fixed, satisfied predecessor. Re-derivation
orders only the unmerged remainder and may not add an edge that would require
re-merging a merged node. A new dependency pointing *into* a merged node is
treated as already-satisfied; a new dependency that would require a merged node
to come *after* unmerged work is rejected as inconsistent with landed history.

### Atomicity is refused, not planned

An atomicity requirement across PR groups — two PR nodes, in one repository or
in different ones, that would have to merge simultaneously with no
compatible-intermediate split — is detected at planning time and **refused**
with guidance to reshape into a compatible-intermediate sequence. The system
never emits a plan that assumes an atomic merge across PR groups.

## The Merge Step and the Pause

The merge order is also the order `/execute` works in. A node's PR is opened
only once every predecessor in the merge order is satisfied, and each node PR
**merges only after all its predecessors have merged**. The coordination PR
merges **last**, after every other indexed PR.

Merging by the agent is opt-in. Without `--merge`, `/execute` never merges
anything: it opens and readies the PRs it can, and a human merges them. With
`/execute --merge`, it merges each node PR in merge order, and then the
coordination PR, only through `skills/execute/scripts/merge-exec.sh` and only
when that PR's merge verdict allows it (the decision rules live with the
script, in `/execute`). A merge counts only once a fresh read of the PR reports
it merged. Once every indexed PR has merged, `/execute` runs finalization on
the coordination branch, pushes it, and marks the coordination PR ready (see
the exception in the
[DRAFT-vs-READY discipline](../docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md));
with `--merge` it then merges it the same way.

A coordinated run ends in one of three outcomes:

| Outcome | When |
|---|---|
| `merged` | The coordination PR merged. |
| `paused-awaiting-merges` | A node can't start because a predecessor hasn't merged, whether it waits on a human or on a merge the verdict didn't allow. |
| `ready-awaiting-merge` | Nothing is left to start, and something (a node PR or the coordination PR) is still unmerged. |

A paused run isn't a failure and doesn't end the effort. The coordination PR is
**left open**, never closed, and it's the durable record the pause rests on:
its PR index, the `head=` field each node's push records, and its merge-order
block. A later `/execute` on the same PLAN, or a `/deliver` run that reaches
`/execute`, resumes from the coordination PR and the node PRs it indexes. It
reads which predecessors have merged since, opens the node PRs that are now
unblocked, and carries on, with no re-scoping.

## The Done-Signal

The single done-signal of a coordinated effort is **the coordination PR
merging**. It cannot merge until every indexed PR has merged and
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
   work by tagging each work item with its `repo`. A public coordination
   PR coordinating a private repo would therefore **name that private repo in
   plaintext in the PLAN**, regardless of any render-layer redaction — making
   redaction theater rather than protection.

Because Private → Public references *are* allowed, a private coordination PR
can legally describe and index everything — public and private repos alike. The
direction only fails one way, so the most-restrictive-visibility rule resolves
it cleanly: any private repo in the effort pulls the coordination PR to private.

**Consequence (enforced at the front door):** a public coordination PR MUST NOT
index or reference a private repo. The skill authoring a public coordination PR
body must not write a private repo's reference into it. The backstop is
`shirabe validate --merge-gate`: when a public coordination PR (its own repo
public) indexes any repo that resolves as private — including the fail-closed
unresolvable case (treated as private) — the gate **refuses fail-closed** with a
diagnostic naming the violation. Every identifier in that diagnostic is routed
through the F1 redaction so the refusal itself does not leak. A public
coordination PR therefore only ever coordinates public repos.

## Hard Rules (Load-Bearing Security)

The following three rules are load-bearing for visibility (R15) and the
merge-last gate (R7/R14/R21). They are requirements, not guidance: every
consumer that authors, validates, or gates MUST satisfy them.

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
private**. The skill authoring a body MUST NOT write a private repo's
identifiers into a public coordination PR body. Any diagnostic path that names a
node (the merge-last gate's blocker reasons, a visibility refusal) MUST resolve
each indexed PR's repo visibility and, for any private repo, surface **only an
opaque node id and merge state** — never the private owner, repo, path, branch,
title, or number.

**Fail closed:** if a repo's visibility cannot be resolved, treat it as
private. Private identifiers MUST be routed through this redaction before they
reach any diagnostic or log. So even where the front-door rule would already
have refused (e.g. an edge it could not see), no private content leaks: the
redaction is the backstop that holds.

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

- The merge-last gate's `gh` use is **read-only**; no coordination step writes
  across a repo boundary. The skill's own `gh pr create`/`gh pr edit`/`gh pr
  close` calls write only the coordination PR's own body/state in its own repo.
  Node PRs are opened by `/execute` in the repository each node names, which
  must be in the write set `/execute` fixes when it starts.
- The only merge call is `skills/execute/scripts/merge-exec.sh`, run only under
  `/execute --merge`. It recomputes the merge verdict from live `gh` reads
  immediately before merging, never trusts a stored verdict or the PR body, and
  never passes an administrator or bypass option.
- `gh` arguments are passed as an argv array, never through a shell; the
  validator process never holds the token bytes.
- `gh`-sourced strings (PR titles, branch names) are treated as untrusted when
  the skill authors them into the body: escape/strip markdown/HTML control
  characters (F3). The authoritative fields of the merge-order block derive from
  validated PLAN/`gh` state, never from free-text titles.
- `repo`/`pr_group` tags are re-validated on **every read** (not only at
  authoring time), because the coordination PR re-derives state from the
  editable body on resume; `pr_group` is constrained to `^[a-z][a-z0-9-]*$` and
  the repo tag to the owner/repo regex before interpolation.
