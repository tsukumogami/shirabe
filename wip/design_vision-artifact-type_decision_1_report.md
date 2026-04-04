<!-- decision:start id="vision-template-structure" status="assumed" -->
### Decision: VISION Template Structure

**Context**

The /explore workflow needs a VISION artifact type that sits above PRDs in the artifact hierarchy, capturing project thesis, audience, value proposition, org fit, and success criteria. The template must work at both org-level (why does this organization exist?) and project-level (why does this project exist within the org?), must follow the established skill pattern (frontmatter, required sections, lifecycle, validation, quality guidance), and must handle the visibility dimension by controlling content richness rather than availability.

Two independent research threads -- a lead template proposal and a codebase skill pattern analysis -- converged on nearly identical structures. The PRD format reference provides the canonical pattern to follow. The Design Doc's section matrix provides the precedent for visibility-gated content.

**Assumptions**

- The `vision-format.md` reference file will live in the skill's `references/` directory alongside other format files. If wrong: file location changes but content doesn't.
- Open Questions follows the PRD pattern exactly (present only in Draft, must be empty or removed for Accepted transition). Both research sources agreed on this.
- VISION docs will be infrequent compared to PRDs and design docs, so the template should optimize for clarity over brevity.
- The Active lifecycle state is persistent and acceptable as a novel pattern deviation from other artifact types that all have terminal "Done" states.

**Chosen: Section Matrix (single template with visibility-gated optional sections)**

A single template with a scope field (`org` | `project`) and a visibility matrix that gates two optional sections to private repos.

**Frontmatter schema:**

```yaml
---
status: Draft
thesis: |
  1 paragraph: the core belief about why this project/org should exist.
scope: org | project
upstream: docs/visions/VISION-<parent>.md  # optional, project-level only
---
```

Required fields: `status`, `thesis`, `scope`. Optional: `upstream` (path to org-level VISION when scope is `project`).

**Required sections (in order):**

1. **Status** -- current lifecycle state
2. **Thesis** -- the core bet. Why this project/org should exist. Written as a hypothesis ("We believe [audience] needs [capability] because [insight]"), not a problem statement.
3. **Audience** -- who benefits. Describes their current situation, not feature requests. Org-level: who the org serves. Project-level: which segment this project targets.
4. **Value Proposition** -- the category of value delivered. Not features. What the audience can't get today.
5. **Org Fit** -- how this relates to the broader portfolio. Org-level: what unifies the portfolio. Project-level: why this project belongs in this org.
6. **Success Criteria** -- project-level outcomes that justify the project's existence. Adoption signals, ecosystem signals, quality signals. Not feature acceptance criteria.
7. **Non-Goals** -- what this project deliberately is NOT. Bounds the project's identity, not a feature's scope. Each non-goal includes reasoning.

**Optional sections:**

- **Open Questions** -- present only in Draft status. Must be empty or removed before transitioning to Accepted.
- **Downstream Artifacts** -- added when downstream work starts. Links to PRDs, Roadmaps, Design Docs that elaborate on this vision.

**Visibility-gated optional sections (private repos only):**

- **Competitive Positioning** -- how this project relates to alternatives in the market. Only in private repos.
- **Resource Implications** -- investment required and opportunity cost. Only in private repos.

**Section matrix:**

| Section | Public | Private | Org-level | Project-level |
|---------|--------|---------|-----------|---------------|
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

