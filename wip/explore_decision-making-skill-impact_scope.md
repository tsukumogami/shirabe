# /explore Scope: decision-making-skill-impact

## Problem Statement
Issue #6 proposes a Decision-Making Skill Framework for shirabe — a 7-phase
structured decision workflow (research, alternatives, validation bakeoff, peer
revision, cross-examination, synthesis, report). This skill generalizes the
design skill's advocate pattern into a reusable component for any decision
requiring multiple alternatives. We need to determine how the existing 8 shirabe
skills change to accommodate it, with emphasis on reusable composition.

## Key Context from User
- The decision skill generalizes the design advocate phase — a bakeoff should
  apply to any decision needing multiple alternatives, not just design approaches
- Decision output must map directly to a single decision in a design doc's
  Considered Options section — no information loss between formats
- Explore's "decision doc" artifact type is the same thing the decision framework
  builds — reuse opportunity
- Design docs need multiple parallel decisions with post-completion cross-validation
  (assumption invalidation across decisions)
- New phases add resumability and re-execution complexity — phase files must stay
  focused on single-phase concerns

## Research Leads

### Lead 1: Design skill decomposition
How would the design skill's Phase 1-2 (advocate agents, side-by-side comparison)
change if approach selection delegates to the decision skill? Map the current
expansion-contraction pattern against the decision skill's 7 phases. Identify what
the design skill keeps vs what it delegates. Consider that a design doc has MULTIPLE
decision questions (Considered Options sections), each potentially running the
decision framework independently.

### Lead 2: Output format mapping
The decision skill produces: Context, Decision, Rationale, Alternatives Considered,
Assumptions. A design doc's Considered Options section has: decision question context,
chosen approach, alternatives with rejection rationale. An explore crystallize
produces: artifact type + scoring. Map these formats to find the reusable core
structure and identify where adapters are needed. The goal is zero information loss.

### Lead 3: Decision skill as reusable sub-operation
Examine the invocation model: how does a parent skill (design, explore, prd) invoke
the decision skill? Consider: working directory conventions (wip/ scoping), agent
spawning patterns, input/output contracts, and how the parent resumes after the
decision completes. Look at how current sub-operations work (e.g., plan's batch
issue creation, work-on's context extraction) for patterns to follow.

### Lead 4: Multi-decision orchestration and assumption invalidation
A design doc may have 3-5 decision questions running in parallel. After all complete,
the spec says each decider reviews peer decisions and may restart from an earlier
phase if assumptions are invalidated. How does this orchestration layer work within
the design skill? Who owns the loop? How does resumability work when a decision
restarts?

### Lead 5: Explore crystallize and decision doc convergence
Explore can produce a "Decision Record" (ADR) artifact. The decision skill produces
a structured decision report. These should be the same thing. How do they converge?
Does explore invoke the decision skill when crystallizing to "Decision Record"? Does
the decision skill's output format become the ADR format?

### Lead 6: Phase file discipline under increased complexity
The decision skill adds 7 phases, each potentially as a reference file. Combined
with design's 6 phases and explore's 5 phases, the total phase count grows
significantly. How do we keep phase files focused? What's the right granularity?
Review the progressive disclosure patterns we just improved and determine if they
hold under this increased complexity.
