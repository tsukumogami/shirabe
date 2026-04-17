# Lead: plan-backed PR model — fork vs. skip

## Findings

### Terminal path in work-on.md

The `finalization → pr_creation → ci_monitor → done` path in `work-on.md` is rigid. `finalization` has three transitions, all targeting `pr_creation`:

- `finalization_status: issues_found` → `implementation` (re-loop)
- `finalization_status: ready_for_pr` (with gate) → `pr_creation`
- `finalization_status: deferred_items_noted` (with gate) → `pr_creation`
- unconditional fallback → `pr_creation`

There is no conditional path out of `finalization` that bypasses `pr_creation`. Every happy-path evidence value leads to `pr_creation`.

The `pr_creation` state `accepts` block defines:
```yaml
pr_status:
  type: enum
  values: [created, creation_failed_retry, creation_failed_escalate]
```

None of these signal "skip" or "shared". The state requires the agent to submit a `pr_url` string alongside `pr_status: created`. There is no bypass route.

### setup_plan_backed vs. setup_issue_backed differences

Both paths converge at `analysis` and share all subsequent states. The only divergence is:
- `setup_issue_backed` routes to `staleness_check`; `setup_plan_backed` skips it and routes directly to `analysis`.
- Plan-backed mode skips `staleness_check` and `introspection` entirely.

But once `analysis` is reached, all three modes (issue-backed, free-form, plan-backed) follow identical paths through `implementation → scrutiny → review → qa_validation → finalization → pr_creation → ci_monitor → done`. There is no further plan-backed divergence after `analysis`.

The `SHARED_BRANCH` variable is declared as `required: false` in the template. The `setup_plan_backed` directive instructs the agent to submit `status: override` when `SHARED_BRANCH` is set. But the template has no mechanism to detect this automatically — it relies entirely on the agent reading the directive and acting accordingly.

### SKILL.md plan-backed child mode documentation

SKILL.md (lines 64-79) documents plan-backed child mode but says nothing about PR creation being the orchestrator's responsibility. It states:

> When the orchestrator provides a `SHARED_BRANCH` variable, do not create a new branch. In `setup_plan_backed`, submit `status: override` and commit directly to `SHARED_BRANCH`.

The `pr_creation` state is not mentioned in the plan-backed child section at all. There is no guidance telling children to skip or defer PR creation. The current model requires the agent to figure this out from context or the `phase-6-pr.md` reference file, which says: "Check if a PR already exists: `gh pr list --head $(git rev-parse --abbrev-ref HEAD)`" — implying the child would find the orchestrator's draft PR and treat it as already created.

In practice, children navigate `pr_creation` by finding the existing draft PR on `SHARED_BRANCH` and submitting its URL as `pr_url`. This works but is semantically incorrect: the child is not reporting on a PR it created; it's re-reporting the orchestrator's PR. If no PR is found (edge case), the child would create a second one — directly breaking the shared PR model.

### Koto `when` condition capabilities

The koto engine's `when` conditions use strict JSON equality matching via `resolve_value()`, which does dot-path traversal (e.g., `gates.ci.exit_code: 0`). The matching function signature:

```rust
let all_match = conditions
    .iter()
    .all(|(field, expected)| resolve_value(evidence, field) == Some(expected));
```

There is no `is_set` operator, no existence check on variables, no boolean operator beyond AND (all fields must match). Variables are substituted into directive text and gate commands via `{{VAR}}` syntax, but variable values are not available in `when` conditions — `when` only matches against submitted evidence fields and gate output fields.

This means `when: SHARED_BRANCH: is_set` (approach c) is not implementable in the current koto version. Template variables cannot be referenced in `when` clauses. The only way to use a variable in routing is to interpolate it into a `command` gate and route on the gate's `exit_code`.

A workaround exists: add a `command` gate like `test -n "{{SHARED_BRANCH}}"` with `override_default` for the case where `SHARED_BRANCH` is empty (or missing). But this requires `SHARED_BRANCH` to be declared in the template (it already is, `required: false`), and the allowlist sanitizer (`^[a-zA-Z0-9._/-]+$`) would reject an empty default string at init time — so when `SHARED_BRANCH` is not set, the variable substitution fails with an error rather than substituting empty.

Actually, examining the variable substitution design: `required: false` variables with no value provided at init time use their `default` value (which defaults to `""`). The empty-string substitution would make `test -n ""` evaluate to exit 1 (string not set). So a gate `type: command; command: test -n "{{SHARED_BRANCH}}"` would pass when `SHARED_BRANCH` is set and fail when not set. This is workable but convoluted.

### Approach evaluation

**Approach a — Evidence-based skip**: Add `pr_status: shared` (or `skipped`) to the `pr_creation` enum. The agent in plan-backed mode submits `pr_status: shared` and koto routes to `done` directly (or a new `done_plan_backed` state), skipping `ci_monitor`.

