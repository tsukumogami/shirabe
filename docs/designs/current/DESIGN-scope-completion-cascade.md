---
schema: design/v1
status: Current
upstream: docs/prds/PRD-scope-completion-cascade.md
problem: |
  The completion cascade walks a finished PLAN's upstream chain and transitions
  each node to its terminal status, dispatching on filename prefix. It has no
  case for a BRIEF. Since /scope produces chains shaped BRIEF -> PRD -> DESIGN ->
  PLAN, a BRIEF now sits as the PRD's upstream. When the walk reaches it, the
  prefix matches none of DESIGN, PRD, ROADMAP, or VISION, so it hits the dispatch
  catchall and fails with "unrecognized filename prefix." The walk stops, the
  BRIEF never reaches Done, and the ROADMAP above it is never finalized. Every
  /scope-produced chain — the default shape — is affected.
decision: |
  Add a handle_brief helper to run-cascade.sh that mirrors handle_prd: log the
  transition, call shirabe transition <path> Done, record a failed step on
  non-zero exit or stage the file and record an ok transition_brief step on
  success. Add a BRIEF-* branch to both case statements — the main dispatch
  (which routes to handle_brief, sets current_doc, and continues the walk) and
  the validation-error case (which derives artifact_type "BRIEF", target_status
  "Done"). A BRIEF transitions in place with no directory move, so the handler
  carries no move-path state. The BRIEF's own `upstream` is optional: the loop's
  existing empty-string guard ends the walk cleanly when it's absent and
  continues to the ROADMAP when it's present, so the branch needs no end-of-chain
  logic. Cover both shapes with paired test scenarios.
rationale: |
  A BRIEF transitions in place to a terminal Done with no directory move, which
  is exactly the PRD handler's shape; mirroring handle_prd reuses a proven path
  rather than inventing one. The change is purely additive — one new helper and
  one new branch in each of the two existing case statements — so no existing
  handler, the PLAN deletion, or the JSON step shape is touched. The strategic
  cascade stays out of scope because a STRATEGY artifact is durable and has no
  PLAN-style completion trigger to extend.
---

# DESIGN: scope-completion-cascade

## Status

Current

## Upstream Design Reference

This design implements [PRD-scope-completion-cascade.md](../prds/PRD-scope-completion-cascade.md),
which is framed by [BRIEF-scope-completion-cascade.md](../briefs/BRIEF-scope-completion-cascade.md).

## Context and Problem Statement

`skills/work-on/scripts/run-cascade.sh` finalizes a finished PLAN's chain. It
deletes the PLAN and walks the `upstream` chain, transitioning each node to its
terminal status: DESIGN to Current, PRD to Done, ROADMAP to Done. The walk
dispatches on each node's filename prefix.

Two case statements switch on that prefix. The main dispatch routes each node to
a handler function; a parallel prefix match in the validation-error path derives
an `artifact_type` and `target_status` for error messages. Neither lists
`BRIEF-*`.

Since `/scope` started producing chains shaped BRIEF -> PRD -> DESIGN -> PLAN, a
BRIEF now sits as the PRD's upstream. When the walk reaches it, the prefix
matches none of the known cases, so it hits the dispatch catchall and fails with
"upstream field ... references ..., which has an unrecognized filename prefix."
The walk stops there. The BRIEF stays in a non-terminal status, the cascade
reports a failure, and any ROADMAP above the BRIEF is never reached. A BRIEF's
`upstream` is optional — it may point at a ROADMAP or be absent — but the
catchall fails either way, before the loop ever gets to read it.

A BRIEF's lifecycle is Draft -> Accepted -> Done with Done terminal, and it
never moves directories. That makes it parallel to a PRD, not a DESIGN.
`shirabe transition` already supports the BRIEF type and emits the same base
result shape a PRD does (`{success, doc_path, old_status, new_status}`, no
`new_path`). The gap is only the missing dispatch.

