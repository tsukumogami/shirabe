---
schema: brief/v1
status: Accepted
problem: |
  `/scope` and `/work-on` take an effort from framing to merged code one repository at
  a time. When a single effort spans several repositories, the author supplies the
  cross-repo coordination by hand — re-describing the contract each session and
  tracking merge state manually — so the effort's framing and running state live only
  in their head and a pasted prompt: unpersisted, unenforced, easy to get wrong.
outcome: |
  `/scope` and `/work-on` carry multi-repo coordination themselves: the plan and its
  upstream framing live in one coordination PR created up front, work is grouped
  per repository, merge order is derived and tracked, and that PR merges last as
  the signal the effort is complete. The author expresses the intent once instead of
  re-pasting a contract each session.
motivating_context: |
  This brief exists because the same multi-paragraph "how we will work this session"
  instruction gets re-pasted before every coordinated multi-repo effort. The
  recurring manual contract is the signal that the coordination it describes wants to
  be a durable, tool-supported capability rather than a prompt the author maintains
  by hand.
---

# BRIEF: Coordinated Multi-Repo Orchestration

## Status

Accepted

Framing drafted under `/scope`. The downstream PRD owns the requirements
articulation; the DESIGN owns the cross-repo technical decisions this brief
deliberately defers.

## Problem Statement

A workspace holds many separate repositories. A single intent — "ship feature X" —
routinely touches several of them: a core library, an SDK, a docs site, a consumer
app. shirabe's chain handles this one repository at a time. `/scope` walks an author
through BRIEF → PRD → DESIGN → PLAN and commits those artifacts to the current
repository; `/work-on` then drives a PLAN's issues onto a single branch and pull
request. Neither has a notion of an effort that spans repositories.

So the author supplies the cross-repo coordination by hand, every session. The
recurring contract reads roughly the same each time: create a coordination branch and
pull request up front to hold the plan and the artifacts that precede it; keep
implementation grouped per repository; merge those PRs in a defined order; merge the
coordination PR last, once everything else is in.

Two things stay manual, and both are fragile:

- **The contract is re-typed each session.** It's the same instruction every time,
  so it's pure toil — and small variations creep in, so the shape drifts.
- **The running state is tracked in the author's head.** Which PRs exist, which have
  merged, what order they merge in — none of it is persisted or enforced. A missed
  merge dependency, or a planning artifact that never actually lands, slips through
  unnoticed.

The cost lands in three places. The framing isn't persisted, so a future reader
can't reconstruct why the effort was shaped the way it was. The coordination isn't
enforced, so mistakes that a checklist would catch get made. And the author repeats
the same setup work at the start of every coordinated effort. The gap is the absence
of a durable, enforceable home for multi-repo coordination — not the absence of any
one command.

## User Outcome

The author expresses the coordination intent once — as a flag, a short intent line,
or a workspace default — instead of re-describing it at the start of every effort.
From there `/scope` and `/work-on` carry the coordination themselves:

- It creates a single coordination PR up front and persists the plan plus the
  upstream framing there, so the effort has one durable home from the beginning.
- It groups implementation so each repository yields one reviewable PR.
- It derives the merge order from the plan's own dependencies and keeps it current as
  PRs open and merge.
- It treats the coordination PR as the last thing to merge, and that merge is the
  single signal that the whole effort is done.

What changes for the author is that the effort's framing and its running state are
persisted and checkable rather than held in their head. And what changes for the next
person — a reviewer, or a maintainer reading months later — is that the whole effort
is legible from one place instead of scattered across branches and recollection.

## User Journeys

### Author kicks off a coordinated effort

A workspace author begins work they already know will span repositories. They invoke
`/scope` with the coordination intent once. Before any implementation starts, the chain
creates the coordination PR and seeds it with the plan and the upstream artifacts
it produces (BRIEF → PRD → DESIGN → PLAN) — so the durable home exists from the first
move, not as an afterthought.

### Author works the plan across repositories

