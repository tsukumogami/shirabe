---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-execute-skill.md
decision_provenance: inline-resolved
problem: |
  /work-on bundles two responsibilities in one workflow — running a single issue and
  iterating a whole plan of many issues. shirabe needs a new implementation-altitude
  parent skill, /execute, that owns plan-level execution for the two ephemeral-home
  plan shapes (single-pr and coordinated), delegating each single issue to a narrowed
  /work-on, while preserving every value capability of today's multi-issue execution
  and running existing PLAN docs unchanged.
decision: |
  Lift the existing work-on-plan orchestrator template, its prose, and the cascade
  script into /execute, and keep work-on.md as /work-on's canonical single-issue
  engine spawned by /execute over a cross-skill path. /execute runs a koto-backed
  plan session with per-issue child sessions for single-pr, and a plain
  durable-state loop over the coordination PR's merge-order DAG for coordinated. The
  storage substrate is the home pull request (durable, cross-branch) projected into a
  wip-yaml-md scratch state file for pattern conformance. /work-on's PLAN input
  becomes a thin execution_mode dispatcher that runs multi-pr in place and hands
  single-pr/coordinated to /execute.
rationale: |
  Reusing the proven orchestrator template avoids reimplementing the eight value
  capabilities and keeps parity by construction; the koto/plain split respects koto's
  lack of cross-repo sessions while still realizing the hierarchical-koto direction
  where it works (single-repo single-pr). On-PR durable state satisfies the pattern's
  cross-branch-resume invariant in v1 without the unbuilt coordination substrate. A
  dispatcher preserves existing /work-on PLAN invocations and evals unchanged.
---

# DESIGN: execute-skill

## Status

Planned

## Context and Problem Statement

shirabe ships two single-agent parent skills — /charter (strategic chain) and
/scope (tactical chain) — that hold state across child steps and inspect children
through a metadata-only surface. The implementation altitude has no equivalent. The
PRD (`docs/prds/PRD-execute-skill.md`) specifies a new /execute parent skill that
owns plan-level execution and delegates each single issue to a narrowed /work-on.

Today /work-on runs two koto state machines: a per-issue machine (`work-on.md`) and
a plan-orchestrator (`work-on-plan.md`) that iterates a whole plan. The
plan-orchestrator already delivers the value the PRD requires preserved with parity
or better (base-branch drift gate, cross-issue carry-forward, dependency-DAG
sequencing with skip-dependents, shared-branch CI choreography, atomic finalization
cascade, crash-resumable setup, self-documenting PR). The design question is how to
move that responsibility into /execute without losing value, run both owned plan
shapes (single-pr and coordinated), satisfy the parent-skill pattern, and keep every
existing PLAN doc running unchanged.

