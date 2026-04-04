# Lead: What would a VISION doc template contain?

## Findings

### Established Frameworks for Pre-PRD Artifacts

Several well-known frameworks address the "why should this exist" layer:

**Product Vision Board (Roman Pichler):** A single-page canvas with five sections: Vision (aspirational statement), Target Group (who benefits), Needs (problems solved), Product (what it is at a high level), Business Goals (how the org benefits). Designed to be the north star that PRDs elaborate on.

**Amazon PR/FAQ (Working Backwards):** A fictional press release written before building anything. Forces you to articulate the customer benefit, the problem, and the solution in plain language. The FAQ section addresses both customer questions ("why would I use this?") and internal questions ("why should we build this?"). The PR/FAQ explicitly avoids implementation details and requirements -- it captures the thesis.

**Lean Canvas (Ash Maurya):** Nine boxes: Problem, Solution, Key Metrics, Unique Value Proposition, Unfair Advantage, Channels, Customer Segments, Cost Structure, Revenue Streams. More business-model-focused than project-focused, but the Problem/Solution/UVP sections map well to a project vision.

**Project Charter (PMI/traditional):** Authorizes a project's existence. Contains: purpose/justification, objectives, high-level requirements, high-level risks, milestones, budget summary, stakeholders, authority. The charter answers "should this project get resources?" -- it's a gate, not a spec.

**Opportunity Assessment (Marty Cagan):** Four questions: (1) What problem does this solve? (2) For whom? (3) How big is the opportunity? (4) What alternatives exist? Designed to be answered in one page before committing to any requirements work.

### What a VISION Doc Captures That Neither PRD Nor Roadmap Does

The consistent pattern across these frameworks: a VISION doc captures **project justification and identity** -- the layer of reasoning that explains why requirements should be written at all.

Specifically, a VISION doc captures:

