# Phase 2 Research: Codebase Analyst

## Lead 1: Template and Content Boundaries

### Findings

**Artifact skill pattern.** Each artifact type follows a consistent structure across three layers: (1) a reference skill (`SKILL.md`) that defines format, frontmatter, sections, lifecycle, validation rules, and content boundaries; (2) a file naming convention and directory; (3) integration with the explore crystallize framework via Phase 5 handlers.

**Frontmatter schema across types:**

| Type | Required Fields | Optional Fields | Purpose |
|------|----------------|-----------------|---------|
| PRD | `status`, `problem`, `goals` | `upstream`, `source_issue` | Self-contained summary for relevance assessment |
| Design Doc | `status`, `problem`, `decision`, `rationale` | `spawned_from` | Executive summary + agent-parseable metadata |
| Roadmap | `status`, `theme`, `scope` | none | Initiative coordination context |
| Spike Report | `status`, `question`, `timebox` | none | Feasibility framing |
| Competitive Analysis | `status`, `market`, `date` | none | Market segment identification |

Pattern: every type has `status` plus 1-3 fields that capture the type's essential identity in one paragraph each, using YAML literal block scalars (`|`). Frontmatter status must match the Status section in the body. The fields are designed so a reader (or agent) can assess relevance without reading the full document.

**Required sections across types:**

All types share a `Status` section as #1. After that, sections are type-specific but follow a consistent ordering principle: context first, then substance, then boundaries/consequences.

- PRD (7 required): Status, Problem Statement, Goals, User Stories, Requirements, Acceptance Criteria, Out of Scope
- Design Doc (9 required): Status, Context and Problem Statement, Decision Drivers, Considered Options, Decision Outcome, Solution Architecture, Implementation Approach, Security Considerations, Consequences
- Roadmap (5 required): Status, Theme, Features, Sequencing Rationale, Progress

**Lifecycle patterns:**

| Type | States | Terminal Behavior |
|------|--------|-------------------|
| PRD | Draft -> Accepted -> In Progress -> Done | Completes (Done) |
| Design Doc | Proposed -> Accepted -> Planned -> Current -> Superseded | Completes or superseded; files move directories |
| Roadmap | Draft -> Active -> Done | Completes (Done) |
| VISION (proposed) | Draft -> Accepted -> Active -> Sunset | Stays Active; never "completes" |

VISION's lifecycle is unique: it doesn't reach a "Done" state. The closest analog is Roadmap (Draft -> Active -> Done), but even Roadmap completes. VISION's "Active" is a persistent state, and "Sunset" represents retirement rather than completion. This is a genuine pattern deviation.

**Content boundaries pattern.** Every artifact type has an explicit "Content Boundaries" or equivalent section stating what the type is NOT. These boundary definitions reference other types, creating a mutual exclusion mesh:

- PRD excludes: technical architecture (design doc), implementation (plan), code examples (design doc), competitive analysis (separate artifact)
- Design Doc excludes: requirements (PRD), task breakdown (plan); has a full "lighter alternatives" section pointing to ADR and Spike
- Roadmap excludes: detailed requirements (PRD), task breakdown (plan), timelines/dates

**Visibility-aware content.** Design Doc has a Document Section Matrix that gates sections by scope x visibility. Market Context is Strategic + Private only. Required Tactical Designs is Strategic only. This pattern directly applies to VISION (competitive positioning and resource implications gated to private repos per the scope doc).

**Validation rules pattern.** Every type has phase-specific validation rules: rules during drafting (frontmatter present, status correct, sections in order) and rules when referenced by downstream workflows (status must be at a specific state). PRD requires "Accepted" or "In Progress" for downstream use; Roadmap requires "Active" for upstream context; Design Doc requires "Accepted" for planning.

### Implications for Requirements

**VISION frontmatter should follow the established pattern:**
```yaml
---
status: Draft
thesis: |
  1 paragraph: the project's reason to exist and core bet.
scope: org | project
upstream: docs/visions/VISION-<parent>.md  # optional, project-level only
---
```

The `thesis` field mirrors how `problem` works in PRD and `theme` works in Roadmap -- a one-paragraph identity statement. The `scope` field (org vs project) is unique to VISION but justified by the two-level design. The `upstream` field follows PRD's optional `upstream` pattern for linking to parent artifacts.

**VISION required sections should be (in order):**
1. Status
2. Thesis -- the project's core bet and reason to exist
3. Audience -- who this serves
4. Value Proposition -- what unique value it delivers
5. Org Fit -- how it fits within the broader portfolio (org-level) or organization (project-level)
6. Success Criteria -- measurable indicators of thesis validation
7. Non-Goals -- explicit exclusions and anti-goals
8. Open Questions -- present only in Draft status (follows PRD pattern)