## Decision Drivers

- Close the gap with the smallest change: one handler plus one branch in each of
  the two existing case statements.
- Leave existing node behavior (DESIGN, PRD, ROADMAP, VISION, PLAN deletion)
  byte-for-byte unchanged.
- Keep the JSON step output shape identical — the BRIEF step is one more step of
  the existing `add_step` form, not a new shape.
- Match the cascade's existing failure semantics so a BRIEF transition failure
  surfaces rather than being swallowed.

## Considered Options

### Decision 1: How the BRIEF handler is shaped

The cascade has two existing handler templates. `handle_design` transitions to
Current and threads a possibly-changed path through a `HANDLE_DESIGN_NEW_PATH`
global because a DESIGN moves directories on transition. `handle_prd` transitions
to Done in place and carries no move-path state. A BRIEF transitions in place to
a terminal Done and never moves, so the question is which template it mirrors.

#### Chosen: Mirror handle_prd

Add `handle_brief(path, found_in)` that follows `handle_prd` exactly:

1. `log_info "Transitioning BRIEF: $path → Done"`.
2. Run `result=$("$SHIRABE_BIN" transition "$path" Done 2>&1)`. On non-zero exit,
   set `ANY_FAILED=true` and `add_step "transition_brief" "$path" "$found_in"
   "failed"` with the first line of the error, then `return 1`.
3. On success, `git add "$path"`, append to `STAGED_FILES`, and
   `add_step "transition_brief" "$path" "$found_in" "ok" ""`.

The handler carries no move-path state because a BRIEF does not move. In the
main dispatch, the `BRIEF-*` branch calls `handle_brief`, sets
`current_doc="$next_path"`, and falls through so the loop reads the BRIEF's
`upstream` and continues — exactly like the `PRD-*` branch.

A BRIEF's `upstream` field is optional. The brief format makes it so: a BRIEF is
the head of the tactical chain, and many are authored without an upstream
ROADMAP, so the field is frequently absent. The walk loop already handles that.
After `handle_brief` sets `current_doc` to the BRIEF, the loop reads its
`upstream` into `current_upstream`; when the field is absent that read yields an
empty string and the existing `while [[ -n "$current_upstream" ]]` guard exits
the loop cleanly. So the BRIEF branch needs no special end-of-chain logic:

- BRIEF **with** an `upstream` ROADMAP — the walk reads it and `handle_roadmap`
  runs and terminates the chain, as it already does for a PRD's upstream.
- BRIEF **without** an `upstream` — the loop's empty-string guard ends the walk
  at the BRIEF. The BRIEF has reached Done; with no further node to reach the
  cascade finalizes `completed`. This is not a failure path; it is the head of
  the chain settling.

Both outcomes are correct finalizations. The `PRD-*` branch relies on the same
guard — it just never hit the absent-upstream case because a PRD's upstream is
required.

#### Alternatives Considered

**Mirror handle_design.** Use the DESIGN template and set
`HANDLE_DESIGN_NEW_PATH`. Rejected: a BRIEF never moves directories, so the
move-path machinery is dead weight and `shirabe transition` on a BRIEF returns no
`new_path` to consume. It would add state the handler can never use.

**A generic in-place transition helper shared by PRD and BRIEF.** Refactor
`handle_prd` and `handle_brief` into one parameterized function. Rejected:
that edits an existing, working handler, which violates the additive constraint
and widens the blast radius for a one-case change. A separate helper keeps the
change purely additive.

## Decision Outcome

**Chosen: Decision 1 — mirror handle_prd.**

### Summary

Three edits to `run-cascade.sh`, all additive:

1. A new `handle_brief` helper placed beside `handle_prd`, identical in shape:
   it logs the transition, calls `shirabe transition <path> Done`, records a
   `failed` step with the error detail on non-zero exit (setting
   `ANY_FAILED=true`), and otherwise stages the file and records an ok
   `transition_brief` step. No move-path state.

