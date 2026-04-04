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

## Scope Expansion (User Redirect)

User redirected: the exploration narrowed prematurely to "add a VISION type" when the real question is the complete strategic-to-tactical pipeline. Round 2 investigated the full artifact pipeline, not just the VISION piece. The Round 1 crystallize decision (PRD for VISION) was rescinded.

## Round 2

### Key Insights

1. Pipeline has 8 stages, 7 well-covered (Lead: current-pipeline). Stage 1 (Inception/Strategic) has 3 gaps: no VISION creation, no Roadmap creation workflow, no complexity-to-feature handoff.

2. Three-diamond model captures pipeline structure (Lead: flexible-pipelines). Explore/Crystallize, Specify/Scope, Implement/Ship. Five named transitions: Advance, Recycle, Skip, Hold, Kill.

3. Five complexity levels needed (Lead: complexity-routing). Trivial and Strategic extend the existing Simple/Medium/Complex table.

4. Fourteen artifact node types with 30+ transitions and 6 gaps (Lead: transition-graph). VISION has no entry point; Spike/Competitive Analysis lack downstream handoffs; Roadmap features lack /explore re-entry.

5. Traceability breaks at Roadmap and Design Doc (Lead: traceability). Need `upstream` fields on both. Cross-repo convention: `owner/repo:path` with `private:` prefix.

6. Pipeline is a funnel, not a tunnel (Lead: flexible-pipelines). Kill/abandon is first-class at every stage.

7. Existing skill patterns are consistent and extensible (PRD agents). Three-layer pattern, Phase 5 handler templates, well-exercised addition pattern.

### Tensions

- Investment-based routing vs complexity labels: resolved as naming change, not restructuring
- Three diamonds vs current commands: resolved as mental model for docs, not command restructuring
- How many features to tackle: resolved as Roadmap (sequence by value and dependency)

### Gaps

- Roadmap creation workflow (format reference only, no guided creation)
- Automated downstream artifact linking (specified but never implemented)
- Cross-repo reference convention (doesn't exist)
- Pipeline mental model documentation (no home)

### Decisions

- Pipeline model: three diverge-converge diamonds with 5 named transitions
- 5 complexity levels: Trivial, Simple, Medium, Complex, Strategic
- Traceability: add upstream to Roadmap and Design Doc; cross-repo convention
- Artifact type: Roadmap (multiple independent features to sequence)

### User Focus

Auto-mode: user redirected scope from VISION-only to complete pipeline. All leads returned with consistent findings. The pipeline is more complete than initially assumed — most gaps are at the strategic entry point and in traceability/stitching.

## Accumulated Understanding

The strategic-to-tactical pipeline is mostly complete. Seven of eight stages have full workflow skills. The primary gap is Stage 1 (Inception/Strategic), which needs three things: the VISION artifact type, a Roadmap creation workflow, and formalized complexity-to-feature handoff from roadmap planning issues.

The pipeline's structure follows a three-diamond model: Explore/Crystallize (understand the problem), Specify/Scope (define and decompose), Implement/Ship (build and release). Five named transition decisions at each boundary: Advance, Recycle, Skip, Hold, Kill. This mental model explains how existing commands relate without requiring restructuring.

Five complexity levels route work through the pipeline: Trivial (just code, no artifacts), Simple (/work-on directly), Medium (/design → /plan), Complex (/explore → full pipeline), Strategic (VISION → Roadmap → per-feature pipelines at lower levels).

The traceability chain from VISION to PR requires two schema fixes (upstream fields on Roadmap and Design Doc), a cross-repo reference convention, and automated downstream artifact linking. These are small additions that close the chain completely.

The work ahead is a portfolio of related improvements, not a single feature. It sequences naturally as: (1) VISION artifact type + crystallize integration, (2) Roadmap creation workflow, (3) Traceability improvements, (4) Complexity routing expansion, (5) Pipeline documentation. Each feature is independently valuable.

Round 1 findings on VISION (template, lifecycle, crystallize signals, scope gating) remain valid and feed into Feature 1 of the roadmap. The PRD research agents' findings on skill patterns and lifecycle details also feed into Feature 1.

## Decision: Crystallize
