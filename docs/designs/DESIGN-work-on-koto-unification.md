---
status: Proposed
problem: |
  The work-on skill and the private /implement workflow serve overlapping
  purposes with different orchestration backends. work-on uses koto for
  single-issue execution; /implement uses a custom Go workflow-tool for
  multi-issue plan execution. Koto v0.6.0 introduced structured gate output
  and first-class overrides, requiring template migration. This design
  specifies how to unify both workflows into a single work-on entry point
  backed entirely by koto, handling free-form tasks, single issues, and
  full plan execution through shared components.
---

# DESIGN: work-on-koto-unification

## Status

Proposed

## Context and Problem Statement

The shirabe plugin provides two implementation workflows that overlap in purpose
but diverge in architecture. The work-on skill handles single GitHub issues and
free-form tasks using koto for state management. The private /implement workflow
handles multi-issue plan execution using a custom Go-based workflow-tool that
provides dependency graph resolution, template-based directive generation,
per-issue state machines, and review/QA panels.

Koto v0.6.0 shipped breaking changes to gate declarations: gates now produce
structured JSON output injected into evidence maps, transitions route on
dot-path references (`gates.ci_check.exit_code`), overrides require mandatory
rationale, and compiler validation enforces the gate/transition/override
contract. The legacy gate format is supported via a transitory
`--allow-legacy-gates` flag.

The goal is a single `/work-on` entry point that:
- Handles free-form tasks, single issues, and plan document paths
- Uses koto for all orchestration (replacing workflow-tool)
- Migrates to v0.6.0 structured gate output
- Shares components (review panels, context management, PR creation) across
  all execution modes

Exploration identified a three-layer architecture:
1. **Koto per-issue state machine**: each issue gets its own koto workflow
2. **Skill-layer orchestrator**: manages the issue queue for multi-issue plans
3. **Shared components**: review panels, context assembly, entry routing

## Decision Drivers

- Koto's state machine is per-workflow by design; hierarchical states were
  explicitly deferred to "a later phase"
- The existing work-on template has 17 states and 8 gates that need v0.6.0
  migration
- workflow-tool's controller loop (dependency resolution, queue management,
  variable interpolation) has no koto equivalent today
- Review panels (3-agent scrutiny, 3-agent code review, QA) require multi-agent
  orchestration that koto gates can't express
- Cross-issue context must be bounded to prevent context window exhaustion on
  large plans (50+ issues)
- The v0.6.0 `--allow-legacy-gates` flag is transitory and will be removed

## Decisions Already Made

These choices were settled during exploration and should be treated as constraints:

- **Orchestrator lives in skill layer, not koto**: koto is per-workflow; multi-issue
  queue management is above its abstraction level
- **Per-issue koto workflows, not monolithic**: each issue gets its own state file;
  avoids koto's lack of sub-workflows/iteration
- **Review panels stay in skill markdown**: koto gates handle binary checks;
  multi-agent orchestration with feedback loops isn't expressible as gates
- **Gate migration proceeds independently**: mechanical refactoring not blocked by
  orchestrator design
- **External state tracking for orchestrator**: hybrid approach with koto context
  for content and a structured manifest for issue tracking
