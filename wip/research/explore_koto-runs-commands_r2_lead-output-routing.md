# Lead: What is the smallest koto change that routes a `default_action`'s output somewhere usable, and what does it cost?

## Findings

### The compatibility rules that actually constrain this change

Three separate disciplines apply, and they pull in different directions.

**Wire format (`docs/STABILITY.md`).** Adding a new `EventPayload` variant is an additive, unversioned change — `CURRENT_SCHEMA_VERSION` does not move (`docs/STABILITY.md` "The rule: additive change does NOT bump the constant"). The mechanical cost of a new event type is fixed and small: a variant on `EventPayload` (`src/engine/types.rs:544`-ish, next to `DefaultActionExecuted`), a `type_name()` match arm (`src/engine/types.rs:1025`), a `Deserialize` payload struct plus parse arm (`src/engine/types.rs:1220-1226`, `1467`), and a docs entry in `docs/reference/session-feed.md` (which already documents `default_action_executed` at line 194/723 with a `tier`). This is the cheapest axis of the whole design space — any option that only needs a new event type pays this fixed cost once.

**Response contract (`DESIGN-koto-next-output-contract.md`) and its baseline (`tests/next_response_baseline.rs`).** New fields on `NextResponse` are allowed as long as they're additive and don't change existing bytes. `tests/next_response_baseline.rs` pins byte-identical JSON for `GateBlocked`, `EvidenceRequired`, `Terminal`, `ActionRequiresConfirmation` (`CONFIRM_TEMPLATE`, `apply` state), and `IntegrationUnavailable` against fixed templates. Critically, **the fixture's `CONFIRM_TEMPLATE` is the only baseline template with a `default_action`, and it only reaches the `confirm` response** (`tests/next_response_baseline.rs:175-197`; recorded body at `action-requires-confirmation`). No baseline sequence combines a `default_action` with a `GateBlocked`/`EvidenceRequired`/`Terminal` outcome. So a field that's `Option<T>` + `skip_serializing_if = "Option::is_none"`, defaulting to `None` whenever no action ran, does not break the baseline — but this is a narrow, easy-to-violate margin: the field must genuinely default to absent on every path the baseline already exercises.

But `NextResponse`'s `Serialize` is hand-rolled (`src/cli/next_types.rs:504-670`, one `map.serialize_entry` call list per variant) and three combinators exhaustively pattern-match every field of every variant: `with_substituted_directive` (`next_types.rs:180`), `with_directive_prefix` (`next_types.rs:245`), `with_details_suppressed_unless_full` (`next_types.rs:~300`). Any new field added to more than one variant has to be threaded through all four of these match blocks, not just the struct definition. That's the real cost driver, not the wire format.

**Variable substitution (`src/engine/substitute.rs`).** `Variables::from_events` (`substitute.rs:62-77`) currently folds exactly one event kind — the single `WorkflowInitialized` — into a flat `HashMap<String,String>`, and re-validates every value against `VALUE_PATTERN` (`substitute.rs:29`, alphanumeric + `. _ - / : @` and space, no shell metacharacters, no newlines). `{{KEY}}` references are compile-time checked against the template's declared `variables:` block (`src/template/types.rs:1505` "when clause references undeclared variable"; same check applies to directive, gate command, and action command/working_dir at lines 782/795/824/835). This means **any new source of substitutable values must (a) be validated against the same allowlist and (b) be traceable to a variable the author declared up front** — there's no way to introduce an ad hoc `{{KEY}}` at runtime that wasn't named in the template's `variables:` schema.

### Options

