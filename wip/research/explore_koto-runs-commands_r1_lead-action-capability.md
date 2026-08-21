# Lead: What does koto's `default_action` actually support today, and what did the design promise that the code does not deliver?

## Findings

### 1. Schema an author writes (source YAML frontmatter)

Parsed by `SourceState` / `SourceActionDecl` in `src/template/compile.rs:49-95` (`#[serde(deny_unknown_fields)]` on `SourceState`, so typos in these keys fail compilation, `src/template/compile.rs:44-46`).

```yaml
states:
  <state_name>:
    default_action:
      command: "<shell command, sh -c>"        # required, non-empty
      working_dir: "<path>"                     # optional, default: session's current_dir
      requires_confirmation: <bool>              # optional, default: false
      polling:                                   # optional; presence = polling mode
        interval_secs: <u32>
        timeout_secs: <u32>                      # required > 0 if polling present
```

Field-by-field, `SourceActionDecl` (`src/template/compile.rs:86-95`) → compiled `ActionDecl` (`src/template/types.rs:199-207`):

| Field | Type | Required | Default | Effect |
|---|---|---|---|---|
| `command` | `String` | yes (non-empty enforced) | — | Run via `sh -c` after `{{VAR}}` substitution (`src/cli/mod.rs:3973`, uses `substitute_command` — shell-escaped form, Issue #186) |
| `working_dir` | `String` | no | session's `current_dir` | Substituted via plain `variables.substitute` (not shell-escaped — it's a path, not a shell word) |
| `requires_confirmation` | `bool` | no | `false` | If true, after the command runs, the advance loop stops with `StopReason::ActionRequiresConfirmation` instead of continuing to gate evaluation |
| `polling` | `Option<PollingConfig>` | no | `None` (one-shot) | Presence switches execution model; `PollingConfig{interval_secs, timeout_secs}`, only `timeout_secs > 0` is validated at compile time (`src/template/compile.rs:846-853`) |

