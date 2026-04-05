---
status: Accepted
upstream: docs/prds/PRD-complexity-routing-expansion.md
problem: |
  The /explore skill's routing tables have 3 complexity levels but the
  pipeline supports 5. Trivial and Strategic work has no documented path.
  Phase 4's type count is stale (says 5, should be 10).
decision: |
  Expand the routing table to 5 rows with concise signals, add a top-down
  detection checklist with embedded tiebreaker rules, update the routing
  guide and decision table for consistency, and fix Phase 4's type count.
rationale: |
  Compact table + checklist keeps the proven scanning format while adding
  the classification detail agents need. Tiebreakers inline in the
  checklist avoid cross-referencing between sections.
---

# DESIGN: Complexity Routing Expansion

## Status

Accepted

## Context and Problem Statement

The /explore skill routes work through three complexity levels
(Simple/Medium/Complex) but the pipeline supports five. Two levels are
missing from the routing tables: Trivial (fire-and-forget fixes that don't
need issues or artifacts) and Strategic (VISION/Roadmap work that spawns
per-feature sub-pipelines).

The technical problem is content design, not code. Three routing-related
sections in `/explore/SKILL.md` need to expand consistently:

1. **Complexity-Based Routing table** — the primary target. Currently 3
   rows, needs 5. Each row needs observable signals that agents can detect
   from user input, and a recommended command path.

2. **Artifact Type Routing Guide** — situation-based advice. Already has a
   trivial row ("This is simple, just do it" -> `/work-on`) but no
   strategic row.

3. **Quick Decision Table** — question-based routing. Missing both trivial
   and strategic entries.

A secondary issue: Phase 4's crystallize step says "five supported types"
but the crystallize framework defines ten. VISION is missing from Phase 4's
explicit type list.

## Decision Drivers

- Signals must be observable from user input (an agent can classify without
  running the full workflow first)
- Adjacent levels need tiebreaker rules to resolve boundary ambiguity
- Existing Simple/Medium/Complex semantics must not change (backward
  compatible)
- All changes are markdown edits to /explore skill files
- The three routing sections must tell a consistent story
- Detection should be top-down (Strategic first, Trivial last) to avoid
  the costlier misclassification of treating strategic work as simple

## Considered Options

### Decision 1: Signal table structure and detection algorithm presentation

The routing table needs to expand from 3 to 5 rows. The question is how
to present signals, paths, tiebreaker rules, and the detection algorithm
without bloating the section agents scan during classification.

Key assumptions:
- The detection algorithm is consumed by agents during classification,
  not by users directly
- Existing Simple/Medium/Complex signal descriptions are adequate and
  don't need expansion
- The /explore SKILL.md is the single home for the routing table

#### Chosen: Compact table with detection checklist

Keep the existing `| Complexity | Signals | Recommended Path |` format
with concise comma-separated signal phrases. Add Trivial and Strategic
rows. Add a "Detection Algorithm" subsection immediately below the table
with an ordered checklist (Strategic first, Trivial last). Tiebreaker
rules are embedded as boundary guidance within each checklist step.

**The 5-row table:**

| Complexity | Signals | Recommended Path |
|------------|---------|------------------|
| Trivial | Self-evident change, no issue needed, single file, no design decisions | `/work-on` directly (no issue) |
| Simple | Clear requirements, few files, one person, no competing approaches | `/work-on` or `/prd` then implement |
| Medium | Known approach, some integration risk, design decisions between viable options | `/design` then `/plan` |
| Complex | Multiple unknowns, shape unclear, can't state requirements or approach | `/explore` to discover first |
| Strategic | Project inception, multi-feature sequencing, thesis validation needed | VISION or `/roadmap` then per-feature pipeline |

**The detection checklist:**

```
1. Does the request reference project direction, multi-feature sequencing,
   or thesis validation?
   YES -> Strategic
   Boundary: if it's about one feature within an existing project -> Complex

2. Can the user clearly state what to build AND how to build it?
   NO (either is unknown) -> Complex
   Boundary: if they know what but not how -> Medium

3. Are there design decisions where reasonable people could disagree
   on the approach?
   YES -> Medium
   Boundary: if you can list the decision questions now -> Medium;
   if too many unknowns to even frame questions -> Complex

4. Does a GitHub issue exist (or should one exist) with defined scope?
   YES -> Simple
   Boundary: if no design decisions and clear acceptance criteria -> Simple;
   if "done" is self-evident without criteria -> Trivial

5. Is the change self-evident and fire-and-forget?
   YES -> Trivial

6. Default -> Simple (create an issue and proceed)
```

The four PRD-mandated discriminators map to checklist steps:
- Trivial vs Simple: step 4 (issue warranted?)
- Simple vs Medium: step 3 (design decisions?)
- Medium vs Complex: step 2/3 boundary (can you list questions?)
- Complex vs Strategic: step 1 boundary (single feature vs project?)