| # | Option | Satisfies | Response contract touched? | Baseline risk | Rough size |
|---|--------|-----------|----------------------------|----------------|------------|
| 1 | Populate `action_output` (or a new `last_action`) on every stop reason, not just `ActionRequiresConfirmation` | (a) agent reads it in the response | Yes — every variant, every combinator | Low if strictly additive+optional, but easy to get wrong | **Largest** — touches struct, Serialize, 3 combinators, `AdvanceResult`/`StopReason`, and every construction site in `mod.rs:4053-4260` and `next.rs` |
| 2 | `capture_stdout_as:` on `ActionDecl` → new `VariableCaptured` event → folded into `Variables::from_events` → consumed by existing `{{VAR}}` substitution | (b) later state's directive/gate-command substitution | No — reuses the existing substitution path, zero `NextResponse` changes | None | **Smallest** for satisfying (b), the motivating case |
| 3 | Merge action output into `current_evidence`/`evidence_value` before gate evaluation (step 6) so `gates.*` when-clauses can route on it | (c) gate routing, but only within the *same* state | No | None | Small, but doesn't reach "a later state" |
| 4 | Write action stdout into the `ContextStore` under a derived key (e.g. `default_action.<state>`) | Agent can `koto context get` it later | No | None | Small, but adds a manual retrieval step no design lead has asked for — weakest option |

### Option 1 in detail: populate action output on every stop reason

This looks like "just fill in an existing field" but is actually the most invasive option, for a reason the code makes visible: **the state that ran the action is frequently not the state the loop stops in.** Step 5 (`src/engine/advance.rs:286-300`) runs the action, and on `ActionResult::Executed` falls through to gates (step 6) and possibly an unconditional transition (step 8) that moves to a *new* state and loops back to step 1 — all within the same `advance_until_stop` call. Only `ActionResult::RequiresConfirmation` stops the loop in the acting state itself (`advance.rs:297-309`). So for the non-confirm path, "the action that ran" and "the state whose response you're building" are different states by the time `dispatch_next`/`mod.rs`'s `StopReason` match constructs the response.

Concretely, this needs:
- A new field threaded through the loop, e.g. `last_action: Option<ActionOutput>` on `AdvanceResult` (`advance.rs:88-95`), overwritten (not merged) every time step 5 executes an action, so it reflects the *most recent* action run this tick regardless of which state it belonged to.
- `NextResponse::EvidenceRequired`, `GateBlocked`, `Integration`, `IntegrationUnavailable`, `Terminal` each gain the field (5 struct arms, `next_types.rs:64-127`).
- The hand-rolled `Serialize` impl gains a conditional `serialize_entry` in each of those 5 arms, plus recomputed field counts (`next_types.rs:504-670`).
- `with_substituted_directive`, `with_directive_prefix`, `with_details_suppressed_unless_full` each need the new field passed through in their match arms (exhaustive matches, no default case) — three more sweeps across the same 5 variants.
- Every construction site — `next.rs`'s `dispatch_next` (5 return points) and `mod.rs`'s `StopReason` match (`mod.rs:4118-4260`, 7 arms) — needs the value plumbed in. `dispatch_next` currently has no notion of "an action ran"; it would need a new parameter, since it's a pure classifier over `template_state` alone (`next.rs:17-19` doc comment says exactly this: "`ActionRequiresConfirmation` is produced by the handler... not by this dispatcher").
- New baseline fixture coverage, since none of the existing sequences combine a non-confirm-halting `default_action` with `GateBlocked`/`EvidenceRequired`/`Terminal`.
- A naming decision: reusing `action_output` for "the last action that ran, possibly several states ago" versus "the pending confirm action in *this* state" conflates two different semantics on one field name across variants; a distinct name (`last_action`) avoids that but is one more thing to design.