2. A `BRIEF-*)` branch in the main dispatch case (after the `PRD-*)` branch)
   that calls `handle_brief "$next_path" "$found_in" || true`, sets
   `current_doc="$next_path"`, and does not `break`. The walk then reads the
   BRIEF's `upstream` field — a ROADMAP — and the existing `handle_roadmap`
   runs and terminates the chain as it already does.

3. A `BRIEF-*)` branch in the validation-error case (alongside DESIGN/PRD/
   ROADMAP) that sets `artifact_type="BRIEF"` and `target_status="Done"`, and a
   matching `BRIEF-*)` entry in that block's `add_step` switch recording
   `transition_brief`. A BRIEF node no longer falls to the catchall, so a missing
   or untracked BRIEF produces a precise error instead of "unrecognized."

A paired test scenario in `run-cascade_test.sh` adds a chain with a BRIEF and
asserts the BRIEF transitions and the walk continues. The error message text
that lists recognized prefixes can be left as-is or extended to mention BRIEF-*;
the functional fix is the dispatch and validation-error branches.

### Rationale

The PRD path is the right template because a BRIEF shares the PRD's exact
transition profile: in-place, terminal Done, base result shape. Reusing that
shape means no new failure handling, no new JSON fields, and no new path
bookkeeping. Keeping `handle_brief` separate rather than refactoring `handle_prd`
keeps every existing line untouched, so the only behavioral delta is that a
BRIEF node — previously a hard failure — now transitions and the walk proceeds.

## Solution Architecture

The walk loop is unchanged in structure. Per node it: validates the upstream
path (validation-error case), then dispatches on prefix (main dispatch case).
The BRIEF additions slot into both.

```
walk node:
  validate_upstream_path(next_path)
    ok      -> main dispatch
    not ok  -> validation-error case (now resolves BRIEF-* -> "BRIEF"/"Done")

  main dispatch on basename(next_path):
    DESIGN-*   -> handle_design   ; continue (existing)
    PRD-*      -> handle_prd       ; continue (existing)
    BRIEF-*    -> handle_brief     ; current_doc=next_path ; continue (NEW)
    ROADMAP-*  -> handle_roadmap   ; break    (existing)
    VISION-*   -> no action        ; break    (existing)
    *          -> failed catchall  ; break    (existing, now unreached by BRIEF)

  end of loop body:
    current_upstream = upstream(current_doc)   # empty if BRIEF has no upstream
  loop guard: while current_upstream is non-empty   # empty -> walk ends cleanly
```

For a BRIEF -> PRD -> DESIGN -> PLAN chain whose BRIEF points at a ROADMAP: the
PLAN is deleted, the walk hits DESIGN (to Current, moves), then PRD (to Done, in
place), then BRIEF (to Done, in place via `handle_brief`), then reads the BRIEF's
`upstream` ROADMAP and runs `handle_roadmap`, which terminates. One run, no
manual cleanup.

When the BRIEF has no `upstream` — the common shape, since the field is optional
— the walk transitions the BRIEF to Done and then the loop's empty-upstream guard
ends the walk at the BRIEF. There is no ROADMAP above it to reach, the cascade
finalizes `completed`, and nothing errors. The `BRIEF-*` branch is identical in
both cases; only what the loop reads next differs.

## Implementation Approach

1. Add `handle_brief` next to `handle_prd` in `run-cascade.sh`, copying its body
   and substituting "BRIEF" in the log line and `transition_brief` in both
   `add_step` calls. Keep `Done` as the target status.
2. Add the `BRIEF-*)` branch to the main dispatch case (after `PRD-*)`):
   `handle_brief "$next_path" "$found_in" || true` then
   `current_doc="$next_path"`. No `break`. The loop then reads the BRIEF's
   `upstream` at line 623; if it's present the walk continues to the ROADMAP, and
   if it's absent the empty-string loop guard ends the walk. No extra logic is
   needed for the absent case.
