# Lead: Is there evidence of real demand for VISION docs?

## Question 1: Is demand real?

**Confidence: Low**

No distinct issue reporters or explicit requests for a VISION artifact type exist across any of the four org repos (tsuku, koto, niwa, shirabe). GitHub issue searches for "vision" across all repos returned zero relevant results. The only demand signal is the current `/explore` session itself (`wip/explore_vision-doc-workflow_scope.md`), which was initiated by the sole maintainer (dangazineu). The scope document's Context section states: "The user is considering a new project for the tsukumogami org and needs this thesis validated and captured before writing requirements." This is a single user's prospective need, not a pattern observed across multiple users or situations.

Shirabe issue #9 (`feat(explore): add adversarial lead for demand validation on directional topics`) was filed by dangazineu with zero comments. It describes the adversarial lead mechanism being used here but does not itself request a VISION artifact type.

The roadmap at `private/tools/docs/roadmaps/ROADMAP-artifact-workflow-redesign.md` completed Features 1-7 without ever identifying a VISION layer as a gap. All 7 features shipped (PRD, Plan, Design, Explore, Implement, Remaining Artifact Types, Polymorphic Plan) and the roadmap's "Vision" section lists exactly 8 artifact types -- none of which is a VISION doc. The roadmap's Out of Scope section lists "How the strategic/tactical context model applies to new artifact types" but does not mention a pre-PRD layer.

## Question 2: What do people do today instead?

**Confidence: Medium**

Two workarounds are observable in durable artifacts:

1. **The vision repo itself is the workaround.** `private/vision/` exists as a private strategic planning hub with `projects/tsuku/` containing design docs, and `org/PROJECTS.md` (empty except for "tsuku" listed as Active). The repo was explicitly designed as the place for "strategic planning, internal notes, pre-announcement features" per its CLAUDE.md. The `DESIGN-tsukumogami-vision.md` document (status: Planned) addresses the repo's role but does not define a VISION artifact type -- it restructured the repo itself. The empty PROJECTS.md confirms no structured project inception process exists.

2. **Roadmaps serve as partial substitutes.** The `ROADMAP-artifact-workflow-redesign.md` has a "Vision" section (line 33) that contains the conceptual model for the entire redesign. This section functions as a project thesis and strategic justification, but it's embedded in a roadmap rather than standing on its own.

No issues, code comments, or docs reference frustration with the absence of a pre-PRD artifact.

## Question 3: Who specifically asked?

**Confidence: Low**

The only identifiable requester is dangazineu, the sole maintainer and org owner. The request is implicit in the current `/explore` session scope document, not an explicit feature request filed as an issue. No other contributors, users, or community members have requested this.

Artifacts citing the need:
- `wip/explore_vision-doc-workflow_scope.md` (line 15): "There's no artifact for 'here's WHY this project should exist, WHAT it offers, and HOW it fits the org.'"

No GitHub issues request a VISION artifact type. No PR descriptions or comments reference it. No closed-and-rejected issues indicate prior consideration.

## Question 4: What behavior change counts as success?

**Confidence: Absent**

No acceptance criteria, stated outcomes, or measurable goals exist for the VISION doc concept beyond what the current exploration's scope document implies. The scope document (lines 17-24) lists what's in scope (new artifact types, workflow changes, crystallize integration) but not success metrics.

The closest analog is the existing artifact-types PRD (`private/tools/docs/prds/PRD-artifact-types.md`), which defined concrete acceptance criteria for the 4 new types added in Feature 6. No equivalent specification exists for a VISION type.

## Question 5: Is it already built?

**Confidence: Medium (that it is NOT built)**

Searched the following locations:

- **Crystallize framework** (`skills/explore/references/quality/crystallize-framework.md`): Lists 5 supported types (PRD, Design Doc, Plan, No Artifact, Rejection Record) and 5 deferred types (Spike Report, Decision Record, Competitive Analysis, Prototype, Roadmap). VISION is not listed in either category. Note: Spike Report, Decision Record, Competitive Analysis, and Roadmap have since graduated from deferred to supported (per `phase-5-produce-deferred.md` and the roadmap's Feature 6 status).

- **Phase 5 produce handlers** (`skills/explore/references/phases/phase-5-produce-deferred.md`): Handles Roadmap, Spike Report, Competitive Analysis, and notes Prototype as the only remaining unsupported type. No VISION handler exists.

- **Explore SKILL.md** (`skills/explore/SKILL.md`): Artifact Type Routing Guide has no VISION entry. Quick Decision Table covers "What should we build and why?" -> PRD, not VISION.

- **Private tools plugin** (`private/tools/`): PRD-artifact-types.md covers the 4 deferred types that were added. No mention of VISION. The roadmap's complete feature list (Features 1-7, all Done) does not include a VISION artifact.

- **Vision repo**: Contains design docs and roadmaps for tsuku but no VISION-type artifact template or format definition.

Nothing resembling a VISION artifact type exists in any codebase searched.

## Question 6: Is it already planned?

**Confidence: Medium (that it is NOT planned)**

- **ROADMAP-artifact-workflow-redesign.md**: All 7 features are marked Done. No Feature 8 or "Future" section mentions VISION docs. Out of Scope does not mention it.
- **Open issues in shirabe**: 15 open issues, none reference VISION docs or pre-PRD artifacts.
- **Open issues in tsuku**: Sampled 60+ issues, none reference VISION docs.
- **Open issues in koto**: Sampled 60+ issues, none reference VISION docs.
- **Open issues in niwa**: All issues are closed, none reference VISION docs.
- **Private tools docs**: No PRD, design doc, or roadmap mentions VISION as a planned artifact type.
- **Vision repo**: `org/PROJECTS.md` is effectively empty. No planning artifacts reference VISION docs.

The concept does not appear in any planning artifact, open issue, or roadmap across the entire workspace.

## Calibration

**Demand not validated.**

The majority of questions returned Absent or Low confidence. No positive rejection evidence exists either -- the concept was never proposed, evaluated, and rejected. It simply hasn't been considered before this exploration session.

Key distinction: the absence of demand signals does not prove the idea is bad. It means:
- No one besides the maintainer has encountered the gap
- The artifact workflow redesign (7 features, all shipped) never identified this layer as missing
- The vision repo exists as an informal workaround but no one has expressed dissatisfaction with it
- The org has exactly one active project (tsuku), so the "org fit" and "portfolio justification" dimensions that a VISION doc would serve have limited applicability until more projects exist

This is a supply-side proposal from the maintainer, not a demand-side request from users encountering a gap.

## Summary

No external demand evidence exists for a VISION artifact type -- the request originates entirely from the sole maintainer's prospective need for a new project, with zero community requests, zero related issues, and zero prior consideration in the completed 7-feature artifact workflow redesign. The main implication is that this is a supply-side proposal whose value depends on whether the org actually launches additional projects (currently only tsuku is active, making "org fit" and "portfolio justification" dimensions largely theoretical). The biggest open question is whether the maintainer's immediate need (capturing a project thesis for a second project) is better served by a lightweight extension to the existing Roadmap artifact rather than a new artifact type.
