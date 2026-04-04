# Lead: How does the strategic/tactical scope dimension interact with VISION docs?

## Findings

### The Current Scope-Visibility Matrix

The planning-context skill defines two orthogonal dimensions with all 8 combinations valid (Action x Scope x Visibility). Key constraints that vary by scope:

- **Market Context**: Only Strategic scope (optional in Private, forbidden in Public)
- **Competitor analysis**: Only Strategic scope (neutral framing in Public)
- **Required Tactical Designs section**: Only Strategic scope
- **Upstream Design Reference section**: Only Tactical scope

The Document Section Matrix shows scope controls which sections appear in design docs. Strategic adds "Market Context" and "Required Tactical Designs." Tactical adds "Upstream Design Reference." Both share the structural backbone (Context, Decision Drivers, Options, Architecture, etc.).

### Where VISION Would Sit in the Current Framework

VISION docs address the layer above PRDs: "why should this project exist, what does it offer, how does it fit the organization." The crystallize framework currently routes to 5 supported types (PRD, Design Doc, Plan, No Artifact, Rejection Record) and 5 deferred types (Spike Report, Decision Record, Competitive Analysis, Prototype, Roadmap). VISION is not in either list.

A VISION doc's core question is: "Should we pursue this project at all, and what's the thesis?" This sits firmly in the strategic scope's domain of "what to build and why" with portfolio-level thinking. The tactical scope focuses on "how to build it" with implementation-level work items.

### Analysis of All 4 Combinations

#### Strategic + Private: Natural Home

This is the canonical combination for VISION docs. The vision repository itself defaults to Strategic scope + Private visibility. A VISION doc here would contain:

- **Project thesis**: Why this project should exist
- **Market context**: Competitive landscape, market opportunity (permitted in Strategic+Private)
- **Organizational fit**: How it fits portfolio strategy (private content)
- **Success criteria**: What would make this project worth pursuing
- **Go/no-go framework**: Decision criteria for proceeding to PRD
- **Competitive positioning**: Direct competitor references (private only)
- **Resource implications**: What pursuing this means for other projects

This combination allows the fullest, most candid version of the document.

#### Strategic + Public: Valid but Constrained

This combination makes sense for open-source projects that want to publicly articulate project vision and invite community input. A VISION doc here would contain:

- **Project thesis**: Why this project should exist (framed for external audience)
- **Problem space**: What gap this addresses in the ecosystem (neutral framing, no competitor names in negative context)
- **Design principles**: Core values driving the project
- **Success criteria**: User-facing goals
- **Scope boundaries**: What the project deliberately won't do
- **Community alignment**: How this fits the broader ecosystem

Missing compared to Strategic+Private: no competitive positioning, no internal resource analysis, no business strategy. The document serves as a public manifesto rather than an internal business case.

#### Tactical + Private: Misaligned but Not Useless

Tactical scope focuses on "how to build it" with implementation-level items. A VISION doc's purpose is fundamentally strategic -- it answers "should we build this at all?" rather than "how do we build it?"

However, there's a narrow use case: when someone overrides to `--tactical` in a strategic-default repo, they're saying "I need implementation-level thinking here." A VISION doc in tactical scope would degenerate into something closer to a project charter or kickoff brief:

- **Project scope statement**: What we're building (assumed already decided)
- **Key constraints**: Technical limits, timeline, dependencies
- **Initial architecture direction**: High-level approach
- **First milestones**: What to deliver first
- **Risk register**: Technical risks to the implementation

This is effectively a "project brief" -- not really a VISION doc. It skips the "should we?" question entirely and jumps to "how do we start?" This overlaps heavily with what a PRD or a combination of PRD + Design Doc already covers.

#### Tactical + Public: Does Not Fit

This combination produces the weakest match. Tactical scope strips the strategic justification. Public visibility strips the competitive and business context. What remains is a public project brief -- which is just a README or a PRD introduction.

A document here would contain:
- What the project does (already in README)
- How to get started contributing (already in CONTRIBUTING.md)
- Near-term goals (already in issues/milestones)

There's no unique value a VISION doc adds in this quadrant that isn't better served by existing artifact types.

### How Existing Scope Constraints Would Apply

If VISION becomes a crystallize-routable type, it needs signal/anti-signal tables and scope constraints like existing types. Based on the analysis:

| Constraint | Behavior for VISION |
|-----------|-------------------|
| Market Context section | Optional in Strategic+Private, No in Public, No in Tactical |
| Competitive Positioning section | Only Strategic+Private |
| Required Tactical Designs | Only Strategic (analogous to design docs) |
| Upstream Design Reference | Not applicable (VISION has no upstream) |
| Go/No-Go Framework | Only Strategic (tactical assumes go) |
| Resource Implications | Only Private |

### Scope Gating Options

Three approaches:

