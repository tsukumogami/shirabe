# Lead: minimal exit path for pre-implemented work

## Findings

### 1. The `analysis` state today

The `analysis` state in `work-on.md` accepts a `plan_outcome` enum with four values:

```
values: [plan_ready, blocked_missing_context, scope_changed_retry, scope_changed_escalate]
```

It has no path for "work is already done." Its only transitions are:
- `plan_ready` → `implementation` (requires `plan_artifact.exists: true`)
- `scope_changed_retry` → self-loop back to `analysis`
- `scope_changed_escalate` → `done_blocked`
- `blocked_missing_context` → `done_blocked`

There is no transition to any terminal state representing successful early exit. Neither the koto template nor the phase-3 reference documents (`references/phases/phase-3-analysis.md`, `references/agent-instructions/phase-3-analysis.md`) give any guidance on what to do when all acceptance criteria are already satisfied by prior commits.

### 2. Terminal state anatomy

The template has three terminal states:

**`done`** — clean success, `terminal: true` with no `failure:` flag. Reached only from `ci_monitor`.

**`done_blocked`** — failure terminal, `terminal: true`, `failure: true`. Reached from many states when something goes wrong. Has `accepts.failure_reason` which is populated via `context_assignments` on incoming transitions.

**`skipped_due_to_dep_failure`** — special-purpose terminal, `terminal: true`, `skipped_marker: true`. No `failure:` flag. Reached from `entry` when `mode: skipped`. Has no `accepts` fields at all — it records a bypass, not an outcome.

`skipped_marker: true` is the notable attribute: it signals to the parent orchestrator that this child was intentionally bypassed, not that it failed. This is distinct from `failure: true`.

### 3. How the parent orchestrator reads child outcomes

In `work-on-plan.md`, `spawn_and_await` uses a `children-complete` gate:

```yaml
gates:
  batch_done:
    type: children-complete
```

The transition to `pr_finalization` requires:
- `batch_outcome: all_success`
- `gates.batch_done.all_complete: true`

The transition to `escalate` requires:
- `batch_outcome: needs_attention`
- `gates.batch_done.all_complete: true`

The orchestrator skill (`SKILL.md`) instructs the agent to set `batch_outcome: all_success` when "all children reached a non-failure terminal state" and `batch_outcome: needs_attention` when "any children reached `done_blocked` or were skipped."

The critical phrase is **"non-failure terminal state."** `done` qualifies. `skipped_due_to_dep_failure` is a non-failure terminal (no `failure: true`) with `skipped_marker: true`, but the skill's instructions treat skipped children as `needs_attention`. There is no explicit documentation on how a hypothetical `done_already_complete` state (no `failure:`, no `skipped_marker:`) would be treated — but by the existing logic, a terminal state with no `failure: true` would be a successful outcome.

The `batch_final_view` context key (read during `pr_finalization` and `escalate`) carries `outcome` fields per child. The values used in the skill are `success`, `failure`, and `skipped`. A new non-failure terminal with no `skipped_marker` would presumably map to `success` in `batch_final_view`, though this is inferred from koto behavior rather than stated explicitly in the template.

### 4. What would `analysis → done_already_complete` require

**Changes to `work-on.md`:**

1. A new enum value in `plan_outcome` within the `analysis` state's `accepts` block:
   ```yaml
   values: [plan_ready, blocked_missing_context, scope_changed_retry, scope_changed_escalate, already_complete]
   ```

2. A new transition from `analysis`:
   ```yaml
   - target: done_already_complete
     when:
       plan_outcome: already_complete
   ```

3. A new terminal state:
   ```yaml
   done_already_complete:
     terminal: true
   ```
   No `failure: true`, no `skipped_marker: true` — this makes it a clean success terminal analogous to `done`.

**No koto engine changes required** for the core path: adding a new enum value to `accepts`, a new transition, and a new terminal state are all purely template-level changes. Koto already supports multiple non-failure terminals (e.g., `done`, `validation_exit`) and custom terminal states with varying markers.

The `already_complete` path could optionally carry context assignments to explain *why* the workflow exited early, similar to how `done_blocked` populates `failure_reason`. For example:
```yaml
- target: done_already_complete
  when:
    plan_outcome: already_complete
  context_assignments:
    completion_note: "AC already satisfied: ${evidence.approach_summary}"
```

This would make the early exit visible in `batch_final_view` without requiring new koto gate features.

**Possible koto feature consideration**: whether koto's `batch_final_view` surfaces a custom `completion_note` alongside the standard `outcome`/`reason` fields is unknown. If not, the note would be stored in context but not automatically propagated to the PR finalization table. This may be acceptable — the important thing is that `batch_outcome: all_success` is set correctly by the parent.

