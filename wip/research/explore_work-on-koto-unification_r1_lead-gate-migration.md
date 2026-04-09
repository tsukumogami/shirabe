# Lead: Gate migration to v0.6.0

## Findings

### Structured Output Schemas (v0.6.0)

Koto v0.6.0 gates return `StructuredGateResult` containing an `outcome` (GateOutcome enum) and `output` (JSON value). Gate output is injected into the evidence map under the `gates.` namespace for transition routing.

**Command gates** (`type: command`)
- Structured output: `{"exit_code": number, "error": string}`
- Exit code is the actual shell exit code (0 for pass, 1-255 for fail, -1 for timeout/error)
- Error field contains stderr message for spawn failures or "timed_out" for timeouts
- Exit code 0 = `outcome: Passed`; non-zero = `outcome: Failed`; -1 timeout = `outcome: TimedOut`

**Context-exists gates** (`type: context-exists`)
- Structured output: `{"exists": boolean, "error": string}`
- Exists = true if the specified context key is present, false otherwise
- Error field empty string on success; contains message on system errors
- True = `outcome: Passed`; false = `outcome: Failed`

**Context-matches gates** (`type: context-matches`)
- Structured output: `{"matches": boolean, "error": string}`
- Matches = true if regex pattern matches the context key content, false otherwise
- Error field empty on success; contains regex compilation error message on bad pattern
- True = `outcome: Passed`; false = `outcome: Failed`

Schema definitions are static and enforced by validation (types.rs:176-183).

### When Clause Referencing

Gate output is injected into evidence under the `gates` namespace. In when clauses, reference gate output using dot-path traversal: `gates.<gate_name>.<field_name>`.

**Examples from test fixtures** (test/functional/fixtures/templates/structured-routing.md):
```yaml
transitions:
  - target: pass
    when:
      gates.ci_check.exit_code: 0
  - target: fix
    when:
      gates.ci_check.exit_code: 1
```

The resolver walks the path segment-by-segment (types.rs:228-240). Invalid paths return `None`, failing that transition's condition.

**Evidence injection rules** (advance.rs:376-451):
- Gate output is ONLY injected if the state has at least one transition with a `when` clause containing a `gates.*` key (called "structured routing" or "gates routing")
- Legacy states (gates with no `gates.*` references) route purely on `outcome: Passed/Failed` blocking behavior, not on output values
- The "gates" key is reserved in the evidence map; CLI validation rejects any `--with-data` payload containing a top-level "gates" key

### Override Defaults

Each gate can declare an optional `override_default` field in the template YAML. When a gate has an active override (stored in `GateOverrideRecorded` event), the override value is injected instead of running the gate command.

**Override value resolution** (advance.rs:309-351):
1. Advance loop checks `GateOverrideRecorded` events from the session history
2. If an override is found for the gate, it is injected as a synthetic `Passed` outcome with the override value as output
3. No `GateEvaluated` event is emitted for overridden gates (only recorded when override was first applied)

**Built-in defaults** (types.rs:194-200, gate.rs:216-222):
- Command: `{"exit_code": 0, "error": ""}`
- Context-exists: `{"exists": true, "error": ""}`
- Context-matches: `{"matches": true, "error": ""}`

The `koto overrides record` command resolves override value by checking: `--with-data` arg → `override_default` field → built-in default → error if none available.

### Validation Rules (D1-D5)

**D1**: Gate type must be one of `command`, `context-exists`, or `context-matches`. Unknown types rejected at compile time.

**D2**: If a gate declares `override_default`, it must be a JSON object with all required fields from that gate type's schema, no extra fields, and correct field types.

Example validation (types.rs:365-436):
```
- Command gate override_default must contain {"exit_code": number, "error": string}
- Context-exists override_default must contain {"exists": boolean, "error": string}
- Context-matches override_default must contain {"matches": boolean, "error": string}
```

**D3**: Transition when clauses must reference only fields declared in that gate's schema OR be conditional on agent evidence (fields in the accepts block). Unknown fields are rejected.

**D4**: For states with pure-gate transitions (when clause contains ONLY `gates.*` keys), at least one transition must fire when all gates use their override defaults. This ensures the template is not deadlocked with overrides applied.

**D5**: In strict mode, a state with gates but no `gates.*` when-clause references is an error (legacy behavior warning in permissive mode).

### Work-on's 8 Gates: Migration Checklist

Based on work-on.md (koto-templates/work-on.md):