1. **Gate to Strategic only**: VISION docs can only be produced in Strategic scope. If someone tries to create one in Tactical scope, redirect to PRD. This is the cleanest approach and avoids producing a document that's really something else wearing a VISION label.

2. **Available everywhere with adapted content**: Let the template adapt per scope, similar to how design docs include/exclude sections based on scope. In Tactical mode, it becomes a "project brief." This risks blurring the line between artifact types.

3. **Available everywhere but warn on tactical**: Allow it but show a diagnostic message: "VISION docs are designed for strategic scope. In tactical scope, consider a PRD instead. Continue anyway?" This preserves flexibility while guiding users toward the right tool.

## Implications

1. **VISION is inherently a strategic artifact.** Its core purpose -- justifying a project's existence and articulating thesis -- is the definition of strategic scope. Making it work in tactical scope requires stripping away the features that distinguish it from a PRD.

2. **The scope dimension reveals a natural artifact hierarchy.** Strategic scope produces VISION and Roadmap (portfolio-level). Tactical scope produces PRD, Design Doc, and Plan (implementation-level). Spike Reports and Decision Records bridge both. This hierarchy maps cleanly: VISION -> PRD -> Design Doc -> Plan.

3. **Visibility affects content richness, not validity.** Both Strategic+Private and Strategic+Public produce meaningful VISION docs. The difference is content governance (can you name competitors, discuss business strategy) rather than whether the artifact type makes sense.

4. **The crystallize framework needs VISION signals that are distinct from PRD signals.** The key discriminator: a VISION doc's core question is "should we build this project?" while a PRD's core question is "what should this project contain?" If the exploration assumes the project will exist, it's a PRD. If the exploration is evaluating whether the project should exist, it's a VISION.

5. **Scope override (`--tactical` in a strategic repo) should suppress VISION as a crystallize option.** If the user explicitly asked for tactical thinking, they don't want a strategic artifact. The crystallize framework already handles scope-dependent behavior for market context and competitor analysis -- VISION gating would follow the same pattern.

## Surprises

1. **Tactical+Private has a plausible but degenerate use case.** The "project brief" pattern isn't worthless, but it's so close to existing artifact types that adding it creates more confusion than value. The interesting finding is that scope override to tactical doesn't just constrain the document -- it fundamentally changes what the document IS, to the point where it should be a different artifact type.

2. **The scope dimension acts as a hierarchy selector, not just a content filter.** For most existing artifact types (Design Doc, PRD), scope changes which sections appear. For VISION, scope changes whether the artifact type is appropriate at all. This is a qualitatively different relationship between scope and artifact type than exists for current types.

3. **Public VISION docs have real value for open-source projects.** The initial assumption might be that VISION is a "private repo thing," but public project manifestos (Rust's vision docs, Kubernetes enhancement proposals) show there's genuine precedent and utility for public strategic articulation.

## Open Questions

1. **Should VISION be a crystallize-routable type or a standalone command?** Current artifact types route through /explore's crystallize framework. But VISION sits above the explore workflow in the artifact hierarchy -- you might want a VISION before you even know what to explore. Should it be `/vision` as a peer to `/explore`, or a type that `/explore` can produce?

2. **What's the lifecycle for a VISION doc?** Design docs go Draft -> Proposed -> Accepted -> Superseded. PRDs have similar states. A VISION doc's lifecycle might need different states: Thesis -> Validated -> Committed -> Archived. The "Validated" state would mean the go/no-go framework was evaluated. When does a VISION doc become "done"?

3. **How does VISION interact with the crystallize decision tree?** If VISION is added as a supported type, what are its anti-signals? The most obvious: "the project already exists and has users" is a strong anti-signal (you're past the VISION stage). But what about "the user already knows they want to build this"? Is that an anti-signal (they've already passed the VISION gate mentally) or is it still worth capturing the thesis formally?

4. **Should tactical scope completely suppress VISION, or just demote it?** The crystallize framework has a demotion mechanism (anti-signals push types below types without anti-signals). Should "tactical scope" be an anti-signal for VISION, or should VISION simply not appear in the candidate list when scope is tactical?

5. **Where do VISION docs live in public repos?** Private repos have a clear home (the vision repository). For public repos in strategic scope, where does the file go? `docs/vision/VISION-<project>.md`? This needs a convention.

## Summary

VISION docs are inherently strategic artifacts -- they make full sense in Strategic+Private and Strategic+Public, degenerate into a redundant "project brief" in Tactical+Private, and add no unique value in Tactical+Public. The cleanest approach is gating VISION to strategic scope only (with visibility controlling content richness, not availability), which means the crystallize framework should either suppress VISION as a candidate in tactical scope or treat tactical scope as a hard anti-signal. The biggest open question is whether VISION should route through the crystallize framework at all, or live as a standalone command that sits above /explore in the workflow hierarchy -- since you may need a VISION before knowing what to explore.
