# Running a Coordinated Effort

shirabe's tactical chain lands one PR by default. `/scope` produces
BRIEF → PRD → DESIGN → PLAN, and `/execute` drives that PLAN onto one branch
and one PR. When the work has to land as several PRs in a particular order,
**coordinated mode** generalizes that machinery: a single coordination PR that
holds the planning chain, implementation grouped into PR nodes, a tracked merge
order, and the coordination PR merging last as the done-signal.

Coordinated mode covers one or more repositories. The PR nodes can all sit in
one repository, one per group of work, or spread across several. The contract
is the same either way.

This guide walks the effort end-to-end. The rules it points at (the lifecycle,
the grouping rule, the two-node merge-order model, the done-signal, and the
security rules the gate enforces) are defined once in
[`references/coordination-strategy.md`](../../references/coordination-strategy.md).
This guide is the practical how-to; that contract is the canon. When the two
seem to disagree, the contract wins.

## How the coordination PR is maintained

The coordination PR body is authored by the workflow skill, like every other
shirabe artifact. There is no `shirabe coordination` subcommand. The skill
writes the body from the template in
[`references/coordination-strategy.md`](../../references/coordination-strategy.md)
and posts and refreshes it with `gh pr create` / `gh pr edit`.
`shirabe validate --coordination-body <file>` gives offline authoring feedback
(declaration marker, ref validity, acyclic merge order) before the post.

The merge-last gate is the safety net: even if the authored body is stale or
hand-edited, `shirabe validate --merge-gate` recomputes merge state live from
`gh` and fails closed, so the coordination PR can't merge until every indexed
PR has. An authoring gap can never cause a wrong merge.

## When to reach for coordinated mode

Use coordinated mode when the work splits into PRs that must land in a
particular order behind a single PR that merges last. That holds when the work
crosses repositories, and it can hold inside one repository too: a change that
has to reach the default branch before the next one can build on it, or a
publish step between two PRs.

If the work lands as one PR, stay on the single-PR path. If it splits into
PRs that are each useful alone and need no shared completion signal, `multi-pr`
fits better. Coordinated mode is additive: with no coordination signal,
`/scope` and `/plan` behave exactly as they always have.

## Step 1: How a PLAN becomes coordinated

`/plan` settles a PLAN's mode in two questions, in order.

**Does the work split?** This is answered from the work itself and recorded in
the PLAN's `split_branch` and `split_rationale`. No flag, intent, or header is
read here, so none of them can make work split. A PLAN that doesn't split is
`single-pr`, whatever you passed.

**What kind of split?** Only a split asks this, and the first level that gives
an answer wins:

1. An explicit flag: `--coordinated` gives `coordinated`, `--no-coordinated`
   gives `multi-pr`.
2. The intent: `--intent=continue` gives `coordinated`, `--intent=stop` gives
   `multi-pr`. No intent gives no answer here.
3. A coordinated-by-default header in the repository's `CLAUDE.md`:
   `## PR Grouping Policy: coordinated`. Other values, such as
   `coarsest-legal`, and every `## Reviewability Ceiling:` value keep their
   meaning as grouping and size preferences but don't turn coordinated mode on.
4. The default, `multi-pr`.