The author runs `/work-on` against the plan, repository by repository. Each
repository's work is grouped into one reviewable PR where it can be — occasionally
more, when the work must split. As those PRs open and merge, the coordination PR's index and merge
order update to match — the author doesn't hand-maintain them, and the PR stays an
accurate picture of where the effort actually is.

### A reviewer or future reader traces the effort

A reviewer opens the coordinating PR during review; or a maintainer lands on it months
later, trying to understand why something was built. Either way, they see the whole
effort from one place: the plan, the framing artifacts, the per-repository PRs, the
merge order, and the done-state — without reconstructing it from scattered branches
and commit archaeology.

### The effort completes and the coordination PR merges last

The author — and any reviewer watching the effort — reaches the end once every
per-repository PR has merged. A completion step finalizes the framing artifacts, and the
coordination PR merges last. That final merge is the one signal they rely on to know
the effort is complete, with no separate "is it actually done?" judgment to make.

## Scope Boundary

### In

- Making `/scope` and `/work-on` coordination-aware so they carry multi-repo coordination.
  Coordinated mode is the multi-repo generalization of what these workflows already do
  single-repo — `/scope`'s artifact chain and `/work-on`'s shared-branch, merge-last,
  consume-before-merge cascade — not a separate tool bolted alongside them.
- The coordination-PR concept: a single PR created up front that holds the
  plan and its upstream framing, merges last, and is finalized and consumed before it
  merges.
- Expressing coordination intent once: the split between behaviors that are durable
  workspace preferences and behaviors that are per-session intent or smart defaults.
  This brief names that the split exists; the PRD pins the exact contract.
- PR granularity for execution: the coarsest *legal* grouping. By default, each
  repository touched by the effort gets one PR carrying its related work, with
  repository boundaries and the cross-repository merge order as the hard breaking
  points. A repository may carry more than one PR when its pieces are independently
  mergeable, independently reviewable and rollback-able, too large to review as one,
  or when grouping them would otherwise break the merge order. Repository boundaries
  are discovered; within-repository boundaries are chosen to minimize churn.
- Cross-repository merge order, derived from the plan's existing dependency data and
  kept current through the effort, including non-PR serialization points such as a
  package publish or release gate.
- Visibility-aware coordination across the workspace's public and private
  repositories — the coordination must respect each repository's visibility.

### Out

- The technical architecture of how cross-repository tracking, the completion cascade,
  and finalizing artifacts across repository boundaries actually work. That's the
  downstream DESIGN.
- The exact representation of the merge order — where it is canonically stored, what
  diagram or table form it takes, and how non-PR gates (like a package publish step)
  are expressed. DESIGN territory.
- How per-repository grouping is validated against the merge order: collapsing the
  plan's issue-level dependencies into per-repository PRs can manufacture ordering
  cycles, so the grouping must be checked for acyclicity and a cycle resolved (split
  at the seam, re-sequence, or stack). Likewise, detecting a cross-repository
  atomicity requirement and reshaping it into a compatible-intermediate sequence is
  DESIGN territory — this brief only records that the constraints exist.
- Changes to the workspace manager's worktree internals. The effort depends on worktree
  creation existing; specifying changes to it is not part of this framing.
- Requirements-level specifics: exact flag names, the precise set of smart-defaults
  versus preferences, frontmatter field names, and validation checks. Those belong in
  the downstream PRD.
- The exact integration shape — whether coordinated behavior arrives as modes or flags on
  `/scope` and `/work-on`, a wrapping orchestrator, or new sub-skills. That this brief
  leaves to DESIGN; it commits only to the workflows being coordination-aware, not to how.
- Whether the multi-repository workspace model itself should change. This frames one
  capability within the existing model, not a re-architecture of the workspace.

## References

- `skills/scope/SKILL.md` — the tactical chain (BRIEF → PRD → DESIGN → PLAN) the
  coordinated mode extends to span repositories.
- `skills/work-on/SKILL.md` — the single-repo precedent for shared-branch plan
  orchestration and the consume-upstream-then-finalize cascade this effort generalizes.
- `skills/plan/SKILL.md` — PLAN decomposition and the dependency graph the cross-repo
  merge order builds on.
