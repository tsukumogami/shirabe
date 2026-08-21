# Lead: How does a command's output reach later states and the agent?

## Findings

**1. Variable substitution is init-time only, immutable thereafter.**
`Variables::from_events()` (`src/engine/substitute.rs:60-75`) builds the entire
`{{VAR}}` binding table by scanning the event log for exactly one event type:
`EventPayload::WorkflowInitialized { variables, .. }`. There is no code path that
adds to or updates this map after init — `koto init --var` (`src/cli/vars.rs:19`,
`substitute_vars`) only writes that one event at workflow creation. No `koto var
set` or equivalent exists. `Variables::substitute()` / `substitute_command()`
(`src/engine/substitute.rs:87-106`) only ever read this frozen map. So today, a
command's stdout categorically cannot become a `{{VAR}}` value — the substitution
system has no ingestion point after init.

**2. The context store is a separate, byte-blob system, gate-only, not
substitution-visible.** `koto context add/get/exists/remove` (`src/cli/context.rs`)
writes/reads raw bytes through `ContextStore` (`src/session/context.rs`), keyed by
string, content-addressed via SHA-256, and emits `ContextAdded`/`ContextRemoved`
events (`src/engine/types.rs`). It is written exclusively by explicit agent CLI
calls — nothing in `src/action.rs` or `src/engine/advance.rs` writes to it. It is
read only by two gate types, `context-exists` and `context-matches`
(`src/gate.rs:73-75`, `GATE_TYPE_CONTEXT_EXISTS`/`GATE_TYPE_CONTEXT_MATCHES`) — never
by `Variables::substitute()`. So context and variables are two disjoint systems:
context is reachable by gates but not by `{{VAR}}` templates; variables are
reachable by `{{VAR}}` templates but not writable after init.

**3. `CommandOutput` from `default_action` is captured, logged, but discarded on
the happy path.** Trace: `src/action.rs:16-107` defines `CommandOutput { exit_code,
stdout, stderr }` and `run_shell_command()`, shared by gates and actions. In
`src/cli/mod.rs`'s `action_closure` (~line 4028), after running the command
(one-shot via `run_shell_command` or polling via `execute_with_polling`,
`src/cli/mod.rs:993-1053`), output is truncated
(`truncate_output(..., MAX_ACTION_OUTPUT_BYTES)`) and unconditionally appended as a
`DefaultActionExecuted { state, command, exit_code, stdout, stderr }` event
(`src/cli/mod.rs:4028-4029`, schema at `src/engine/types.rs:544-550`). That's where
persistence ends for the common case: back in `src/engine/advance.rs:286-315`, the
advance loop matches on `ActionResult`:
- `ActionResult::Executed { .. }` → **fields destructured and discarded** ("Continue
  to gate evaluation" — no fields flow into `current_evidence`,
  `gate_evidence_map`, or anywhere else).
- `ActionResult::Skipped` → discarded (override evidence existed).
- `ActionResult::RequiresConfirmation { exit_code, stdout, stderr }` → **only this
  branch propagates the value**, via `StopReason::ActionRequiresConfirmation`.

So on the success/no-confirmation path (the "happy path" the exploration cares
about), `CommandOutput` is a dead end after the event log write: it isn't merged
into gate evidence, isn't injected into `{{VAR}}`/vars evidence, and isn't returned
in the `koto next` JSON.

**4. `koto next` only surfaces action output for the confirmation-required path.**
In `src/cli/mod.rs` (~4197-4213), `NextResponse::ActionRequiresConfirmation` is the
only response variant carrying `action_output: ActionOutput { command, exit_code,
stdout, stderr }` (`src/cli/next_types.rs:109, 788`). `grep` across
`next_types.rs`/`mod.rs` confirms `action_output`/`ActionOutput` appear nowhere else
— not on `Terminal`, `GateBlocked`, `EvidenceRequired`, or `Integration`. So an agent
only ever sees a `default_action`'s stdout in the JSON when the template author set
`requires_confirmation: true` on that action, forcing a stop specifically so a human
or agent can review the output before continuing.

**5. Gates capture output for their own contract, not as a durable/reusable
value.** `evaluate_gates()` (`src/gate.rs`) runs `command`-type gates through the
same `run_shell_command`-style execution and returns a `StructuredGateResult {
outcome, output: serde_json::Value }` per gate (per
`DESIGN-structured-gate-output.md`). This `output` **is** injected into evidence via
`gate_evidence_map` in `src/engine/advance.rs` (the `gates.*` namespace,
`GATES_EVIDENCE_NAMESPACE`), and `when` clauses / `skip_if` can route on
`gates.<name>` (confirmed at `advance.rs` ~350-420, `has_gates_routing` check).
This is real precedent for "a command result becomes evidence usable by later
routing" — but it's scoped to gate commands within the *same* state's transition
decision, evaluated fresh every state re-entry; it isn't durable across states and
isn't exposed as a general-purpose named variable other states or `{{VAR}}`
substitution can reference.

