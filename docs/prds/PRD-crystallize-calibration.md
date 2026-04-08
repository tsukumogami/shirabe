---
status: Draft
problem: |
  The crystallize framework biases toward artifact types that investigate
  unknowns (design docs, spikes) over types that document agreements (PRDs,
  VISIONs). When requirements or thesis are verbally settled but not written
  down, the framework still routes to investigation artifacts.
goals: |
  Add "known but undocumented" signals so the framework routes to the right
  artifact type when the answer is settled but not captured. Soften
  anti-signals that penalize documentation of existing agreements.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Crystallize Framework Calibration

## Status

Draft

## Problem statement

The crystallize framework in /explore Phase 4 scores artifact types using
signal/anti-signal tables. The current tables bias toward investigation:
signals reward open questions ("how should we build this?", "can we do
this?") while anti-signals penalize settled answers ("requirements were
provided as input", "approach is known").

This creates a specific failure mode: when a team has verbally agreed on
requirements, thesis, or technical approach but hasn't written it down,
the framework routes to an investigation artifact (design doc, spike)
instead of a documentation artifact (PRD, VISION). The user then runs a
design exploration for something already decided, wasting time on a
question that's already answered.

Three mechanisms cause this:

1. **Missing signals.** No artifact type has signals for "known but
   undocumented." PRD signals are about unclear/contested requirements,
   not about capturing agreed ones. VISION signals are about thesis
   validation, not thesis documentation.

2. **Punitive anti-signals.** PRD has "requirements were provided as
   input" as an anti-signal -- the framework penalizes exactly the
   scenario where a PRD is most useful. VISION has "specific users and
   needs already identified" as an anti-signal, penalizing documented
   strategic clarity.

3. **Demotion rule amplification.** Any type with one or more anti-signals
   drops below all types with zero anti-signals, regardless of raw score.
   In "known but undocumented" scenarios, documentation artifacts often
   trigger anti-signals (because the answers exist), causing them to rank
   below investigation artifacts that happen to have zero anti-signals.

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
one or more anti-signals below all types with zero. Consider softening
this: distinguish between anti-signals that indicate genuine
misclassification ("this is the wrong artifact type") vs anti-signals
that indicate partial fit ("this type applies but with caveats").

**R4. Preserve investigation routing.** Spikes, design docs with open
questions, and other investigation artifacts must still score correctly
when questions are genuinely open. The calibration adds documentation
paths without removing investigation paths.

### Non-functional

**R5. Changes scoped to crystallize framework.** Modifications only to
the signal/anti-signal tables and scoring rules in the crystallize
framework reference file. No changes to /explore phases, other skills,
or the detection algorithm.

**R6. Backward compatible signal semantics.** Existing signals keep their
meaning. New signals are additive. Anti-signal changes are clearly
documented as intentional recalibration.

## Acceptance criteria

- [ ] PRD signal table includes "known but undocumented" signals
- [ ] VISION signal table includes "known but undocumented" signals
- [ ] Design Doc signal table includes "known but undocumented" signals
- [ ] Anti-signals that penalize documentation of agreements are softened
      or removed
- [ ] Demotion rule is reviewed and adjusted if needed
- [ ] Investigation artifacts still score correctly for genuinely open
      questions
- [ ] All changes are in the crystallize framework reference file
- [ ] Evals updated to test "known but undocumented" classification

## Out of scope

- Changes to /explore phases or the detection algorithm
- Changes to other skills (/prd, /design, /vision, /plan)
- The artifact type decision reference (F12 -- separate feature)
- New artifact types or lifecycle states
- Scoring for Roadmap, Rejection Record, or No Artifact types (unless
  the recalibration surfaces issues there too)

## Decisions and trade-offs

**Additive signals over anti-signal removal.** Adding "known but
undocumented" signals is safer than removing existing anti-signals.
Removal risks making the framework too permissive (recommending PRD when
a design doc is genuinely needed). Addition gives the framework a new
dimension to score on without breaking existing classification.

**Demotion rule refinement is optional.** The demotion rule is aggressive
but it prevents a common error (high-scoring wrong type beats low-scoring
right type). Softening it might fix the documentation bias but could
introduce new misclassification. The PRD requires reviewing it but
doesn't mandate changing it -- if adding signals is sufficient, the rule
can stay as-is.

## Related

- **ROADMAP-strategic-pipeline.md** -- Feature 7 describes this work
- **skills/explore/references/quality/crystallize-framework.md** -- the
  file containing the signal/anti-signal tables and scoring rules
- **DESIGN-complexity-routing-expansion.md** (Current) -- F4 added the
  five-level routing model; the crystallize framework is the scoring
  engine inside the Complex and Strategic levels
- **F12 (Artifact Type Decision Reference)** -- a separate shared
  reference for needs-* label classification; complementary but
  independent
