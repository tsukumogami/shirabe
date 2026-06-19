---
status: In Progress
problem: |
  `/scope` and `/work-on` operate one repository at a time. When an effort spans
  several repositories, the author hand-supplies the cross-repo coordination contract
  every session and tracks merge state manually — so the effort's framing and running
  state are unpersisted, unenforced, and easy to get wrong.
goals: |
  Make `/scope` and `/work-on` capstone-aware so they carry multi-repo coordination:
  a single coordinating record created up front holding the plan and its upstream
  artifacts, implementation grouped to the coarsest legal per-repo PRs, a derived and
  tracked merge order, and the record merging last as the one completion signal —
  with the intent expressed once instead of re-pasted each session.
upstream: docs/briefs/BRIEF-capstone-orchestration.md
motivating_context: |
  Authors re-paste the same multi-paragraph "how we will work this session" contract
  before every coordinated multi-repo effort. The recurring manual contract is the
  signal that the coordination wants to be a tool-supported capability.
---

# PRD: Capstone Orchestration

## Status

In Progress

## Problem Statement

shirabe's tactical chain is single-repo by construction. `/scope` walks an author
through BRIEF → PRD → DESIGN → PLAN and commits those artifacts to the current
repository; `/work-on` drives a PLAN's issues onto one branch and one pull request in
that repository. Neither has any notion of an effort that spans repositories.

Authors routinely run efforts that do span repositories — a core library plus an SDK,
a docs site, and a consumer app. For those, the author supplies the coordination by
hand every session: a multi-paragraph contract that says "open a coordinating PR up
front to hold the plan and the upstream artifacts; keep implementation grouped per
repository; merge the per-repo PRs in a defined order; merge the coordinating record
last." Two things then stay manual and fragile: the contract is re-typed each session
(toil, drift), and the running state — which PRs exist, which have merged, in what
order — lives only in the author's head, so a missed merge dependency or a planning
artifact that never lands slips through. The framing isn't persisted for future
readers, and the coordination isn't enforced.

This affects the workspace author driving a coordinated effort, and the reviewer or
future maintainer who must later reconstruct why the effort was shaped as it was.

## Goals

- An author expresses multi-repo coordination intent once — per invocation or as a
  workspace default — rather than re-describing it each session.
- `/scope` and `/work-on` carry the coordination: a single coordinating record created
  up front, holding the plan and its upstream artifacts, kept current as work proceeds,
  merging last as the completion signal.
- Implementation is decomposed predictably (coarsest legal per-repo grouping) with a
  merge order that is derived, tracked, and always executable.
- The effort's framing and running state are persisted and checkable instead of held in
  the author's head — legible from one place for reviewers and future readers.
- The capstone is a generalization of existing single-repo machinery, behaving
  consistently across `/scope`, `/work-on`, and the `shirabe` CLI.

## User Stories

- As a **workspace author** starting an effort I know will touch several repositories,
  I want to declare capstone intent once so that the coordinating record is created and
  seeded up front without me writing a contract.
- As a **workspace author** working through the plan, I want each repository's work to
  land as one reviewable PR (split only when necessary) and the merge order maintained
  for me, so I don't track cross-repo state by hand.
- As a **reviewer**, I want to open the coordinating PR and see the whole effort — plan,
  upstream artifacts, per-repo PRs, merge order, done-state — so I can review it without
  reconstructing it from scattered branches.
- As a **future maintainer**, I want the effort's framing and decisions to remain in one
  durable place after the work merges, so I can understand why it was built this way.
- As a **workspace author**, I want to set the coordination defaults once at the
  workspace level so that routine efforts need no per-session declaration.

## Requirements

Functional — intent and configuration:

- **R1.** `/scope` and `/work-on` accept capstone intent for an effort via a
  per-invocation signal (a flag or short intent), and a workspace-level default can
  enable capstone behavior so the author need not declare it each session.
- **R2.** The coordination behaviors are expressed as: (a) a **durable workspace
  preference** for the PR-grouping policy, and (b) **smart defaults** — for capstone
  creation, artifact persistence on the record, sequencing, and merge-order tracking —
  that activate automatically, announce themselves, and are overridable per invocation.
- **R3.** When capstone intent is absent, `/scope` and `/work-on` behave exactly as they
  do today (single-repo, no coordinating record): the capability is additive, never a
  regression to the existing single-repo path.

Functional — coordinating record (capstone) lifecycle:

- **R4.** On a capstone effort, a single coordinating record is created **up front**,
  before implementation begins, on its own branch and pull request.
- **R5.** The coordinating record holds the effort's PLAN together with its upstream
  artifacts (BRIEF, PRD, DESIGN). Per the artifact lifecycle, BRIEF/PRD/DESIGN are durable
  and remain after merge; the PLAN is a working artifact, present during the effort and
  consumed by the completion cascade before the record merges (R8) — so "held" and
  "consumed before merge" describe the same artifact at different lifecycle points, not a
  contradiction.
