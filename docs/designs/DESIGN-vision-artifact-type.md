---
status: Proposed
problem: |
  The /explore workflow's crystallize framework has no artifact type for the
  pre-requirements layer -- project thesis, org fit, and strategic justification
  go undocumented or get shoehorned into Roadmap "Vision" sections.
decision: |
  Add VISION as the sixth supported crystallize type with a dedicated /vision
  creation skill, anti-signal scope gating for tactical suppression, and a
  human-gated lifecycle (Draft, Accepted, Active, Sunset). /explore hands off
  to /vision the same way it hands off to /prd and /design.
rationale: |
  VISION fills a genuine gap between "idea" and "requirements" that every major
  product framework acknowledges. The anti-signal approach for scope gating
  requires zero structural changes to the scoring mechanism, and the heavy
  anti-signal count (7) prevents false-positive recommendations.
---

# DESIGN: Vision Artifact Type

## Status

Proposed

## Context and Problem Statement

The /explore workflow can crystallize into 9 artifact types, but none capture
the pre-requirements layer: why a project should exist, what it offers, and
how it fits the organization. When exploring a new project idea, the closest
options are PRD (too feature-specific, assumes the project already exists) or
Roadmap (sequences features, doesn't justify the project itself). Project
thesis and strategic justification either go undocumented or get embedded in
roadmap "Vision" sections, losing their identity as a distinct decision layer.

This design adds VISION as a supported artifact type in the crystallize
framework, with a dedicated `/vision` creation skill that owns all
lifecycle management, a Phase 5 handoff from /explore, and integration
into the existing pipeline.

## Decision Drivers

- Must integrate into the existing crystallize framework without structural
  changes (the scoring mechanism is type-agnostic)
- Must have clear boundaries with PRD and Roadmap to prevent misrouting
- Must work at both org-level and project-level scope
- Gated to strategic scope (tactical is a hard anti-signal, per exploration
  decision D4)
- Visibility controls content richness, not availability (Strategic+Public
  and Strategic+Private both valid)
- Must follow the established skill pattern (frontmatter spec, required
  sections, lifecycle, validation, quality guidance)
- Each doc type should have its own skill that owns all lifecycle
  management details for that type
- /explore hands off to /vision (auto-continue pattern, like /prd and
  /design), but /vision also works as a standalone command

## Considered Options

### Decision 1: Template Structure

**Context.** The VISION template needs to capture project thesis, audience,
value proposition, org fit, success criteria, and non-goals. It must work at
both org-level (why does this org exist) and project-level (why does this
project exist within the org), and handle the visibility dimension (public
repos get fewer sections than private). Two research threads -- an
exploration template proposal and a codebase skill pattern analysis --
converged on nearly identical structures.

Key assumptions:
- The `vision-format.md` reference file lives in the skill's `references/`
  directory alongside other format files
- Open Questions follows the PRD pattern (Draft only, must resolve for
  Accepted)
- VISIONs are infrequent; template optimizes for clarity over brevity
- The persistent Active state is a novel but acceptable lifecycle deviation

#### Chosen: Section Matrix (single template with visibility-gated optional sections)

A single template with a `scope` field (`org` | `project`) and a visibility
matrix that gates two optional sections to private repos.

**Frontmatter:**

```yaml
---
status: Draft
thesis: |
  1 paragraph: the core belief about why this project/org should exist.
scope: org | project
upstream: docs/visions/VISION-<parent>.md  # optional, project-level only
---
```

Required fields: `status`, `thesis`, `scope`. Optional: `upstream`.

**Required sections (in order):**

1. **Status** -- current lifecycle state
2. **Thesis** -- the core bet, written as a hypothesis ("We believe
   [audience] needs [capability] because [insight]"), not a problem
   statement
3. **Audience** -- who benefits, describing their current situation
4. **Value Proposition** -- category of value delivered, not features
5. **Org Fit** -- how this relates to the broader portfolio
6. **Success Criteria** -- project-level outcomes (adoption, ecosystem,
   quality signals), not feature acceptance criteria
7. **Non-Goals** -- what this project deliberately is NOT, each with
   reasoning

**Optional sections:**

- **Open Questions** -- Draft status only, must resolve for Accepted
- **Downstream Artifacts** -- added when downstream work starts

**Visibility-gated (private repos only):**

- **Competitive Positioning** -- market alternatives
- **Resource Implications** -- investment and opportunity cost

**Section matrix:**

| Section | Public | Private | Org | Project |
|---------|--------|---------|-----|---------|
| Status | Required | Required | Required | Required |
| Thesis | Required | Required | Required | Required |
| Audience | Required | Required | Required | Required |
| Value Proposition | Required | Required | Required | Required |
| Competitive Positioning | -- | Optional | Optional | Optional |
| Resource Implications | -- | Optional | Optional | Optional |
| Org Fit | Required | Required | Required | Required |
| Success Criteria | Required | Required | Required | Required |
| Non-Goals | Required | Required | Required | Required |
| Open Questions | Draft only | Draft only | Draft only | Draft only |
| Downstream Artifacts | When exists | When exists | When exists | When exists |

**Content boundaries (VISION does NOT contain):**

- Feature requirements or user stories (PRD)
- Feature sequencing or timelines (Roadmap)
- Technical architecture decisions (Design Doc)
- Implementation tasks (Plan)
- Full competitive analysis (separate artifact; VISION can reference
  positioning but not duplicate analysis)

#### Alternatives Considered

- **Strict PRD Mirror** (fixed sections, no visibility gating): simplest
  approach, but ignores the visibility constraint. Private repos lose the
  ability to capture competitive positioning and resource implications.

- **Dual Template** (separate org and project templates): two format files
  with ~70% overlap. Org/project differences are in section guidance, not
  structure. Creates sync burden with no precedent in the current system.

### Decision 2: Crystallize Framework Integration

**Context.** The crystallize framework scores artifact types using
signal/anti-signal tables and a demotion rule. VISION is the sixth
supported type. The open question: should tactical scope be a pre-filter
(remove from candidates before scoring) or a regular anti-signal?

Key assumptions:
- The demotion rule remains absolute (1 anti-signal demotes below all
  clean-scoring types)
- No other future type needs scope-based gating at type-selection level

#### Chosen: Anti-Signal for tactical scope gating

Tactical scope is VISION's seventh anti-signal: "Scope is tactical
(override or repo default)." It participates in the standard scoring and
demotion procedure -- no structural changes to the framework.

**Signal/anti-signal table (8 signals, 7 anti-signals):**

| Signals | Anti-Signals |
|---------|-------------|
| Project doesn't exist yet (no repo, no codebase) | Project already exists and question is about its next feature |
| Exploration centered on "should we build this?" | Requirements or user stories emerged (route to PRD) |
| Org fit or strategic alignment was the core question | A PRD, design doc, or roadmap already covers this project |
| Thesis validation was the exploration's primary output | Single coherent feature emerged (route to PRD) |
| Multiple fundamentally different project directions viable | Specific users and needs already identified |
| Target audience not yet well-defined | Negative conclusion -- project should NOT exist (route to Rejection Record) |
| Core question is "should this project exist?" | Scope is tactical (override or repo default) |
| Exploration produced strategic justification arguments | |

**Tiebreaker rules (4 new entries for Step 3):**

1. **VISION vs PRD:** Does the project exist yet? No -> VISION. Yes -> PRD.
2. **VISION vs Roadmap:** "Should we do this at all?" -> VISION. "What
   sequence?" -> Roadmap.
3. **VISION vs Rejection Record:** "Proceed" -> VISION. "Don't proceed" ->
   Rejection Record.
4. **VISION vs No Artifact:** Does anyone else need the strategic argument?
   Yes -> VISION. No -> No Artifact.

**Disambiguation rule:**

When exploration surfaces both strategic justification AND feature
requirements, VISION comes first. Strategic justification must be accepted
before requirements are worth writing.

#### Alternatives Considered

- **Pre-Filter:** Remove VISION from candidates when scope is tactical.
  Rejected: introduces a structural concept (candidate filtering) that
  doesn't exist in the framework, violating the no-structural-changes
  constraint. Reduces observability by hiding suppression reasoning.

- **Hybrid:** Pre-filter for scope, anti-signals for content. Rejected:
  combines both mechanisms' costs without proportional benefit.

### Decision 3: Lifecycle Transition Rules

**Context.** VISION has four states (Draft, Accepted, Active, Sunset) --
decided during exploration. Open questions: what triggers each transition,
can Active VISIONs be edited in place, is Sunset reversible, does VISION
need Superseded alongside Sunset?

Key assumptions:
- Downstream skills will eventually validate upstream VISION status
- Thesis section is a reliable proxy for project identity change
- A transition script (like design doc's `transition-status.sh`)
  handles all state changes deterministically

#### Chosen: Script-Driven Transitions with Directory Movement

All transitions are executed by a deterministic script
(`scripts/transition-status.sh`) that validates preconditions, updates
status in both frontmatter and body, and moves files between directories
when status changes. Follows the same pattern as the design doc
transition script.

**Transition table:**

| Transition | Preconditions | Directory Movement |
|-----------|---------------|-------------------|
| Draft -> Accepted | Open Questions empty/removed | None (stays in `docs/visions/`) |
| Accepted -> Active | At least one downstream artifact references this VISION | None (stays in `docs/visions/`) |
| Active -> Sunset | Reason provided (abandoned, pivoted, or invalidated) | Moves to `docs/visions/sunset/` |

**Directory mapping:**

| Status | Directory |
|--------|-----------|
| Draft, Accepted, Active | `docs/visions/` |
| Sunset | `docs/visions/sunset/` |

**Script interface:**

```
scripts/transition-status.sh <vision-doc-path> <target-status> [superseding-doc]

# Examples:
scripts/transition-status.sh docs/visions/VISION-koto.md Accepted
scripts/transition-status.sh docs/visions/VISION-koto.md Active
scripts/transition-status.sh docs/visions/VISION-koto.md Sunset
scripts/transition-status.sh docs/visions/VISION-koto.md Sunset docs/visions/VISION-koto-v2.md
```

The script validates allowed transitions, rejects forbidden ones with
an error, updates frontmatter + body status, adds `superseded_by` field
when a successor is provided, and uses `git mv` to move Sunset docs.
JSON output for programmatic consumption (same format as design doc
script).

**Forbidden transitions:** Draft -> Active (must endorse first), Draft ->
Sunset (delete instead), Active -> Accepted/Draft (regression), Sunset ->
any (terminal, irreversible).

**In-place edit rule:** Active VISIONs can be edited for everything except
the Thesis. Thesis changes signal a project pivot -- create a new VISION
and Sunset the old one via the script with the superseding doc argument.

**No separate Superseded state.** Sunset covers all termination scenarios.
When superseded, the script records the successor path in frontmatter
(`superseded_by`) and in the body Status section ("Sunset: superseded by
[VISION-X](path)"). One Active VISION per project at a time.

#### Alternatives Considered

- **Human-only transitions (no script):** Transitions done manually by
  editing status and moving files. Rejected: error-prone (forgetting to
  update frontmatter OR body, forgetting to move files), and the design
  doc skill already established that scripts handle this better.

- **Reversible Sunset:** Allow Sunset -> Active for project revival.
  Rejected: no other artifact type has reversible terminal state. Creates
  ambiguity when superseded VISIONs are reversed. New VISION for revival
  is cleaner.

## Decision Outcome

The three decisions compose cleanly. A single template (Decision 1) with
visibility-gated sections is scored by the crystallize framework using
anti-signals (Decision 2), and managed through human-gated lifecycle
transitions (Decision 3).

The design is intentionally conservative: VISION has the most anti-signals
(7) of any supported type, ensuring it's only recommended when the
exploration genuinely points to a pre-project strategic artifact. The
heavy anti-signal count reflects that VISION occupies a narrow niche.
The lifecycle is the simplest in the system (all human-triggered),
appropriate for an artifact created a handful of times per project.

## Solution Architecture

### Overview

The /vision skill follows the same pattern as /prd: a SKILL.md that
defines both the format specification AND a multi-phase creation workflow.
/explore hands off to /vision via the auto-continue pattern (writes a
handoff artifact, invokes /vision in the same session). /vision also
works standalone when someone already knows they want a vision document.

Four deliverables:

1. **`skills/vision/SKILL.md`** -- Creation skill with format spec,
   lifecycle management, validation rules, quality guidance, content
   boundaries, and a multi-phase creation workflow. Follows the /prd
   pattern: format reference embedded in the same file as the workflow.

2. **`skills/vision/references/phases/*.md`** -- Phase files for the
   creation workflow (scope, discover, draft, validate).

3. **`skills/explore/references/quality/crystallize-framework.md`**
   (modified) -- Add VISION to the Supported Types section with signal
   table, tiebreaker rules, and disambiguation rule. Move from 5 to 6
   supported types in Step 1.

4. **`skills/explore/references/phases/phase-5-produce-vision.md`** --
   Phase 5 handoff handler. Writes `wip/vision_<topic>_scope.md` and
   auto-invokes /vision (same pattern as phase-5-produce-prd.md).

5. **`skills/explore/references/phases/phase-5-produce.md`** (modified)
   -- Add VISION to the routing table as auto-continue (same row pattern
   as PRD and Design Doc).

### Components

```
skills/vision/
  SKILL.md                          <-- format + creation workflow
  scripts/
    transition-status.sh            <-- deterministic lifecycle transitions
  references/
    phases/
      phase-1-scope.md              <-- conversational scoping
      phase-2-discover.md           <-- parallel research agents
      phase-3-draft.md              <-- produce VISION draft
      phase-4-validate.md           <-- jury review

skills/explore/
  references/
    quality/
      crystallize-framework.md      <-- add VISION supported type
    phases/
      phase-5-produce.md            <-- add VISION routing entry
      phase-5-produce-vision.md     <-- handoff to /vision (auto-continue)
```

### Key Interfaces

**Crystallize -> Produce handoff.** When `phase-5-produce.md` receives
"VISION" as the chosen type, it reads `phase-5-produce-vision.md`. The
handler writes `wip/vision_<topic>_scope.md` (synthesized from
exploration findings) and auto-invokes /vision. This is the same
auto-continue pattern used for PRD and Design Doc.

**Standalone entry.** `/vision <topic>` starts the creation workflow
directly, bypassing /explore. The skill detects whether a handoff
artifact exists (`wip/vision_<topic>_scope.md`) and skips Phase 1 if so.

**Creation workflow phases.** Modeled after /prd (lighter since VISIONs
are shorter documents):

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0. Setup | Branch, visibility detection | On topic branch |
| 1. Scope | Conversational scoping | Problem statement + research leads |
| 2. Discover | Parallel research agents | Research findings in wip/ |
| 3. Draft | Produce VISION draft | Complete VISION draft |
| 4. Validate | Jury review (thesis quality, boundaries) | Validated VISION |

Phase 2 agents investigate: audience validation, value proposition
clarity, org fit evidence, competitive landscape (private only), and
success criteria measurability.

Phase 4 jury focuses on VISION-specific quality: is the thesis a
hypothesis (not a problem statement)? Do success criteria avoid
feature-level metrics? Does org fit explain why HERE and not elsewhere?
Are non-goals about identity (not scope)?

**Lifecycle management.** The /vision skill owns all status transitions:
- Draft -> Accepted: `/vision accept <path>` (validates Open Questions
  resolved)
- Accepted -> Active: `/vision activate <path>` (validates downstream
  artifact exists)
- Active -> Sunset: `/vision sunset <path>` (records reason in Status
  section)

**Visibility check.** The skill reads visibility from CLAUDE.md (same
as /explore Phase 0). Public repos get 7 required sections. Private
repos additionally get Competitive Positioning and Resource Implications
as optional sections.

**Naming.** Output: `docs/visions/VISION-<topic>.md` (kebab-case).

### Data Flow

**Via /explore handoff:**
```
wip/explore_<topic>_scope.md ----+
wip/explore_<topic>_findings.md -+---> phase-5-produce-vision.md
wip/explore_<topic>_decisions.md +        |
                                          v
                               wip/vision_<topic>_scope.md
                                          |
                                          v
                                    /vision (auto-continue)
                                          |
                                          v
                               docs/visions/VISION-<topic>.md
```

**Standalone:**
```
/vision <topic>
    |
    v
Phase 1: Scope (conversational)
    |
    v
Phase 2: Discover (agents)
    |
    v
Phase 3: Draft
    |
    v
Phase 4: Validate (jury)
    |
    v
docs/visions/VISION-<topic>.md
```

## Implementation Approach

### Phase 1: Vision Creation Skill

Create the full `/vision` skill with format specification, creation
workflow, lifecycle management, transition script, and phase files.

Deliverables:
- `skills/vision/SKILL.md`
- `skills/vision/scripts/transition-status.sh`
- `skills/vision/references/phases/phase-1-scope.md`
- `skills/vision/references/phases/phase-2-discover.md`
- `skills/vision/references/phases/phase-3-draft.md`
- `skills/vision/references/phases/phase-4-validate.md`

### Phase 2: Crystallize Framework Update

Add VISION to the crystallize framework as a supported type. Update
the scoring procedure, add tiebreaker rules and disambiguation. Also
clean up the stale "Deferred Types" section -- it still lists Roadmap,
Spike Report, Competitive Analysis, and Decision Record as deferred,
but all four already have working produce handlers. Only Prototype
remains deferred.

Deliverables:
- Modified `skills/explore/references/quality/crystallize-framework.md`

### Phase 3: Phase 5 Handoff Handler

Create the handoff handler (writes scope artifact, auto-invokes /vision)
and add routing.

Deliverables:
- `skills/explore/references/phases/phase-5-produce-vision.md`
- Modified `skills/explore/references/phases/phase-5-produce.md`

### Phase 4: Evals

Create eval scenarios for the vision skill per CLAUDE.md conventions.

Deliverables:
- `skills/vision/evals/evals.json`

## Security Considerations

This design adds a document template, a scoring table entry, and a
produce handler to the workflow skills. It does not download, execute,
or process external inputs. It requires no filesystem, network, or
process permissions beyond what /explore already has, and introduces
no new dependencies.

The one relevant dimension is the **visibility gate**: the Phase 5
produce handler relies on the `## Visibility` value in the exploration
scope file (written by Phase 0 from CLAUDE.md) to decide whether to
include Competitive Positioning and Resource Implications sections. If
the scope file has an incorrect visibility value, private content could
appear in a public repo's VISION doc. This is low severity -- CLAUDE.md
is the authoritative source (immutable per repo), Phase 0 reads it
directly, and PR review catches mismatches. The same pattern is already
used for Design Doc's Market Context and Competitive Analysis's
private-repo restriction.

## Consequences

### Positive

- Fills the pre-PRD gap: project thesis and strategic justification get
  their own artifact type instead of being shoehorned into Roadmaps or
  lost in wip/ research files
- Follows established patterns: the skill structure, crystallize
  integration, and produce handler all mirror existing types
- Heavy anti-signal count (7) prevents false-positive VISION
  recommendations

### Negative

- Adds a sixth supported type to the crystallize framework, increasing
  the scoring surface (6 types x signals/anti-signals per type)
- VISION's lifecycle (persistent Active, no Done) is a novel pattern that
  status management tooling hasn't handled before
- The Thesis-boundary edit rule requires human judgment about what counts
  as a "Thesis change" vs a rewording

### Mitigations

- The scoring surface increase is minimal: the framework is type-agnostic,
  so adding one type doesn't change the procedure complexity
- The novel lifecycle is simple enough (4 states, all human-triggered)
  that tooling changes are trivial
- The Thesis boundary can be refined through usage if it proves too coarse
  or too fine in practice, without changing the lifecycle states