The PLAN records which level decided as `split_mode_source` (`flag`, `intent`,
`header`, or `default`, and `none` when the work didn't split), so you can see
why a PLAN got its mode. A script computes both values; it isn't a judgment
call.

### The intent route

You usually don't pass `--intent` to `/plan` yourself. `/scope --intent=continue`
or `--intent=stop` forwards the intent, along with any `--coordinated` or
`--no-coordinated` you gave `/scope`, to its `/plan` hop. So "scope this and
I intend to carry on to execution" resolves a split to `coordinated`, and
"scope this and stop" resolves it to `multi-pr`, unless a flag says otherwise.
`/deliver` always runs `/scope` with `--intent=continue`.

The intent also changes when the coordination PR appears. Without `--intent`,
a `/scope` run whose coordination flag or header is set creates the
coordination PR up front, before its first child document. With `--intent`,
the PLAN's mode isn't known until the `/plan` hop returns, so no coordination
PR is created up front: `/scope`'s publish step opens it at exit, once the
PLAN says `coordinated`. An intent run that's abandoned partway has no
coordination PR to close.

## Step 2: The PR-grouping policy

Implementation is grouped to the **coarsest legal unit**. Across repositories
that means, by default, **one PR per repository**. Fewer PRs means fewer
merge-order nodes and a smaller coordination surface.

Work splits into more than one PR, in one repository or across several, only
on a recorded trigger:

- the slices are independently mergeable,
- the slices are independently rollback-able,
- a single PR would exceed the configured reviewability ceiling, or
- a split is needed to break a cycle in the merge order.

Absent a recorded trigger, don't split. The triggers and their exact semantics
are single-sourced in the [contract](../../references/coordination-strategy.md).
The `## Reviewability Ceiling:` header sets the size threshold for the third
trigger: leave it at `default` to defer to the contract, or set a concrete
value in `CLAUDE.md` to override it.

## Step 3: Issue-free coordinated PLANs

A coordinated PLAN files no GitHub issues by default. Its tracking level
defaults to `none`, and at `none` each work item is an outline under
`## Issue Outlines` carrying two fields:

```markdown
### Issue 3: feat(cli): add the plugin loader

**Repo**: owner/tool

**Group**: loader
```

`**Repo**:` names the repository the item lands in, and `**Group**:` names the
PR group inside it. Together they pick the item's PR node. Nothing is filed,
and `/execute` makes no `gh issue` call while it runs such a PLAN: each work
item reads its outline straight from the PLAN.

Issues are filed only when the tracking level asks for them (`issues` or
`issues-and-milestone`, through a flag or a `## Tracking Level:` header). Even
then `/plan` files them behind an explicit filing approval, asked
interactively or decided on the record under `--auto`, and each issue gets a
`_Repo: <owner/repo> | Group: <pr_group>_` row in the Implementation Issues
table instead of the outline fields.

## Step 4: The lifecycle

A coordinated effort runs in four phases.

**1. Create the coordination PR.** It's a docs-only draft PR on its own
branch, holding the planning chain and the PLAN. `/scope` creates it: up front
on a run without `--intent`, at exit on a run with one. The skill authors its
body from the contract's template (a declaration that it's a coordination PR,
the artifact chain, the PR index, and a fenced merge-order block, all derived
from the PLAN) and checks it with `shirabe validate --coordination-body` before
posting. `/plan` collapses its work-item dependency graph into a
`(repo, pr_group)` merge order and validates it acyclic at authoring time, so
an unschedulable effort is never committed.

**2. Drive the PR nodes with `/execute`.** `/execute docs/plans/PLAN-<topic>.md`
is the driver of a coordinated PLAN. It finds the coordination PR by its branch
through the ownership filter (never by title), then works the PR nodes in merge
order. Each node's PR opens only once every predecessor is satisfied. As PRs
open and move, `/execute` re-authors the coordination PR's index. State lives
on the coordination branch and PR, so an interrupted effort reconnects from
durable state; no session file is the source of truth.

