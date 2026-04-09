<!-- decision:start id="koto-template-three-entry-modes" status="assumed" -->
### Decision: Unified koto template structure for three entry modes

**Context**

The work-on skill's koto template currently implements a dual-path topology: issue-backed and free-form modes branch at the entry state via evidence routing, follow mode-specific pre-analysis chains, then converge at the analysis state and share all subsequent phases through completion. The template has 17 states and 8 gates. Adding plan-backed execution (multi-issue plans from /implement) requires a third entry path.

The per-issue koto workflow architecture is already decided: plan-backed mode creates one koto workflow per issue, with a skill-layer orchestrator managing the queue across issues. This means the koto template doesn't need to represent multi-issue iteration -- it only needs to route a third mode through an appropriate pre-analysis path to the shared backbone.

Koto supports evidence routing via when conditions on enum fields, gate routing via structured output, self-loops, and split topology. It does not support template composition, sub-workflows, or bounded iteration.

**Assumptions**

- Per-issue koto workflows remain the settled architecture for plan-backed mode. If this changes, the template would need internal multi-issue orchestration that koto can't express today.
- Plan-backed pre-analysis (reading the plan doc, extracting per-issue goals and acceptance criteria) is expressible as 2-3 koto states. If it turns out to need dynamic behavior, those states would move to the skill layer.
- The 3-way mode enum at entry doesn't create compile-time validation issues. The existing dual-path pattern already uses mutual-exclusion when conditions that scale to a third branch.

**Chosen: Single monolithic template with 3 entry branches (Option A)**

Add `plan_backed` to the entry state's mode enum alongside `issue_backed` and `free_form`. Create a short pre-analysis chain for plan-backed mode (plan context injection, plan validation, then setup) that converges at the existing analysis state. The template grows from 17 to approximately 20 states.

The entry state becomes:
```yaml
entry:
  accepts:
    mode:
      type: enum
      values: [issue_backed, free_form, plan_backed]
  transitions:
    - target: context_injection
      when: { mode: issue_backed }
    - target: task_validation
      when: { mode: free_form }
    - target: plan_context_injection
      when: { mode: plan_backed }
```

The plan-backed pre-analysis chain handles reading the plan document, extracting the current issue's goals and acceptance criteria, and setting up the branch and baseline. It then joins the shared backbone at analysis.

All post-analysis states (implementation, finalization, pr_creation, ci_monitor, done, done_blocked) remain unchanged. The skill-layer orchestrator handles sequencing across issues by initializing separate koto workflows.

**Rationale**

The per-issue workflow architecture eliminates the original argument against Option A. The exploration identified multi-issue post-analysis orchestration as A's weakness, but that concern applies only if a single koto workflow must manage multiple issues. Since each issue gets its own workflow, the template stays simple -- it just needs a third pre-analysis branch.

Keeping all routing in the koto template preserves three properties that matter:
1. Compile-time path validation: koto's compiler checks mutual exclusivity and reachability across all three mode branches.
2. Full resume reliability: koto state files capture the exact position in the workflow. No skill-layer state needed for pre-analysis phases.
3. Single-file maintainability: one template to update, one set of states to reason about.

Option D (skill-layer delegation) would move pre-analysis outside koto's visibility. That was justified when pre-analysis needed dynamic behavior koto couldn't express. With per-issue workflows, the pre-analysis is static and fits naturally as koto states.

**Alternatives Considered**

- **Option B (Template composition with base + overlays)**: Koto has no include or composition mechanism. Templates are monolithic YAML. This option is infeasible without building a custom pre-processor, which adds tooling complexity for no structural benefit.
- **Option C (Three separate templates)**: Duplicates the shared backbone (analysis through done, 7+ states) across three files. Changes to shared states must be applied three times. Loses the unified entry point and splits decision logs across templates. The maintenance burden doesn't justify the per-template simplicity.
- **Option D (Single template + skill-layer delegation)**: Moves pre-analysis to the skill layer, reducing koto's visibility into workflow progress. Originally recommended by exploration because it avoided multi-issue orchestration in the state machine. With per-issue workflows decided, the multi-issue concern is resolved, and D's trade-off (less visibility, partial resume) is no longer worth making.

**Consequences**

The template grows modestly (3 new states for plan-backed pre-analysis). The skill-layer orchestrator for plan-backed mode remains outside the template -- it manages the queue of issues and initializes per-issue koto workflows. The entry state's mode enum becomes the single point of mode detection, and all mode-specific behavior before analysis is explicitly modeled in the template.

When koto adds bounded iteration (feature #105), the architecture can evolve: the orchestrator could potentially move into koto. But that's an optimization, not a prerequisite. The per-issue workflow approach works today with no koto feature gaps.
<!-- decision:end -->
