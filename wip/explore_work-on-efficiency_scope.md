---
topic: work-on-efficiency
phase: 1-scope
---

# Explore Scope: work-on-efficiency

## Visibility

Public

## Core Question

How can we reduce the operational overhead of the work-on skill's plan orchestrator
mode while preserving its structural guarantees? The friction falls into two buckets:
shirabe template changes that can be made now (docs fast path, pre-implemented work
exit, plan-backed PR model, context key consistency) and koto engine capabilities
that need to be requested (batch_final_view in context, directive variable
interpolation). We need to understand what each fix requires and whether there are
patterns from other parts of the system that inform the right approach.

## Context

This exploration follows direct execution friction observed while driving the
work-on-friction-fixes plan through the plan orchestrator. Five inefficiencies
were observed and documented in a post-execution assessment:

1. **Ceremony-to-work ratio**: 10+ state transitions for a doc-only change (paragraph
   added to one file). Scrutiny, review, and QA panels add overhead with no benefit
   for non-code changes.
2. **No "already done" exit**: pre-implemented issues drove through all 10 states.
   No path exists to say "AC verified, nothing to commit."
3. **Parallel file conflicts**: issues 4 and 5 both touched SKILL.md concurrently,
   causing one to overwrite the other's work. No coordination mechanism exists.
4. **Incorrect plan-backed PR model**: child workflows drive through `pr_creation`
   even though the orchestrator owns the PR. Children submitted the orchestrator's
   PR URL as their own.
5. **Missing koto API surface**: `batch_final_view` context key documented but
   absent at runtime. Directive hardcoded `koto next work-on-plan` instead of the
   actual workflow name.

The repo's CLAUDE.md mentions a CI-gate + deterministic-script pattern from the
tools repo. Several validation scripts exist (`validate-plan.sh`, `plan-to-tasks.sh`)
but no equivalent scripts guard the child workflow template paths.

## In Scope

- Shirabe template changes: `work-on.md`, `work-on-plan.md`, `SKILL.md`
- Template complexity routing (docs vs. code issue types)
- Pre-implemented work handling in the child workflow state machine
- Parallel agent coordination for shared-file issues
- Plan-backed PR model correctness
- Koto API surface gaps (feature requests, not engine changes)
- CI gate additions that could validate template consistency

## Out of Scope

- Koto engine internals (we file issues, not implement)
- Changes to the single-issue work-on flow (focus is plan orchestrator mode)
- work-on.md states before `analysis` (entry, context_injection, etc.)
- Evals for the new behavior (separate concern)

## Research Leads

1. **Does koto support complexity-based routing in a single template, or does a docs fast path require a separate template?**
   Needs to understand whether koto's conditional transition syntax can branch
   based on evidence submitted at `entry` (e.g., `issue_type: docs`), or whether
   routing to a shorter state sequence requires forking into a second template file.
   The answer determines whether we can solve this with one template change or two.

2. **What is the minimal clean exit path for pre-implemented work, and what state should it terminate in?**
   When `analysis` finds all AC already satisfied, the child needs to exit cleanly
   without touching implementation/scrutiny/review states. Investigate whether the
   koto template can add an `analysis → done_already_complete` transition, what
   evidence field would trigger it, and whether this is a shirabe change or requires
   a koto gate feature.

3. **Can parallel-agent file conflicts be prevented at PLAN generation time, and what's the right detection mechanism?**
   Investigate whether `plan-to-tasks.sh` or `validate-plan.sh` could detect that
   two issue outlines describe changes to the same file, and automatically add a
   `waits_on` dependency. Assess feasibility of static analysis on the issue outline
   text vs. requiring explicit file-list annotations in the PLAN doc format.

4. **Should plan-backed children skip `pr_creation` entirely, and what koto template pattern enables this?**
   Investigate whether a separate `work-on-plan-backed.md` template (forked from
   `work-on.md` with `pr_creation` removed) is cleaner than trying to route around
   `pr_creation` via evidence values. Consider the maintenance cost of a fork vs.
   the semantic incorrectness of the current approach.

5. **What koto API changes are needed, and which can be worked around in the template today?**
   Investigate the `batch_final_view` gap (documented but not exposed), the hardcoded
   `work-on-plan` workflow name in directives (should interpolate `{{WF_NAME}}`), and
   context key naming inconsistencies (`review_results` vs `review_results.json`).
   Determine which are koto bugs to file vs. shirabe template bugs to fix now.

6. **What CI gates would provide the strongest enforcement with the least maintenance overhead?**
   The plan scripts have CI jobs (`check-plan-docs.yml`, `check-plan-scripts.yml`,
   `check-work-on-scripts.yml`). Investigate what additional checks would catch
   template consistency issues (e.g., mermaid diagram matches YAML states, context
   key names match gate definitions, child template state count for docs vs code paths).