**6. `DecisionRecorded` / evidence-routing / mid-state-decision-capture are agent
submissions, not command results.** `DESIGN-mid-state-decision-capture.md` adds
`DecisionRecorded { state, decision: Value }`, written when the *agent* submits a
decision via `koto next --with-data`, not when a shell command produces a value.
`DESIGN-template-evidence-routing.md` is about `accepts`/`when` matching against
agent-submitted evidence fields (e.g. `decision: proceed`), again agent-authored,
not command-produced. Neither design provides an automatic command-stdout → durable
state path; both require the agent to be the one asserting the value.

**7. shirabe's actual convention today is a fully manual workaround.**
`skills/work-on/references/koto-context-conventions.md` and
`docs/guides/koto-context-patterns.md` (both in `public/shirabe`) describe the
pattern shirabe uses everywhere: the agent runs the shell command itself, reads the
value in its own context, and pipes/writes it into `koto context add <WF> <key>`
(stdin-preferred, or an ephemeral file). There is no koto-side automation of this —
`default_action` is declared in `TemplateState`
(`docs/designs/current/DESIGN-default-action-execution.md`) but per the lead's own
observation and confirmed by `grep -rn "default_action" skills/`, shirabe's koto
templates never populate it. The "then run `git rev-parse --abbrev-ref HEAD`"
prose instruction is exactly this workaround: the agent executes the mechanical
command by hand because koto has no way to hand the *value* back into template
state.

## Implications

- Today, **a template author cannot declare "run this command and bind its stdout
  to variable X"** for `{{VAR}}` substitution, gates, or later directive text on
  the happy (non-confirmation) path. The only place a `default_action`'s stdout is
  agent-visible is the confirmation-required detour, and even there it's a one-shot
  JSON field, not a bindable variable usable in subsequent states.
- The closest existing precedent for "durable, reusable command result" is the gate
  `output` → `gates.*` evidence namespace, but it's re-evaluated per state entry and
  scoped to `when`/`skip_if` routing, not general `{{VAR}}` interpolation into
  instruction text.
- The design doc for default-action execution (`DESIGN-default-action-execution.md`)
  itself claims "on gate failure with accepts block, agent sees action output in
  fallback directive" — but the code trace in Findings 3-4 shows this is **not
  actually wired** for the `Executed` (success, no-confirmation) case; only
  `RequiresConfirmation` propagates output. That's a gap between the design's stated
  intent and the shipped `advance.rs` behavior worth flagging explicitly, not
  something to assume works.

## Surprises

- `ActionResult::Executed { .. }`'s fields are destructured with `{ .. }` in
  `advance.rs:291` specifically to discard them — this reads as a deliberate
  scoping decision (event log is authoritative, in-loop state stays lean) rather
  than an oversight, but it directly blocks the "bind stdout to a variable" use
  case without further engine work.
- Variables and context are two structurally separate systems with no bridge
  between them; a template author reaching for "store this value where `{{VAR}}`
  can see it" has no existing mechanism, only "store this value where a gate can
  check for its presence/content" (context-exists/context-matches).

## Open Questions

- Would the smallest fix be: (a) let `ActionResult::Executed` output feed into the
  same `evidence`/`gates.*`-style map so subsequent `when`/`skip_if` in the *same*
  tick can route on it (mirrors existing gate-output precedent, minimal engine
  change), or (b) introduce a genuine post-init variable-binding mechanism (e.g. a
  new `EventPayload::VariableBound` reducible by `Variables::from_events()`) so
  action output becomes a `{{VAR}}` usable in later states' directives/commands
  too? These have different blast radii — (a) is scoped to the advance loop and
  reuses `GATES_EVIDENCE_NAMESPACE`-style plumbing; (b) touches the substitution
  system's core "immutable, init-time" invariant documented in
  `DESIGN-template-variable-substitution.md` and would need its own design pass.
- Is the `DESIGN-default-action-execution.md` claim about fallback-directive
  action-output visibility aspirational/planned-but-unimplemented, or is there a
  later PR that wired it that this pass didn't find? Worth a targeted `git log -p`
  / `git blame` check on `advance.rs`'s `ActionResult::Executed` arm before
  concluding it's simply unimplemented.

## Summary

Today, `default_action`'s stdout is captured into `CommandOutput`, truncated, and
written to the event log as `DefaultActionExecuted`, but on the normal
(non-confirmation) success path `src/engine/advance.rs:291` discards the fields
outright — it never reaches `{{VAR}}` substitution (which only ever reads the
one-time `WorkflowInitialized` event), the context store (gate-only, agent-write-only),
or the `koto next` JSON (only `ActionRequiresConfirmation` carries `action_output`).
The only real precedent for a command result becoming reusable, routable state is
gate `output` feeding the `gates.*` evidence namespace for that state's own
transition decision — not a general variable-binding mechanism — so shirabe's
current workaround of having the agent run commands by hand and manually pipe
results into `koto context add` is the only way to move a command's value forward
today.