1. **context_artifact** (context_injection state)
   - Type: `context-exists`, key: `context.md`
   - Output schema: `{"exists": boolean, "error": string}`
   - When clause: `gates.context_artifact.exists: true` (if using structured routing)
   - Override default: `{"exists": true, "error": ""}` (built-in sensible for free-form tasks; could be false if artifact is truly optional)
   - Current behavior: gate failure routes to same state with override acceptance

2. **on_feature_branch** (setup_issue_backed and setup_free_form states)
   - Type: `command`, command: `test "$(git rev-parse --abbrev-ref HEAD)" != "main"`
   - Output schema: `{"exit_code": number, "error": string}`
   - When clause: `gates.on_feature_branch.exit_code: 0` (if structured routing used)
   - Override default: `{"exit_code": 0, "error": ""}` (sensible default; overrides typically mean "trust this is on a feature branch")
   - Note: Appears in two states; may want to reference same gate twice with different when conditions

3. **baseline_exists** (setup_issue_backed and setup_free_form states)
   - Type: `context-exists`, key: `baseline.md`
   - Output schema: `{"exists": boolean, "error": string}`
   - When clause: `gates.baseline_exists.exists: true`
   - Override default: `{"exists": true, "error": ""}`
   - Note: Appears in two states

4. **staleness_fresh** (staleness_check state)
   - Type: `command`, command: `check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '.introspection_recommended == false'`
   - Output schema: `{"exit_code": number, "error": string}`
   - When clause: `gates.staleness_fresh.exit_code: 0` (exit 0 = fresh, non-zero = stale)
   - Override default: `{"exit_code": 0, "error": ""}` (assumes codebase is fresh by default when overridden)

5. **introspection_artifact** (introspection state)
   - Type: `context-exists`, key: `introspection.md`
   - Output schema: `{"exists": boolean, "error": string}`
   - When clause: `gates.introspection_artifact.exists: true`
   - Override default: `{"exists": true, "error": ""}`

6. **plan_artifact** (analysis state)
   - Type: `context-exists`, key: `plan.md`
   - Output schema: `{"exists": boolean, "error": string}`
   - When clause: `gates.plan_artifact.exists: true`
   - Override default: `{"exists": true, "error": ""}`

7. **code_committed** (implementation state)
   - Type: `command`, command: `test "$(git rev-parse --abbrev-ref HEAD)" != "main" && test "$(git log --oneline main..HEAD | wc -l)" -gt 0 && go test ./... 2>/dev/null`
   - Output schema: `{"exit_code": number, "error": string}`
   - When clause: `gates.code_committed.exit_code: 0`
   - Override default: `{"exit_code": 0, "error": ""}` (overrides mean "trust implementation is complete and tested")
   - Gotcha: Complex multi-clause command; exit code is from final test, not intermediate checks

8. **ci_passing** (ci_monitor state)
   - Type: `command`, command: `gh pr checks $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number // empty') --json state --jq '[.[] | select(.state != \"SUCCESS\")] | length == 0' | grep -q true`
   - Output schema: `{"exit_code": number, "error": string}`
   - When clause: `gates.ci_passing.exit_code: 0`
   - Override default: `{"exit_code": 0, "error": ""}` (override means "CI checks passed or bypassed")
   - Gotcha: Command chains multiple gh calls; fragile to API changes

### Migration Concerns

**Issue 1**: Current template uses implicit gate blocking without structured when clauses. Many states have gates but no transition conditions referencing `gates.*`. Need to either:
- Add `gates.*` when clauses to all transitions (structured mode)
- Add explicit agent evidence fields (via accepts block) that trigger on gate failure
- Accept D5 warning in permissive mode

**Issue 2**: Multiple states reuse gate names (`on_feature_branch`, `baseline_exists` appear in two states). In v0.6.0, each state evaluates its own gates independently. Reusing names is safe but the test conditions must be identical or the transition logic must differentiate them. Consider:
- Keep gate names in each state (current approach) - requires separate when clauses per state
- Or refactor workflow to centralize setup checking

**Issue 3**: Override semantics unclear for some gates. Example:
- `context_artifact` in issue-backed mode is required (no bypass documented)
- But current code paths accept both `completed` and `override` verdicts
- Migration must decide: does `override_default` mean "force assume artifact exists" or "force assume it doesn't exist"?

**Issue 4**: Command gates with complex shells (multiple pipes, jq, nested sh -c) are fragile. Errors in intermediate steps are not visible; only final exit code is captured. Migration should consider:
- Breaking complex commands into simpler gates or multiple gates
- Capturing stderr for debugging
- Adding explicit error handling in gate output