This option answers "can the agent see *something* ran" but, by itself, does not answer the motivating case (a later state's directive needing the branch name) unless the agent manually copies the value into the next state's evidence submission — which defeats the "koto runs it, agent doesn't have to" goal.

### Option 2 in detail: `capture_stdout_as` → event → `Variables::from_events`

This is the option that actually satisfies the motivating case, and it composes with machinery that already exists rather than extending the response contract.

**Template author's view:**
```yaml
variables:
  BRANCH:
    required: false
    default: ""
states:
  detect-branch:
    default_action:
      command: "git rev-parse --abbrev-ref HEAD"
      capture_stdout_as: BRANCH
    transitions:
      - target: implement

  implement:
    # ...
```
```markdown
## implement

Work on branch `{{BRANCH}}`. Do not commit to main.
```
The author still declares `BRANCH` in the top-level `variables:` block (with an empty default) exactly as Issue #141's optional-variable pattern already requires — `capture_stdout_as` doesn't introduce a new variable *namespace*, it gives an existing declared variable a second way to acquire a value, alongside `koto init`'s materialization from CLI flags.

**Engine changes:**
1. `src/template/types.rs`: add `capture_stdout_as: Option<String>` to `ActionDecl` (`types.rs:200-208`, parallel to `requires_confirmation`). Compile-time validation: if present, the name must be a key in `self.variables` (mirrors the existing "undeclared variable" check pattern at `types.rs:824` for `extract_refs(&action.command)`, except this is a bare identifier, not a `{{...}}` reference, so it's a direct map lookup, not a regex extraction).
2. `src/engine/types.rs`: new `EventPayload::VariableCaptured { key: String, value: String }` variant, `type_name()` arm, `Deserialize` struct + parse arm — same four-touchpoint pattern `DefaultActionExecuted` already used (`types.rs:544`, `1025`, `1220`, `1467`).
3. `src/engine/advance.rs` step 5 (`advance.rs:286-300`): on `ActionResult::Executed` or `RequiresConfirmation` (the command ran either way), if `action.capture_stdout_as` is `Some(key)`, trim the stdout, run it through `crate::engine::substitute::validate_value(key, &trimmed)`, and only if it passes, call `append_event(&EventPayload::VariableCaptured { key, value: trimmed })`. **Validate-then-skip, not validate-then-fail** — a capture that doesn't fit the allowlist (multi-line output, stray shell metacharacters) should silently not update the variable rather than aborting the whole `koto next` call; the alternative (propagating a hard error) turns a template author's loose regex/multi-line command into a total outage for that workflow, which is a worse failure mode than "the variable keeps its stale/default value and the directive text is a little wrong." This needs an explicit decision recorded in the actual design doc, not just inferred from precedent.
4. `src/engine/substitute.rs`: extend `Variables::from_events` to also fold `EventPayload::VariableCaptured` entries into the map, **in event order, later overwriting earlier** (so a loop that re-runs the same capturing action multiple times reflects the latest run). This is a ~5-line change to the existing `find_map` → becomes a fold over the full iterator instead of a single `find_map`.
5. **The same-tick staleness gap (the actual subtlety here):** `mod.rs:3177` builds `variables` from `&events` *before* `advance_until_stop` runs at `mod.rs:4053`, and the final substitution at `mod.rs:4282` reuses that pre-loop snapshot. `append_closure` (`mod.rs:3911-3915`) does persist each event to disk synchronously as the loop runs, so the data is safely recorded — but the in-memory `variables` binding doesn't see it. Concretely: a state whose `default_action` captures `BRANCH` and then auto-advances unconditionally into a state whose directive says `{{BRANCH}}`, all in one `koto next` call (exactly the "happy path, no agent turn" case this whole exploration is about), would emit the *unsubstituted or stale* value in that same response. The fix is small but not optional: either (a) re-read events from the backend after `advance_until_stop` returns and rebuild `Variables` before the final substitution, or (b) have `AdvanceResult` carry the set of captured key/value pairs from this tick (accumulated alongside `last_action` if Option 1 is also done) and merge them into `variables` in `mod.rs` before calling `with_substituted_directive`. (b) avoids a redundant disk read and is the one to prefer. Either way this is a required part of "the smallest change that works," not a nice-to-have — without it, Option 2 silently fails on exactly the auto-advance case that motivates it, and only succeeds if the agent happens to call `koto next` a second time.

Total surface: one field on `ActionDecl`, one compile-time check, one new `EventPayload` variant (fixed, cheap, additive per `STABILITY.md`), a ~10-line change to `advance.rs` step 5, a ~5-line fold change to `substitute.rs`, and the AdvanceResult-merge fix in (5) above (~10-15 lines across `advance.rs`/`mod.rs`). No `NextResponse` field, no `Serialize` impl change, no baseline fixture at risk, no combinator threading. This is why it's the smaller option despite doing the thing the motivating case actually asks for.

### Option 3 in detail: merge into `current_evidence` for gate routing

`advance.rs:451-470` already merges `current_evidence` with a `"gates"` sub-object (`gate_evidence_map`) into `evidence_value` before `skip_if` and transition resolution — this is precisely the mechanism the lead's criterion (c) describes, just not populated from action output today. Extending it: after step 5 executes an action, insert `{"action": {"exit_code":..., "stdout":...}}` into the same merged map (guarded the same way `gate_evidence_map` is guarded, so legacy states without an `action.*`-referencing `when` clause aren't affected), then a transition can route on `action.exit_code` the same way it routes on `gates.foo.exit_code` today.

This is cheap (no new event type, no response field, entirely inside `advance.rs`'s existing evidence-assembly block at lines 451-470) but it only ever reaches the *same* state's own transitions — `current_evidence` is reset to `BTreeMap::new()` on every transition (`advance.rs:514`, `558`), which round 1 already established. It cannot reach "a later state," so it does not satisfy the motivating case on its own — it's a good complement to Option 2 (e.g. "if the git command failed, route to an error state instead of capturing garbage into BRANCH"), not a substitute for it.

### Option 4 in detail: write to the `ContextStore`

`ContextStore` (`src/session/context.rs`) already supports `add`/`get`/`list_keys` and is exercised via `koto context add/get` (`src/cli/context.rs`). The engine could call `store.add(session, &format!("default_action.{state}"), stdout.as_bytes())` **in-process** after every action execution, giving the agent a durable, retrievable artifact. But nothing today makes context-store content flow into `{{VAR}}` substitution or gate routing — the doc note in the lead's brief ("context store is gate-readable and agent-writable only") means a `context-exists`/`context-matches` gate *can* check for the key's presence/pattern, but the *value itself* never reaches a directive's text without the agent explicitly running `koto context get` and pasting it in. That reintroduces the manual step the whole design is trying to eliminate, so this is the weakest option for the stated goal — worth naming because it's cheap and already-built, not because it's competitive with Option 2.

The orchestrator's empirical probe (round 2, `wip/research/explore_koto-runs-commands_r2_lead-empirical-probe.md`, P11-P13) rules out the zero-koto-change variant of this option entirely: an action shelling out to `some-command | koto context add <session> key` deadlocks — the outer `koto next` holds a workspace-scoped lock for the duration of the advance loop, so any nested koto invocation that touches the session store (read or write, own session or another) hangs until the action's 30-second timeout kills it. `koto version` (no session access) is fine; everything else isn't. That means the phrasing above — "the engine could call `store.add(...)` in-process" — is not a stylistic preference, it is the *only* way this option can work at all. A `capture:`-style field that writes to the context store has to call `ContextStore::add` directly from inside `advance.rs`, using the same `store: &dyn ContextStore` handle the CLI's own `context add` handler uses (`src/cli/context.rs:21`), never by constructing a shell command that re-enters the koto binary.

## Implications

All four options were already engine-side by construction — none of the code sketches above route through a nested koto CLI invocation — but the orchestrator's empirical probe (P11-P13) makes that a hard requirement rather than a design preference. Every option in this lead's list, and every option any future lead proposes, must write state from inside `advance.rs`/the engine crate directly (an in-process `ContextStore::add`, an in-process event append via the existing `append_event` closure, an in-process merge into `current_evidence`), never by having the action's shell command re-enter `koto` as a subprocess. That forecloses the cheapest-looking template-only workaround (piping a command's output into `koto context add` from within the action itself) entirely, and it's the reason Option 2's engine-side event-append design is not just smaller than Option 1 on response-contract grounds but is one of only a few families of design that can work at all.

Option 2, alone, is the smallest change that satisfies the motivating case as stated. It leaves the response contract, its baseline test, and its four exhaustive-match combinators completely untouched, which is the main reason its blast radius is so much smaller than Option 1's — those combinators are the real cost center in this codebase, not the wire-format or event-log additions. Anyone reaching for Option 1 first (because "just populate an existing field" sounds smallest) will find out partway through that the field has to be threaded through five variants and four separate functions, and that the acting state and the stopping state are frequently different states in the auto-advance case — the same subtlety that makes Option 2 harder than a first glance suggests.

Options 2 and 3 are not mutually exclusive and solve different halves of "usable": 2 gets the value into prose the agent reads, 3 gets it into machine-checkable routing within the state that produced it. A template author who wants both ("capture the branch name for later prose, and also fail fast in this state if the git command errored") would reach for both — but that is a superset of what this lead's motivating case asks for, and isn't required to answer it.

## Surprises

The action-that-ran and the state-the-loop-stops-in are not the same thing once auto-advance chains through several states in one tick — this wasn't obvious from round 1's framing ("the action runs, stdout is captured... but `advance.rs:291` discards the fields") and it's the single fact that reorders which option is actually smallest. Round 1 correctly identified that output is discarded; it didn't need to say *where* the loop is by the time you'd want to re-attach it, and that's exactly where option 1's cost balloons.

The second surprise is the same-tick staleness gap in Option 2 itself: naively wiring `VariableCaptured` into `Variables::from_events` looks complete and passes a mental test ("the event is on disk, substitution reads events, done") but silently fails on the auto-advance-in-one-tick case specifically, because `mod.rs` snapshots `Variables` before the loop runs. That's the one place in this whole design where "looks done" and "is done" diverge, and it's easy to miss without tracing the exact order of `mod.rs:3177` vs `mod.rs:4053` vs `mod.rs:4282`.

## Open Questions

- Does `capture_stdout_as` need multi-value support (e.g. capturing named regex groups from stdout, not just the whole trimmed string) for anything shirabe actually wants to do, or is "the entire trimmed stdout, allowlist-validated" sufficient for the known cases (branch name, single-token status values)? The PRD/plan step should confirm shirabe's concrete `default_action` candidates don't need multi-line or structured capture before locking the design to single-string.
- Should a failed capture (output doesn't pass `VALUE_PATTERN`) be silent, or should it write a distinguishable event (e.g. reuse `VariableCaptured` with a `failed: true`/omit-and-log) so a human debugging a workflow can tell "never captured" apart from "captured but value is stale from three runs ago"? Silent-skip is the safer runtime default but makes debugging harder; worth a decision, not an accident.
- Whether Option 1 (or a narrower version of it, e.g. only adding `last_action` to `EvidenceRequired` and `Terminal`, the two most common non-confirm stop reasons) is worth doing *at all* given Option 2 covers the motivating case — that's a scope call for whoever writes the actual design doc, not something this lead needs to resolve.

## Summary

The smallest koto change that actually satisfies the motivating case — a `default_action`'s output reaching a *later* state's directive text — is a `capture_stdout_as:` field on `ActionDecl` that emits a new additive `VariableCaptured` event, folded into the existing `Variables::from_events`/`{{VAR}}` substitution path; it touches no `NextResponse` field, no hand-rolled `Serialize` arm, and none of the four exhaustive-match combinators that make response-contract changes expensive, but it does need a same-tick staleness fix (rebuild or merge `Variables` after the advance loop runs, not before) or it silently fails on exactly the auto-advance-in-one-call case the design is for. Populating `action_output` on every `NextResponse` stop reason looks smaller at first glance but is actually the most invasive option, because the acting state and the stopping state diverge once auto-advance chains through several states in one tick, forcing the field through five variants, the Serialize impl, and three combinators. Merging action output into the per-state evidence map for `gates.*` routing is cheap and useful as a same-state guard but cannot reach a later state on its own, and writing to the `ContextStore` is cheap but reintroduces the manual agent step the design is trying to remove.