- **What koto features it requires**: Adding a new enum value to `pr_status`, a new transition condition, and a new target state (or reusing `done`). All are standard accepted/when constructs — implementable today.
- **Implementability**: Yes, straightforward. Add `shared` to `pr_status` values, add transition `when: {pr_status: shared} → done`. No new koto features needed.
- **Main cost**: The `pr_creation` state is still visited; the agent must still make a `koto next` call. The state's directive must instruct plan-backed children to detect `SHARED_BRANCH` and submit `pr_status: shared`. This detection is agent-side logic, not template-enforced.
- **Risk**: The agent could submit `pr_status: created` with the orchestrator's PR URL (current behavior). The new enum value only helps if the agent is correctly instructed. Nothing structurally prevents misuse.

**Approach b — Template fork (`work-on-plan-backed.md`)**: Create a separate template that is `work-on.md` minus `pr_creation` and `ci_monitor`. `finalization` routes directly to `done_plan_backed` (a new terminal state). The orchestrator uses this template via the `default_template` field in `spawn_and_await`.

- **What koto features it requires**: `spawn_and_await` in `work-on-plan.md` has `materialize_children: {default_template: work-on.md}`. The template name is hardcoded in the orchestrator. To use `work-on-plan-backed.md`, either change the default template in `work-on-plan.md` or support per-task template override in the tasks JSON (not a current feature — the `materialize_children` block does not support per-child template overrides based on task data).
- **Implementability**: The template itself is easy to write. But using it requires either: (1) changing the default_template in the orchestrator (all children use the fork), or (2) a per-task template override capability in koto (not supported). Since all children in a plan-backed workflow are plan-backed, option (1) works — change `work-on-plan.md` to use `default_template: work-on-plan-backed.md`.
- **Maintain cost**: Two templates in sync. Shared states (`entry` through `finalization`) must be kept consistent across both files. Adding a state to `work-on.md` requires adding it to `work-on-plan-backed.md` too, or deliberate divergence. This is a real maintenance burden that grows with template complexity (currently 17 states).
- **Benefit**: Structural enforcement. A child running `work-on-plan-backed.md` physically cannot reach `pr_creation`. No agent instruction required; the workflow simply terminates at `done_plan_backed` after `finalization`.

**Approach c — Conditional terminal after finalization (`when: SHARED_BRANCH: is_set`)**: Add a `finalization → done_plan_backed` transition that fires when `SHARED_BRANCH` is set, bypassing `pr_creation`.

- **What koto features it requires**: An `is_set` operator on `when` conditions, or a mechanism to route based on template variable values. **Neither exists in the current koto engine.** `when` only matches against submitted evidence and gate output (strict JSON equality, dot-path traversal). Variables are not part of the evidence map and cannot appear in `when` clauses.
- **Implementability**: Not directly implementable today. Could be approximated with a command gate (`test -n "{{SHARED_BRANCH}}"`) that injects a gate output field (`gates.shared_branch_set.exit_code`) into the evidence map, then routes on `gates.shared_branch_set.exit_code: 0 → done_plan_backed`. This is architecturally sound (uses existing koto features) but requires changing `finalization` to add a gate and two new transitions. The gate's exit code would encode the plan-backed vs. issue-backed distinction structurally.

The command-gate approximation of approach c deserves more attention:
```yaml
finalization:
  gates:
    shared_branch_set:
      type: command
      command: "test -n \"{{SHARED_BRANCH}}\""
      override_default:
        exit_code: 1
        error: ""
  accepts:
    finalization_status: ...
  transitions:
    - target: done_plan_backed
      when:
        gates.shared_branch_set.exit_code: 0
        finalization_status: ready_for_pr
    - target: pr_creation
      when:
        gates.shared_branch_set.exit_code: 1
        finalization_status: ready_for_pr
    ...
```

This works mechanically. But every `finalization_status` value now needs two transitions (one per gate path), doubling the transition count. And the override_default handling for the case where `SHARED_BRANCH` is unset (not provided at init time) needs careful testing — if the variable substitution panics on unset variables rather than defaulting to empty, this breaks.

From the variable substitution design: "required: false variables with no value provided at init time use their default value (which defaults to `""`)" — but the allowlist requires at least one character (`+` quantifier). An empty-string `SHARED_BRANCH` would fail allowlist validation at init time. This means the command-gate approach only works if `SHARED_BRANCH` always has a value at init time (even a dummy placeholder for non-plan-backed workflows), which is not the current design.

## Implications

1. **Approach b (template fork) is the cleanest structural solution** and is implementable today with only one change to `work-on-plan.md` (the `default_template` value). The template itself is straightforward to write.

2. **Approach a (evidence-based skip) is implementable with lowest disruption** — one new enum value, one new transition. But it relies on agent judgment to detect plan-backed mode and submit the right evidence. It does not eliminate `pr_creation` from the child's state path.

