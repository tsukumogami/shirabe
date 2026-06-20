---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-execute-skill.md
milestone: "execute-skill"
issue_count: 7
---

# PLAN: execute-skill

## Status

Active

## Scope Summary

Stand up the new `/execute` implementation-altitude parent skill, extract the
plan-orchestration responsibility out of `/work-on` into it, and prove existing
PLAN docs keep running — delivered as one pull request.

## Decomposition Strategy

**Walking skeleton.** The design's load-bearing risk is the new cross-skill
coupling — `/execute` spawning `/work-on`'s `work-on.md` engine over a
`CLAUDE_PLUGIN_ROOT`-anchored path — and the two execution paths interact at runtime
through shared state and the lifted template. Issue 1 is a thin end-to-end slice that
runs a single-pr PLAN through `/execute` to a merged PR, forcing the cross-skill
template resolution and the delegation contract to work first. Every later issue
thickens one layer (dispatcher, cascade, coordinated path, state/resume, conformance,
evals) on top of a proven skeleton.

## Issue Outlines

### Issue 1: feat(execute): skeleton — run a single-pr PLAN end to end

**Goal**: A minimal `/execute` SKILL.md plus the lifted `work-on-plan` koto template
runs an existing single-pr PLAN to a single merged PR, delegating each issue to
`/work-on`'s `work-on.md` over the cross-skill path.

**Acceptance Criteria**:
- [x] `skills/execute/SKILL.md` exists with a single-pr execution path and the
  minimal parent-skill structural elements.
- [x] `skills/execute/koto-templates/execute.md` (lifted from `/work-on`) drives
  issues via per-issue `work-on.md` child sessions resolved at
  `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md`.
- [x] A preflight check asserts the cross-skill `work-on.md` path resolves before
  any child is spawned.
- [x] An existing single-pr PLAN doc runs end to end through `/execute` to one merged
  PR with no edit to the PLAN.

**Dependencies**: None

**Type**: docs
**Files**: `skills/execute/SKILL.md`, `skills/execute/koto-templates/execute.md`

### Issue 2: feat(work-on): narrow to single-issue + execution_mode dispatcher

**Goal**: Reduce `/work-on`'s PLAN input to a thin `execution_mode` dispatcher and
remove the plan-orchestrator, leaving `/work-on` a single-issue engine.

**Acceptance Criteria**:
- [x] `/work-on <PLAN>` reads `execution_mode` and routes: multi-pr in place per
  issue; single-pr and coordinated handed off to `/execute`.
- [x] `/work-on` no longer contains the plan-orchestrator; a single-issue invocation
  behaves exactly as before.
- [x] `execution_mode` is enum-re-validated in the dispatcher before any path or
  branch interpolation.
- [x] `/work-on`'s existing PLAN-detection evals are repointed to the dispatcher
  behavior and pass.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `skills/work-on/SKILL.md`

### Issue 3: feat(execute): extract finalization cascade + escape hatch

**Goal**: Move `run-cascade.sh` and the `WORK_ON_ALLOW_UNTRACKED_ACS` allowance into
`/execute` and wire the atomic finalization cascade into the single-pr path.

**Acceptance Criteria**:
- [x] `skills/execute/scripts/run-cascade.sh` performs the atomic upstream-lifecycle
  cascade (PLAN delete + BRIEF/PRD/DESIGN/ROADMAP transitions) with pre/post probes.
- [x] The `WORK_ON_ALLOW_UNTRACKED_ACS` escape hatch is relocated with the script and
  still works.