3. Add the `BRIEF-*)` branches to the validation-error case: one in the
   artifact_type/target_status switch (`"BRIEF"` / `"Done"`) and one in the
   `add_step` switch (`transition_brief`).
4. In `run-cascade_test.sh`, add a `write_brief` fixture helper that takes an
   optional `upstream` argument (no move; in-place status rewrite). When the
   argument is given it writes an `upstream:` frontmatter line; when it is empty
   it omits the field entirely, so the fixture can produce both a BRIEF that
   points at a ROADMAP and one that doesn't — matching the optional field in the
   real format. Add a `BRIEF-*)` case to the `shirabe` stub that rewrites status
   and emits the base result shape (no `new_path`), parallel to the stub's
   `PRD-*)` case.
5. Add two scenarios, committed like the other fixtures:
   - A chain through a BRIEF that carries an upstream ROADMAP
     (PLAN -> ... -> BRIEF -> ROADMAP). Assert via `assert_json` that the
     `transition_brief` step exists with status `"ok"` and that the walk reaches
     the upstream ROADMAP (the `update_roadmap_feature` step is present).
   - A chain through a BRIEF with no upstream (PLAN -> ... -> BRIEF). Assert the
     `transition_brief` step exists with status `"ok"`, that the walk ends at the
     BRIEF with no catchall failure, and that `cascade_status` is `completed`.
     This is the scenario that would catch a regression where an absent BRIEF
     upstream is mishandled.
   Existing scenarios stay unchanged and still pass.

## Security Considerations

- **Download verification**: Not applicable. This change only adds a shell
  dispatch case and a test; it downloads and verifies nothing.
- **Execution isolation**: Not applicable beyond the existing surface.
  `handle_brief` invokes the same `shirabe transition` subprocess the PRD and
  DESIGN handlers already invoke, with no new external input or elevated
  permission. The BRIEF path comes from the chain walk, identical to other nodes.
- **Supply chain risks**: Not applicable. No new dependency, binary, or recipe
  source is introduced.
- **User data exposure**: Not applicable. The handler reads and rewrites a
  local doc's status and stages it for commit, the same data flow the existing
  handlers use. Nothing is transmitted.

## Boundary

- **BRIEF is a non-moving graph type.** Its lifecycle is Draft -> Accepted ->
  Done with Done terminal and no directory move, so `handle_brief` mirrors
  `handle_prd` (in place) rather than `handle_design` (with move). It carries no
  move-path state.
- **The change is additive.** It adds one helper and one branch in each of the
  two existing case statements. No existing handler is altered: DESIGN still
  transitions to Current with its move, PRD to Done, ROADMAP to Done with a walk
  break, VISION still breaks with no action, and PLAN deletion is untouched. The
  JSON step output keeps the existing `add_step` shape; the BRIEF step is one
  more step of that form.
- **The strategic `/charter` cascade is out of scope.** A STRATEGY artifact is
  durable and has no discrete PLAN-style completion trigger, so there is no
  terminal cascade to extend for it.

## Consequences

**Positive:**

- Every `/scope`-produced chain finalizes in one cascade run; no BRIEF is left
  in a non-terminal status. When the BRIEF carries an upstream ROADMAP the walk
  reaches it; when the BRIEF has no upstream — the common case, since the field
  is optional — the walk ends cleanly at the BRIEF with `completed`, not a
  failure.
- A BRIEF transition failure surfaces as a `failed` step with the transition
  error, matching the PRD handler's failure path, rather than being swallowed.
- Validation errors on a BRIEF node now read precisely ("BRIEF" / "Done")
  instead of "unrecognized filename prefix."

**Negative / trade-offs:**

- `handle_brief` duplicates `handle_prd`'s body rather than sharing a helper. We
  accept the duplication to keep the change additive and the existing PRD path
  untouched; a future refactor could unify the two in-place handlers if a third
  in-place type appears.