3. **Approach c (conditional terminal via `is_set`)** is not implementable in its clean form. The command-gate approximation works mechanically but is awkward and breaks the single-responsibility principle of `finalization`. The empty-string allowlist problem may require a dummy non-empty placeholder value for `SHARED_BRANCH` in non-plan-backed workflows, which is a larger change to the init call sites.

4. **The maintenance cost of approach b is the primary objection**. With 17 shared states, keeping `work-on.md` and `work-on-plan-backed.md` in sync is a real cost. Any template change must be applied to both files, and the mermaid diagrams for both must be regenerated and committed. If the template evolves quickly (new states, new phases), this doubles the churn.

5. **Approach b could be made less expensive** by separating the shared prefix into a base template if koto supported template composition or includes. It does not — templates are self-contained. So the fork is a full copy.

6. **The model mismatch is real but low-impact today**: children currently navigate `pr_creation` by finding the existing draft PR and submitting its URL. This works in happy-path scenarios. The risk is when the draft PR doesn't exist (edge case) or when a child's CI is run against its own commits rather than the orchestrator's PR checks. Both are likely rare in practice.

## Surprises

1. **`SHARED_BRANCH` is already declared in `work-on.md` as `required: false`** — the template already signals plan-backed mode awareness. But the variable is only used in the directive text of `setup_plan_backed`, not in any gate or transition condition. The template does not structurally enforce anything based on `SHARED_BRANCH`.

2. **SKILL.md is silent on PR creation for plan-backed children**. The plan-backed child mode documentation (lines 64-79) describes branch handling in detail but says nothing about `pr_creation`. This is a documentation gap as much as a structural gap.

3. **The `pr_creation` state's directive instructs the agent to check for an existing PR** ("Check if a PR already exists: `gh pr list --head ...`"). This is precisely the workaround children use today. The directive implicitly handles the plan-backed case, just not explicitly.

4. **Koto's `when` conditions have no operator vocabulary** — only strict equality. There is no `!=`, no `>`, no `is_set`, no regex. This is a deliberate design choice (see the DESIGN-template-evidence-routing.md). Extending `when` with new operators would be a koto engine change, not just a template change.

5. **The `materialize_children` block in `work-on-plan.md` uses `default_template: work-on.md`** — a single hardcoded template for all children. Changing this to `work-on-plan-backed.md` would be a one-line change that switches all children to the fork. The word "default" suggests per-task overrides might be intended for the future, but the current tasks JSON schema does not include a template field.

## Open Questions

1. **What is the actual error rate from children mishandling `pr_creation`?** If children reliably find the existing draft PR and submit its URL, the practical impact may be minimal even if semantically wrong. Quantifying this would inform whether a fix is urgent.

2. **Could approach b be implemented with a partial fork — only the finalization-onward states?** Koto does not support template composition, so no. But the question of whether koto should support it is worth tracking.

3. **If approach a is chosen, should the `pr_creation` directive be updated** to explicitly tell plan-backed children to submit `pr_status: shared`? Without this update, approach a only adds an enum value but agents still need to infer the right behavior.

4. **What happens to `ci_monitor` in approach a?** If plan-backed children skip `pr_creation` and go to `done`, they also skip `ci_monitor`. Is that correct? The orchestrator's `work-on-plan.md` has its own `ci_monitor` for the shared PR. So yes — children should not run CI monitoring; that's the orchestrator's job.

5. **Does the allowlist restriction on variable values (`^[a-zA-Z0-9._/-]+$`) block the command-gate approximation of approach c?** Yes, unless `SHARED_BRANCH` is always set to a non-empty value at init time. This would require changing issue-backed and free-form `koto init` calls to pass `--var SHARED_BRANCH=none` (or similar placeholder), which is a broader change.

## Summary

The `finalization → pr_creation → ci_monitor → done` path in `work-on.md` is unconditional — all three modes drive through it with no existing bypass. `pr_creation` accepts only `[created, creation_failed_retry, creation_failed_escalate]`; plan-backed children currently navigate it by finding the orchestrator's existing draft PR and submitting its URL, which is semantically incorrect but works in practice.

Of the three approaches, the template fork (approach b) offers the cleanest structural fix: `work-on-plan-backed.md` would terminate at `done_plan_backed` after `finalization`, physically preventing children from reaching `pr_creation`. This requires changing one line in `work-on-plan.md` (`default_template`) but carries ongoing maintenance cost for the 17 shared states. The evidence-based skip (approach a) is the lowest-disruption option — add `pr_status: shared` to the enum and a new transition to `done`, requiring no new koto features, but it remains agent-side convention rather than structural enforcement.

Approach c (variable-based routing) is not implementable today: koto `when` conditions only support strict JSON equality on submitted evidence and gate output, with no `is_set` operator for variables. A command-gate workaround exists but is complicated by the allowlist restriction on empty variable values, making it impractical without broader init-call changes.