Not present at all in the schema: no per-action `timeout_secs` for the command itself (that's hardcoded, see §4), no field to write the command's stdout into a named context/evidence key, no `env` field, no `retries` count separate from polling, no `max_polls` count (only wall-clock timeout).

Compile-time validation (`src/template/types.rs:807-853`):
- Rejects a state having both `integration` and `default_action` (`state {:?}: cannot have both integration and default_action`)
- Rejects empty `command`
- Every `{{VAR}}` reference in `command` or `working_dir` must be declared in the template's `variables:` block or be a `RUNTIME_VARIABLE_NAME`
- `polling.timeout_secs` must be `> 0` — **no upper bound is enforced**, despite the design's Security Considerations explicitly recommending one ("compile-time validation should enforce a maximum timeout (e.g., 1 hour)", design doc line 449-451). A template author can declare `timeout_secs: 999999999` and it compiles.

Real fixture example, `tests/integration_test.rs:3846-3873`:
```yaml
setup:
  default_action:
    command: "touch marker.txt"
  gates:
    file_exists:
      type: command
      command: "test -f marker.txt"
  transitions:
    - target: done
```
And a `requires_confirmation` fixture, `tests/next_response_baseline.rs:180-188`:
```yaml
apply:
  default_action:
    command: "echo ready"
    requires_confirmation: true
  transitions:
    - target: done
```
Zero templates in the workspace actually use `default_action` outside test fixtures — confirmed separately (0 hits in `public/shirabe`, per the exploration's orientation doc), consistent with what I found: `check-template-interpolation.sh` in shirabe knows the `default_action:` key shape (for `{{VAR}}` vs bare `$VAR` linting) but no shirabe template declares one.

### 2. Execution point — `src/engine/advance.rs`

`advance_until_stop` (`src/engine/advance.rs:168-186`) takes a fourth closure, `execute_action: &A` where `A: Fn(&str, &ActionDecl, bool) -> ActionResult` — note the **third `bool` parameter (`has_evidence`) that the design did not specify** (design's signature was `Fn(&str, &ActionDecl) -> ActionResult`, design doc lines 288-289). The engine computes `has_evidence = !current_evidence.is_empty()` and hands the decision to skip to the closure (`src/engine/advance.rs:287-289`), rather than the engine itself short-circuiting to `Skipped` as literally described in the design ("if evidence is non-empty, the closure returns `Skipped` and the engine proceeds to gates," design doc line 305). Functionally equivalent — the actual CLI closure implementation does check `has_evidence` and returns `Skipped` immediately (`src/cli/mod.rs:3968-3972`) — but the responsibility moved from engine to caller.

Step numbering also shifted from the design's 8-step list to a 9-step doc comment in code (`src/engine/advance.rs:151-159`): terminal(3) → integration(4) → **action execution(5)** → gates(6) → skip_if(7) → transition resolution(8). This matches the design's intended order (integration before action, action before gates).

Execution logic (`src/engine/advance.rs:286-315`):
```
if state has default_action:
    result = execute_action(state, action, has_evidence)
    match result:
        Executed{..}   -> fall through to gate evaluation
        Skipped        -> fall through to gate evaluation
        RequiresConfirmation{exit_code,stdout,stderr} -> STOP loop,
            return StopReason::ActionRequiresConfirmation{state, exit_code, stdout, stderr}
```
This matches the design's decision (override skip / requires_confirmation halt / otherwise continue to gates) exactly in outcome, only the "who decides `Skipped`" mechanism differs.

### 3. CLI closure implementation — `src/cli/mod.rs:3968-4051`

The action closure is defined inline inside `handle_next` (not `src/cli/next.rs` as the lead's brief suggested — that file only holds `dispatch_next`, used for `--to` directed transitions, and doesn't touch `default_action` at all).

- **Override check**: `if has_evidence { return ActionResult::Skipped }` (line 3970-3972) — confirms evidence-in-current-epoch prevents execution, matching the design.
- **Variable substitution**: `command` via `variables.substitute_command()` (shell-escaped — a hardening beyond what the design specified, tied to a separate Issue #186 fix); `working_dir` via plain `variables.substitute()`.
- **`working_dir` resolution**: empty string → session `current_dir`; non-empty → `PathBuf::from(variables.substitute(&action.working_dir))`.
- **Execution**: `polling.is_some()` → `execute_with_polling(...)` (`src/cli/mod.rs:995`); else → `crate::action::run_shell_command(&command, &wd, 30)` — **the `30` is a hardcoded literal, not configurable** by the template author (`ActionDecl` has no `timeout_secs` field at all — this matches the design's own schema, which also omitted it, so it's "design-and-code agree," but it's a real authoring gap: a one-shot `default_action` cannot run longer than 30 seconds no matter what the author wants).
- **Output truncation**: `truncate_output(&output.stdout, MAX_ACTION_OUTPUT_BYTES)` where `MAX_ACTION_OUTPUT_BYTES = 64 * 1024` (`src/cli/mod.rs:61`) — matches the design's 64KB truncation exactly.
- **Event emission**: `EventPayload::DefaultActionExecuted{state, command, exit_code, stdout, stderr}` appended via `backend.append_event(&name, &event_payload, &now_iso8601())` (`src/cli/mod.rs:4029-4037`) — note the append's `Result` is discarded (`let _ = ...`), so a failed event append doesn't fail the action or the request.
- **Result construction**: `requires_confirmation` selects between `ActionResult::RequiresConfirmation{..}` and `ActionResult::Executed{..}` (both carry the same three fields).

`run_shell_command` itself (`src/action.rs:26-107`) matches the design and the orientation: `sh -c`, own process group via `setpgid(0,0)`, `SIGKILL` to the whole group on timeout via `killpg`, stdout/stderr piped and read to completion, `timeout_secs == 0` falls back to `DEFAULT_TIMEOUT_SECS = 30`.

### 4. Event log — `DefaultActionExecuted`

`src/engine/types.rs:544-550`:
```rust
DefaultActionExecuted {
    state: String,
    command: String,   // post-substitution, as actually run
    exit_code: i32,
    stdout: String,     // truncated to 64KB
    stderr: String,     // truncated to 64KB
}
```
`type_name()` maps it to `"default_action_executed"` (`src/engine/types.rs:1025`), it round-trips through the standard payload deserialize/serialize path (`src/engine/types.rs:1221-1223`, `2185`, `2203`), and it's consumed by the dashboard renderer (`src/cli/dashboard_data.rs:854`). This exactly matches the design's `DefaultActionExecuted` event shape — no delta here.

**Output does NOT flow into the `koto next` response for non-confirmation actions.** This is the most consequential gap versus the design's stated data flow (design doc line 228-229: "on gate failure with accepts block, agent sees action output in fallback directive"). Checked directly: `NextResponse::EvidenceRequired` (`src/cli/next_types.rs:64-71`) and `NextResponse::GateBlocked` (`src/cli/next_types.rs:72-78`) both have `blocking_conditions: Vec<BlockingCondition>` (gate results) but **no `action_output` field**. `ActionOutput` (`src/cli/next_types.rs:788-793`) is only ever attached to `NextResponse::ActionRequiresConfirmation` (`src/cli/next_types.rs:104-111`). So: if a `default_action` runs, doesn't require confirmation, and the subsequent gate fails, the agent's `koto next` response tells it which gate failed (`blocking_conditions`) but says nothing about what the action printed — that's recoverable only by reading the JSONL event log directly (not part of the normal `koto next` contract), which no documented CLI surface does for the agent automatically.

### 5. `requires_confirmation` / `ActionRequiresConfirmation` — what the agent sees

`StopReason::ActionRequiresConfirmation{state, exit_code, stdout, stderr}` (`src/engine/advance.rs:75-81` implied by match arm) maps in `src/cli/mod.rs:4200-4205` to `NextResponse::ActionRequiresConfirmation{state, directive, details, advanced, action_output, expects, unassigned_children}`. Its wire `action` value is `"confirm"` (`src/cli/next_types.rs:627`) — the design explicitly kept `"confirm"` and `"done"` stable across the output-contract rewrite (DESIGN-koto-next-output-contract.md line 62), and that held. The agent gets the full `command`/`exit_code`/`stdout`/`stderr` for the confirmation-gated action (`ActionOutput`, `src/cli/next_types.rs:788-793`), then presumably must submit evidence to proceed (not traced further here — outside this lead's scope, but the general `koto next --to`/evidence submission path applies).

### 6. Polling / retry — `execute_with_polling`, `src/cli/mod.rs:995-1060ish`

- Deadline = `Instant::now() + Duration::from_secs(polling.timeout_secs)` — wall clock, not iteration count.
- Each iteration: run command with **hardcoded 30s timeout** (`run_shell_command(command, working_dir, 30)`, line 1022 — same fixed timeout as one-shot, not derived from `polling.interval_secs` or any config).
- Success condition: if the state has gates, success = *all* gates `Passed` (`GateOutcome::Passed`) after running the command; if the state has *no* gates, success = `exit_code == 0`.
- On timeout: returns the last command's output with `stderr` appended `"\npolling timed out after {N} seconds"` — this makes it back into the `DefaultActionExecuted` event and (if `requires_confirmation`) into `action_output`, but if `requires_confirmation` is false, a polling timeout on a gate-having state falls into the same "no `action_output` surfaced on gate failure" gap as §4.
- Shutdown handling: checked both before each command execution and inside the sleep loop, in `interval_secs`-bounded slices, to stay responsive to signals — this is *more* than the design specified (design only said the polling loop "uses the same signal/shutdown checks as the advance loop," didn't detail sub-interval polling).
- Gate command variable substitution inside the polling closure only applies `variables.substitute_command` (template vars), not the `vars_for_gates`/runtime-var substitution the main `gate_closure` does (compare `src/cli/mod.rs:539-548` vs `~1024-1026` in the polling gates map) — a small inconsistency: polling-state gates may not get the same runtime `--var` substitution as normal gate evaluation gets, worth a closer look if `ci_monitor`-style gates ever reference runtime vars beyond template vars.

### 7. Output contract surfacing — `src/cli/next_types.rs`, design doc `DESIGN-koto-next-output-contract.md`

The output-contract design's action-value rename shipped and is consistent: `"confirm"` for `ActionRequiresConfirmation`, matching six documented variants (`EvidenceRequired`→`evidence_required`, `GateBlocked`→`gate_blocked`, `Integration`→`integration`, `IntegrationUnavailable`→`integration_unavailable`, `ActionRequiresConfirmation`→`confirm`, `Terminal`→`done`) — actually seven variants counting `Error`, and the design doc's own `src/cli/next.rs` comment note ("doc comment corrected to six... includes ActionRequiresConfirmation") is consistent with what's in code (comment says "six possible responses," `src/cli/next_types.rs:57`). `blocking_conditions_from_gates` (`src/cli/next_types.rs:824`) is the shared helper the design called for, used to eliminate the gate-result→BlockingCondition duplication between `advance.rs`/`mod.rs` and `next.rs`'s `dispatch_next`.

### Design-vs-code delta table

| Design promise | Code reality | Verdict |
|---|---|---|
| `ActionDecl{command, working_dir, requires_confirmation, polling}` on `TemplateState` | Exact match, `src/template/types.rs:199-207`, `src/template/types.rs:69` | **Matching** |
| YAML `default_action:` on `SourceState`, mapped 1:1 to compiled `ActionDecl` | Exact match, `src/template/compile.rs:61`, `239-246` | **Matching** |
| Compile-time: reject `integration`+`default_action`, empty command, validate `{{VAR}}` refs | Exact match, `src/template/types.rs:807-844` | **Matching** |
| Compile-time: enforce a max polling timeout (e.g. 1 hour) | **Not implemented** — only `timeout_secs > 0` is checked (`src/template/compile.rs:846-853`) | **Promised-but-absent** |
| Fourth closure `Fn(&str, &ActionDecl) -> ActionResult`; engine itself returns `Skipped` on evidence | Closure is `Fn(&str, &ActionDecl, bool) -> ActionResult`; engine passes `has_evidence` and delegates the skip decision to the closure | **Present-but-different** (same externally observable behavior, different internal contract) |
| `ActionResult::{Executed, Skipped, RequiresConfirmation}` | Exact match, `src/engine/advance.rs:35-48` | **Matching** |
| `StopReason::ActionRequiresConfirmation{state, output}` | `StopReason::ActionRequiresConfirmation{state, exit_code, stdout, stderr}` — flattened fields instead of a nested `output`, functionally the same data | **Present-but-different** (cosmetic) |
| `DefaultActionExecuted{state, command, exit_code, stdout, stderr}` event, 64KB truncation | Exact match, `src/engine/types.rs:544-550`, `src/cli/mod.rs:61,4025-4026` | **Matching** |
| `run_shell_command` shared between `gate.rs` and action executor | Exact match, `src/action.rs:26`, used by both (per module doc comment `src/action.rs:1-3`) | **Matching** |
| "On gate failure with accepts block, agent sees action output in fallback directive" | `EvidenceRequired`/`GateBlocked` responses have `blocking_conditions` but no `action_output` field; `ActionOutput` only attaches to `ActionRequiresConfirmation` | **Promised-but-absent** |
| `"confirm"` action value stable for `ActionRequiresConfirmation` | Exact match, `src/cli/next_types.rs:627` | **Matching** |
| Polling wraps "the same execute-then-check loop" with interval/timeout | Implemented with an added sub-interval shutdown check the design didn't specify (extra robustness) | **Present-but-different** (better than spec) |
| Per-action configurable command timeout | No such field exists in `ActionDecl` in either the design or the code — always hardcoded 30s (`src/action.rs:12`, called with literal `30` at both call sites in `src/cli/mod.rs`) | **Matching the design, but a real authoring gap** (design never proposed this field either) |
| Action stdout as a route to write context/evidence keys automatically | No such mechanism; `context_assignments` is a wholly separate, transition-level feature (`src/template/types.rs:1219-1242`) unconnected to `default_action` | **Not promised, not present** — clarifies an open question from the exploration's scope doc |

## Implications

For the shirabe `/execute`/`/work-on` gap: `default_action` is a fully-shipped, tested, working primitive — not a "koto doesn't support this yet" situation. A template author today can express "run this shell command automatically when entering this state, optionally poll until a gate passes, optionally require confirmation before continuing" with a five-line YAML block, no code changes to koto needed. The mechanical shell commands embedded in shirabe's `/execute`/`/work-on` prose (e.g., `git rev-parse --abbrev-ref HEAD`) are exactly the shape `default_action` was built for (Issue #71's own problem statement cites this as the target: "agents perform mechanical work that koto should handle"). This is squarely an "unused koto feature," not a missing one.

The one gap that would genuinely bite a template author converting shirabe's mechanical commands to `default_action`: if the action succeeds (or fails) and its exit code alone doesn't satisfy the gate, the agent doesn't get to see stdout/stderr in the `koto next` response unless the author also set `requires_confirmation: true` (which forces a stop on every single execution, defeating "auto-execute without agent involvement on the happy path" for that state). For pure fire-and-forget deterministic commands (e.g. `git rev-parse`) this doesn't matter — the output isn't meant for gate/agent consumption. But if a template author wants "run X, and if it fails let the agent see why" without also gating every successful run on confirmation, the current output contract doesn't support that: the agent would have to separately inspect the JSONL event log, which isn't a documented `koto next` workflow.

## Surprises

- The closure's third `bool` parameter (`has_evidence`) is a genuine, unremarked deviation from the design's two-parameter closure signature — it moves the override-skip decision from engine to caller without changing the design doc or any comment explaining why.
- `working_dir` uses *unescaped* variable substitution while `command` uses shell-escaped substitution (Issue #186) — a security-relevant asymmetry the design didn't call out (design doc's Security Considerations section discusses only command substitution, not path substitution for `working_dir`).
- The design's own Security Considerations section flagged the missing max-timeout enforcement as a required mitigation ("Compile-time validation should enforce a maximum timeout... and require the field when polling is declared") — the second half ("require the field") *is* honored (timeout_secs is mandatory whenever `polling` block is present, structurally, since `PollingConfig` has no `#[serde(default)]` on `timeout_secs`), but the max-value cap was dropped entirely with no comment marking it as deferred.
- Polling's gate-command variable substitution appears to only apply template-var substitution, not the runtime `--var` substitution path the main gate closure applies — a possible latent bug for any future `ci_monitor`-with-runtime-vars template, not confirmed by a failing test, just observed from reading the two closures side by side.

## Open Questions

- Is the polling-gates runtime-var substitution gap (§6, last bullet) intentional or an oversight? Would need a template author to hit it with a `polling` state whose gate command references a `--var`-supplied (not template-declared) value to confirm.
- Does any downstream skill (`koto-skills` plugin, AGENTS.md, koto.mdc) document the "`action_output` not surfaced except on `requires_confirmation`" behavior for template authors, so they know to reach for `requires_confirmation` or the event log when they need visibility into a non-confirmation action's output? Not checked in this pass — out of scope (docs under `plugins/koto-skills/` weren't read).

## Summary

`default_action` is fully implemented end to end — YAML schema, compile-time validation, a fourth engine closure, CLI execution with process-group-isolated shell commands, event logging, polling, and confirmation-gating — and matches the design doc closely aside from a few cosmetic signature differences and one dropped safety control (no max polling timeout enforced, despite the design requiring one). The one substantive gap is that action stdout/stderr only reaches the agent's `koto next` response when `requires_confirmation` is set; on the happy path or on a bare gate failure, output lands only in the JSONL event log, not in `blocking_conditions` or any other response field. Zero templates in the workspace use `default_action` today, confirming this is an unused-but-working capability, not a missing one — a strong candidate for shirabe's `/execute`/`/work-on` mechanical-command steps.