- **R6.** The coordinating record's tracked contents — the per-repo PR index, the merge
  order, and the effort status — stay current as implementation PRs open and merge,
  without the author maintaining them by hand.
- **R7.** The coordinating record merges **last**; its merge is the single signal that
  the effort is complete.
- **R8.** Before the coordinating record merges, the planning artifacts are finalized to
  their terminal states and the spent PLAN is consumed — generalizing `/work-on`'s
  single-repo consume-before-merge cascade across repositories.
- **R9.** Whether a capstone is active for an effort is discoverable from durable state
  (the record and its branch), so the workflow can reconnect after a context reset
  without a separate session store.

Functional — decomposition and merge order:

- **R10.** Implementation is decomposed to the **coarsest legal grouping**: by default
  each repository touched by the effort gets one PR carrying its related work, and one
  PR never spans repositories.
- **R11.** A repository carries more than one PR only when at least one holds: the pieces
  are independently mergeable, independently reviewable and rollback-able, the combined
  change exceeds the workspace's configured reviewability ceiling, or grouping them would
  otherwise break the merge order. The reviewability ceiling is a workspace preference; a
  split announces and records the triggering condition.
- **R12.** The merge order is derived from the PLAN's dependency data and represents both
  PR-to-PR dependencies and **non-PR serialization gates** (for example, a package
  publish or release step between repositories).