#### Alternatives considered

**Expanded table + separate tiebreaker section**: longer signal
descriptions (1-2 sentences per cell) and a dedicated boundary table,
with the detection algorithm as a third subsection. Rejected because
three independent sections to maintain in sync, and longer cells slow
agent scanning.

**Two-tier presentation**: compact table in place, full detail in a
reference section at the bottom of SKILL.md. Rejected because agents may
skip the reference section during classification, and cross-location
sync is harder to maintain.

## Decision Outcome

The routing section grows from a 3-row table (~6 lines) to a 5-row table
plus a detection checklist (~25 lines total). The table is the summary;
the checklist is the specification. Agents read the checklist sequentially,
hit the first YES, and get immediate boundary guidance for the adjacent
level.

Simple, Medium, and Complex keep their current signal language. Trivial
adds "below Simple" for fire-and-forget work. Strategic adds "above
Complex" for project-level work. The detection order (Strategic first)
means the costlier misclassification — treating strategic work as simple
— is caught at the top of the checklist.

The Artifact Type Routing Guide and Quick Decision Table get small
updates to match: a strategic row in the routing guide, and trivial +
strategic entries in the decision table. Phase 4's stale type count is
fixed as a mechanical correction.

## Solution Architecture

### Overview

All changes live in /explore skill files. No new files, no other skills
touched. The routing section expansion is the primary deliverable; the
routing guide, decision table, and Phase 4 updates are secondary.

### Components

```
skills/explore/
  SKILL.md                              <-- MODIFIED: 3 routing sections updated
  references/
    phases/
      phase-4-crystallize.md            <-- MODIFIED: fix stale type count
```

### Key Interfaces

**Complexity-Based Routing section.** Replace the current 3-row table
with the 5-row table above. Add a "### Detection Algorithm" subsection
immediately below with the ordered checklist. The section heading stays
the same (`### Complexity-Based Routing`).

**Artifact Type Routing Guide.** Add one row:

| Situation | Route To | Why |
|-----------|----------|-----|
| "I need to justify this project" or "I have a multi-feature initiative" | `/explore --strategic <topic>` | Strategic scope; needs VISION or Roadmap before features |

The existing "This is simple, just do it" row already covers trivial
routing. Verify the wording is consistent with the new Trivial level
signals.

**Quick Decision Table.** Add two rows:

| Core Question | Best Fit | Alternative |
|---------------|----------|-------------|
| "Do I need any artifact at all?" | No artifact, `/work-on` directly | `/prd` if scope creep is likely |
| "Should this project exist?" or "Which features should we build?" | VISION or Roadmap via `/explore --strategic` | `/explore` without flag if scope is unclear |

**Phase 4 crystallize step.** Update the type count in
`phase-4-crystallize.md` to match the crystallize framework's actual
supported types. Ensure VISION appears in the type list. This is a
mechanical fix — no scoring or signal changes.

### Data Flow

No data flow changes. The routing tables are passive references
consulted by agents during classification. No runtime state, no artifacts
produced by the routing logic itself.

## Implementation Approach

### Phase 1: Complexity-Based Routing expansion

Replace the 3-row table with the 5-row table and add the detection
algorithm subsection.

Deliverables:
- `skills/explore/SKILL.md` (Complexity-Based Routing section modified)

### Phase 2: Routing guide and decision table updates

Add strategic row to routing guide, trivial + strategic entries to
decision table. Verify existing trivial row consistency.

Deliverables:
- `skills/explore/SKILL.md` (Artifact Type Routing Guide and Quick
  Decision Table sections modified)

### Phase 3: Phase 4 type count fix

Fix the stale type count and add VISION to the type list.

Deliverables:
- `skills/explore/references/phases/phase-4-crystallize.md` (modified)

### Phase 4: Evals

Add eval scenarios testing complexity classification at each level.

Deliverables:
- `skills/explore/evals/evals.json` (modified)

## Security Considerations

No security dimensions apply. This design modifies markdown routing
tables and a detection checklist in skill documentation. No external
inputs are processed, no permissions change, no dependencies are added.

## Consequences

### Positive

- Agents can classify all 5 complexity levels with explicit signals and
  a sequential detection procedure
- Trivial work stops triggering full /explore scoping conversations
- Strategic work gets a documented entry point instead of being
  shoe-horned into the Complex level
- All three routing sections tell a consistent story about 5 levels
- Phase 4 type count matches reality

### Negative

- The routing section grows from ~6 to ~25 lines, making it longer to
  scan during casual reading
- The detection checklist adds a prescriptive classification procedure
  that agents may follow too rigidly instead of using judgment

### Mitigations

- The table itself stays compact (5 rows, same format). The checklist is
  a separate subsection that agents consult only when classification is
  ambiguous.
- The default (step 6: Simple) prevents over-classification. If an agent
  can't decide, it picks the safest middle ground.
