---
schema: prd/v1
status: In Progress
problem: |
  shirabe has no implementation-altitude parent skill that owns plan-level
  execution. That responsibility is bundled into /work-on, which today both runs a
  single issue and iterates a whole plan of many issues. The result is no clean
  coordinator an author can hand a finished plan to, and a single-issue path
  weighed down by plan-orchestration concerns. Plans whose units land as several
  pull requests across repositories have nowhere durable to hold the across-issue
  picture, and an interrupted run loses it.
goals: |
  A new /execute skill owns plan-level execution for the two plan shapes that have
  a session-scoped ephemeral home — single-pr (one shared pull request) and
  coordinated (multi-repo, a coordination pull request) — delegating each single
  issue to a narrowed /work-on. It preserves, with parity or better, every
  value-adding capability of today's multi-issue execution, and existing PLAN docs
  keep running end to end without being rewritten.
upstream: docs/briefs/BRIEF-execute-skill.md
motivating_context: |
  The strategic chain (/charter) and tactical chain (/scope) already ship as
  single-agent parent skills; the implementation altitude is the remaining gap.
  shirabe#196 added multi-repo coordinated execution, and the plan-iteration
  responsibility currently inside the single-issue executor is the natural thing
  for the new coordinator to own.
---

# PRD: execute-skill

## Status

In Progress

## Problem Statement

shirabe gives authors two coherent parent-skill experiences — the strategic chain
(/charter) and the tactical chain (/scope) — each a single coordinator that holds
state across steps, delegates each step to a child, and inspects only what it needs
to. The implementation altitude has no such coordinator.

The single workflow that executes work today, /work-on, does two jobs at once: it
runs one issue to a merged pull request, and it iterates a whole plan of many
issues. Bundling both has two costs. There is no clean plan-level coordinator an
author can hand a finished plan to and watch run; and the single-issue path carries
plan-orchestration weight that does not belong at the altitude of one issue.