1. **Thesis** -- the core belief about why this project should exist. Not a problem statement (that's PRD territory), but the hypothesis about what opportunity or need creates the conditions for this project.

2. **Org fit** -- how this project relates to other projects and the organization's direction. A PRD treats a project as self-contained. A VISION doc places it in context.

3. **Target audience and their world** -- who benefits and what their current reality looks like. A PRD has user stories for specific features; a VISION describes the audience's situation at a higher level.

4. **Success identity** -- what "winning" looks like for the project as a whole, not for individual features. A PRD has acceptance criteria for features. A VISION has success criteria for the project's existence.

5. **Non-goals at the project level** -- what this project deliberately is NOT. Different from a PRD's "out of scope" (which bounds a single feature). A VISION's non-goals bound the project's identity.

6. **Strategic justification** -- why now, why us, what's the cost of not doing this. This doesn't belong in a PRD (which assumes the decision to build is already made) or a Roadmap (which sequences already-decided work).

### Proposed Template

```markdown
---
status: Draft
thesis: |
  1 sentence: the core belief about why this project should exist.
scope: org | project
upstream: <path to org-level VISION if this is project-level>
---

# VISION: <Project or Org Name>

## Status

Draft

## Thesis

1-2 paragraphs. The core belief driving this project. Not a problem statement
(that comes later in PRDs). This is the hypothesis: "We believe [audience] needs
[capability] because [insight about their world]." State it as a bet, not a fact.

## Audience

Who benefits from this project existing? Describe their current situation, not
their feature requests. What is true about their world that makes this project
relevant?

For org-level VISIONs: who does the org serve?
For project-level VISIONs: which segment of the org's audience does this project
target?

## Value Proposition

What does this project offer that its audience can't get today? Not features --
the category of value. "Reproducible tool installation without system
dependencies" is a value proposition. "A CLI that runs `tsuku install`" is a
feature.

## Org Fit

How does this project relate to the organization's other projects and direction?

For org-level VISIONs: what unifies the portfolio? What's the common thread?
For project-level VISIONs: why does this project belong in this org? What does
it share with sibling projects? What would be lost if it were a standalone
project elsewhere?

## Success Criteria

What would make this project's existence justified? Not feature acceptance
criteria (those belong in PRDs). Project-level outcomes:
- Adoption signals (who uses it, how often)
- Ecosystem signals (integrations, extensions, contributions)
- Quality signals (reliability, performance thresholds)

## Non-Goals

What is this project deliberately NOT? These bound the project's identity, not
a feature's scope. Each non-goal should explain the reasoning.

## Open Questions

Present only in Draft status. Unresolved questions about the project's direction.
Must be empty or removed before transitioning to Accepted.

## Downstream Artifacts

Added when downstream work starts. Links to PRDs, roadmaps, and other artifacts
that elaborate on this vision.
```

### Boundary Analysis: VISION vs PRD vs Roadmap

| Dimension | VISION | PRD | Roadmap |
|-----------|--------|-----|---------|
| **Core question** | Why should this exist? | What should we build? | In what order? |
| **Unit of scope** | Entire project or org | Single feature or capability | Multiple features across time |
| **Audience description** | Who they are, what's true about their world | User stories for specific features | Assumed known (references PRDs) |
| **Success definition** | Project-level outcomes | Feature acceptance criteria | Milestone completion |
| **Time horizon** | Indefinite (identity doesn't expire) | Until feature ships | Planning horizon (quarters, releases) |
| **Justification** | Why this project should get resources | Why this feature matters (within project) | Why this sequence (dependencies, risk) |
| **Non-goals** | What the project is NOT | What the feature excludes | What this planning horizon excludes |
| **Upstream dependency** | Org strategy (informal or org-level VISION) | VISION or nothing | PRDs or design docs |
| **Downstream artifacts** | PRDs, Roadmaps | Design docs, Plans | Issues, milestones |
| **Mutability** | Rarely changes; rewrite signals a pivot | Changes via new PRD | Updated each planning cycle |
| **Who decides** | Project lead / org leadership | Product + engineering | Product + engineering |

### Key Boundary Rules

**VISION does not contain:**
- User stories (that's PRD)
- Acceptance criteria (that's PRD)
- Feature lists (that's PRD or Roadmap)
- Sequencing or timelines (that's Roadmap)
- Technical architecture (that's Design Doc)
- Implementation tasks (that's Plan)

**VISION does contain that PRD does not:**
- Why the project should exist at all
- How the project fits the org
- Project-level identity and non-goals
- Strategic justification

**VISION does contain that Roadmap does not:**
- Thesis and audience definition
- Org fit rationale
- Value proposition (what category of value, not what features)

### Org-Level vs Project-Level VISIONs

The template works at both levels with scope-dependent interpretation:

| Section | Org-Level | Project-Level |
|---------|-----------|---------------|
| Thesis | Why does this org exist? | Why does this project exist within the org? |
| Audience | Who does the org serve? | Which audience segment does this project target? |
| Value Proposition | What category of value does the org create? | What specific value does this project add? |
| Org Fit | What unifies the portfolio? | How does this project relate to siblings? |
| Success Criteria | Org health metrics | Project adoption and quality metrics |
| Non-Goals | What the org won't become | What this project won't do |
| Upstream | None (root of the hierarchy) | Org-level VISION |

The `scope` frontmatter field (org vs project) signals which interpretation applies. Project-level VISIONs should reference their org-level VISION via `upstream`.

### Lifecycle

```
Draft --> Accepted --> Active --> Sunset
```

| Status | Meaning | Transition Trigger |
|--------|---------|-------------------|
| Draft | Under development, open questions remain | Created by workflow |
| Accepted | Vision locked, ready for downstream PRDs/Roadmaps | Human approval |
| Active | Downstream work is in progress | First downstream artifact started |
| Sunset | Project is winding down or has been replaced | Deliberate decision to stop |

Unlike PRDs (which end at "Done" when a feature ships), VISIONs don't "complete" -- they stay Active as long as the project exists. A VISION that needs fundamental revision indicates a pivot, which should be a new VISION doc (old one transitions to Sunset with a link to the replacement).

### Naming Convention

Following existing patterns:
- File: `docs/visions/VISION-<name>.md`
- Org-level: `docs/visions/VISION-tsukumogami.md`
- Project-level: `docs/visions/VISION-koto.md`, `docs/visions/VISION-shirabe.md`

## Implications

1. **VISION is a genuine new artifact type, not a section of an existing type.** The boundary analysis shows it captures information that no current artifact addresses. Trying to shoehorn project thesis into a PRD's problem statement or a Roadmap's introduction would misrepresent the content's purpose and lifecycle.

2. **The crystallize framework needs a VISION entry.** Key signals: exploration surfaced org-fit questions, audience definition is unclear, the core question is "should this project exist?" rather than "what features should it have?" Anti-signals: requirements are already clear, the project's identity is established and uncontested.

3. **VISION sits at the top of the artifact hierarchy.** The dependency chain is: VISION -> PRD -> Design Doc -> Plan -> Issues. Roadmaps can branch from VISION directly (sequencing features before requirements are written for each) or from a collection of PRDs.

4. **Org-level and project-level work with the same template.** The `scope` field and section-level guidance handle the differences without requiring two separate artifact types.

5. **The strategic/tactical scope dimension matters here.** VISION docs are inherently strategic. A "tactical VISION" is likely a contradiction -- if you're at the tactical level, you probably need a PRD, not a VISION. This is a useful crystallize anti-signal.

## Surprises

1. **VISIONs don't have a "Done" state.** Unlike every other artifact in the current system, a VISION's lifecycle doesn't end with completion. It stays Active until the project is deliberately wound down. This is a different lifecycle pattern that the status management tooling would need to accommodate.

2. **The PR/FAQ format is closer to a VISION than to a PRD.** Amazon's "Working Backwards" process is often described as a requirements technique, but the press release portion is pure thesis and value proposition -- it's a VISION doc with a narrative wrapper. The FAQ portion starts to bleed into PRD territory. This suggests the boundary between VISION and PRD is real but there's a well-trodden path through it.

3. **Non-goals at the project level are qualitatively different from feature-level out-of-scope.** A PRD says "this feature won't handle X." A VISION says "this project will never be Y." The difference is identity vs scope. Conflating them leads to projects that drift from their original purpose because the identity boundary was never explicit.

## Open Questions

1. **Should VISION be a first-class crystallize output, or should it stay deferred?** Adding it to the supported types means /explore can produce VISIONs directly. But the current deferred-type pattern (inform user, suggest alternative) might be appropriate for an initial release since VISION creation is infrequent.

2. **Does the /explore workflow need a "project inception" mode, or is regular /explore sufficient?** The scope document mentions this possibility. If someone runs `/explore "should we build a new tool for X?"`, does the existing discover-converge loop naturally land on VISION as an output, or does it need special handling?

3. **Where should VISION docs live in multi-repo orgs?** The tsukumogami workspace has multiple repos. An org-level VISION doesn't naturally belong in any single repo. Project-level VISIONs belong in their project's repo. Does the workspace root need a `docs/visions/` directory?

4. **How does VISION interact with the private/public visibility dimension?** Strategic justification may include competitive reasoning that belongs only in private contexts. Should VISION docs have visibility-aware sections, or should the private/public split be handled by having separate private strategy docs that feed into the public VISION?

5. **Is there a meaningful intermediate artifact between VISION and PRD?** Lead 3 in the scope document asks this directly. The frameworks surveyed suggest "opportunity assessment" as a lightweight gate, but it might fold into the VISION's thesis section rather than warranting its own artifact type.

## Summary

A VISION doc captures project justification and identity -- thesis, audience, org fit, and project-level success criteria -- filling a genuine gap above PRDs (which define features) and Roadmaps (which sequence them). The template works at both org and project levels via a scope field, but introduces a novel lifecycle pattern (Active rather than Done) that differs from all existing artifact types. The biggest open question is whether VISION should be a first-class crystallize output immediately or start as a deferred type, given that project inception is infrequent compared to feature development.
