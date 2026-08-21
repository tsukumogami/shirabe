# Lead: What happens when a koto-executed command fails — is there a real, implemented fallback-to-agent path, and what does the agent see?

## Findings

**1. Action execution in the advance loop does not stop on failure by default.**
`src/engine/advance.rs:286-320` (step 5 of the loop) calls the injected `execute_action`
closure and matches on `ActionResult`. `ActionResult::Executed { .. }` (src/engine/advance.rs:36-40)
is returned for *any* exit code, including non-zero — the match arm's comment literally
says "Continue to gate evaluation" (advance.rs:290-292). The loop only stops for an action
if `ActionResult::RequiresConfirmation` comes back (advance.rs:299-311), which produces
`StopReason::ActionRequiresConfirmation`. Whether that variant fires is controlled entirely
by the template's static `requires_confirmation: bool` flag on the action
(src/template/types.rs:205), not by the exit code — the CLI's action closure at
src/cli/mod.rs:4039-4051 branches on `action.requires_confirmation`, unconditionally, after
running the command. So `requires_confirmation` is an "always ask" flag for irreversible
actions (per DESIGN-default-action-execution.md:442, "prevents irreversible actions from
running unattended"), not a failure-only fallback. This matches the design doc's own spec:
"If requires_confirmation: stop loop with ActionRequiresConfirmation" (DESIGN-default-action-execution.md:119) —
no exit-code condition anywhere in that trigger.

**2. Command execution mechanics (`src/action.rs`).** `run_shell_command` (action.rs:26-104)
covers three failure modes koto distinguishes internally: non-zero exit (`exit_code` set,
stdout/stderr captured, action.rs:79-84), spawn failure (`exit_code: -1`, stderr =
`"failed to spawn command: {e}"`, action.rs:50-57), and timeout (`exit_code: -1`, stderr =
`"command timed out after N seconds"`, process group SIGKILL'd, action.rs:85-98). All three
are captured identically as a `CommandOutput { exit_code, stdout, stderr }` — the advance
loop's step 5 treats all three the same way: if `requires_confirmation` is false, it's
`ActionResult::Executed` and the loop proceeds regardless of which of the three happened.

**3. The actual failure-surfacing mechanism is an accompanying gate, not the action itself.**
Because a failing default_action alone doesn't stop the loop, the only way a template makes
a bad action visible to the agent is by pairing it with a *gate* that independently detects
the failure (e.g., re-checking exit code, an artifact, or a follow-up command). Gate failure
handling is real and does stop the loop: `src/engine/advance.rs` step 6 evaluates
`template_state.gates`; any `Failed`/`TimedOut`/`Error` outcome produces
`StopReason::GateBlocked(gate_results)` (unless the state has an `accepts` block, in which
case it falls through to `StopReason::EvidenceRequired` — the actual, implemented
"gate-with-evidence-fallback" pattern from issue #69, visible in the classification comments
at src/cli/next.rs:24-27 and the fallback logic at src/cli/next.rs:57-69). `koto next`'s main
handler in `src/cli/mod.rs` (~4123-4163) converts this into `NextResponse::GateBlocked` or
`NextResponse::EvidenceRequired`, both carrying `blocking_conditions` built by
`blocking_conditions_from_gates` (src/cli/next_types.rs:824-856).

**4. Gate failure output is much thinner than action failure output — it drops stdout/stderr.**
`evaluate_command_gate` (src/gate.rs:206-230) only ever produces
`{"exit_code": N, "error": ""}` (or `"timed_out"` / a spawn-error string) as the gate's
structured `output` — it does *not* capture the command's stdout/stderr into that JSON
(compare to `CommandOutput` in action.rs, which the gate evaluator discards after reading
`exit_code`). `BlockingCondition.output` (next_types.rs:770-784) carries that same thin
JSON straight through to the agent. So: if a default_action fails and the failure is
detected via a paired gate (the normal path per finding 3), the agent sees only an exit code
in `blocking_conditions[].output`, not the actual command's stderr — even though the
*action's* stdout/stderr was captured and persisted to the event log via the
`DefaultActionExecuted` event (src/cli/mod.rs:4025-4031, event payload defined per
DESIGN-default-action-execution.md:243-256). That richer output only reaches the agent
directly when `requires_confirmation: true` triggers `ActionRequiresConfirmation`, whose
`action_output: ActionOutput` (next_types.rs:788-793) does carry `command`, `exit_code`,
`stdout`, `stderr` (constructed at src/cli/mod.rs:4197-4218).

**5. No conditional/branching instruction text exists anywhere in the template or output
contract.** `TemplateState.directive` is a single `String` field (src/template/types.rs:55),
authored once per state. Every stop-reason branch in `src/cli/mod.rs`'s response-building
match (~4123-4218) — `GateBlocked`, `EvidenceRequired`, `ActionRequiresConfirmation` — uses
the identical `directive: directive.clone()` (or `final_template_state.directive.clone()`)
regardless of whether the state's action succeeded, failed, or is pending confirmation.
There is no mechanism in `src/template/compile.rs` or the state-rendering path for
different prose per `StopReason`, per exit code, or per gate outcome. The "on the happy
path, the agent never sees these directives" claim in
DESIGN-shirabe-work-on-template.md:566 is true only in the structural sense that the loop
auto-advances past states that don't stop it — not because koto conditionally selects
different text. There is exactly one directive string per state; it's shown whenever
`koto next` stops there for any reason.

**6. The "three-path model" (default/override/failure) is a shirabe-side *design*, not a
koto engine primitive.** DESIGN-shirabe-work-on-template.md (lines 540-720) defines it for
the not-yet-built `/work-on` template: deterministic states get "Tier 2" directives
(3-8 lines, override/failure guidance only) versus "Tier 1" judgment states (10-25 lines,
always shown). The doc explicitly separates concerns: "This design specifies WHAT happens
at each step; the engine design specifies HOW koto executes it"
(DESIGN-shirabe-work-on-template.md:576). The three paths as implemented in koto's engine
today are: (a) **default** = action runs, no stop, if not `requires_confirmation`;
(b) **override** = evidence submitted before entry skips the action entirely
(`ActionResult::Skipped`, advance.rs:41-42, cli/mod.rs:3970-3973) — this is unconditional
skip-on-evidence-presence, not specifically "the agent noticed a failure and intervened";
(c) **failure** = not a first-class action-level path at all; it only exists insofar as a
gate independently catches the bad outcome and the agent later calls
`koto overrides record` (src/cli/overrides.rs:76-84, `resolve_override_applied` at
overrides.rs:55-72) to substitute a passing gate value with mandatory `--rationale`, per
DESIGN-gate-override-mechanism.md (status: Current, already implemented — `GateOverrideRecorded`
events are read by the advance loop and injected into `gates.*` evidence, per that doc's
decision section). That override call is the actual mechanism by which "the agent tells
koto it is satisfied" after taking over from a failed automated step — but it operates on
gates, not on default_action results directly, and it requires a template author to have
declared `override_default` (or rely on `built_in_default`) on the *gate*, not the action.

**7. `koto next`'s output contract (`src/cli/next_types.rs`) has the right fields for
action failure detail, but only on the `ActionRequiresConfirmation` variant.** `ActionOutput`
(next_types.rs:788-793: `command`, `exit_code`, `stdout`, `stderr`) is the only place in the
six-variant `NextResponse` enum (next_types.rs:57-134) that carries raw stdout/stderr from a
command. `GateBlocked` and `EvidenceRequired` carry `blocking_conditions: Vec<BlockingCondition>`
whose `output` field (next_types.rs:783) is gate JSON, not action JSON, and — per finding 4 —
never includes stdout/stderr for command gates. There is no `remediation` prose field
anywhere in `next_types.rs`; the closest thing is the state's static `directive`/`details`
strings (finding 5).

**8. `src/cli/retry.rs` is not the "agent takes over from a failed action" mechanism.**
Despite the name, it's coordinator/child-workflow retry machinery (`RetryChildSnapshot`,
`ChildOutcome`, `handle_retry_failed` at retry.rs:383) for re-dispatching failed *child
workflows* in a fan-out, unrelated to single-state default_action failure recovery. The
actual agent-driven recovery surface for action/gate failure is `koto overrides record`
(finding 6), not `koto retry`.

## Implications

- shirabe cannot build the target design ("koto runs commands; agent only sees prose on
  failure, with full failure detail") purely by setting `default_action` + `requires_confirmation`
  on template states, because `requires_confirmation` fires unconditionally (success or
  failure) rather than only on failure. Using it as a failure gate would mean the agent is
  interrupted on every successful run too — the opposite of the "happy path is silent"
  requirement.
- The only implemented way to get silent-on-success / stop-on-failure behavior today is:
  default_action (no requires_confirmation) + a paired gate that re-derives the same
  success condition. That works for stopping the loop, but the agent then only receives a
  bare exit code in `blocking_conditions[].output`, not the command's stdout/stderr — the
  richest failure detail (the actual error text) is stuck in the `DefaultActionExecuted`
  event log entry, not exposed through the `koto next` response that stopped the loop.
- Recovery from that stop is via `koto overrides record` against the *gate*, which requires
  the template to declare `override_default` on the gate (or rely on a generic
  `built_in_default`) — this is a gate-level bypass-with-rationale, not "the agent runs the
  failed command and koto sees the result," which is closer to what shirabe's current
  prose-instruction pattern does (agent literally executes the shell command itself).

## Surprises

- `requires_confirmation` is not a failure fallback at all — it's an unconditional
  "always stop for confirmation" flag, primarily intended for irreversible actions
  (PR creation, etc.), by explicit design (DESIGN-shirabe-work-on-template.md:540-544,
  reversibility table). Conflating it with "on failure" would be a misreading of both the
  code and the design doc.
- Gate output for command gates is genuinely lossy: `evaluate_command_gate` throws away
  stdout/stderr and keeps only `exit_code` (src/gate.rs:206-230). Any failure-detection
  strategy that routes through gates (the only implemented stop-the-loop path for action
  failures) inherently loses the actionable error text unless the template author finds
  another way to surface it (e.g., writing it to a context-store key a `context-matches`
  gate then reads).
- `src/cli/retry.rs`'s name is misleading relative to this lead's question — it's entirely
  about child-workflow coordination retry, not single-action recovery.

## Open Questions

- Does any part of the codebase let a `GateBlocked`/`EvidenceRequired` response pull in the
  most recent `DefaultActionExecuted` event's stdout/stderr for the same state (e.g. via
  `koto status`)? Not found in this pass — worth a follow-up grep on `derive_last_gate_evaluated`
  and any "last action" projection in `src/engine/persistence.rs` if another lead needs it.
- DESIGN-template-evidence-routing.md was listed alongside the other designs but not read in
  this pass; it may bear on whether action output can be merged into evidence for
  conditional routing (advance.rs step 5 currently does not merge action output into
  `current_evidence` before step 6/7 — confirmed absent, but the design doc might propose
  changing that).

## Summary
Action failure alone never stops koto's advance loop — `ActionResult::Executed` fires for any exit code, and only a template-declared `requires_confirmation` flag (which fires unconditionally, success or failure) or a *separately declared gate* actually halts execution and reaches the agent. The gate-with-evidence-fallback path and the gate override mechanism (`koto overrides record`) are both real and implemented, but gate output drops stdout/stderr, so the richest failure detail (captured in the `DefaultActionExecuted` event) only reaches the agent through the `ActionOutput` field when `requires_confirmation` is set — not through the normal failure-detection path. There is no conditional/branching instruction text anywhere: `TemplateState.directive` is one static string per state shown identically regardless of stop reason, so the "prose only on failure" design in DESIGN-shirabe-work-on-template.md is a target for a not-yet-built template, not a mechanism koto's engine implements today.
