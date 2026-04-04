---
status: Proposed
upstream: docs/prds/PRD-roadmap-skill.md
problem: |
  The roadmap artifact type has a format-reference skill but no creation
  workflow. Users manually author roadmaps or rely on /explore's inline
  template, which lacks guided scoping, research, and review.
decision: |
  Add a /roadmap creation skill following the /vision pattern: SKILL.md with
  embedded workflow, 4 phase files with roadmap-specific agents and jury, a
  transition script, and an /explore auto-continue handoff replacing the
  current inline production.
rationale: |
  The /vision skill establishes the pattern. Roadmaps need domain-specific
  concerns (multi-feature coordination, dependency validation, sequencing
  justification) that inline production can't address. The auto-continue
  handoff is consistent with PRD, Design Doc, and VISION.
---

# DESIGN: Roadmap Creation Skill

## Status

Proposed

## Context and Problem Statement

The roadmap artifact type has a format-reference skill (private plugin) that
defines structure, lifecycle, and validation rules, but no creation workflow.
Users must manually author roadmaps or rely on /explore's inline production
handler, which writes a bare template without guided scoping, research, or
review. Every other major artifact type (PRD, Design Doc, VISION) has a
dedicated creation skill with a multi-phase workflow. Per the strategic
pipeline roadmap's cross-cutting decision, each doc type should have its own
skill.

This design adds a `/roadmap` creation skill to shirabe, following the
pattern established by /vision.

## Decision Drivers

- Must follow cross-cutting decisions from ROADMAP-strategic-pipeline.md:
  dedicated skill per doc type, script-driven transitions, completion
  lifecycle cascades, draft-merge prevention
- Must work standalone (`/roadmap <topic>`) and via /explore handoff
- Must follow the /vision skill pattern (SKILL.md with workflow, references/
  for format and phases, scripts/ for transitions)
- Adopt existing format spec from private plugin's roadmap SKILL.md
- Roadmaps have a simpler lifecycle (Draft -> Active -> Done) with no
  directory movement
