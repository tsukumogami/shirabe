# Explore Scope: capstone-orchestration

## Visibility

Public

## Core Question

The author repeatedly pastes a long "how we will work this session" prompt before
running `/scope` then `/work-on` across a multi-repo workspace. Which parts of that
manual operating contract can be baked into shirabe's workflows as workspace
preferences, per-invocation intent/flags, or smart defaults — and how should the
central idea, a **capstone PR** (a single-pr PLAN generalized to a multi-repo org),
be incorporated into the `/scope` → `/work-on` chain?

## Context

- Home: `public/shirabe` (Public visibility, Tactical scope). Implementation may
  call into niwa primitives but the workflow logic lives in shirabe skills.
- The manual prompt decomposes into 5 separable conventions:
  1. **Capstone PR** — one worktree/PR created up front, holds the overarching
     plan + all upstream artifacts (brief/PRD/design/roadmap), updated as `/scope`
     and `/work-on` run, merged last as the completion signal, fully consumed
     before merge.
  2. **Planning artifacts persist to the capstone branch** — scope outputs and
     roadmap corrections land there, not scattered.
  3. **Sequencing** — produce artifacts via `/scope` first, then reconcile related
     artifacts.
  4. **Implementation worktree policy** — ≤1 worktree per repo (unless work is
     genuinely independent) so each repo yields exactly one reviewable PR.
  5. **Explicit merge order** — a known sequence for merging the per-repo PRs.
- Author's framing (verbatim intent): the capstone is "the implementation of a
  single-pr plan on a multi-repo org. The plan is created in the capstone PR (along
  with all the artifacts that come before it), and completely consumed within the PR
  before it's merged. The PR only merges after the plan is completed."
- This maps onto shirabe's existing single-pr PLAN lifecycle
  (Draft → Active → Done → DELETED, CI-enforced) — a known anchor for the design.
- Author explicitly wants the interface model (preference vs flag vs default) left
  open and explored as a trade-off, not pre-decided.

## In Scope

- How shirabe's `/scope`, `/work-on`, `/plan` handle branches, worktrees, PRs, and
  artifact persistence today.
- Generalizing the single-pr PLAN lifecycle to a multi-repo capstone.
- Classifying each of the 5 conventions as preference / flag / smart default.
- niwa primitives the workflows can lean on (worktree, mesh, state).
- Where capstone session state lives and how merge order is computed/driven.

## Out of Scope

- Implementing the change (this is exploration; crystallize routes to PRD/design/plan).
- Private/strategic framing — this is tactical shirabe ergonomics.
- niwa CLI feature work beyond identifying what shirabe needs from it.

## Research Leads

1. **How do `/scope`, `/work-on`, and `/plan` handle branches, worktrees, PRs, and
   artifact persistence today?**
   Need the current mechanics before proposing where a capstone hooks in. Especially:
   does `/work-on` already accept a PLAN doc and drive multiple issues through one
   shared branch/PR? Where do `/scope` artifacts get written and committed?

2. **How is the single-pr PLAN lifecycle implemented today, and can it generalize to
   a multi-repo capstone?**
   The author framed the capstone as exactly this. Map the Draft → Active → Done →
   DELETED lifecycle, the CI enforcement (single-pr ephemeral plans deleted before
   merge), and what assumptions are single-repo-bound vs liftable.

3. **What does niwa offer for cross-repo worktrees and coordination today?**
   The capstone + worktree-per-repo + merge-order conventions lean on niwa. Catalog
   the worktree primitives, mesh/delegation, and any workspace state niwa tracks
   (e.g. instance.json) that shirabe could read or extend.

4. **Which conventions are durable workspace preferences vs per-session intent vs
   smart defaults — and what are the trade-offs?**
   The interface-model lead the author asked to explore. Classify each of the 5
   conventions; some (≤1 worktree/repo) feel like durable config, others (this
   session's capstone) feel like per-session intent. Compare ergonomics, statefulness,
   and discoverability of each model.

5. **Where should capstone session state live, and who computes/drives merge order?**
   The capstone PR is updated throughout a multi-step, multi-repo session — the
   workflow must remember "a capstone is active" and reconnect across resets. Examine
   candidates (wip/ artifact, niwa workspace state, the capstone branch itself). Does
   `/plan`'s dependency graph already produce the data merge order needs?

6. **What prior art exists for "one coordinating PR + per-repo PRs + explicit merge
   order" in multi-repo / monorepo-of-repos workflows?**
   Light landscape pass. Look at stacked-PR tools, merge queues, change-set
   coordinators, and topic/cross-repo merge mechanisms — what's transferable to a
   capstone pattern and what's overkill for a single-author workspace.
