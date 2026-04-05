---
status: Accepted
problem: |
  The /explore skill routes work through a 3-level complexity table
  (Simple/Medium/Complex) but the pipeline supports 5 levels. Trivial work
  and strategic work have no documented routing path, causing agents to
  either over-process simple changes or miss the VISION/Roadmap entry points
  that Features 1 and 2 delivered.
goals: |
  Expand the routing model to 5 levels with observable signals for each,
  so agents classify incoming work into the right pipeline path. Fix stale
  type counts in Phase 4.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Complexity Routing Expansion

## Status

Accepted

## Problem statement

The /explore skill has three routing-related sections in its SKILL.md:
an Artifact Type Routing Guide (situation-based), a Quick Decision Table
(question-based), and a Complexity-Based Routing table (complexity-based).
The complexity table defines 3 levels: Simple, Medium, Complex.

The pipeline actually supports 5 levels. Trivial work (typo fixes, config
tweaks) has no documented path — if it reaches /explore, the full
scoping conversation runs even when the answer is obvious. Strategic work
(VISION -> Roadmap -> per-feature) has no entry in the routing table,
even though the VISION skill (F1) and Roadmap skill (F2) are now live.

A secondary issue: Phase 4's crystallize step says "five supported types"
but the crystallize framework defines ten. VISION is missing from Phase 4's
explicit type list. This causes confusion when agents try to reconcile
the two numbers.

## Goals

- Agents can classify incoming work into one of 5 complexity levels using
  observable signals
- Each level maps to a specific command path through the pipeline
- The three routing sections in /explore SKILL.md are consistent with
  the 5-level model
- Phase 4's stale type count is corrected

## User stories

1. As an agent receiving a trivial request ("fix this typo"), I want the
   routing table to tell me to skip /explore entirely so I don't waste
   the user's time with scoping questions.

2. As an agent receiving a strategic request ("I have a new business idea"),
   I want the routing table to tell me to start with /explore in strategic
   scope so the crystallize framework can route to VISION or Roadmap.

3. As an agent classifying work complexity, I want clear tiebreaker rules
   between adjacent levels so I don't misclassify a simple task as medium
   or a complex project as merely medium.

4. As a maintainer reading the /explore SKILL.md, I want the three routing
   sections to tell a consistent story about complexity levels so I don't
   get confused by contradictions.

## Requirements

### Functional

**R1. Expand Complexity-Based Routing to 5 levels.** Add Trivial and
Strategic rows to the existing table. Each row has: level name, signals
(observable from user input), and recommended path (command sequence).

**R2. Signal definitions use observable discriminators.** Each level's
signals must be things an agent can detect from the user's input, not
abstract properties. Key discriminators between adjacent levels:
- Trivial vs Simple: Does a GitHub issue exist or is one warranted?
- Simple vs Medium: Are there design decisions where reasonable people
  could disagree?
- Medium vs Complex: Can you list the decision questions right now?
- Complex vs Strategic: Single capability vs multiple features / project
  inception?

**R3. Tiebreaker rules for adjacent levels.** Each boundary between
levels has a tiebreaker rule that resolves ambiguity. These appear
alongside the signal table, not in a separate section.

**R4. Top-down detection order.** Signals are checked Strategic-first,
Trivial-last. Higher complexity is harder to misclassify downward. The
detection algorithm is documented as a decision tree or ordered checklist.

**R5. Update Artifact Type Routing Guide.** Add a strategic row
("I have a new business idea" or "I need to justify this project" ->
`/explore --strategic`). The existing "This is simple, just do it" row
already covers trivial, but should be reviewed for consistency.

**R6. Update Quick Decision Table.** Add entries for trivial ("Do I need
any artifact at all?" -> No artifact, just implement) and strategic
("Should this project exist?" -> VISION via /explore).

**R7. Fix Phase 4 stale type count.** Update the Phase 4 crystallize
step to reflect the actual number of supported types in the crystallize
framework (currently says 5, should match reality). Ensure VISION appears
in the type list.

### Non-functional

**R8. Markdown only.** All changes are in /explore SKILL.md and
related phase files. No compiled code, no other skills modified.

**R9. Backward compatible.** The existing Simple/Medium/Complex levels
keep their current semantics. Trivial and Strategic are additive, not
replacements.

## Acceptance criteria

- [ ] Complexity-Based Routing table has 5 rows: Trivial, Simple, Medium,
      Complex, Strategic
- [ ] Each level has observable signals and a recommended command path
- [ ] Tiebreaker rules exist for all 4 boundaries between adjacent levels
- [ ] Detection algorithm documented as ordered checklist (Strategic first)
- [ ] Artifact Type Routing Guide has a strategic row
- [ ] Quick Decision Table has trivial and strategic entries
- [ ] Phase 4 type count matches the crystallize framework's actual count
- [ ] VISION appears in Phase 4's type list
- [ ] Existing Simple/Medium/Complex semantics unchanged
- [ ] No changes to skills outside /explore

## Out of scope

- Changes to the crystallize framework scoring or signal tables (separate
  feature — see F7 in roadmap)
- Changes to /work-on, /prd, /design, /plan, /vision, /roadmap skills
- New commands or skills
- Pipeline model changes (already defined in the roadmap)
- Enforcement of complexity classification (agents use routing as guidance,
  not as a hard gate)

## Decisions and trade-offs

**Top-down detection over bottom-up.** Check Strategic first, Trivial
last. An agent that starts at Trivial and works up might stop too early
("this looks simple enough") and miss strategic scope. Starting from
Strategic and working down means the costlier misclassification (treating
strategic work as simple) is caught first.

**Phase 4 type count fix included.** The stale count is a bug that
affects agent behavior. Fixing it alongside the routing expansion is
cleaner than a separate PR, since both changes touch /explore's Phase 4
documentation.

**Tiebreakers inline, not separate.** Putting tiebreaker rules next to
the signal table keeps the decision context close to where agents need
it. A separate section would force agents to cross-reference.

## Related

- **ROADMAP-strategic-pipeline.md** — Feature 4 describes this work;
  the 5-level pipeline model is defined in the Theme section
- **F7 (Crystallize Framework Calibration)** — new feature to be added
  to the roadmap, addressing the crystallize framework's bias toward
  unknowns over undocumented knowns
