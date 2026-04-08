---
status: Draft
problem: |
  The crystallize framework biases toward investigation artifacts over
  documentation artifacts, and its signal tables are trapped inside
  /explore while other skills (/plan, /triage) make the same artifact-type
  decision with ad-hoc heuristics. Two problems, one root cause: the
  signal definitions need recalibrating and extracting into a shared
  reference.
goals: |
  Create a shared artifact-type signal reference with calibrated signals
  (including "known but undocumented" scenarios). Update the crystallize
  framework and /plan to consume it. Merges F7 and F12.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Crystallize Calibration and Artifact Type Decision Reference

## Status

Draft

## Problem statement

Two related problems share a root cause.

**Documentation bias (F7).** The crystallize framework in /explore Phase 4
scores artifact types using signal/anti-signal tables. The tables bias
toward investigation: signals reward open questions ("how should we build
this?", "can we do this?") while anti-signals penalize settled answers
("requirements were provided as input", "approach is known"). When a team
has verbally agreed on requirements or thesis but hasn't written it down,
the framework routes to an investigation artifact instead of a
documentation artifact.

Three mechanisms cause this:

1. **Missing signals.** No artifact type has signals for "known but
   undocumented." PRD signals are about unclear/contested requirements,
   not about capturing agreed ones. VISION signals are about thesis
   validation, not thesis documentation.

2. **Punitive anti-signals.** PRD has "requirements were provided as
   input" as an anti-signal. VISION has "specific users and needs already
   identified" as an anti-signal. Both penalize exactly the scenario where
   these artifact types are most useful.

3. **Demotion rule amplification.** Any type with one or more anti-signals
   drops below all types with zero anti-signals, regardless of raw score.
   Documentation artifacts trigger anti-signals in settled scenarios,
   dropping below investigation artifacts with zero anti-signals.

**Inconsistent classification (F12).** Multiple skills decide what
artifact type work needs: /explore scores types in the crystallize
framework, /plan assigns needs-* labels in Phase 1, /triage assesses
untriaged issues. Each uses different heuristics for the same question.
The crystallize framework has the most thorough logic but it's embedded
in /explore and not reusable.

**Shared root cause.** The signal definitions need to live in one place,
be calibrated for both investigation and documentation scenarios, and be
consumable by any skill that classifies work.

## Goals

- Shared reference document with artifact-type signals consumable by
  multiple skills
- "Known but undocumented" signals so the framework routes correctly when
  the answer is settled but not captured
- Anti-signals that don't penalize documenting settled decisions
- /explore crystallize framework consumes the shared reference
- /plan Phase 1 consumes the shared reference for needs-* labels
- Investigation artifacts still score correctly for genuinely open
  questions

## User stories

1. As an agent crystallizing exploration findings where the user already
   knows what to build, I want the framework to recommend PRD so I
   capture requirements instead of re-investigating them.

2. As an agent in /plan assigning a needs-* label, I want to use the same
   signal definitions as /explore so classification is consistent.

3. As a skill author adding a new classification point, I want a shared
   reference to import rather than inventing my own heuristics.

## Requirements

### Functional

**R1. Create shared artifact-type signal reference.** Create
`references/artifact-type-signals.md` defining observable signals and
anti-signals for each artifact type. This is the single source of truth
for "what does this work need?"

**R2. Add "known but undocumented" signals.** For PRD, VISION, and Design
Doc, add signals that detect when the answer is settled but not captured.
These should be observable from user input or exploration findings.

**R3. Soften punitive anti-signals.** Review anti-signals that penalize
documentation of agreements. Either remove them, add qualifying conditions,
or reclassify them.

**R4. Refine the demotion rule.** Review the current rule (any anti-signal
demotes below all zero-anti-signal types). If adding signals is sufficient
to fix the bias, the rule can stay. If not, soften it to distinguish
genuine misclassification from partial fit.

**R5. Update crystallize framework.** The crystallize framework in
`skills/explore/references/quality/crystallize-framework.md` references
or imports the shared signal tables instead of maintaining its own copy.
The scoring mechanics (count signals, subtract anti-signals, apply
demotion) stay in the crystallize framework -- only the signal definitions
move to the shared reference.

**R6. Update /plan Phase 1.** /plan's needs-* label assignment in Phase 1
references the shared signal document instead of its current ad-hoc
heuristics ("requirements unclear -> needs-prd, approach unclear ->
needs-design").

**R7. Preserve investigation routing.** Spikes, design docs with open
questions, and other investigation artifacts still score correctly when
questions are genuinely open.

### Non-functional

**R8. No changes to /explore phases or detection algorithm.** The
crystallize framework's scoring mechanics are unchanged. Only the signal
table content and its location change.

**R9. Backward compatible.** Existing signals keep their meaning. New
signals are additive. Anti-signal changes are documented as intentional
recalibration.

## Acceptance criteria

- [ ] `references/artifact-type-signals.md` exists with signal tables for
      all artifact types
- [ ] PRD, VISION, and Design Doc tables include "known but undocumented"
      signals
- [ ] Anti-signals that penalize documentation of agreements are addressed
- [ ] Demotion rule reviewed and adjusted if needed
- [ ] Crystallize framework references the shared signal document
- [ ] /plan Phase 1 references the shared signal document for needs-*
      labels
- [ ] Investigation artifacts still score correctly
- [ ] Evals updated for "known but undocumented" classification

## Out of scope

- Changes to /explore phases or detection algorithm
- Changes to /prd, /design, /vision skill internals
- New artifact types or lifecycle states
- Enforcement of classification (signals are guidance, not hard gates)

## Decisions and trade-offs

**Merge F7 and F12.** Originally scoped as separate features: F7
calibrates the crystallize framework, F12 creates a shared reference. But
F7's calibration work (adding signals, softening anti-signals) is the
same work F12 needs for a good shared reference. Doing them separately
means touching the same tables twice. Merging delivers consistent signals
in one pass.

**Shared reference with framework-specific scoring.** The signal
definitions move to the shared reference. The scoring mechanics (signal
counting, demotion rule, tiebreakers) stay in the crystallize framework.
This lets /plan use the signals with a simpler decision process while
/explore keeps its full scoring engine.

**Additive signals over anti-signal removal.** Adding "known but
undocumented" signals is safer than removing existing anti-signals.
Removal risks making the framework too permissive. Addition gives a new
dimension without breaking existing classification.

## Related

- **ROADMAP-strategic-pipeline.md** -- Features 7 and 12 (merged)
- **skills/explore/references/quality/crystallize-framework.md** -- the
  file containing current signal tables and scoring rules
- **skills/plan/references/phases/phase-1-analysis.md** -- current ad-hoc
  needs-* label heuristics
- **references/pipeline-model.md** -- pipeline reference that describes
  the role of crystallize in the workflow