The cost is sharpest on plans whose issues land as several pull requests across
repositories that must merge in a defined order. Nothing durable holds the
across-issue picture — what has merged, what is blocked, what comes next, whether
the whole set is done — so an author tracks it by hand and loses it when a session
ends. This work matters now because the coordinated execution mode (shirabe#196)
just landed, giving multi-repo plans a durable coordination home worth
orchestrating against, and because the plan-orchestration capability already exists
inside /work-on and can be moved rather than rebuilt.

## Goals

- Stand up /execute as the implementation-altitude member of the parent-skill trio,
  owning plan-level execution for the two ephemeral-home plan shapes.
- Move the plan-orchestration responsibility out of /work-on, leaving it a focused
  single-issue executor, without losing any value that responsibility delivers
  today.
- Make a finished plan runnable in one move, with progress reported against the
  whole and a single done-signal for a coordinated set.
- Keep every existing PLAN doc running end to end with no rewrite.

## User Stories

- As a feature author with a finished single-pr plan, I want to hand the whole plan
  to one coordinator so that its issues are driven to a single merged pull request
  without my dispatching each one.
- As an author with a coordinated multi-repo plan, I want the coordinator to walk
  the merge order across repositories and tell me when the whole set is done, so
  that I track one conversation instead of a wall of pull requests.
- As an author whose execution session was interrupted, I want to re-invoke the
  coordinator and have it resume from the plan's durable state — even on another
  branch — so that I never restart or reconstruct where things stood.
- As a maintainer of an existing PLAN doc, I want my plan to keep running under the
  new coordinator without editing the doc, so that the migration costs me nothing.
- As an author running a multi-pr milestone of independent issues, I want each issue
  run on its own through the single-issue executor, so that the simple case stays
  simple and nothing orchestrates what needs no coordination.

## Requirements

### Skill shape and conformance

- **R1.** /execute is a new single-agent parent skill at the implementation
  altitude, distinct from /work-on, conforming to the parent-skill pattern v1: the
  required SKILL.md structural elements, a topic-keyed state file with the
  conditional-field discipline and hard-finalization check, the resume ladder, the
  three named exit paths, metadata-only child inspection, and the pattern's security
  surfaces.
- **R2.** The pattern's three exit names are preserved, bound to execution outcomes:
  full-run (the plan is driven to its done-signal), abandonment-forced (the run is
  stopped before completion and the partial state is recorded), and re-evaluation
  (execution halts at a boundary where an upstream artifact must change before the
  plan can proceed). /execute is the downstream owner of the PLAN lifecycle that
  /scope's resume ladder redirects to.

### Input and mode ownership

- **R3.** /execute accepts a finished PLAN doc (`schema: plan/v1`) as input and runs
  it. It MUST accept existing PLAN docs unchanged — the `execution_mode`,
  `upstream`-chain, milestone, issue-count, and issue-table fields as they exist
  today, including the legacy four-column Implementation Issues table — and MUST NOT
  require any PLAN doc to be rewritten to run. Execution escape hatches that PLAN
  authors rely on today (for example the allowance for untracked acceptance criteria)
  MUST continue to work.
- **R4.** /execute owns plan-level execution for exactly two plan shapes:
  single-pr (many issues driven through one shared pull request) and coordinated
  (independent pull requests across repositories walked in merge order, governed by a
  docs-only coordination pull request that merges last). It does not own multi-pr
  (single-repo, independent pull requests) execution.
- **R5.** The owned shapes are defined by having a session-scoped ephemeral home for
  the plan's non-durable artifacts: the single pull request (single-pr) or the
  coordination pull request (coordinated). /execute holds the PLAN doc and `wip/`
  supporting artifacts in that home for the duration of execution and removes them
  before the home merges. multi-pr is excluded because it has no such home — its
  PLAN doc is persisted in the repository for the plan's duration and its per-issue
  artifacts live only for one issue.

### Delegation and the narrowed executor

- **R6.** /execute delegates each single issue to /work-on through the existing
  single-issue execution contract, and does not reimplement single-issue mechanics.
  /work-on continues to own per-issue value (the gated per-issue lifecycle artifacts
  and right-sized code-review panels) behind that contract.
- **R7.** The plan-orchestration responsibility is removed from /work-on. After this
  work, /work-on no longer iterates a whole plan; it executes a single issue.
  Multi-pr plans execute as independent per-issue /work-on runs against the
  repository-persisted PLAN doc — one issue at a time, each its own pull request, no
  cross-issue carry-forward — with no plan-level coordinator involved.

### Parity-or-better value capabilities (owned shapes)

The following capabilities exist in today's multi-issue execution and MUST be
preserved with parity or better in /execute for the shapes it owns. None may
regress.

- **R8.** Base-branch drift gate: before advancing the plan, /execute brings the
  working branch current against its base branch and classifies the impact of the
  incoming commits; an intent-changing change halts and escalates, while a
  non-intent-changing change is absorbed and the run proceeds.
- **R9.** Cross-issue carry-forward: within the ephemeral home, context and learning
  from completing one issue inform the next. (Available in single-pr and coordinated;
  intentionally absent in multi-pr.)
- **R10.** Dependency-aware sequencing: issues run in dependency order, and a failed
  issue isolates its dependents (skip-dependents) rather than failing the whole plan
  blindly.
- **R11.** CI choreography: single-pr drives one shared branch and a single draft
  pull request through a draft-before-ready posture with dirty-merge detection;
  coordinated walks the merge order of per-unit pull requests and gates the
  done-signal on the coordination contract's live merge-gate, the merge-last pull
  request being the single, non-bypassable done-signal.
- **R12.** Atomic self-verifying finalization cascade: at plan completion /execute
  performs the upstream-lifecycle cascade (PLAN removal plus BRIEF/PRD/DESIGN/ROADMAP
  transitions) as one self-verifying finalization with pre- and post-condition
  probes.
- **R13.** Crash-resumable, self-documenting execution: setup is idempotent and
  crash-resumable; execution resumes from the plan's durable state, including across
  branches and sessions; the resulting pull request body documents what the plan did;
  and on a forced stop, /execute records an operator-facing summary of what completed,
  what remains, and why it stopped.

### Coordinated-mode orchestration

- **R14.** For coordinated plans, /execute takes over the track-to-merge-last loop:
  it refreshes the coordination state from the live source of truth, walks the
  merge-order graph of pull-request nodes and gate nodes — dispatching each unblocked
  pull-request node to /work-on and resolving each gate node before its dependents
  advance — and treats the coordination contract's merge-gate as both the per-unit
  status read and the whole-plan done-signal. Creating the coordination home up front
  remains /scope's responsibility; /execute consumes it.

### Autonomous execution

- **R18.** Autonomous-execution mandate. When the author authorizes an autonomous
  run (an explicit autonomy mode/flag, or a clear instruction such as "run
  autonomously" or "don't stop"), /execute runs the plan to its done-signal or a
  genuine blocker (R19) without pausing for checkpoints, confirmation, reassurance,
  or unsolicited advisory stops. It MUST NOT stop merely because the work is large,
  because many issues remain, or out of concern for its own context budget. In the
  default (interactive) mode the existing human-approval behavior is unchanged; the
  mandate governs the authorized-autonomous mode specifically.
- **R19.** Blocker taxonomy. A genuine blocker that legitimately halts an autonomous
  run is one of: a delegated issue that fails or is blocked in a way needing human
  judgment and that cannot be auto-resolved or isolated via skip-dependents; an
  upstream-must-change (re-evaluation) boundary; a merge conflict or dirty state
  requiring human resolution; or a destructive or irreversible action requiring
  confirmation. The following are explicitly NOT blockers and MUST NOT stop an
  autonomous run: a decision that has a reasonable default (take the default, record
  it, continue); the size or remaining count of the work; or the coordinator's own
  context budget — which the delegation architecture (R6, R15) keeps bounded by
  design. On a genuine blocker, /execute stops with the forced-stop operator summary
  (R13); it does not stop otherwise.

### Inspection and progress

- **R15.** /execute inspects issue, pull-request, and unit state only through status
  surfaces (lifecycle status, content fingerprints, validator and merge-gate
  results), never by reading child artifact bodies, and reports progress against the
  whole plan.

### Non-functional

- **R16.** No value regression: every capability in R8–R13 has a corresponding,
  verifiable behavior in /execute for the shapes it owns; the migration does not
  ship lower value than current multi-issue execution.
- **R17.** Mechanism-neutral requirements: these requirements state capabilities and
  contracts, not the execution mechanism. Whether /execute's plan iteration uses koto
  is a downstream design decision (see Decisions and Trade-offs).

## Acceptance Criteria

- [ ] An existing single-pr PLAN doc runs to a single merged pull request under
  /execute with no edit to the doc.
- [ ] An existing multi-pr PLAN doc still completes — each issue run independently
  through /work-on, each its own pull request — with no edit to the doc and no
  plan-level coordinator involved.
- [ ] A coordinated PLAN runs: /execute walks the merge order, dispatches each
  unblocked unit to /work-on, and reports the plan done only when the coordination
  merge-gate passes in ready posture.
- [ ] An intent-changing upstream change introduced mid-plan halts the run and
  escalates rather than proceeding.
- [ ] Cross-issue carry-forward is observable across two issues of a single-pr plan;
  it is absent (by design) in a multi-pr run.
- [ ] A failed issue isolates its dependents (they are skipped) rather than failing
  the whole plan.
- [ ] Plan completion performs the finalization cascade atomically: the PLAN is
  removed and the upstream chain transitions in one self-verifying finalization.
- [ ] /work-on no longer contains the plan-orchestration path; invoking /work-on on
  a single issue behaves exactly as before.
- [ ] An interrupted coordinated run resumes from durable state on a different branch
  and continues at the next unblocked unit.
- [ ] A non-intent-changing base-branch change introduced mid-plan is absorbed and the
  run proceeds without halting (the drift gate's non-halt branch).
- [ ] The ephemeral session artifacts (the PLAN doc and `wip/`) are removed from the
  session home before that home — the single pull request or the coordination pull
  request — merges.
- [ ] The resulting pull request body documents what the plan did (the issues it ran
  and their outcomes).
- [ ] A forced-stop run records an operator-facing summary of what completed, what
  remains, and why it stopped.
- [ ] A coordinated run resolves a gate node (a non-pull-request node) before its
  dependents advance.
- [ ] /execute reads only status surfaces during a run (no child artifact bodies),
  verified against the metadata-only child-inspection contract in the parent-skill
  pattern references.
- [ ] /execute passes the parent-skill conformance checks defined in the parent-skill
  pattern references (state schema, resume ladder, three exit names, security
  surfaces).
- [ ] An authorized autonomous run drives a multi-issue plan from start to the
  done-signal with no intermediate approval, checkpoint, or reassurance prompt.
- [ ] An autonomous run that hits a genuine blocker (a delegated issue fails needing
  human judgment) stops with the forced-stop operator summary; an autonomous run that
  hits a defaultable decision takes the default, records it, and continues without
  stopping.
- [ ] An autonomous run does not stop due to plan size, remaining-issue count, or
  coordinator-context concern.

## Out of Scope

- Single-issue execution mechanics — these remain in /work-on, which /execute calls
  down to.
- Multi-pr (single-repo, independent pull requests) plan orchestration — these run
  as independent per-issue /work-on runs against a repo-persisted PLAN, not through
  a plan-level coordinator.
- The choice of whether /execute's plan iteration uses koto or another mechanism,
  and the nested-session model — downstream design (direction recorded below).
- Building the shared coordination substrate (cross-session, cross-branch state
  primitive) the coordinator relies on — separate amplifier work.
- The review-time redirect mechanism (changing course mid-execution on a human
  redirect) — separate downstream feature.

## Decisions and Trade-offs

- **D1 — /execute is a new skill, not a rename of /work-on.** /work-on persists as
  the single-issue executor /execute delegates to, so there is nothing to rename.
  Closes the BRIEF's new-skill-vs-rename question.
- **D2 — Mode ownership is drawn by the ephemeral-artifact home, not pull-request
  count.** single-pr and coordinated each have a session-scoped home (the single PR,
  the coordination PR) for the PLAN doc and `wip/`; that home is what lets a
  coordinator hold and carry state across issues. multi-pr has no such home — its
  PLAN is repo-persisted and its per-issue artifacts are single-issue-scoped — so it
  is excluded on principle, not by arbitrary line-drawing.
- **D3 — koto is the intended direction but the mechanism is deferred to design.**
  koto sessions are themselves ephemeral session artifacts. The intended direction
  is a hierarchical model: a parent koto session at the plan level with child koto
  sessions per issue. koto has no cross-repo session today, so a single plan-level
  koto session for a coordinated (multi-repo) run is hard and the nested-koto model
  may be deferred initially. The PRD requires the capabilities (R8–R13)
  mechanism-neutrally; the design chooses koto-or-not and the nesting shape.
- **D4 — Carry-forward is required for the owned shapes and intentionally absent for
  multi-pr.** This keeps the parity guardrail satisfied: multi-pr issues are
  independent and never carried forward, so per-issue-only artifacts are correct
  there, while single-pr and coordinated keep the carry-forward value.
- **D6 — True autonomy is an explicit skill mandate, not just an architectural
  property.** The coordinator-plus-ephemeral-teams architecture keeps the
  coordinator's context bounded over an arbitrarily long run (it delegates each issue
  to a fresh child and inspects only the metadata surface), which removes the main
  driver of premature stopping. But the architecture alone is not sufficient: a model
  driving the skill inherits a default caution that stops mid-run to "advise a
  checkpoint." So the skill MUST explicitly forbid that (R18) and MUST name the narrow
  set of genuine blockers (R19). This is the difference between a run that uses the
  hours the author gave it and one that wastes them by stopping after the first step.
- **D5 — Multi-pr execution is independent per-issue /work-on runs.** A multi-pr plan
  executes one issue at a time through /work-on against the repository-persisted PLAN
  doc, with no plan-level coordinator and no cross-issue state. Whether /work-on
  offers a thin sequential convenience loop over a milestone's issues, or the author
  dispatches them one at a time, is a downstream design detail; either way carries no
  cross-issue state. (Resolves the BRIEF/PRD multi-pr open question.)

## Known Limitations

- The coordinated nested-koto session model may be deferred because koto sessions do
  not span repositories; coordinated execution may initially drive per-unit work
  without a single plan-spanning koto session.
- The coordination contract exposes status and the done-signal through a live
  merge-gate recompute rather than a structured per-node status surface; /execute
  must work from that surface, and a richer per-node read may be future work.
- The human-facing PLAN format reference lags the validator (it documents single-pr
  and multi-pr but not coordinated); aligning it is adjacent doc debt the design or
  plan should pick up.
- The legacy four-column Implementation Issues table is only hint-migrated by
  validation, not rejected, so /execute must still parse it for older PLAN docs.