- **R13.** The merge order the system produces is always executable (no cyclic "A waits
  on B waits on A"). If a grouping would produce a cyclic order, the system surfaces it
  and resolves it (split at the seam, re-sequence, or stack) rather than emitting a
  deadlocked plan.
- **R14.** The coordinating record's own merge is gated on every per-repo PR in its index
  having merged.

Functional — cross-repo correctness and visibility:

- **R15.** Coordination respects each repository's visibility: a public coordinating
  record never embeds private-repo content, and cross-repo references use the
  `owner/repo:path` convention.
- **R16.** A requirement for cross-repository merge atomicity (two repos that must change
  "simultaneously") is detected and refused with guidance to reshape the work into a
  compatible-intermediate sequence — the system never silently attempts an atomic
  cross-repo merge, which plain PRs cannot provide.

Functional — consistency:

- **R17.** The capstone contract (its lifecycle, grouping rule, merge-order semantics,
  and done-signal) is defined in a single canonical place that `/scope`, `/work-on`, and
  the `shirabe` CLI all bind to, so capstone behavior is consistent across them and
  cannot drift between consumers.

Functional — resilience and lifecycle edges:

- **R20.** The capability defines an abandonment path: if an effort is abandoned, the
  coordinating record is closed without merging and its planning artifacts are left in a
  documented state (force-materialized or marked), never silently orphaned.
- **R21.** If a coordination step — record creation, PR-index or merge-order update,
  merge-gating, or the cross-repo finalize/consume cascade — cannot complete, the failure
  is surfaced and the effort halts rather than proceeding on stale or partial state; the
  coordinating record does not merge while finalization is incomplete.
- **R22.** If the PLAN changes mid-effort, the per-repo PR index and merge order are
  re-derived so the coordinating record stays consistent with the current PLAN.

Non-functional:

- **R18.** Every smart-default capstone behavior (R2b) announces itself in the invocation's
  output when it activates — naming the behavior and how to override it — and is overridable
  per invocation (least astonishment).
- **R19.** Coordination relies only on the coordinating record, git/`gh`, and existing
  niwa worktree creation — it introduces no new always-on coordination service or state
  store.

## Acceptance Criteria

- [ ] Invoking `/scope` (or `/work-on`) with capstone intent on a fresh effort creates a
      coordinating record on its own branch/PR before any implementation PR exists. (R1, R4)
- [ ] A workspace-level default can enable capstone behavior such that an effort run with
      no per-invocation flag still produces a coordinating record. (R1, R2a)
- [ ] Running `/scope` or `/work-on` without capstone intent produces the current
      single-repo behavior with no coordinating record and no new prompts. (R3)
- [ ] The coordinating record contains the PLAN, the upstream BRIEF/PRD/DESIGN, and a
      per-repo PR index at creation, so the whole effort is present in one place. (R5)
- [ ] With the workspace default ON, an effort run with a per-invocation override to OFF
      produces no coordinating record and the current single-repo behavior. (R1, R2, R3)
- [ ] After an implementation PR merges, the coordinating record's PR index and merge
      order reflect the new state without a manual edit. (R6)
- [ ] The coordinating record cannot be merged while any per-repo PR in its index is
      unmerged. (R7, R14)
- [ ] At completion, the planning artifacts are at terminal statuses and the spent PLAN
      is gone from the record before it merges. (R8)
- [ ] If the cross-repo finalize/consume cascade fails partway, the coordinating record
      does not merge and the failure is surfaced. (R8, R21)
- [ ] Re-entering an in-flight effort after a context reset re-discovers the active
      capstone from durable state, with no separate session file required. (R9)
- [ ] A decomposition that touches N repositories yields one PR per repository by default;
      no PR contains changes to more than one repository. (R10)
- [ ] A repository is split into multiple PRs only when a documented split trigger applies
      (including exceeding the configured reviewability ceiling), and the trigger is
      recorded. (R11)
- [ ] The merge order includes any required non-PR gate (e.g., a publish step) as an
      ordering node between the PRs it separates. (R12)
- [ ] A decomposition that would create a cyclic merge order is rejected or auto-resolved;
      the system never emits a merge order with a cycle. (R13)
- [ ] A public coordinating record contains no private-repo paths, names, or issue numbers;
      cross-repo references use `owner/repo:path`. (R15)
- [ ] An effort requiring cross-repo atomic merge is refused with reshaping guidance rather
      than producing a plan that assumes simultaneous merge. (R16)
- [ ] By inspection, a single canonical definition of the capstone contract exists, and
      `/scope`, `/work-on`, and the CLI reference it without restating it. (R17)
- [ ] Each smart-default capstone behavior emits an announcement in the invocation output
      naming the behavior and its override, and is suppressible/overridable by an explicit
      flag. (R18)
- [ ] No new long-running service or state store is introduced; coordination uses only the
      record, git/`gh`, and niwa worktree creation. (R19)
- [ ] Abandoning an effort closes the coordinating record without merging and leaves its
      planning artifacts in a documented state, not silently orphaned. (R20)
- [ ] A failure in any coordination step halts the effort and surfaces the error rather
      than proceeding on stale or partial state. (R21)
- [ ] Editing the PLAN mid-effort re-derives the PR index and merge order on the coordinating
      record. (R22)

## Out of Scope

- The technical architecture of cross-repo tracking, the cross-repo finalize/consume
  cascade, and the cycle-resolution algorithm. (DESIGN)
- The exact representation of the coordinating record and merge order — file vs PR-body
  location, table/diagram form, gate syntax. (DESIGN)
- The exact integration shape — whether capstone behavior arrives as flags/modes on
  `/scope` and `/work-on`, a wrapping orchestrator, or new sub-skills, and how the
  canonical contract of R17 is materialized. (DESIGN; a leading candidate is recorded in
  Decisions and Trade-offs.)
- Changes to niwa's worktree internals beyond consuming the existing
  create/list/destroy surface. (separate, if needed)
- Whether the multi-repository workspace model itself should change. This is one
  capability within the existing model.

## Known Limitations

- Reconciling a mid-effort PLAN change (R22) or an abandonment (R20) against per-repo PRs
  that have **already merged** is a real semantic edge: an already-landed PR cannot be
  un-grouped or un-ordered. The PRD requires re-derivation and a documented abandonment
  state; how each reconciles with already-merged work is a DESIGN decision.
- R12's non-PR gates are represented in the merge order; whether a gate is enforced as a
  **hard** merge block during execution (versus advisory) is a DESIGN decision, since hard
  enforcement may depend on CI or branch protection not available in every repository.

## Decisions and Trade-offs

- **Naming — adopt "capstone."** The artifact and intent use the term "capstone."
  Alternative: a more self-explanatory term for readers without context. Chosen because
  it is the established term in practice and the concept is defined in a canonical
  reference (R17) that gives a cold reader the definition. (Closes the brief's naming
  open question.)
- **Preference-vs-smart-default split.** The PR-grouping policy is a durable workspace
  preference (R2a); capstone creation, artifact persistence, sequencing, and merge-order
  tracking are smart defaults that announce and are overridable (R2b). Alternatives: make
  everything a per-invocation flag (loses the "express once" goal) or everything a
  preference (forces config before first use). Chosen because it matches shirabe's
  existing flag > CLAUDE.md-header > default precedent and directly removes the
  re-pasting toil. (Closes the brief's preference-vs-intent open question.)
- **Coarsest legal grouping over rigid one-PR-per-repo.** Grouping minimizes churn subject
  to legality (acyclic-after-grouping plus a reviewability ceiling), and a repo may split
  for cause including to break a merge-order cycle. Alternative: strict one-PR-per-repo
  (can deadlock the merge order; can force unreviewably large PRs). (From the granularity
  sub-exploration.)
- **Single canonical contract + aware consumers (leading integration approach).** The
  capstone strategy is articulated once as a cross-cutting reference that `/scope`,
  `/work-on`, and the CLI bind to, mirroring how `parent-skill-pattern.md` is shared by
  `/scope` and `/charter`. Alternative: embed the contract in each consumer (drifts). The
  exact materialization is a DESIGN decision; R17 only requires the single source of truth.
- **Reviewability ceiling is a configurable preference, not a hard-coded line count.** R11's
  "too large to review" split trigger resolves against a workspace-configured ceiling rather
  than a fixed threshold, so the subjective judgment becomes an objective, recorded check.
  Alternative: a fixed line count (brittle across repos and change types) or pure human
  judgment (not testable). The exact default and unit are a DESIGN detail.