- Must produce output that /plan can consume (features with needs-* labels)
- Minimum 2 features (single-feature work doesn't need a roadmap)

## Considered Options

### Decision 1: Creation Workflow Phases

**Context.** The /roadmap skill follows the same 4-phase pattern as /vision
and /prd (Scope, Discover, Draft, Validate). Roadmaps have distinct
concerns: they sequence multiple features, not define a single one.

Key assumptions:
- Phase 3 (Draft) follows the same structural pattern as /vision and /prd
- Always produces Draft status; Active requires human approval
- All features start as "Not started" at creation time
- 4-role pool is sufficient; cross-repo analyst may be needed later

#### Chosen: Roadmap-adapted 4-phase pattern with domain-specific roles

**Phase 1 (Scope)** tracks 6 roadmap-specific coverage dimensions:

| Dimension | What to understand |
|-----------|-------------------|
| Theme clarity | What initiative, why coordinated sequencing? |
| Feature identification | What features, at least 2? Any gaps? |
| Dependency awareness | Which features depend on each other? |
| Sequencing constraints | Hard blockers vs soft preferences? |
| Downstream artifact state | What does each feature need next (needs-*)? |
| Scope boundaries | What's in this roadmap vs excluded? |

**Phase 2 (Discover)** uses 3 fixed agent roles (always all three):

| Role | Investigates |
|------|-------------|
| Feature completeness analyst | Gaps in feature list, granularity issues |
| Dependency validator | Hidden dependencies, stated dependency accuracy |
| Sequencing analyst | Ordering justification, parallelization, needs-* annotation accuracy |

**Phase 4 (Validate)** uses 3 fixed jury roles:

1. **Theme coherence reviewer** -- features belong together, each independently
   describable, granularity matches PRD level, at least 2 features
2. **Sequencing and dependency reviewer** -- dependencies explicit not implied,
   no circularity, rationale explains constraints not just order,
   parallelization acknowledged
3. **Annotation and boundary reviewer** -- needs-* labels match descriptions,
   no downstream content (requirements, architecture, issue lists), no dates,
   structural validation rules met

#### Alternatives Considered

- **Single "roadmap analyst" role for Phase 2**: can't investigate
  completeness, dependencies, and sequencing with equal depth from one
  perspective.
- **4-role pool with selection heuristic**: added a downstream artifact
  assessor as a 4th role with a pick-3-of-4 heuristic. Over-engineered —
  needs-* annotation checking folds naturally into the sequencing analyst
  role. 3 fixed roles is simpler with no practical loss.
- **Reuse PRD roles**: PRD roles investigate single-feature concerns, miss
  multi-feature coordination questions entirely.

### Decision 2: /explore -> /roadmap Handoff

**Context.** Currently /explore produces roadmaps inline via
`phase-5-produce-deferred.md`. Per cross-cutting decision, this should
become an auto-continue handoff.

Key assumptions:
- /roadmap Phase 1 output matches the handoff artifact format
- /roadmap ships in the same PR as the routing table change
- Phase 2 agents consume candidate features as investigation targets

#### Chosen: Auto-continue handoff with theme + candidate features

Three changes:

1. **New `phase-5-produce-roadmap.md`** writes `wip/roadmap_<topic>_scope.md`
   with: Theme Statement, Initial Scope (covers/doesn't cover), Candidate
   Features, Coverage Notes, Decisions from Exploration. Then invokes
   `/shirabe:roadmap <topic>`.

2. **Updated routing table** in `phase-5-produce.md`: Roadmap row changes
   from `phase-5-produce-deferred.md` (terminal) to
   `phase-5-produce-roadmap.md` (auto-continue).

3. **Remove Roadmap section** from `phase-5-produce-deferred.md`. No
   fallback. After removal, deferred retains: Prototype, Spike Report,
   Competitive Analysis.

**Handoff artifact template:**

```markdown
# /roadmap Scope: <topic>

## Theme Statement
<2-3 sentences: what initiative, why coordination matters>

## Initial Scope
### This Roadmap Covers
- <capability area from exploration>

### This Roadmap Does NOT Cover
- <excluded work with reasoning>

## Candidate Features
1. <feature>: <rationale from exploration>
2. <feature>: <rationale>

## Coverage Notes
<Gaps for /roadmap Phase 2 to resolve>

## Decisions from Exploration
<Accumulated decisions, or omitted if none>
```

**Divergences from PRD/VISION templates:** Theme Statement replaces Problem
Statement (roadmaps coordinate, not solve). Candidate Features replace
Research Leads (agents investigate features, not open questions). Initial
Scope uses covers/doesn't cover (matching roadmap format's scope field).

#### Alternatives Considered

- **Keep inline as fallback**: contradicts cross-cutting decision, creates
  dual code paths, masks errors when /roadmap isn't set up.
- **Reuse PRD template verbatim**: roadmaps aren't problem-driven. Candidate
  features are better investigation targets than research leads.

## Decision Outcome

The two decisions compose cleanly. Phase 1's scope document template matches
the handoff artifact format (both use theme statement + candidate features),
so /roadmap works identically whether entered standalone or via /explore
handoff. Phase 2's agent roles investigate the candidate features. Phase 4's
jury validates the qualities that the roadmap format spec defines as good.

The inline production path is fully replaced by the auto-continue handoff,
consistent with PRD, Design Doc, and VISION.

## Solution Architecture

### Overview

The /roadmap skill follows the /vision pattern. Five deliverables:

1. **`skills/roadmap/SKILL.md`** -- creation skill with format spec
   (adopted from private plugin), creation workflow, and lifecycle management

2. **`skills/roadmap/references/`** -- format spec reference file and 4
   phase files

3. **`skills/roadmap/scripts/transition-status.sh`** -- handles
   Draft -> Active -> Done transitions

4. **`skills/explore/references/phases/phase-5-produce-roadmap.md`** --
   handoff handler (auto-continue to /roadmap)

5. **`skills/explore/references/phases/phase-5-produce-deferred.md`** and
   **`phase-5-produce.md`** (modified) -- remove inline Roadmap production,
   update routing table

### Components

```
skills/roadmap/
  SKILL.md                          <-- format + creation workflow
  scripts/
    transition-status.sh            <-- Draft/Active/Done transitions
  references/
    roadmap-format.md               <-- format spec (adopted from private)
    phases/
      phase-1-scope.md              <-- conversational scoping (6 dimensions)
      phase-2-discover.md           <-- 4-role agent pool
      phase-3-draft.md              <-- produce roadmap from findings
      phase-4-validate.md           <-- 3-role jury

skills/explore/
  references/
    phases/
      phase-5-produce.md            <-- update routing: Roadmap -> auto-continue
      phase-5-produce-roadmap.md    <-- handoff to /roadmap
      phase-5-produce-deferred.md   <-- remove Roadmap section
```

### Key Interfaces

**Crystallize -> Produce handoff.** Same auto-continue pattern as VISION.
`phase-5-produce-roadmap.md` writes `wip/roadmap_<topic>_scope.md` and
invokes `/shirabe:roadmap <topic>`.

**Standalone entry.** `/roadmap <topic>` starts the creation workflow.
Detects handoff artifact; skips Phase 1 if present.

**Lifecycle management.** The /roadmap skill owns transitions:
- Draft -> Active: `transition-status.sh <path> Active`
  (precondition: feature list complete, human approval)
- Active -> Done: `transition-status.sh <path> Done`
  (precondition: all features terminal)

**No directory movement.** All roadmaps stay in `docs/roadmaps/` regardless
of lifecycle state (matching the existing private plugin convention).

**Downstream consumption.** /plan reads roadmaps and enriches them directly:
creates GitHub issues (one per feature with needs-* labels), adds an
Implementation Issues table and Mermaid dependency graph into the roadmap,
creates a GitHub milestone, and transitions the roadmap to Active. No
separate PLAN doc is produced — the roadmap IS the plan at the portfolio
level. Roadmap planning is always multi-pr. Each feature's issue then
triggers its own pipeline (PRD -> design -> plan -> implement).

Note: this changes /plan's behavior when `input_type: roadmap`. The /plan
skill's Phase 7 writes into the roadmap doc instead of creating a PLAN doc.
This is a /plan modification, not a /roadmap deliverable — but the /roadmap
skill must produce output that supports this flow.

**Crystallize framework.** Roadmap is already a supported type in the
crystallize framework (promoted from deferred in Feature 1). The signal
table, tiebreaker rules, and scoring procedure require no changes. The
only crystallize-related change is the routing table update (Roadmap row
from deferred-inline to auto-continue).

### Data Flow

**Via /explore handoff:**
```
wip/explore_<topic>_findings.md ---> phase-5-produce-roadmap.md
                                          |
                                          v
                               wip/roadmap_<topic>_scope.md
                                          |
                                          v
                                    /roadmap (Phase 2)
                                          |
                                          v
                               docs/roadmaps/ROADMAP-<topic>.md
```

**Standalone:**
```
/roadmap <topic>
    |
    v
Phase 1: Scope (6 coverage dimensions)
    |
    v
Phase 2: Discover (2-3 agents from 4-role pool)
    |
    v
Phase 3: Draft (produce roadmap)
    |
    v
Phase 4: Validate (3-role jury)
    |
    v
docs/roadmaps/ROADMAP-<topic>.md (Draft)
```

## Implementation Approach

### Phase 1: Roadmap Creation Skill

Create the full /roadmap skill with format spec (adopted from private
plugin), creation workflow, and phase files.

Deliverables:
- `skills/roadmap/SKILL.md`
- `skills/roadmap/references/roadmap-format.md`
- `skills/roadmap/references/phases/phase-1-scope.md`
- `skills/roadmap/references/phases/phase-2-discover.md`
- `skills/roadmap/references/phases/phase-3-draft.md`
- `skills/roadmap/references/phases/phase-4-validate.md`

### Phase 2: Transition Script

Create the lifecycle transition script.

Deliverables:
- `skills/roadmap/scripts/transition-status.sh`

### Phase 3: Explore Handoff

Replace inline production with auto-continue handoff and update routing.

Deliverables:
- `skills/explore/references/phases/phase-5-produce-roadmap.md`
- Modified `skills/explore/references/phases/phase-5-produce.md`
- Modified `skills/explore/references/phases/phase-5-produce-deferred.md`

### Phase 4: Evals

Create eval scenarios for the roadmap skill.

Deliverables:
- `skills/roadmap/evals/evals.json`

## Security Considerations

Same profile as the VISION skill: document template, scoring table entry,
and produce handler. No external inputs, no new permissions, no new
dependencies. The visibility gate applies (roadmaps don't have
visibility-gated sections, so no gating logic needed — simpler than VISION).

## Consequences

### Positive

- Roadmap creation gets the same guided workflow as PRDs, designs, and
  VISIONs instead of bare template production
- Domain-specific agents catch common roadmap problems (feature gaps,
  hidden dependencies, unjustified ordering)
- Consistent auto-continue handoff across all major artifact types
- /plan integration is unchanged — /roadmap produces the same format

### Negative

- One more skill to maintain (though it follows an established pattern)
- Removes inline production fallback — if /roadmap has issues, /explore
  can't produce roadmaps at all

### Mitigations

- Pattern is proven across 3 prior skills — maintenance cost is low
- If /roadmap breaks, the error surfaces clearly (better than silent
  fallback to a lower-quality template)
