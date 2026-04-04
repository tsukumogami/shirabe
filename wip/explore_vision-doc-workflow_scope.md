# Explore Scope: vision-doc-workflow

## Visibility

Public

## Topic Type: Directional

## Core Question

What artifact types and workflow extensions are needed to support the journey from "I have a project idea" to "I have requirements I can design against" — the layer above PRDs that captures project thesis, org fit, and strategic justification? This may be a single VISION doc type or a small pipeline of artifacts, and it needs to integrate with the existing crystallize framework and /explore workflow.

## Context

The current artifact-centric workflow (8 types: PRD, Design Doc, Plan, Roadmap, Spike Report, Decision Record, Competitive Analysis, Prototype) assumes you already know what project you're building. There's no artifact for "here's WHY this project should exist, WHAT it offers, and HOW it fits the org." The private tools plugin completed Features 1-7 of the artifact workflow redesign, but none address the pre-PRD layer. The vision repo's org/PROJECTS.md is empty — project inception has no structured process. The user is considering a new project for the tsukumogami org and needs this thesis validated and captured before writing requirements.

## In Scope

- New artifact types that sit above PRD in the pipeline
- Workflow changes to /explore to produce pre-PRD artifacts
- Integration with the existing crystallize framework
- What to adopt from the private tools plugin's completed artifact types
- Lifecycle and naming conventions for new types
- How strategic/tactical scope affects these artifacts

## Out of Scope

- Implementation of the artifacts/skills themselves (this exploration produces the design)
- Changes to /prd, /design, or /plan commands
- Migration of existing documents to new formats
- Go code changes to workflow-tool

## Research Leads

1. **What do established product/strategy frameworks say about the artifacts between "idea" and "requirements"?**
   Lean Canvas, business model canvas, Amazon 6-pager, opportunity assessments, project charters. What's the industry consensus on what belongs before a PRD?

2. **What would a VISION doc template contain, and how does it differ from a PRD and a Roadmap?**
   Need sharp boundaries. A PRD has user stories and acceptance criteria. A Roadmap sequences features. What does a VISION capture that neither does?

3. **Are there intermediate artifacts needed between VISION and PRD?**
   Opportunity assessments, project charters, strategy briefs. Is there a meaningful gap, or does VISION -> PRD cover it?

4. **How should the crystallize framework be extended to score/route to VISION (and any new types)?**
   Need signal/anti-signal tables. What distinguishes "this exploration should produce a VISION" from "this should produce a PRD"?

5. **What patterns from the private tools plugin should be adopted into shirabe?**
   The private plugin has 5 deferred types that shirabe doesn't support yet. Should those ship alongside VISION, or independently?

6. **How does the strategic/tactical scope dimension interact with VISION docs?**
   What does a VISION doc look like in tactical scope? Does it even make sense there?

7. **What lifecycle and workflow changes are needed beyond just adding a new artifact type?**
   Project registry, /explore "project inception" mode, new commands. What structural changes support this?

8. **Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)
   You are a demand-validation researcher. Investigate whether evidence supports pursuing this topic. Report what you found. Cite only what you found in durable artifacts. The verdict belongs to convergence and the user.

   ## Visibility

   Public

   Respect this visibility level. Do not include private-repo content in output that will appear in public-repo artifacts.

   ## Six Demand-Validation Questions

   Investigate each question. For each, report what you found and assign a confidence level.

   Confidence vocabulary:
   - **High**: multiple independent sources confirm
   - **Medium**: one source type confirms without corroboration
   - **Low**: evidence exists but is weak
   - **Absent**: searched relevant sources; found nothing

   Questions:
   1. Is demand real? Look for distinct issue reporters, explicit requests, maintainer acknowledgment.
   2. What do people do today instead? Look for workarounds in issues, docs, or code comments.
   3. Who specifically asked? Cite issue numbers, comment authors, PR references.
   4. What behavior change counts as success? Look for acceptance criteria, stated outcomes, measurable goals.
   5. Is it already built? Search the codebase and existing docs for prior implementations.
   6. Is it already planned? Check open issues, linked design docs, roadmap items.

   ## Calibration

   Produce a Calibration section that explicitly distinguishes:
   - **Demand not validated**: majority of questions returned absent or low confidence
   - **Demand validated as absent**: positive evidence that demand doesn't exist or was rejected
