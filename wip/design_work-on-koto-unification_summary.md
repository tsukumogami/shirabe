# Design Summary: work-on-koto-unification

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** Unify work-on and /implement into a single koto-backed workflow that handles free-form tasks, single issues, and multi-issue plans, while migrating to koto v0.6.0 structured gate output.

## Design Decisions (Phase 1-3)
Four decisions evaluated with cross-validation, all high confidence:

1. **Template topology:** Single monolithic per-issue template with 3-way entry routing (~23 states)
2. **Orchestrator:** Koto parent workflow (work-on-plan.md) + dependency script (plan-deps.sh). Revised from original hybrid orchestrator after koto v0.7.0 shipped hierarchical workflows.
3. **Gate migration:** Strict v0.6.0 mode, selective decomposition of code_committed into 3 atomic gates, mixed routing on all gated states.
4. **Review panels:** Context-exists gates for persistence, evidence enums for transition routing. New scrutiny/review/qa_validation states.

## Post-Design Revisions

### koto v0.7.0 revision (2026-04-05)
Koto shipped hierarchical multi-level workflows (#127, v0.7.0). Decision 2 revised:
- **Dropped:** manifest JSON, reconciliation protocol, 3 of 4 script subcommands
- **Added:** parent workflow template (work-on-plan.md) with children-complete gate
- **Simplified:** dependency script to single `next-ready` subcommand
- **Result:** koto is single source of truth for all state

### ISSUE_SOURCE variable (2026-04-11)
Added `ISSUE_SOURCE` enum variable (`github | plan_outline`) to distinguish plan items that are GitHub issues (multi-pr mode: staleness check, gh issue view) from pure outline items (read PLAN section, skip staleness).

### Batch child spawning (2026-04-11)
Filed tsukumogami/koto#129 requesting declarative batch child spawning from parent evidence. Would eliminate the dependency script entirely -- the parent submits the full task list (names, templates, vars, deps) as evidence, and koto owns scheduling and ordering.

## Security Review (Phase 5)
**Outcome:** Option 3 (N/A with justification)
**Summary:** Design restructures internal workflow orchestration without new attack surfaces, external dependencies, or data exposure paths.

## Blockers

- **tsukumogami/koto#129** (needs-design): declarative batch child spawning. When this ships, the design's Decision 2 should be revised again to drop the dependency script. The plan orchestrator template would submit the task manifest as evidence instead of the skill layer iterating with a script.

## Current Status
**Phase:** 6 - Final Review (complete, awaiting approval)
**Blocked on:** koto#129 for final orchestrator simplification before /plan
**Last Updated:** 2026-04-12

## Next Steps
When koto#129 is resolved:
1. Revise Decision 2 to drop the dependency script in favor of koto's batch spawning
2. Update Solution Architecture (components, interfaces, data flow)
3. Update Implementation Approach (Phase 4 simplifies significantly)
4. Accept the design and run /plan to decompose into issues
