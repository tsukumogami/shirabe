---
status: Draft
problem: |
  The crystallize framework biases toward investigation artifacts over
  documentation artifacts. When requirements or thesis are verbally settled
  but not written down, the framework routes to design docs or spikes
  instead of PRDs or VISIONs.
goals: |
  Calibrate the signal tables so the framework routes "known but
  undocumented" work to documentation artifacts. All changes in
  crystallize-framework.md.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Crystallize Framework Calibration

## Status

Draft

## Problem statement

The crystallize framework in /explore Phase 4 scores artifact types using
signal/anti-signal tables. The tables bias toward investigation: signals
reward open questions ("how should we build this?", "can we do this?")
while anti-signals penalize settled answers ("requirements were provided
as input", "approach is known").

When a team has verbally agreed on requirements, thesis, or technical
approach but hasn't written it down, the framework routes to an
investigation artifact (design doc, spike) instead of a documentation
artifact (PRD, VISION).

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

## Goals

- Framework correctly routes "known but undocumented" work to documentation
  artifacts (PRD, VISION, Design Doc)
- Anti-signals don't penalize the act of documenting settled decisions
- The demotion rule still protects against genuine misclassification but
  doesn't amplify the documentation bias
- Investigation artifacts (spike, design doc with open questions) still
  score correctly when questions are genuinely open

## User stories

1. As an agent crystallizing exploration findings where the user already
   knows what to build, I want the framework to recommend PRD so I
   capture requirements instead of re-investigating them.

2. As an agent crystallizing a strategic exploration where the thesis is
   clear, I want the framework to recommend VISION so I document the
   justification instead of exploring whether the project should exist.

3. As an agent crystallizing work where the technical approach was decided
   in discussion, I want the framework to recommend Design Doc as a record
   of the decision, not a Spike to re-investigate feasibility.

## Requirements

### Functional

**R1. Add "known but undocumented" signals.** For PRD, VISION, and Design
Doc, add signals that detect when the answer is settled but not captured.
These should be observable from exploration findings (e.g., "requirements
emerged as statements, not questions" or "thesis is asserted, not
debated").

**R2. Soften punitive anti-signals.** Review anti-signals that penalize
documentation of agreements. Either remove them, reclassify them as
neutral, or add qualifying conditions (e.g., "requirements provided as
input" is only an anti-signal when the PRD already exists, not when
requirements are verbal).

**R3. Refine the demotion rule.** The current rule demotes any type with
one or more anti-signals below all types with zero. If adding signals
(R1) and softening anti-signals (R2) are sufficient to fix the bias, the
rule can stay. If not, soften it to distinguish genuine misclassification
from partial fit.

**R4. Preserve investigation routing.** Spikes, design docs with open
questions, and other investigation artifacts must still score correctly
when questions are genuinely open.

### Non-functional

**R5. All changes in one file.** Modifications only to
`skills/explore/references/quality/crystallize-framework.md`. No changes
to /explore phases, other skills, or the detection algorithm.

## Acceptance criteria

- [ ] PRD signal table includes "known but undocumented" signals
- [ ] VISION signal table includes "known but undocumented" signals
- [ ] Design Doc signal table includes "known but undocumented" signals
- [ ] Anti-signals that penalize documentation of agreements are softened
      or removed
- [ ] Demotion rule is reviewed and adjusted if needed
- [ ] Investigation artifacts still score correctly for genuinely open
      questions
- [ ] All changes are in crystallize-framework.md
- [ ] Evals updated to test "known but undocumented" classification

## Out of scope

- Extracting signals into a shared reference document (revisit when a
  second consumer beyond /explore exists)
- Changes to /plan Phase 1 needs-* label heuristics
- Changes to /explore phases or the detection algorithm
- Changes to other skills
- New artifact types or lifecycle states
- Deferred Types and Disambiguation Rules sections (no signal tables)

## Decisions and trade-offs

**Calibrate in place, don't extract.** The original plan merged this with
F12 (shared reference extraction). Review found the extraction is
premature: /triage doesn't exist yet, and /plan's needs-* logic is a
four-line lookup that doesn't need a shared reference. Fix the signal
tables directly in crystallize-framework.md. F12 stays on the roadmap for
when a real second consumer materializes.

**Additive signals over anti-signal removal.** Adding "known but
undocumented" signals is safer than removing existing anti-signals.
Removal risks making the framework too permissive. Addition gives a new
dimension without breaking existing classification.

**Demotion rule refinement is conditional.** The rule is aggressive but
prevents a common error. If R1 and R2 are sufficient to fix the bias, the
rule stays. Changing it is a fallback, not a default.

## Related

- **ROADMAP-strategic-pipeline.md** -- Feature 7 describes this work
- **skills/explore/references/quality/crystallize-framework.md** -- the
  file being modified
- **DESIGN-complexity-routing-expansion.md** (Current) -- F4 added the
  five-level routing model; the crystallize framework is the scoring
  engine inside the Complex and Strategic levels
