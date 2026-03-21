---
status: Proposed
problem: |
  Shirabe's workflow skills make decisions at 39 blocking points across 5 skills,
  using AskUserQuestion as the universal mechanism. This creates three problems:
  agents ask before researching, decisions aren't structurally recorded, and
  workflows can't run autonomously. Issue #6 proposes a 7-phase decision-making
  framework that generalizes the design skill's advocate pattern. This design
  covers the framework itself, a lightweight decision protocol for smaller choices,
  and a non-interactive execution mode that lets workflows run end-to-end without
  human input.
decision: |
  (to be determined during design phases)
rationale: |
  (to be determined during design phases)
---

# DESIGN: Decision Framework

## Status

Proposed

## Context and Problem Statement

Shirabe's 5 workflow skills (explore, design, prd, plan, work-on) block on user
input at 39 points. 28% are questions the agent could answer by researching first.
49% are judgment calls where the agent already computes a recommendation but waits
for confirmation. 26% are approval gates.

Issue #6 proposes a structured decision-making skill — a 7-phase workflow (research,
alternatives, validation bakeoff, peer revision, cross-examination, synthesis, report)
that generalizes the design skill's advocate pattern into a reusable component.

But the decision skill alone doesn't solve the full problem. Lightweight decisions
(decomposition strategy, loop exits, implicit architecture choices) need the same
assumption-tracking discipline without the overhead of 7 phases. And all skills need
a non-interactive mode where the agent exhausts research, makes assumptions, and
lets the user review at the end.

This design covers three tightly coupled components:
1. The decision-making skill (heavyweight, 7 phases)
2. A lightweight decision protocol (3-step micro-workflow)
3. A non-interactive execution mode (cross-cutting)

## Decision Drivers

- Decisions must be recorded structurally, not lost in conversation logs
- The same assumption-tracking pattern must work for both heavyweight and lightweight decisions
- Non-interactive mode must work across all skills without per-skill special-casing
- The decision skill must be invocable as a sub-operation (by design, explore) and standalone
- Multi-decision orchestration (design docs with 3-5 decision questions) needs parallel execution with cross-validation
- Phase files must stay focused and under 150 lines despite increased complexity
- The output of a decision must map directly into a design doc's Considered Options section with zero information loss

## Decisions Already Made

From the exploration (2 rounds, 9 research leads):

- The decision skill generalizes design's Phase 1-2 advocate pattern. Design delegates its approach selection to the decision skill and keeps orchestration.
- Explore hands off to the decision skill when crystallize selects Decision Record. Explore's convergence loop stays unchanged.
- Cross-validation (checking assumptions across parallel decisions) is the design skill's concern, not the decision skill's. The decision skill stays isolated.
- Status is derived from artifact existence, not separate trackers.
- The crystallize framework stays inline (mechanical scoring, not a substantive decision).
- A canonical decision report structure (Context, Assumptions, Chosen, Rationale, Alternatives, Consequences) serves both standalone decision records and embedded design doc sections.
- Four complexity tiers: trivial (no record), lightweight (micro-protocol), standard (decision skill fast path), critical (full 7-phase).