The coordinated execution mode (shirabe#196) keeps durable coordination state on a
docs-only coordination pull request that merges last (a PR-Index plus a merge-order
DAG of pull-request nodes and gate nodes), with `shirabe validate --merge-gate` as
the live, fail-closed status read and done-signal.

## Decision Drivers

- **Parity or better:** no value capability of today's multi-issue execution may
  regress (PRD R8–R13, R16).
- **Backward compatibility:** existing PLAN docs run end to end with no rewrite (PRD
  R3); the `execution_mode` enum, the legacy four-column issue table, and the
  untracked-acceptance-criteria escape hatch all keep working.
- **Parent-skill conformance:** state schema, resume ladder, three exit names,
  metadata-only child inspection, and the six security surfaces (PRD R1, R2, R15).
- **koto's cross-repo limit:** koto has no session that spans repositories, so a
  single plan-level koto session cannot cover a coordinated multi-repo run.
- **Clean narrowing:** /work-on must end up a legible single-issue engine.
- **SE2 independence:** the design must not depend on the unbuilt coordination
  substrate; cross-branch resume must work in v1.

## Considered Options

Decisions were resolved inline under parent orchestration
(`decision_provenance: inline-resolved`); full evaluations are in
`wip/design_execute-skill_decision_{1,2,3}_report.md`.

### Decision 1 — Plan-iteration mechanism

- **Option A — single lifted koto session for both modes.** Rejected: koto cannot
  span repositories, so a coordinated multi-repo run cannot share one koto session.
- **Option B — plain non-koto loop for both modes, calling /work-on (koto per
  issue).** Rejected: discards the proven `work-on-plan` template for single-pr and
  risks parity regression by reimplementation.
- **Option C — hybrid (chosen).** single-pr runs the lifted `work-on-plan` koto
  template as a plan-level session with per-issue child koto sessions (the
  hierarchical-koto direction, valid where single-repo nesting works); coordinated
  runs a plain durable-state loop over the coordination PR's merge-order DAG. Per-issue
  delegation is uniform: one /work-on (`work-on.md`) invocation per issue, each its
  own koto session.

### Decision 2 — Orchestrator extraction and PLAN routing

- **Extraction — shared library both skills reference.** Rejected: a neutral or
  plan-hosted template muddies the single-issue legibility the narrowing is meant to
  buy.
- **Extraction — move into /execute (chosen, E3).** Move `work-on-plan.md`, the
  orchestrator prose, and `run-cascade.sh` (with the `WORK_ON_ALLOW_UNTRACKED_ACS`
  escape hatch) into /execute; keep `work-on.md` in /work-on as the canonical
  single-issue engine /execute spawns by cross-skill path.
- **Routing — hard-remove /work-on PLAN input.** Rejected: breaks existing
  invocations and /work-on's own evals.
- **Routing — thin dispatcher (chosen, R1).** `/work-on <PLAN>` keeps working as a
  thin dispatcher that reads `execution_mode`: it runs multi-pr in place per issue
  (PRD D5) and hands single-pr/coordinated PLANs to /execute.

### Decision 3 — State substrate and conformance binding

- **Option A — wip-yaml-md only (like /charter, /scope).** Rejected: fails the
  cross-branch-resume invariant (I-6).
- **Option B — koto-context-store.** Rejected: unbuilt amplifier substrate; deferred.
- **Option C — on-home-PR durable + wip-yaml-md scratch (chosen).** The home pull
  request (coordination PR for coordinated, single PR for single-pr) is the durable,
  cross-branch source of truth; `wip-yaml-md` is a reconstructable per-session
  projection carrying the pattern's five-field schema, `child_snapshots:`, and the
  `parent_orchestration:` sentinel.

## Decision Outcome

/execute is a new single-agent parent skill at the implementation altitude. It owns
plan-level execution for single-pr and coordinated plans and delegates every single
issue to /work-on's `work-on.md` engine.

- **single-pr:** /execute runs the lifted `work-on-plan` koto template as a
  plan-level session, iterating issues in dependency order, spawning a per-issue
  child koto session per issue, carrying context forward on the shared branch, and
  driving one draft pull request through the draft-before-ready CI choreography to a
  single merged pull request (the done-signal).
- **coordinated:** /execute runs a plain durable-state loop: refresh coordination
  state from live `gh`, walk the merge-order DAG, dispatch each unblocked
  pull-request node to /work-on (per repo) and resolve each gate node before its
  dependents advance, and treat `shirabe validate --merge-gate --mode=ready` as the
  per-node status read and the merge-last done-signal.
- **multi-pr:** not owned by /execute; the /work-on dispatcher runs it in place, one
  issue at a time, against the repo-persisted PLAN.

The home pull request is the durable substrate; a `wip-yaml-md` projection carries
conformance state. The three exit names bind to execution outcomes: full-run = the
merged-PR done-signal; abandonment-forced = a forced stop (unmergeable PR, failed
gate node, or escalation) leaving an abandonment-marked PR and a frozen PLAN as the
review surface; re-evaluation = an upstream-must-change boundary that writes a
Decision Record and does not re-execute.

## Solution Architecture

### Components

- **/execute SKILL.md** — plain-English parent skill with the seven required
  structural elements and the execution phases (setup, mode detection, per-mode
  execution loop, finalization).
- **Lifted orchestrator** — `skills/execute/koto-templates/execute.md`, the
  orchestrator prose, and `skills/execute/scripts/run-cascade.sh` (moved from
  /work-on, including the `WORK_ON_ALLOW_UNTRACKED_ACS` allowance).
- **/work-on (narrowed)** — retains `skills/work-on/koto-templates/work-on.md` as the
  canonical single-issue engine; its PLAN input becomes a thin `execution_mode`
  dispatcher.
- **State** — `wip/execute_<topic>_state.md` (scratch projection) over the durable
  home-PR state. For coordinated, that durable state is the coordination PR's
  PR-Index + merge-order DAG. For single-pr, it is the committed state on the
  `impl/<slug>` branch (the koto context and the in-flight PLAN), reachable from any
  branch through the single pull request — not free-text in the PR description.

### Interfaces

- **Single-issue delegation contract:** /execute spawns `work-on.md` child koto
  sessions over the cross-skill path
  `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md`, passing the
  existing injected variables (including `SHARED_BRANCH`); each child returns its
  `summary.md`, terminal state, and final view. /execute does not reimplement
  single-issue mechanics.
- **Coordination contract:** `shirabe validate --merge-gate` (live status + fail-closed
  done-signal) and `--coordination-body` (offline authoring check). Creating the
  coordination home up front stays /scope's responsibility; /execute consumes it.
- **Parent-skill conformance:** five-field state schema with conditional fields and
  the R9 hard-finalization check; the resume ladder, whose main/topic-branch rows do
  a topic-keyed home-PR lookup (via `gh`) before declaring "no state → fresh,"
  satisfying I-6; metadata-only inspection of issue/PR/unit status; the six security
  surfaces.

### Data flow (single-pr)

1. Entry (`/execute <PLAN>` directly, or handed off by the /work-on dispatcher).
2. Read `execution_mode`; on single-pr, `koto init` the plan session from the lifted
   template; `plan-to-tasks` materializes children on an `impl/<slug>` shared branch
   with one draft PR.
3. Per issue in dependency order: base-branch drift gate → spawn `work-on.md` child →
   carry context forward → CI choreography; a failed issue skips its dependents.
4. Finalization: `run-cascade.sh` performs the atomic upstream-lifecycle cascade
   (PLAN removal + BRIEF/PRD/DESIGN/ROADMAP transitions, pre/post probes); the single
   PR goes ready and merges (done-signal).

### Data flow (coordinated)

1. Entry against an existing coordination PR.
2. Loop: refresh coordination state from live `gh` → walk merge-order DAG → dispatch
   each unblocked PR node to `work-on.md` (per repo), resolve gate nodes → re-gate.
3. Done when `--merge-gate --mode=ready` passes and the coordination PR merges last.

Cross-unit carry-forward in coordinated mode flows through the coordination PR's
durable state rather than a shared branch (there is no single branch across repos);
the precise carry-forward payload is a plan-time detail (see Consequences).

### Autonomous execution contract

A coordinator-driven design is what makes hours-long autonomous runs feasible, and the
skill must be explicit about the behavior or the model driving it reverts to a default
caution that stops mid-run.

**Why the architecture enables it.** /execute holds only the metadata surface — issue
and PR status, the merge-gate result, child terminal states — and offloads every
issue's real work to a fresh /work-on child (its own koto session, its own context).
The coordinator's context therefore does not grow with the number of issues; a
hundred-issue plan costs the coordinator roughly what a one-issue plan costs. This
removes the dominant cause of premature stopping (the driver running low on context
and bailing to "checkpoint").

**Why the architecture is not sufficient.** Bounded context removes the cause, but a
model driving the loop still tends to stop and seek reassurance on long work. So the
skill carries an explicit mandate: when authorized to run autonomously, the
orchestrator loop runs to the done-signal or a genuine blocker and does NOT pause for
checkpoints, confirmation, reassurance, or unsolicited advisory stops, and does NOT
stop because the work is large or out of context concern (PRD R18). The mandate lives
in the SKILL prose and in the koto orchestrator-loop directives so it binds at every
tick, not only at entry.

**Why this skill and not /charter or /scope.** The strategic and tactical chains already run autonomously well, because each of their steps produces a *different* artifact (vision/strategy/roadmap; brief/prd/design/plan). That heterogeneity gives them momentum for free: each step is visibly distinct, its completion is unambiguous, and the chain has a concrete terminus. /execute is the homogeneous case — the same "implement an issue" step repeated over many issues — so it lacks that built-in momentum, and the cautious-stop instinct surfaces precisely as "I've done several of these, maybe I should check in." The mandate must kill that specific non-blocker and replace the vibe-of-enough with the concrete done-signal (all issues merged / the coordination PR merges last). This is why the explicit mandate is load-bearing for /execute specifically and not bolted onto every skill.

**Blocker taxonomy.** A genuine blocker halts the run and emits the forced-stop
operator summary: a child that fails or is blocked in a way needing human judgment and
cannot be auto-resolved or isolated by skip-dependents; an upstream-must-change
re-evaluation boundary; a merge conflict or dirty state needing human resolution; or a
destructive/irreversible action requiring confirmation. Not blockers (must not stop):
a decision with a reasonable default (take it, record it in the koto decision log,
continue); the size or remaining count of the work; or the coordinator's own context
budget. The autonomy mode rides the existing execution-mode surface (the --auto /
interactive distinction the other shirabe skills carry, resolved flag > CLAUDE.md
header > default); the default stays interactive so existing behavior is unchanged.

## Implementation Approach

1. **Extract the orchestrator.** Move `work-on-plan.md`, orchestrator prose,
   `run-cascade.sh`, and the `WORK_ON_ALLOW_UNTRACKED_ACS` allowance into /execute.
   Leave `work-on.md` in /work-on.
2. **Narrow /work-on + dispatcher.** Reduce /work-on's PLAN input to a thin
   `execution_mode` dispatcher (multi-pr in place; hand off single-pr/coordinated).
   Update /work-on prose to the single-issue framing, and repoint /work-on's existing
   PLAN-detection evals from the old plan-orchestrator behavior to the dispatcher
   behavior so they keep passing.
3. **/execute SKILL.md + single-pr path.** Author the parent skill, phases, and the
   koto-backed single-pr execution path over the lifted template.
4. **/execute coordinated path.** Implement the plain durable-state loop over the
   merge-order DAG with `--merge-gate` gating.
5. **State, resume, exits.** Implement the `wip-yaml-md` projection, the home-PR
   resume lookup (I-6), and the three exit-path bindings.
6. **Backward-compat evals.** End-to-end evals: an existing single-pr PLAN through
   /execute; an existing multi-pr PLAN through the /work-on dispatcher; legacy
   four-column table parsing; the cross-skill koto-template path resolution.

## Security Considerations

- **Cross-skill koto-template path resolution.** /execute `koto init`-ing children
  against `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md` is a new
  load-bearing coupling; a misresolved path is a silent break. Mitigation: an
  end-to-end eval that asserts the resolved path and a guarded preflight check.
- **Inherited parent-skill security surfaces.** Slug re-validation on resume —
  including the slug recovered from the gh-fetched home pull request during the
  cross-branch resume lookup, not only on-disk glob matches; a closed write-target
  set; `execution_mode` enum re-validation before any path/branch interpolation, at
  both consumers (the /execute entry and the /work-on dispatcher, each an untrusted
  enum consumer); the unconditional, silent clear of any stale `parent_orchestration:`
  sentinel at session start; the visibility boundary (public skill); and no
  interpolation of untrusted PLAN-body content into emitted shell commands (PLAN
  content is data, not instructions).
- **Coordination-body re-authoring.** /execute re-authors the coordination body from
  live `gh` each loop, so the body's offline authoring checks apply on write, not
  only the merge-gate on read: the full `--coordination-body` validation surface
  (declaration marker, PR-Index, acyclic merge-order DAG) is re-run when /execute
  rewrites the body, never just the merge-gate.
- **Fail-closed done-signal.** The merge-gate recompute is fail-closed against live
  `gh`; a `gh` failure halts rather than falsely signaling done. `gh` auth is a
  precondition.
- **Finalization cascade safety.** The cascade is atomic and self-verifying (pre/post
  probes) so a partial finalization cannot silently leave the upstream chain
  inconsistent.

## Consequences

### Positive

- Completes the parent-skill trio at the implementation altitude; /work-on becomes a
  legible single-issue engine.
- Parity by construction: the proven orchestrator template is reused, not
  reimplemented.
- SE2-independent: on-PR durable state satisfies cross-branch resume in v1.
- Existing PLAN docs run unchanged; the dispatcher preserves /work-on PLAN
  invocations.

### Negative

- Two parent-layer execution paths (koto single-pr, plain coordinated) instead of one.
- A new cross-skill koto-template coupling with a silent-break failure mode.
- Coordinated crash-resume is not koto-backed in v1 (durable state is on the
  coordination PR, but there is no plan-spanning koto session).
- Coordinated cross-unit carry-forward rides on the coordination PR's durable state
  rather than a shared branch; its exact payload (what one unit records for the next)
  is specified at plan time, where single-pr inherits the shared-branch carry-forward
  verbatim from the lifted template.
- Coordinated-mode parity and autonomy are delivered honestly through the coordination
  contract plus per-child /work-on mechanisms and SKILL prose — a plain durable-state
  loop — not the koto state machine: so single-pr gets structural (state-machine)
  enforcement of the drift gate, skip-dependents, and autonomy, while coordinated
  relies on the coordination contract plus prose for the same behaviors. The unified
  cross-repo koto session that would give coordinated the same structural enforcement
  is the deferred amplifier-layer item.

### Mitigations / deferrals

- End-to-end evals and a preflight path check cover the cross-skill coupling.
- A unified plan-spanning koto session and koto-backed coordinated crash-resume defer
  to a later amplifier-layer substitution when a cross-repo koto session primitive
  exists; the substrate-substitution surface keeps this a swap, not a redesign.
