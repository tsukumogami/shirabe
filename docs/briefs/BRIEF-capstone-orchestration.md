---
schema: brief/v1
status: Draft
problem: |
  Coordinating an effort that spans several repositories in one workspace has no
  durable, tool-supported shape. The author re-describes the whole coordination
  contract by hand each session and tracks cross-repo merge state manually, so the
  effort's framing and its running state live only in their head and a pasted
  prompt — unpersisted, unenforced, and easy to get wrong.
outcome: |
  An author starts a coordinated multi-repo effort and the workflow carries the
  coordination: the plan and its upstream framing live in one coordinating record
  created up front, work is grouped to one reviewable PR per repo, merge order is
  derived and tracked, and that record merges last as the signal the effort is
  complete. Intent is expressed once instead of re-pasted each session.
motivating_context: |
  This brief exists because the same multi-paragraph "how we will work this session"
  instruction gets re-pasted before every coordinated multi-repo effort. The
  recurring manual contract is the signal that the coordination it describes wants to
  be a durable, tool-supported capability rather than a prompt the author maintains
  by hand.
---

# BRIEF: Capstone Orchestration

## Status

Draft

Framing drafted under `/scope`. The downstream PRD owns the requirements
articulation; the DESIGN owns the cross-repo technical decisions this brief
deliberately defers.

## Problem Statement

A workspace holds many separate repositories. A single intent — "ship feature X" —
routinely touches several of them: a core library, an SDK, a docs site, a consumer
app. But the workflow tools that take an author from idea to merged code operate one
repository at a time. They have no notion of an effort that spans repos.

So the author supplies the coordination by hand, every session. The recurring
contract reads roughly the same each time: create a coordinating branch and pull
request up front to hold the plan and the artifacts that precede it; keep
implementation to one PR per repository; merge those PRs in a defined order; merge
the coordinating record last, once everything else is in.

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
From there the workflow carries the coordination:

- It creates a single coordinating record up front and persists the plan plus the
  upstream framing there, so the effort has one durable home from the beginning.
- It groups implementation so each repository yields one reviewable PR.
- It derives the merge order from the plan's own dependencies and keeps it current as
  PRs open and merge.
- It treats the coordinating record as the last thing to merge, and that merge is the
  single signal that the whole effort is done.

What changes for the author is that the effort's framing and its running state are
persisted and checkable rather than held in their head. And what changes for the next
person — a reviewer, or a maintainer reading months later — is that the whole effort
is legible from one place instead of scattered across branches and recollection.

## User Journeys

### Author kicks off a coordinated effort

A workspace author begins work they already know will span repositories. They express
the capstone intent once. Before any implementation starts, the workflow creates the
coordinating record and seeds it with the plan and the upstream artifacts that frame
the effort — so the durable home exists from the first move, not as an afterthought.

### Author works the plan across repositories

The author moves through the plan's items, repository by repository. Each repository's
work is grouped into one reviewable PR where it can be — occasionally more, when the
work must split. As those PRs open and merge, the coordinating record's index and merge
order update to match — the author doesn't hand-maintain them, and the record stays an
accurate picture of where the effort actually is.

### A reviewer or future reader traces the effort

A reviewer opens the coordinating PR during review; or a maintainer lands on it months
later, trying to understand why something was built. Either way, they see the whole
effort from one place: the plan, the framing artifacts, the per-repository PRs, the
merge order, and the done-state — without reconstructing it from scattered branches
and commit archaeology.

### The effort completes and the record merges last

The author — and any reviewer watching the effort — reaches the end once every
per-repository PR has merged. A completion step finalizes the framing artifacts, and the
coordinating record merges last. That final merge is the one signal they rely on to know
the effort is complete, with no separate "is it actually done?" judgment to make.

## Scope Boundary

### In

- The coordinating-record concept: a single record created up front that holds the
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
- Whether the multi-repository workspace model itself should change. This frames one
  capability within the existing model, not a re-architecture of the workspace.

## Open Questions

- Whether the durable surface is named "capstone" or given a more self-explanatory term
  for readers without context. The PRD owns the naming choice.
- The precise boundary, convention by convention, between a durable workspace preference
  and per-session intent. Settled in principle during exploration; the PRD pins it.

## References

- `skills/work-on/SKILL.md` — the single-repo precedent for shared-branch plan
  orchestration and the consume-upstream-then-finalize cascade this effort generalizes.
- `skills/plan/SKILL.md` — PLAN decomposition and the dependency graph the cross-repo
  merge order builds on.