### 5. SKILL.md guidance on pre-completed work

The `analysis` directive in `SKILL.md` (the prose section at the bottom of `work-on.md`) says:

> Self-loop with `scope_changed_retry` (up to 3 times). After 3, use `scope_changed_escalate`. Submit `blocked_missing_context` if stuck.

The `references/phases/phase-3-analysis.md` document lists four evidence options but says nothing about detecting that work is already done.

The `references/agent-instructions/phase-3-analysis.md` agent instruction document has no guidance about pre-implemented work. Step 4 ("Design Solution") describes exploring approaches, step 5 ("Create Plan") describes writing a plan. There is no branch for "work is already complete — write no plan, exit early."

In summary: no existing documentation covers this scenario.

### 6. The `plan_artifact` gate dependency

The `analysis → implementation` transition has a hard gate dependency:

```yaml
- target: implementation
  when:
    plan_outcome: plan_ready
    gates.plan_artifact.exists: true
```

This gate checks for `context key: plan.md`. The `done_already_complete` transition would not check this gate — no plan artifact is needed for a clean early exit. This is appropriate and consistent with how `done_blocked` transitions work (they also bypass the plan gate).

## Implications

1. The change is **purely a shirabe template change** to `work-on.md`. No koto engine feature is needed. The existing terminal state model already handles non-failure terminals cleanly.

2. The parent orchestrator's `batch_outcome` logic in `SKILL.md` would count `done_already_complete` as a success ("non-failure terminal state") without modification, since it has no `failure: true` flag. However, the skill instructions would benefit from an explicit note clarifying this, since agents currently interpret `batch_outcome` from the set `{all_success, needs_attention}`.

3. The `analysis` phase instruction documents (`phase-3-analysis.md` and `agent-instructions/phase-3-analysis.md`) would need corresponding updates to describe how to detect pre-implemented work and what evidence to submit.

4. `pr_finalization` reads `batch_final_view` to build the PR description table. If `done_already_complete` children appear with `outcome: success`, the table will show them as successes — which is correct. The PR description may want a note distinguishing "implemented this session" from "already done," but that's cosmetic.

## Surprises

- `skipped_due_to_dep_failure` has no `accepts` block at all. It receives no evidence submission — the transition from `entry` carries the entire semantics. A `done_already_complete` state would differ from this pattern: the transition from `analysis` would carry the evidence (via `context_assignments`), and the terminal state itself is just a landing node.

- The `validation_exit` terminal (from free-form task validation) also has no `failure: true` and no `skipped_marker: true`. It's a clean exit that currently appears unreachable from plan-backed mode. This is a precedent for "clean exit before implementation" as a terminal pattern, but it's not wired into the batch machinery — it's only used in standalone (non-plan-backed) mode.

- Nothing in the `analysis` state directive or agent instructions says "check whether the work is already done." An agent following today's instructions would always produce a `plan.md` and submit `plan_ready`, even when analysis reveals all AC are satisfied. The bug is in the instructions, not just the state machine.

## Open Questions

1. Does koto's `batch_final_view` surface a custom context key like `completion_note` alongside standard `outcome`/`reason` fields, or only the built-in fields? This affects whether the PR description table can distinguish "already complete" from "implemented this session."

2. Should `done_already_complete` require a context artifact (e.g., `completion_note.md`) as a gate, analogous to how `done` requires CI to pass? Or is an evidence field sufficient?

3. Should the parent orchestrator's `batch_outcome` logic explicitly name `done_already_complete` as a success-equivalent state, or is the current "non-failure terminal" heuristic sufficient and safe?

4. Should `done_already_complete` skip the `pr_creation` step entirely, or is there a case where pre-implemented work still needs a PR (e.g., commits exist that haven't been pushed)?

5. Is there a middle ground where the analysis state produces a lightweight "verification plan" (just the AC check steps) rather than a full implementation plan, before exiting? This would preserve the plan artifact gate and keep the state machine simpler, at the cost of still writing a context artifact.

## Summary

The `analysis` state currently has no path for pre-implemented work: its `plan_outcome` enum has no `already_complete` value, and neither the koto template nor any reference document gives the analysis agent guidance on detecting this case. Adding `analysis → done_already_complete` requires only a shirabe template change to `work-on.md` — a new enum value in `plan_outcome`, a new transition, and a new `terminal: true` state with no `failure:` flag — which koto's existing terminal state model handles without any engine changes. The parent orchestrator's `batch_outcome: all_success` logic would count this state correctly as a success because it has no `failure: true`, though the skill instructions and analysis phase documents would also need updates to tell agents when and how to submit `already_complete` evidence.
