# Explore Scope: work-on-readiness

## Visibility

Public

## Core Question

What gaps remain between the current state of the work-on skill and a production-ready release? Specifically: what document format requirements are unenforced, what CI coverage is missing, what parsing robustness issues exist in the orchestration scripts, and what patterns from proven tooling could harden the end-to-end workflow?

## Context

The work-on skill was extended in this branch with: (1) run-cascade.sh for post-implementation artifact lifecycle transitions, (2) work-on-plan.md as a plan orchestrator template, and (3) koto 0.8.1 fixing the children-complete gate. Five friction items from the validation run remain open in shirabe scripts/templates. The tools repo (private) has established patterns for CI enforcement, deterministic parsing, and blocking pre-flight checks that haven't been ported.

## In Scope

- CI coverage gaps for work-on-specific scripts and templates
- plan-to-tasks.sh parsing robustness (formats, truncation, error feedback)
- Document format pre-flight validation (PLAN, DESIGN, PRD, ROADMAP)
- Patterns from tools repo CI and script design worth porting to shirabe
- orchestrator_setup resilience and crash recovery
- run-cascade.sh coverage and error handling

## Out of Scope

- koto engine internals (bugs filed separately)
- The /plan, /design, /prd skills (only work-on integration points)
- Strategic roadmap decisions (what new features to add beyond current scope)

## Research Leads

1. **What does plan-to-tasks.sh actually parse, and what formats does it miss?**
   Friction items #2, #4, #5 all point to this script. Need to know exactly what formats are handled vs. what /plan produces.

2. **What CI jobs cover work-on, and what's missing?**
   run-cascade_test.sh appears to have no CI trigger. What else is uncovered?

3. **What document format validation exists, and where does it fail silently?**
   The cascade and plan-to-tasks both do runtime defensive checks. Is pre-flight validation absent entirely?

4. **What patterns from the tools repo are worth porting?**
   Tools has wip/ enforcement, 80+ golden file tests, blocking label checks, and introspection phases. Which translate directly to shirabe?
