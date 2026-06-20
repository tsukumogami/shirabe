# Running a Coordinated Multi-Repo Effort

shirabe's tactical chain is single-repo by default. `/scope` produces
BRIEF → PRD → DESIGN → PLAN in one repository, and `/work-on` drives that
PLAN onto one branch and one PR. When a feature spans more than one
repository, **coordinated mode** generalizes that machinery across repos: a
single coordination PR created up front, per-repo implementation grouped to
the coarsest legal unit, a tracked merge order, and the coordination PR
merging last as the done-signal.

This guide walks the effort end-to-end. The rules it points at —the
lifecycle, the grouping rule, the two-node merge-order model, the done-signal,
and the load-bearing security rules— are defined once in
[`references/coordination-strategy.md`](../../references/coordination-strategy.md).
This guide is the practical how-to; that contract is the canon. When the two
seem to disagree, the contract wins.

## Current status and limitations

Coordinated mode is **experimental**. The decision logic is in place and
tested — per-repo grouping, the acyclic two-node merge order with
atomicity refusal, the `shirabe validate --merge-gate` merge-last gate, the
F1/F2/F4 security rules, and the most-restrictive-visibility rule. Two seams
are not yet fully wired, so read this before relying on it:

- **`shirabe coordination create` and `sync` render the PR body to stdout;
  they do not open or edit the PR yet.** Creating the coordination PR and
  refreshing its body still go through `gh pr create` / `gh pr edit` around
  the rendered output (the skill, or you, run that glue). Full
  PR-mutation wiring is a planned follow-up.
- **No end-to-end production run has happened yet.** Coordinated mode did not
  exist while it was being built, so the first coordinated effort is the first
  real exercise of the create → sync → gate → merge-last chain outside unit
  tests. Start with a small, low-stakes two-repo effort and watch the gate
  actually block the coordination PR until the per-repo PRs land.

The merge-last gate is the safety net regardless: even if the rendered body
is stale or hand-edited, `shirabe validate --merge-gate` recomputes merge
state live and fails closed, so a wiring gap cannot cause a wrong merge.

## When to reach for coordinated mode

Use coordinated mode when both hold:

- the work spans more than one repository, and
- the per-repo PRs must land in a particular order behind a single PR that
  merges last.

If your change lives in one repo, stay on the single-repo chain. Coordinated
mode is additive: with no coordination intent, `/scope` and `/work-on` behave
exactly as they always have. You don't pay for what you don't ask for.

## Step 1 — Declare coordination intent

Intent resolves on the same precedence stack shirabe uses elsewhere:
**`flag > CLAUDE.md-header > default`**. Higher wins.

**The flag (highest precedence).** Pass `--coordinated` to `/scope` or
`/work-on` to turn coordination on for this invocation. Pass
`--no-coordinated` to force the single-repo path even when a workspace default
would enable it. The flag is per-invocation and overrides everything below.

**The CLAUDE.md header (workspace default).** Two durable preferences live as
convention headers in the repo's `CLAUDE.md`, next to `Repo Visibility` and
`Planning Context`:

```
## PR Grouping Policy: coarsest-legal

## Reviewability Ceiling: default
```

These set the workspace defaults for how per-repo work is grouped and at what
size a single PR is too large to review. They're preferences, not a switch
that flips coordinated mode on by itself. A reader finds them in the same
place as the other convention headers.

**The default.** Absent a flag or a coordinated-default signal, intent is
absent and you get the single-repo chain.

Set the flag when an effort is coordinated; set the headers when your
workspace coordinates routinely and you want the preference to persist.

## Step 2 — The PR-grouping policy

Per-repo implementation is grouped to the **coarsest legal unit**: by default,
**one PR per repository**. Fewer PRs means fewer merge-order nodes and a
smaller cross-repo coordination surface.

A repo splits into more than one PR only on a recorded trigger:

- the slices are independently mergeable,
- the slices are independently rollback-able,
- a single PR would exceed the configured reviewability ceiling, or
- a split is needed to break a cycle in the merge order.

Absent a recorded trigger, don't split. The triggers and their exact
semantics are single-sourced in the
[contract](../../references/coordination-strategy.md); the `## PR Grouping
Policy:` header sets the preference, and the `## Reviewability Ceiling:` header
sets the size threshold for the third trigger. Leave the ceiling at `default`
to defer to the contract, or set a concrete value in `CLAUDE.md` to override.

## Step 3 — The lifecycle

A coordinated effort runs in four phases.

**1. Create up front.** When intent is present, `/scope` (or `/work-on`)
creates the coordination PR at the start, before any implementation work. The
coordination PR is a docs-only PR on its own branch. Its body is *rendered
from* the PLAN —a declaration that it's a coordination PR, the artifact chain,
the PR-index, and a fenced merge-order block— and is never hand-authored.
`/plan` collapses its issue-level dependency graph into a `(repo, pr_group)`
merge order and validates it acyclic at authoring time, so an unschedulable
effort is never committed.

**2. Track.** As per-repo PRs open and progress, `/work-on` calls `shirabe
coordination sync` on each pass. Sync reads each indexed PR on your own `gh`
credentials, rewrites the PR-index, and recomputes the merge order and the
merge-last gate. State lives on the coordination branch and PR, so an
interrupted effort reconnects from durable state —no session file is the
source of truth. Sync and gate are smart defaults: each announces itself when
it activates and names its per-invocation override.

**3. Group and merge per-repo PRs in order.** Each repo's PR finalizes its own
artifacts; writes stay repo-local. Per-repo PRs merge in the validated order.
The cross-repo boundary is a read-only verification gate —"all upstreams
terminal, all per-repo PRs merged"— so no coordination step ever writes across
a repo boundary.

**4. Merge last.** Once every indexed PR has merged and finalization is
complete, the gate passes, the coordination PR consumes its own PLAN, and
merges. That merge is the done-signal. There's no separate "effort complete"
marker —the merged coordination PR is it. The non-bypassable backstop is
`shirabe validate --merge-gate`, which `lifecycle.yml` runs under `--mode=ready`:
it keeps the coordination PR unmerged while any indexed PR is open or
finalization is incomplete.

## The merge order

The merge order is a two-node DAG. **PR nodes** are one per `(repo, pr_group)`
unit and are satisfied when their PR merges. **Gate nodes** are named,
verifiable conditions that aren't themselves PRs —a package publish, for
example— and are satisfied only when the condition verifies live at gate time.
A gate that can't be verified fails closed and blocks everything ordered after
it. Edges mean "must merge or be satisfied before."

The gate always recomputes merge state from live `gh` queries, never from the
editable PR body. A stale rendered body can mislead a human reader, but it
can't cause a wrong merge, because the gate doesn't trust it.

## What gets refused

A cross-repo **atomicity** requirement —two repos that would have to merge
simultaneously with no compatible-intermediate split— is detected at planning
time and refused, with guidance to reshape the work into a sequence that lands
in a compatible order. shirabe never emits a plan that assumes an atomic
cross-repo merge.

## Visibility

Cross-repo references use `owner/repo:path`. A public coordination PR never
embeds private-repo content: the render path resolves each indexed PR's repo
visibility and, for any private repo, shows a redacted placeholder carrying
only an opaque node id and merge state. If visibility can't be resolved, the
repo is treated as private. These fail-closed rules (F1, F2, F4) are
load-bearing and live in the
[contract](../../references/coordination-strategy.md); this guide describes
them, it doesn't define them.

## The contract

For the authoritative lifecycle, grouping rule, merge-order model,
done-signal, and security rules, read
[`references/coordination-strategy.md`](../../references/coordination-strategy.md).
Every consumer —`/scope`, `/work-on`, and the `shirabe coordination`
subcommand— binds to that contract; this guide does the same.