### Test Fixture Examples

`structured-routing.md` shows the canonical v0.6.0 pattern:
- Gates evaluated
- Output available in when clause via `gates.<name>.<field>`
- Transitions route on specific output field values
- No explicit agent evidence needed for gate routing

`structured-gates.md` shows blocking behavior without routing:
- Gate failure appears in `blocking_conditions` output
- Transition requires agent submission (accepts block implicit)
- No `gates.*` when clause

## Implications

1. **Transition routing refactoring required**: All 8 gates must move from implicit boolean blocking to explicit when-clause routing with `gates.*` references. This affects all state definitions in the template.

2. **Override strategy must be defined**: For each gate, decide whether override_default represents "assume this passed" or "assume this failed" and document it. This directly impacts how agents override gates in production.

3. **Command gate complexity**: The most fragile gates are `code_committed` and `ci_passing` due to shell piping. v0.6.0 doesn't simplify this, but structured output might help agents detect and retry on specific error conditions.

4. **Context artifact semantics unclear**: Current code accepts both `completed` and `override` verdicts, but the gate itself doesn't disappear. Migration must clarify whether:
   - Override means "force the gate to pass"
   - Or "skip the gate and allow manual artifact upload"

5. **Multi-state gate reuse**: `on_feature_branch` and `baseline_exists` appear twice. Either:
   - Move them to a parent state that both paths require
   - Or accept that the same gate is evaluated twice with identical logic
   - v0.6.0 doesn't provide gate inheritance or abstraction

## Surprises

1. **Gate output is always injected**: Even when gates fail, output is injected into evidence if the state has structured routing. This allows when clauses to distinguish "exit_code: 1" from "exit_code: 127" (command not found), enabling fine-grained routing on failure reasons.

2. **Override mechanism is ephemeral**: Overrides are stored as `GateOverrideRecorded` events in history, not in the template. A future invocation needs to parse the event log to reconstruct active overrides. This is runtime state, not configuration.

3. **Legacy vs. structured modes**: The validation system (D5) permits both legacy (boolean pass/fail) and structured (gates.* routing) gates in the same template, but NOT in the same state. A state must pick one mode consistently. This affects how mixed transitions are handled.

4. **Schema validation is strict**: override_default must match the schema exactly. A command gate override_default with `{"exit_code": 0, "error": "", "extra_field": "x"}` fails D2 validation, even though extra fields are harmless at runtime. This forces template authors to be precise.

5. **D4 reachability is compile-time only**: The template compiler checks that pure-gate transitions fire with override defaults, but agents can provide evidence that bypasses gate routing entirely. D4 only validates gate-only transitions, not mixed (agent + gate) routing.

## Open Questions

1. **Ambiguous verdict mapping**: In work-on, a state with a gate accepts `status: completed, override, blocked`. How does this map to gate output?
   - Does `override` suppress gate evaluation entirely, or inject a synthetic passed result?
   - Current code (advance.rs) shows synthetic passed; confirm this matches intent.

2. **Error field population**: For context-exists gates, what populates the `error` field?
   - Code shows empty string on success/failure
   - Only non-empty on context store unavailable
   - Is this intentional or should it capture "key not found" reason?

3. **D4 strict vs. permissive**: Should work-on compile in strict mode (D5 error on legacy gates)?
   - Or should it use `--allow-legacy-gates` and accept warnings?
   - Strict mode would force all transitions to explicitly reference `gates.*`

4. **Multi-state gate name collisions**: If two states have a gate named `on_feature_branch`, and both are visited in the same invocation:
   - Are overrides tracked per-state or globally by gate name?
   - Can the same gate be overridden differently in different states?

5. **Command gate timeout semantics**: Timeout exit code is -1 with error "timed_out". But the template command already has a timeout value (default 30s).
   - Should complex commands like `ci_passing` have longer timeouts?
   - How do agents know a gate timed out vs. failed?

## Summary

Koto v0.6.0 structured gate output provides `{exit_code/exists/matches, error}` for each gate type, injected into evidence under `gates.NAME.FIELD` for routing via when clauses; work-on's 8 gates all have clear schema migrations (4 context-exists, 4 command) and reasonable override defaults, but the template must be refactored from implicit boolean blocking to explicit structured when-clause routing (D5 compatibility), and semantic ambiguity remains around override verdicts ("force pass" vs. "skip gate") that must be resolved before implementation.