**VISION content boundaries should explicitly exclude:**
- Feature requirements (that's a PRD)
- Feature sequencing or timelines (that's a Roadmap)
- Technical architecture decisions (that's a Design Doc)
- Implementation tasks (that's a Plan)
- Competitive analysis detail (that's a separate artifact in private repos; VISION can reference competitive positioning in private visibility but shouldn't duplicate the full analysis)

The boundary rule: if you're writing "what to build" instead of "why this project should exist," the content belongs downstream.

**VISION validation rules should include:**
- During drafting: frontmatter has `status`, `thesis`, `scope`; status is Draft; all required sections present; scope is `org` or `project`; if `scope: project` and `upstream` is set, upstream file must exist
- During downstream use: status must be Accepted or Active; Draft VISIONs cannot serve as upstream context for PRDs or Roadmaps
- Transition rules: Draft -> Accepted requires Open Questions empty/removed and human approval; Accepted -> Active when downstream work begins; Active -> Sunset requires explicit rationale documented

**Visibility-aware sections (following Design Doc's section matrix pattern):**

| Section | Private | Public |
|---------|---------|--------|
| Status | Required | Required |
| Thesis | Required | Required |
| Audience | Required | Required |
| Value Proposition | Required | Required |
| Competitive Positioning | Optional | No |
| Resource Implications | Optional | No |
| Org Fit | Required | Required |
| Success Criteria | Required | Required |
| Non-Goals | Required | Required |
| Open Questions | Draft only | Draft only |
| Downstream Artifacts | When exists | When exists |

### Open Questions

1. **Should VISION have an optional "Downstream Artifacts" section?** PRD has this pattern (added when downstream work starts). For VISION, this would track which Roadmaps, PRDs, or Design Docs implement the vision. Given that VISION stays Active and accumulates downstream work over time, this seems valuable but wasn't specified in the exploration decisions.

2. **What triggers Active -> Sunset?** The exploration says VISION "stays Active rather than completing" but Sunset needs a defined trigger. Should the VISION doc itself state sunset conditions (like success criteria for thesis invalidation)?

3. **Is there a "Superseded" state?** Design Docs have Superseded. If a project pivots fundamentally, does the old VISION get Sunset and a new one gets created, or should there be a Superseded state that links to the replacement? The exploration chose a 4-state lifecycle (Draft -> Accepted -> Active -> Sunset) without Superseded.


## Lead 3: Phase 5 Produce Handler

### Findings

**Phase 5 routing structure.** The produce phase reads `wip/explore_<topic>_crystallize.md` to determine the chosen type, then routes to a type-specific sub-file. The routing table in `phase-5-produce.md` maps each type to a reference file and a handoff behavior (auto-continue vs. terminal stop).

**Three handoff categories exist:**

1. **Auto-continue (skill invocation)**: PRD, Design Doc, Decision Record. These write handoff artifacts then immediately invoke the downstream skill (`/shirabe:prd`, `/shirabe:design`, `/shirabe:decision`). The session continues seamlessly.

2. **Terminal with user action**: Plan. Tells the user to run `/plan <topic>` separately. No artifacts produced beyond what's already in wip/.

3. **Terminal with inline production**: Roadmap, Spike Report, Competitive Analysis. These produce the final artifact directly in Phase 5 (writing to `docs/roadmaps/`, `docs/spikes/`, or `docs/competitive/`), commit, and tell the user what to do next. No downstream skill invocation.

**VISION maps to category 3 (terminal with inline production).** Per the scope doc: "Produced inline in Phase 5, not via a separate command." This matches the Roadmap/Spike/Competitive pattern exactly.

**Inline production pattern (from deferred types).** Each inline producer:

1. Writes the artifact file to its canonical location with full frontmatter and populated sections
2. Synthesizes content from exploration findings (doesn't just copy raw research)
3. Commits with a conventional commit message: `docs(explore): produce <type> for <topic>`
4. Tells the user what was created and what to do next (review, transition status)
5. Leaves wip/ artifacts untouched

**Specific inline patterns by type:**

Roadmap: writes `docs/roadmaps/ROADMAP-<topic>.md` with frontmatter (`status`, `theme`, `scope`), Status section, Theme, Features (with per-feature structure: description, dependencies, status, downstream), Sequencing Rationale, and Progress table. User message tells them to review feature list, then transition to Active.

Spike Report: writes `docs/spikes/SPIKE-<topic>.md` with frontmatter (`status`, `question`, `timebox`), Status section, Question, Context, Approach, Findings, Recommendation. Removes `needs-spike` label if applicable. User message tells them to complete investigation within timebox.

Competitive Analysis: checks repo visibility first. Refuses in public repos with alternatives. In private repos, writes `docs/competitive/COMP-<topic>.md` with frontmatter (`status`, `market`, `date`), full sections.

**Visibility gating precedent.** Competitive Analysis already has a visibility check in Phase 5. VISION's scope doc says "Visibility controls content richness (what sections appear), not availability" -- so VISION wouldn't refuse in public repos but would omit certain sections. This is a different pattern from Competitive Analysis (which refuses entirely in public repos) and more like Design Doc's section matrix approach.

**Handoff artifact patterns for auto-continue types (for contrast):**

PRD handoff writes `wip/prd_<topic>_scope.md` matching /prd Phase 1's output format: Problem Statement, Initial Scope (In/Out), Research Leads, Coverage Notes, Decisions from Exploration. Then invokes `/shirabe:prd <topic>`.

Design Doc handoff writes two files: (1) design doc skeleton at `docs/designs/DESIGN-<topic>.md` with frontmatter and partial sections, (2) summary file at `wip/design_<topic>_summary.md`. Then invokes `/shirabe:design <topic>`.

Decision Record handoff writes a decision brief at `wip/explore_<topic>_decision-brief.md`, then invokes `/shirabe:decision`.

VISION doesn't need this two-step handoff since it produces inline.

**Decisions file integration.** Both PRD and Design Doc handoff files check for `wip/explore_<topic>_decisions.md` and include accumulated decisions. The inline producers (Roadmap, Spike, Competitive) don't explicitly mention this file but synthesize from findings. VISION's inline producer should similarly synthesize exploration decisions into the document sections rather than including a raw "Decisions" section.

### Implications for Requirements

**VISION Phase 5 handler should:**

1. Be added to the deferred types file (`phase-5-produce-deferred.md`) or, given its distinct visibility handling, get its own file (`phase-5-produce-vision.md`). A separate file is more consistent with the pattern where each type with unique behavior gets its own handler -- Roadmap, Spike, and Competitive Analysis share a file only because they were all "deferred" types without dedicated skills. Since VISION is being built as a supported type with its own skill, a dedicated file makes more sense.

2. Check repo visibility to determine content richness (not availability). In private repos, include Competitive Positioning and Resource Implications sections. In public repos, omit those sections. This differs from Competitive Analysis (which refuses entirely) and follows the Design Doc section matrix pattern instead.

3. Check scope context. VISION is gated to strategic scope. If the exploration ran in tactical scope, this handler should never be reached (the crystallize phase should prevent it). But as a safety check, the handler should verify strategic scope.

4. Write `docs/visions/VISION-<topic>.md` with:
   - Full frontmatter (`status: Draft`, `thesis`, `scope` as org or project, `upstream` if project-level)
   - All required sections populated from exploration findings
   - Visibility-gated sections included or omitted based on repo context
   - Synthesized content, not raw research output

5. Commit: `docs(explore): produce vision for <topic>`

6. Tell the user what was created and what to do next. Following the Roadmap pattern:
   > Created `docs/visions/VISION-<topic>.md` as a Draft vision document. Review the thesis and success criteria, then transition to Accepted when ready.
   >
   > To start downstream work, create a Roadmap or PRD referencing this vision as upstream context.

7. Leave wip/ artifacts untouched (standard cleanup rule).

**Routing table update.** The Phase 5 produce routing table needs a new row:

| Chosen Type | Reference File | Handoff |
|-------------|----------------|---------|
| Vision | `phase-5-produce-vision.md` | Stops -- terminal |

**PROJECTS.md integration.** Per the scope doc, PROJECTS.md is in-scope. The Phase 5 handler should update PROJECTS.md when producing a VISION, adding/updating the project entry. This is new behavior not present in any existing handler -- none of the current types update a registry file during production. This needs specification: does the handler create PROJECTS.md if it doesn't exist? What state does the project entry get (likely "Evaluating" since a Draft VISION means the project is being evaluated)?

### Open Questions

1. **Separate file or addition to deferred?** The scope doc says VISION is a "supported crystallize type," implying it should be first-class like PRD and Design Doc rather than lumped with deferred types. A separate `phase-5-produce-vision.md` file is the cleaner path. This is a structural decision for the PRD.

2. **PROJECTS.md update mechanics in Phase 5.** Should the handler create/update PROJECTS.md automatically, or should the user message mention it as a manual step? The scope doc lists PROJECTS.md as in-scope but the exploration noted this wasn't fully specified. The Phase 5 handler is the natural place for automatic updates since it's already writing files and committing.

3. **Org-level vs project-level differences in production.** The handler needs to determine `scope: org` vs `scope: project` and set the `upstream` field accordingly. What signal from the exploration determines this? The crystallize phase would need to capture this choice, or the handler infers it from context (e.g., whether the exploration is in the vision repo vs a project repo).


## Summary

The existing artifact skill system follows a consistent three-layer pattern: frontmatter (status + 1-3 identity fields), required sections (context first, substance, then boundaries), and phase-specific validation rules. VISION fits this pattern cleanly with `thesis` and `scope` as its identity fields, a 7-8 section structure, and a lifecycle that deviates only in its persistent "Active" state. The Phase 5 handler should be a standalone file following the inline production pattern (write artifact, commit, inform user) with a visibility-gated section matrix rather than a visibility-gated availability check, plus a new PROJECTS.md registry update that has no precedent in existing handlers.
