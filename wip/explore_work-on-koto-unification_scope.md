# Explore Scope: work-on-koto-unification

## Visibility

Public

## Core Question

How should we evolve work-on into a unified implementation workflow that handles free-form tasks, single issues, and full plan execution -- replacing both the current work-on (koto-backed) and the private /implement workflow (workflow-tool-backed) -- while migrating to koto v0.6.0's structured gate output and first-class override system?

## Context

Koto recently released v0.6.0 with breaking changes to gate declarations: gates now produce structured JSON output that feeds into transition routing via dot-path references, a first-class override mechanism with mandatory rationale, and compiler validation of the gate/transition/override contract. Legacy gate format works with --allow-legacy-gates but that flag is transitory.

The current work-on skill already uses koto with 8 gates across a dual-path topology (issue-backed and free-form). The private /implement workflow uses a custom Go-based workflow-tool for multi-issue orchestration with dependency graph resolution, template-based directive generation, per-issue state machines, and review/QA panels. The goal is to absorb /implement's capabilities into work-on using koto for orchestration, producing a single entry point that routes based on input type (free-form task, single issue, or plan document path).

## In Scope

- Migrating work-on's existing gates to koto v0.6.0 structured output format
- Absorbing /implement's controller loop, multi-issue state, and review pipeline
- Identifying gaps: what koto can handle vs koto feature requests vs workflow redesigns
- Shared components across all three entry modes
- Context utilization patterns for multi-issue execution

## Out of Scope

- Changes to koto itself (identify feature requests only)
- /implement-doc design-doc-backed flow (focus on PLAN-backed execution)
- Modifications to explore, design, prd, or plan skills

## Research Leads

1. **What does migrating work-on's 8 gates to v0.6.0 structured output actually look like?**
   The current gates use context-exists and command types. We need to understand what each gate's structured output schema is, how to reference it in when clauses, and whether override_defaults make sense for each.

2. **Can koto express a dependency-graph-driven controller loop, or is that a gap?**
   workflow-tool's core value is controller next -- it resolves dependencies, picks the next ready issue, and emits a templated directive. Koto's state machine is per-workflow, not per-issue-within-a-workflow. This might be the biggest architectural question.

3. **How should multi-issue state map to koto's model?**
   workflow-tool maintains a rich JSON state file with per-issue status, commits, reviewer results, QA results, and dependency graphs. Koto has context keys (markdown blobs) and evidence maps. What's the right translation?

4. **What does entry-point routing look like in a single koto template?**
   Work-on currently has two entry paths (issue-backed, free-form) that converge at analysis. Adding a third path (plan-backed, multi-issue) means the template topology gets more complex. How do we keep it clean?

5. **Which workflow-tool capabilities become koto feature requests vs workflow redesigns?**
   Template variable interpolation, auto-skip of blocked issues, per-issue state transitions, directive generation -- some of these might map to koto features, others might need the workflow to work differently.

6. **How do the scrutiny/review/QA agent panels integrate with koto's gate system?**
   /implement runs 3-agent scrutiny panels and 3-agent review panels as gates between issue states. These are currently orchestrated by the skill's markdown instructions. With koto's new structured gate output, could these become formal koto gates?

7. **What context utilization patterns from /implement should carry over, and how?**
   /implement passes previous issue summaries, files changed, and key decisions to each subsequent issue via template variables. Work-on uses koto context keys. How do we preserve cross-issue context without blowing up the context window?
