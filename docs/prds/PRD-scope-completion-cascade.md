---
schema: prd/v1
status: Done
problem: |
  The completion cascade walks a finished PLAN's upstream chain and transitions
  each node to its terminal status, but it has no handler for a BRIEF node. Since
  /scope produces chains shaped BRIEF -> PRD -> DESIGN -> PLAN, the cascade now
  hits a BRIEF as the PRD's upstream, fails with "unrecognized filename prefix,"
  and stops. The BRIEF never reaches Done and the ROADMAP above it is never
  reached.
goals: |
  Add a BRIEF handler to the completion cascade so a chain whose walk passes
  through a BRIEF finalizes cleanly: the BRIEF transitions to Done in place, the
  step is recorded like the others, and the walk continues to the upstream
  ROADMAP. Existing DESIGN, PRD, ROADMAP, and PLAN behavior is unchanged.
upstream: docs/briefs/BRIEF-scope-completion-cascade.md
---

# PRD: scope-completion-cascade

## Status

Done

## Problem Statement

The completion cascade (`skills/work-on/scripts/run-cascade.sh`) deletes a
finished PLAN and walks its `upstream` chain, transitioning each node to its
terminal status: DESIGN to Current, PRD to Done, ROADMAP to Done. The walk
dispatches on each node's filename prefix.

There is no case for a BRIEF. `run-cascade.sh` has two case statements that
switch on the node prefix — a main dispatch that routes to a handler function,
and a parallel prefix match that builds error messaging — and neither lists
`BRIEF-*`. Since `/scope` started producing chains shaped BRIEF -> PRD ->
DESIGN -> PLAN, a BRIEF now sits as the PRD's upstream. When the walk reaches
it, the prefix matches neither DESIGN, PRD, ROADMAP, nor VISION, so it hits the
dispatch catchall and fails with "unrecognized filename prefix." The walk stops
there.

The effect is that every `/scope`-produced chain — the default shape — can never
fully finalize. The BRIEF stays in a non-terminal status, the cascade reports a
failure, and the ROADMAP above the BRIEF is never reached.

A BRIEF transitions in place with no directory move (Draft -> Accepted -> Done,
terminal Done), so it parallels the existing PRD handler rather than the DESIGN
handler. `shirabe transition` already supports the BRIEF type and emits the same
base result shape PRD does.

## Goals

- A finished PLAN whose chain runs through a BRIEF cascades cleanly to
  completion, with the BRIEF transitioning to Done alongside DESIGN and PRD.
- The walk continues past the BRIEF to its upstream ROADMAP rather than stopping
  with an error.
- The change is the smallest one that closes the gap: a BRIEF dispatch case, a
  BRIEF entry in the error-messaging case, and a paired test. Existing node
  behavior is untouched.

## User Stories

- As a skill author, I finish implementing a PLAN that `/scope` produced from a
  BRIEF -> PRD -> DESIGN -> PLAN chain, the cascade fires, and the whole chain
  finalizes in one run with no manual cleanup of the BRIEF.
- As a skill author, my cascade reaches the BRIEF node and transitions it to
  Done — its terminal status, with no directory move — and the completion
  summary shows that transition as a successful step beside the DESIGN and PRD
  ones.
- As a skill author, the walk reads the BRIEF's upstream field and continues to
  the ROADMAP, so the chain settles end to end instead of dying on an
  "unrecognized filename prefix" error.

## Requirements

**R1 — BRIEF dispatch handler.** The main dispatch case in `run-cascade.sh`
gains a `BRIEF-*` branch that routes to a handler transitioning the BRIEF to
Done. The handler mirrors the existing PRD handler's shape: log the transition,
call `shirabe transition <path> Done`, on failure mark the run failed and record
a failed step with the error detail, on success stage the file and record an
ok step. The BRIEF does not move directories, so the handler does not set or
consume any move-path state.

**R2 — Transition the BRIEF to Done.** The handler calls
`"$SHIRABE_BIN" transition "$path" Done` and treats a non-zero exit as a failed
step (matching the PRD handler's error path), so a transition failure surfaces
in the cascade output rather than being swallowed.

**R3 — Continue the walk to the BRIEF's upstream.** After a successful BRIEF
transition, the walk reads the BRIEF's `upstream` field and continues, reaching
the upstream ROADMAP. The BRIEF is not terminal for the walk; it does not
`break` the chain the way ROADMAP and VISION do.

**R4 — Recognize BRIEF in the error-messaging case.** The parallel prefix-match
case that derives `artifact_type` and `target_status` for error messages gains a
`BRIEF-*` branch (artifact_type "BRIEF", target_status "Done"), so a BRIEF node
no longer falls to the catchall and is no longer described as "unrecognized."

**R5 — Consistent JSON step output.** The BRIEF handler records its step through
the existing `add_step` call with the same field shape the DESIGN and PRD steps
use (step name, path, found-in source, status, detail). The step name
identifies the BRIEF transition (for example `transition_brief`). No new output
field or shape is introduced.

**R6 — Paired test.** `run-cascade_test.sh` gains a scenario whose chain runs
through a BRIEF (for example PLAN -> ... -> BRIEF -> ROADMAP), following the
existing scenarios. It adds a BRIEF fixture helper and a `BRIEF-*` case to the
`shirabe` stub that rewrites status in place and emits the base result shape (no
`new_path`), parallel to the stub's PRD case. The scenario asserts the BRIEF
transition step exists with status "ok" and that the walk continues to the
upstream node.

## Acceptance Criteria

- [ ] A cascade run over a chain containing a BRIEF transitions the BRIEF to Done,
  records a `transition_brief` (or equivalently named) step with status "ok", and
  continues the walk to the BRIEF's upstream ROADMAP without erroring.
- [ ] The error-messaging case resolves a BRIEF node to artifact_type "BRIEF" and
  target_status "Done"; a BRIEF node no longer triggers the "unrecognized
  filename prefix" failure.
- [ ] A failed `shirabe transition` on the BRIEF marks the run failed and records a
  failed step carrying the transition error, matching the PRD handler's failure
  path.
- [ ] The BRIEF step's JSON matches the existing `add_step` shape; no new field is
  added and the DESIGN, PRD, and ROADMAP step shapes are unchanged.
- [ ] The new test scenario passes, and the existing scenarios still pass.

## Must preserve

- DESIGN transitions to Current (with its directory move), PRD transitions to
  Done, and ROADMAP transitions to Done and terminates the walk — all unchanged.
- PLAN deletion is unchanged.
- The cascade's JSON step output keeps the existing `add_step` shape; the BRIEF
  step is one more step of the same form, not a new shape.

## Out of Scope

- The strategic-chain cascade. A STRATEGY artifact is durable and has no discrete
  PLAN-style completion trigger, so there is no terminal cascade to extend for it.
- Any change to how DESIGN, PRD, ROADMAP, or PLAN nodes transition, move, or
  terminate the walk. This work adds the missing BRIEF case only.
- Changes to the BRIEF lifecycle itself or to `shirabe transition`, which already
  supports the BRIEF type.

## Related

- Upstream framing: `docs/briefs/BRIEF-scope-completion-cascade.md`.
- Cascade script with the handler gap: `skills/work-on/scripts/run-cascade.sh`.
- Paired cascade test harness: `skills/work-on/scripts/run-cascade_test.sh`.
- BRIEF lifecycle and terminal status: `crates/shirabe-validate/src/transition.rs`.
