# Exploration Findings: vision-doc-workflow

## Core Question

What artifact types and workflow extensions are needed to support the journey from "I have a project idea" to "I have requirements I can design against" — the layer above PRDs that captures project thesis, org fit, and strategic justification?

## Round 1

### Key Insights

1. Industry consensus confirms a distinct pre-requirements layer (Lead: pre-prd-frameworks). Cagan's Opportunity Assessment, Amazon PR/FAQ, Product Thesis, and Lean Canvas all recognize this layer. Universal core: problem justification, target audience, competitive landscape, differentiator, success criteria — without specifying features.

2. VISION is a genuine new artifact type with clear boundaries (Lead: vision-template). Answers "should this exist and what's the thesis?" — distinct from PRD ("what should we build?") and Roadmap ("in what order?"). Captures thesis, audience, value proposition, org fit, success criteria, non-goals. Novel lifecycle: Draft -> Accepted -> Active -> Sunset (stays Active rather than completing).

3. No intermediate artifacts needed between VISION and PRD (Leads: intermediate-artifacts, pre-prd-frameworks). A well-structured VISION absorbs opportunity assessments, strategy briefs, hypothesis docs, and project charters as sections rather than separate documents.

4. Crystallize framework handles VISION without structural changes (Lead: crystallize-extension). Needs signal/anti-signal table, three tiebreaker rules (vs PRD, Roadmap, No Artifact), one disambiguation rule. Sharpest discriminator: project existence.

5. Shirabe already produces 3 of 5 deferred types (Lead: private-plugin-patterns). What's missing are reference standards (lifecycle, validation, labels), not production capability. These should ship independently.

6. VISION is inherently strategic-scope (Lead: scope-interaction). Full value in Strategic+Private and Strategic+Public. Degenerates in tactical scope. Tactical should be a hard anti-signal.

7. Org infrastructure exists but lacks connecting workflow (Lead: lifecycle-workflow). Vision repo, PROJECTS.md, new-repo-playbook all exist. PROJECTS.md should become a lifecycle-tracked registry.

8. Demand is supply-side only (Lead: adversarial-demand). Zero community requests. Workarounds (vision repo, roadmap "Vision" section) confirm the gap exists despite no explicit demand.

### Tensions

- **VISION vs Project Brief naming**: VISION wins — it captures lasting project identity, not a one-time evaluation
- **Crystallize output vs above /explore**: resolved in favor of crystallize output — the user's scenario IS an exploration that should produce a VISION
- **VISION vs strategic Roadmap**: resolved as distinct — different core questions, different lifecycles

### Gaps

- Template details (frontmatter schema, exact sections) need specification during design
- PROJECTS.md lifecycle mechanics (transition triggers, /explore integration)
- Phase 5 produce handler design

### Decisions

- VISION is the only new pre-PRD artifact type; no intermediates
- Name: VISION, not Project Brief
- Delivery mechanism: supported crystallize type, not standalone command
- Scope gating: strategic only; tactical is a hard anti-signal
- Reference standards for existing deferred types ship independently
- Proceed despite supply-side demand
- PROJECTS.md lifecycle tracking is in-scope

### User Focus

Auto-mode: user requested agents expand their thinking on adding a VISION doc to /explore. All 8 leads returned with consistent findings and the key tensions resolved cleanly.

## Accumulated Understanding

A single new artifact type — VISION — fills the gap between "project idea" and "requirements." It captures project thesis, audience, value proposition, org fit, success criteria, and non-goals. No intermediate artifacts are needed at this org's scale.

VISION integrates into the existing /explore workflow as a supported crystallize type, gated to strategic scope. The crystallize framework's type-agnostic scoring mechanism handles it with a new signal/anti-signal table and tiebreaker rules. The sharpest discriminator between VISION and PRD is project existence: if the project doesn't exist yet and the exploration validated whether it should, that's a VISION.

The pipeline becomes: VISION -> Roadmap (optional, for multi-feature projects) -> PRD -> Design Doc -> Plan -> Issues. VISION's lifecycle (Draft -> Accepted -> Active -> Sunset) differs from other artifacts because projects don't "complete" — they stay Active.

Supporting changes include PROJECTS.md as a lifecycle-tracked project registry and a new Phase 5 produce handler. Reference standards for existing deferred types (roadmap, spike, ADR) are independently valuable but not prerequisites.

Demand is supply-side: the maintainer needs this for a second project. Workarounds (vision repo, roadmap "Vision" sections) confirm the gap. The artifact workflow redesign (7 features, all shipped) never identified this layer because the org had only one project.

## Decision: Crystallize
