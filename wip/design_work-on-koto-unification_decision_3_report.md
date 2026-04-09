<!-- decision:start id="gate-migration-patterns" status="assumed" -->
### Decision: Gate Migration Patterns for v0.6.0

**Context**

work-on's koto template has 8 gates that need migration from legacy boolean blocking to v0.6.0 structured output format. The gates break down into two categories: 4 context-exists gates (straightforward schema: `{exists, error}`) and 4 command gates (schema: `{exit_code, error}`). The command gates range from a simple branch check (`test branch != main`) to complex multi-clause shells. The most complex is `code_committed`, which chains a branch check, commit count check, and test suite run into a single command -- making failures opaque since only the final exit code is captured. The `ci_passing` gate similarly chains multiple `gh` API calls.

Koto v0.6.0 introduces three key changes: gate output is injected into the evidence map under `gates.NAME.FIELD` for transition routing, override defaults must match gate type schemas (D2), and strict mode (D5) requires every gated state to have `gates.*` references in its when clauses. The `--allow-legacy-gates` flag permits legacy behavior but is a deprecation path. Mixed routing (combining `gates.*` conditions with agent evidence in the same when clause) is natively supported and tested via the `mixed-routing` fixture.

**Assumptions**

- `--allow-legacy-gates` is a deprecation path, not a permanent feature. If this is wrong, permissive mode could remain viable, but it would prevent using structured output for error routing.
- Decomposing `code_committed` into three gates won't cause meaningful evaluation latency. The individual checks (branch, git log, go test) are each fast, and `go test` was already part of the compound command.
- Gate overrides are tracked globally by name, not per-state. Two states sharing `on_feature_branch` would share an override. This is acceptable because both states need the same check to pass.

**Chosen: Strict Mode with Selective Decomposition**

Compile in strict mode (no `--allow-legacy-gates`). Add `gates.*` when clauses to every gated state's transitions using mixed routing (combining gate conditions with agent evidence). Decompose `code_committed` into three atomic gates; keep all other gates intact.

The specific migration for each gate:

**Context-exists gates (4 gates, direct migration):**
- `context_artifact`, `baseline_exists`, `introspection_artifact`, `plan_artifact`
- When clause: `gates.NAME.exists: true`
- Override default: built-in `{"exists": true, "error": ""}` (no explicit override_default needed)

**Simple command gates (2 gates, direct migration):**
- `on_feature_branch` -- command: `test "$(git rev-parse --abbrev-ref HEAD)" != "main"`
- `staleness_fresh` -- command: `check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '.introspection_recommended == false'`
- When clause: `gates.NAME.exit_code: 0`
- Override default: built-in `{"exit_code": 0, "error": ""}` (no explicit override_default needed)

**Decomposed gate (code_committed -> 3 gates):**
- `on_feature_branch_impl` -- command: `test "$(git rev-parse --abbrev-ref HEAD)" != "main"`
- `has_commits` -- command: `test "$(git log --oneline main..HEAD | wc -l)" -gt 0`
- `tests_passing` -- command: `go test ./... 2>/dev/null`
- Each gets its own when clause: `gates.NAME.exit_code: 0`
- Implementation state transitions can route on individual failures for targeted agent remediation

**Preserved compound gate (ci_passing, no decomposition):**
- Command stays as-is: the full `gh pr checks` pipeline
- When clause: `gates.ci_passing.exit_code: 0`
- Rationale: CI failure remediation is uniform regardless of which check failed -- the agent either fixes code or reports unresolvable. Decomposition would add complexity without changing agent behavior.

**Mixed routing pattern for all states:**
Transitions combine gate conditions with agent evidence. Example for the implementation state:
```yaml
transitions:
  - target: finalization
    when:
      gates.on_feature_branch_impl.exit_code: 0
      gates.has_commits.exit_code: 0
      gates.tests_passing.exit_code: 0
      implementation_status: complete
  - target: implementation
    when:
      implementation_status: partial_tests_failing_retry
```

This pattern means D4 doesn't constrain transitions (it only validates pure-gate routes), and agents can still override gate failures through their evidence submissions.

**Rationale**

Strict mode eliminates dependency on the deprecated `--allow-legacy-gates` flag and ensures the template is fully compatible with v0.6.0's intended usage. Selective decomposition targets the gate where diagnostic value is highest: `code_committed` fails most often during implementation, and agents need to know whether they're on the wrong branch, haven't committed yet, or have failing tests -- these require different remediation actions. The `ci_passing` gate doesn't benefit from decomposition because the agent's response to any CI failure is the same: investigate and fix or escalate. Mixed routing preserves the existing agent evidence flow while adding structured gate conditions, which is the least disruptive migration path for the transition definitions.

**Alternatives Considered**

- **Full Decomposition (strict, decompose all compound gates)**: Decomposes both `code_committed` and `ci_passing`, increasing gate count to 11. Rejected because `ci_passing` decomposition adds complexity without changing agent remediation behavior. The diagnostic benefit of knowing which specific CI check failed is minimal when the agent will read CI output regardless.

- **Preserve All Compound Gates (strict, no decomposition)**: Keeps all 8 gates as-is and adds structured routing. Rejected because `code_committed` failures are the most common pain point in work-on workflows, and agents waste cycles investigating which clause failed when the exit code is opaque.

- **Permissive Incremental Migration**: Uses `--allow-legacy-gates` to migrate simple gates first. Rejected because it creates dependency on a deprecated flag and introduces technical debt. The full migration is not significantly harder than a partial one, and the incremental approach means two rounds of template changes instead of one.

**Consequences**

The implementation state's gate section grows from 1 gate to 3. Template authors and contributors need to understand mixed routing (gates.* + agent evidence in when clauses). The total gate count across the template increases from 8 to 10. Override behavior becomes clearer: all overrides mean "assume the gate passed" using built-in defaults, with no need for explicit override_default fields on any gate. The `summary_exists` gate in the finalization state (context-exists, not one of the original 8) also migrates to structured routing for consistency.
<!-- decision:end -->
