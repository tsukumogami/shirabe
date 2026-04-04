# Explore Scope: vision-doc-workflow

## Visibility

Public

## Topic Type: Directional

## Core Question

What does the complete strategic-to-tactical pipeline look like — from "I have a project idea" all the way through to "I have implementation tasks"? What artifact types, transitions, commands, and workflow steps does each stage need? The VISION doc is one piece; the full pipeline design is the deliverable.

## Context

The current artifact-centric workflow (8 types: PRD, Design Doc, Plan, Roadmap, Spike Report, Decision Record, Competitive Analysis, Prototype) assumes you already know what project you're building. There's no artifact for "here's WHY this project should exist, WHAT it offers, and HOW it fits the org." The private tools plugin completed Features 1-7 of the artifact workflow redesign, but none address the pre-PRD layer. The vision repo's org/PROJECTS.md is empty — project inception has no structured process. The user is considering a new project for the tsukumogami org and needs this thesis validated and captured before writing requirements.

## In Scope (expanded in Round 2)

- The complete artifact pipeline from project idea to implementation tasks
- All artifact types needed at each stage (including VISION from Round 1)
- Transitions between stages: what triggers movement, what's automatic, what needs human input
- Flexibility: loops (explore → discover more), skips (simple features → /work-on), branches (VISION → multiple PRDs), and re-entry points
- How strategic/tactical scope maps to pipeline stages
- Commands needed at each stage (existing and new)
- How the pipeline handles different complexity levels
- Integration with the existing crystallize framework

## Out of Scope

- Implementation of artifacts/skills themselves (this exploration produces the design)
- Go code changes to workflow-tool
- Migration of existing documents to new formats

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

## Round 2 Research Leads (Full Pipeline)

9. **What does the current end-to-end pipeline look like today, with all its gaps and workarounds?**
   Map every stage from idea to merged PR. For each stage: what command runs, what artifact enters, what artifact exits, what decisions are made. Identify where the pipeline breaks or forces workarounds. Include the private plugin's completed features to show the fullest picture.

10. **How do established product development frameworks model flexible, non-linear pipelines?**
   Shape Up (bets, not backlogs), Dual Track Agile (discovery + delivery), Amazon Working Backwards, Basecamp's Hill Charts. How do they handle loops, skips, and branches? What can we learn about modeling a pipeline that isn't strictly sequential?

11. **What does the complete artifact type hierarchy look like, and what are all the valid transitions?**
   Build the full graph: VISION, PRD, Design Doc, Plan, Roadmap, Spike, Decision Record, Competitive Analysis, Rejection Record, No Artifact. For each pair, is there a valid transition? What triggers it? Where do loops occur? Where are skip paths? Model this as a directed graph with conditions on edges.

12. **How should the pipeline handle different complexity levels (simple, medium, complex, strategic)?**
   A typo fix shouldn't go through VISION. A new project shouldn't skip to /work-on. What determines which stages are needed? How does the routing table from /explore's skill already handle this, and how should it expand? Consider the existing complexity-based routing table.

13. **What commands/skills are needed at each pipeline stage, and which already exist?**
   Map commands to pipeline stages. Identify: what's missing (VISION production), what needs modification (/explore crystallize expansion), what's already complete (/prd, /design, /plan, /work-on). Consider whether VISION needs its own command or if /explore covers it.

14. **How do artifacts reference each other across the pipeline, and how should traceability work?**
   Existing patterns: PRD has `upstream` field, Design Doc references PRD, Plan references design/PRD. How should VISION connect to downstream artifacts? How do you trace from an implementation issue back to the original VISION? What about cross-repo references (vision repo → public project repos)?