**3. Merge the node PRs in order.** Each node PR merges only after all its
predecessors have. Without `--merge`, `/execute` merges nothing: it opens and
readies the PRs it can and a human merges them. With `--merge`, it merges each
node PR when that PR's merge verdict allows (see
[Running /execute](execute-friction.md#merging-with---merge)), and a merge
counts only once a fresh read of the PR reports it `MERGED`.

**4. Merge last.** Once every node PR reads `MERGED`, `/execute` runs the
finalization cascade once, on the coordination branch, pushes it, and marks the
coordination PR ready after the merge-last gate passes. With `--merge` it then
merges the coordination PR, last. That merge is the done-signal; there's no
separate "effort complete" marker. The non-bypassable backstop is
`shirabe validate --merge-gate`, which `lifecycle.yml` runs under
`--mode=ready`: it keeps the coordination PR unmerged while any indexed PR is
open or finalization is incomplete.

## Single-repo coordinated efforts

When every work item names the same repository, each PR group is its own PR
node. `/execute` cuts one branch per node, named `impl/<slug>-<node-id>`, from
the default branch's tip, in its own `git worktree`. Two groups in one
repository get two branches and two PRs; they never share a branch.

A node branch is never cut from the coordination branch or from a
predecessor's branch. That keeps the PLAN and the planning chain off the
default branch until the coordination PR merges, which still happens last.
Because the node branch doesn't carry the PLAN, each work item reads its
outline from the coordination checkout.

A multi-repo PLAN whose items all carry `Group: default` gets one node, and one
branch, per repository. Mixed shapes work the same way: the node is always
`(repo, pr_group)`.

## Pausing and resuming

A node whose predecessor hasn't merged can't start. When that's the only thing
left to do, `/execute` ends `outcome=paused-awaiting-merges`. The pause isn't a
failure. It prints the repositories it wrote to, each unmerged PR with
`waiting=human` or `waiting=predecessor` and the condition it's waiting on, and
the command that continues the run:

```
outcome=paused-awaiting-merges
repos=owner/tool
pr=https://github.com/owner/tool/pull/41 waiting=predecessor reason=predecessor-unmerged
resume=/execute docs/plans/PLAN-plugin-system.md
```

The `resume=` line carries ` --merge` exactly when the paused run had it. The
coordination PR is left open, never closed: its PR index, the `head=` each
node's push recorded, and its merge-order block are what the pause rests on.

Merge the waiting PR (or let a later `/execute --merge` do it), then run the
`resume=` command. The new run reads node state from the coordination PR's
index and live `gh`, skips any node whose PR is already `MERGED`, opens no
second PR for a node already indexed, and makes no scoping commit. A `/deliver`
run on the same topic resumes the same way when it reaches `/execute`.

A run that ends with nothing left to start but a PR still unmerged ends
`outcome=ready-awaiting-merge` instead. Only a run that saw the coordination PR
reach `MERGED` on a live read ends `outcome=merged`.

If you decide to abandon the effort mid-flight, close the coordination PR
unmerged and note the partial state. That's the operator's call; `/execute`
never closes it on its own.

## The merge order

The merge order is a two-node DAG. **PR nodes** are one per `(repo, pr_group)`
unit and are satisfied when their PR reads `MERGED`. **Gate nodes** are named
conditions that aren't PRs (a package publish, for example) and are satisfied
only when the condition verifies live at gate time. A gate that can't be
verified fails closed and blocks everything ordered after it. Edges mean "must
merge or be satisfied before."

The gate always recomputes merge state from live `gh` queries, never from the
editable PR body. A stale body can mislead a human reader, but it can't cause
a wrong merge, because the gate doesn't trust it.

## What gets refused

An **atomicity** requirement across PR groups (two PR nodes, in one repository
or in different ones, that would have to merge simultaneously with no
compatible intermediate) is detected at planning time and refused, with
guidance to reshape the work into a sequence that lands in a compatible order.
shirabe never emits a plan that assumes an atomic merge.

A work item whose `**Repo**:` names a repository outside the PLAN's write set
ends the run `outcome=error` with `step=execute:write-set`.

## Visibility

Cross-repo references use `owner/repo:path`. A public coordination PR never
embeds private-repo content: the skill must not author a private repo's
reference into a public body, and `shirabe validate --merge-gate` enforces it.
It resolves each indexed PR's repo visibility and refuses a public
coordination PR over a private indexed repo, redacting any private identifier
in its diagnostics to an opaque node id. If visibility can't be resolved, the
repo is treated as private. These fail-closed rules live in the
[contract](../../references/coordination-strategy.md); this guide describes
them, it doesn't define them.

## The contract

For the authoritative lifecycle, grouping rule, merge-order model, done-signal,
body template, and security rules, read
[`references/coordination-strategy.md`](../../references/coordination-strategy.md).
`/scope` creates the coordination PR and `/execute` maintains it, both authoring
the body from that contract's template, and `shirabe validate` checks it
(`--coordination-body` statically, `--merge-gate` live).