- [x] single-pr completion runs the cascade before the PR flips to ready
  (DRAFT-before-READY).

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/execute/scripts/run-cascade.sh`

### Issue 4: feat(execute): coordinated track-to-merge-last loop

**Goal**: Implement `/execute`'s plain durable-state loop over the coordination PR's
merge-order DAG, gated on `shirabe validate --merge-gate`.

**Acceptance Criteria**:
- [x] On `execution_mode: coordinated`, `/execute` refreshes coordination state from
  live `gh`, walks the merge-order DAG of PR nodes and gate nodes, dispatches each
  unblocked PR node to `work-on.md` per repo, and resolves each gate node before its
  dependents advance.
- [x] The done-signal is gated on `shirabe validate --merge-gate --mode=ready`
  (fail-closed: a `gh` failure halts, never falsely signals done).
- [x] The coordination body is re-authored from live `gh` each loop, re-running the
  full `--coordination-body` validation on write.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `skills/execute/SKILL.md`, `skills/execute/koto-templates/execute.md`

### Issue 5: feat(execute): state projection, cross-branch resume, exit paths

**Goal**: Implement the `wip-yaml-md` state projection, the on-home-PR durable resume
lookup (I-6), and the three exit-path bindings.

**Acceptance Criteria**:
- [x] `wip/execute_<topic>_state.md` carries the five-field schema, `child_snapshots:`,
  and the `parent_orchestration:` sentinel.
- [x] The resume ladder does a topic-keyed home-PR lookup via `gh` before declaring
  "no state → fresh chain," so a resume on a different branch continues the run.
- [x] The three exit names bind: full-run = merged-PR done-signal; abandonment-forced
  = forced stop leaving an abandonment-marked PR and a frozen PLAN; re-evaluation =
  an upstream-must-change Decision Record with no re-execution.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `skills/execute/SKILL.md`

### Issue 6: feat(execute): parent-skill conformance + security surfaces

**Goal**: Bind the seven SKILL.md structural elements, metadata-only child inspection,
and the six security surfaces.

**Acceptance Criteria**:
- [x] `/execute` SKILL.md has the seven required structural elements and inspects
  issue/PR/unit state only through status surfaces (no child-body reads).
- [x] The six security surfaces are bound: slug re-validation including the
  `gh`-recovered home-PR slug; a closed write-target set; `execution_mode`
  re-validation at both `/execute` and the `/work-on` dispatcher; the unconditional
  silent `parent_orchestration:` clear; the visibility boundary; and no interpolation
  of untrusted PLAN-body content into emitted shell.
- [x] `shirabe validate` passes the parent-skill conformance checks (state schema,
  resume ladder, exit names, security surfaces).
- [x] The autonomy mandate is bound in the SKILL prose and the orchestrator-loop
  directives: an authorized autonomous run drives to the done-signal or a genuine
  blocker without checkpoint/reassurance stops (PRD R18/R19).

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:5>>

**Type**: docs
**Files**: `skills/execute/SKILL.md`

### Issue 7: test(execute): backward-compatibility end-to-end evals

**Goal**: Prove existing PLAN docs keep working and the cross-skill coupling holds.

**Acceptance Criteria**:
- [x] An eval runs an existing single-pr PLAN through `/execute` to a merged PR
  unchanged.
- [x] An eval runs an existing multi-pr PLAN through the `/work-on` dispatcher one
  issue at a time, unchanged.
- [x] An eval parses a legacy four-column Implementation Issues table.
- [x] An eval asserts the cross-skill `work-on.md` path resolves (the preflight from
  Issue 1).
- [x] Parity-survival evals assert each capability carried over by the lifted template
  still fires under `/execute`: the drift gate halts on an intent-changing base-branch
  change and absorbs a non-intent-changing one; cross-issue carry-forward is
  observable across two issues of a single-pr plan; a failed issue skips its
  dependents; and the finalization cascade runs atomically.
- [x] A coordinated-mode eval asserts cross-unit carry-forward through the coordination
  PR's durable state (the coordinated payload, which is not inherited from the
  single-pr shared-branch path).

**Dependencies**: Blocked by <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:4>>, <<ISSUE:5>>, <<ISSUE:6>>

**Type**: task
**Files**: `skills/execute/evals/`

## Dependency Graph

## Implementation Sequence

- **Critical path:** Issue 1 (skeleton) → Issue 5 (state/resume) → Issue 6
  (conformance/security) → Issue 7 (evals).
- **Parallelizable after Issue 1:** Issues 2, 3, 4, and 5 are independent thickening
  layers and can proceed in parallel once the skeleton lands.
- **Integration last:** Issue 7 depends on every thickening layer; it is the
  backward-compatibility gate that proves no existing PLAN regressed.