- Feature requirements or user stories (that's a PRD)
- Feature sequencing or timelines (that's a Roadmap)
- Technical architecture decisions (that's a Design Doc)
- Implementation tasks (that's a Plan)
- Full competitive analysis (that's a separate artifact; VISION can reference positioning but not duplicate analysis)

The boundary rule: if you're writing "what to build" instead of "why this should exist," the content belongs downstream.

**Lifecycle:**

```
Draft --> Accepted --> Active --> Sunset
```

| Status | Meaning | Transition Trigger |
|--------|---------|-------------------|
| Draft | Under development, open questions remain | Created by workflow |
| Accepted | Vision locked, ready for downstream PRDs/Roadmaps | Human approval, Open Questions resolved |
| Active | Downstream work is in progress | First downstream artifact started |
| Sunset | Project winding down or replaced | Deliberate decision to stop |

Transition rules:
- Draft -> Accepted: Open Questions must be empty/removed. Human must approve.
- Accepted -> Active: A downstream artifact (PRD, Roadmap) has been created referencing this VISION.
- Active -> Sunset: Explicit decision documented. If replaced by a new vision, link to successor.

VISIONs don't have a "Done" state. Active is persistent. A fundamental revision means creating a new VISION (old one goes to Sunset).

**Validation rules:**

During drafting:
- Frontmatter has `status`, `thesis`, `scope`
- Frontmatter `status` matches Status section in body
- `scope` is `org` or `project`
- All 7 required sections present and in order
- If `scope: project` and `upstream` is set, upstream file must exist
- Visibility-gated sections only present in private repos

During approval (Draft -> Accepted):
- Open Questions section empty or removed
- Thesis is a clear hypothesis, not a problem statement
- Success Criteria are measurable at project level

When referenced by downstream artifacts:
- Status must be Accepted or Active
- Draft VISIONs cannot serve as upstream context

**Quality guidance per section:**

Thesis: States a bet, not a fact. "We believe X because Y" not "X is needed." One to two paragraphs.

Audience: Describes people and their situation, not feature requests. Specific enough to evaluate whether a proposed feature serves them.

Value Proposition: Category of value, not features. "Reproducible tool installation without system dependencies" not "a CLI that runs install."

Org Fit: Explains why this project belongs here, not just what it does. Would something be lost if this were a standalone project elsewhere?

Success Criteria: Project-level outcomes. Avoids feature-level acceptance criteria. Measurable where possible but not artificially quantified.

Non-Goals: Each explains reasoning. Bounds identity ("this project will never be Y"), not scope ("this feature excludes Z").

**Naming convention:**

- File: `docs/visions/VISION-<name>.md`
- Org-level: `docs/visions/VISION-<org-name>.md`
- Project-level: `docs/visions/VISION-<project-name>.md`

**Rationale**

The section matrix approach handles both the org/project and public/private dimensions within a single template, following Design Doc precedent for visibility gating. The seven required sections capture the full scope of project justification without bleeding into PRD territory. The lifecycle deviation (no "Done" state) is genuine and necessary -- VISIONs describe project identity, which persists as long as the project exists.

A single template with inline scope guidance avoids the maintenance burden and template drift risk of dual templates, while the visibility matrix adds just enough flexibility for private repos without complicating the public-repo experience.

**Alternatives Considered**

- **Strict PRD Mirror (fixed sections, no visibility gating)**: Simplest approach -- same structure as PRD with no visibility dimension. Rejected because it ignores the constraint that visibility should control content richness. Private repos would lose the ability to capture competitive positioning and resource implications, which are legitimate VISION-level concerns in private contexts.

- **Dual Template (separate org and project templates)**: Two format reference files with ~70% overlap. Rejected because the org/project differences are in section guidance (what to write), not structure (which sections exist). Two templates create sync burden and agent complexity (must detect which template applies) for no structural benefit. No precedent exists for dual templates in the current skill system.

**Consequences**

- The VISION format reference file becomes the authoritative template, following the same structure as `prd-format.md`.
- Phase 5 produce handlers need a visibility check to include or exclude the two gated sections.
- The lifecycle system must accommodate a persistent Active state without a terminal Done state. This is a pattern the status transition tooling hasn't handled before.
- Org-level vs project-level is a guidance concern, not a structural one. The `scope` field signals interpretation, and per-section guidance tells authors how to adapt content.
- Downstream artifacts (PRDs, Roadmaps) can reference VISIONs via `upstream`, creating a clear traceability chain from thesis through requirements to implementation.
<!-- decision:end -->
