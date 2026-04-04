# Lead: Are there intermediate artifacts needed between VISION and PRD?

## Findings

### Candidate intermediate artifacts

The product management literature names roughly six document types that sit between a vision statement and a requirements specification. Here's what each one does and whether it earns its keep in a small dev-tools org.

**1. Opportunity Assessment / Opportunity Brief**

Answers "Is this worth pursuing?" Typically contains market size, competitive landscape, effort estimate, and a go/no-go recommendation. In enterprise orgs, this gates resource allocation -- a PM writes one before getting headcount.

*For this org:* The "resource allocation gate" doesn't apply when one or two people make all the decisions. However, the *analytical content* -- "what problem exists, who has it, what alternatives exist, is this tractable" -- is genuinely useful. That content overlaps heavily with what /explore already produces during its discover-converge rounds and with what an adversarial demand-validation lead investigates. An opportunity assessment is /explore's accumulated findings, wearing a suit.

**2. Project Charter**

Answers "What are the boundaries and authority?" Names the project, its sponsor, its objectives, success criteria, constraints, assumptions, and who has decision authority. Common in PMI/PMBOK-style organizations.

*For this org:* Charters solve a coordination problem (who decides, who's accountable) that doesn't exist in a one-person or tiny team. The useful parts -- objectives, constraints, assumptions -- are already captured well by the PRD's Problem Statement + Goals + Out of Scope sections. A charter adds no distinct value here.

**3. Strategy Brief / Strategic Context Document**

Answers "How does this fit the bigger picture?" Connects a project to org-level strategy, explains why now, and positions it relative to other initiatives.

*For this org:* This is the strongest candidate for something a VISION doc should contain but a PRD shouldn't. A PRD says "we need feature X because users need Y." A strategy brief says "Feature X matters because it advances our position in Z, complements project W, and must happen before Q." The "org fit" and "why now" framing is genuinely distinct from both VISION (which is about the project's own ambition) and PRD (which is about specific requirements). The question is whether it's a separate document or a section.

**4. Problem Statement / Problem Definition Document**

Answers "What exactly is the problem?" Isolates the problem from any proposed solution. Who's affected, what's broken, what evidence exists, what happens if we do nothing.

*For this org:* The PRD already has a required Problem Statement section. A standalone problem definition document would be the PRD's problem statement extracted into its own file. That's redundant unless the problem is so complex or contested that it needs its own exploration cycle -- which is exactly what /explore does. The explore workflow's adversarial demand-validation lead already covers "is the problem real?" investigation. No distinct artifact needed.

**5. Hypothesis Document / Investment Thesis**

Answers "What bet are we making?" Frames the project as a testable hypothesis: "We believe [action] will achieve [outcome] for [audience] because [evidence]." Common in lean startup methodology and growth-stage product orgs.

*For this org:* The hypothesis framing is valuable as a *thinking tool* but doesn't need its own document type. A well-written VISION doc can include the thesis as a section: "We believe X because Y, and we'll know we're right when Z." Forcing it into a separate document adds process without adding clarity.

**6. Business Case / Cost-Benefit Analysis**

Answers "Is this worth the investment?" ROI analysis, cost projections, risk assessment. Standard in enterprise IT governance.

*For this org:* Overkill. A developer tools org with tiny teams doesn't need formal cost-benefit analysis documents. The relevant question ("is this worth my time?") is answered by the VISION doc's strategic rationale and the opportunity assessment content that /explore already generates.

### How the current workflow already covers most of this

Looking at the existing shirabe pipeline:

- **/explore** (discover-converge rounds) already functions as the opportunity assessment and problem definition. The adversarial demand-validation lead explicitly asks "Is demand real? What do people do today? Who asked?" This is opportunity assessment content.

- **PRD** already captures problem statement, goals, requirements, acceptance criteria. It has an `upstream` field pointing to roadmaps.

- **Roadmap** already sequences features and captures the "what's next" strategic framing.

- **Crystallize framework** already routes exploration findings to the right artifact type. The gap isn't in *routing* -- it's that none of the destination types capture the *project-level thesis* (why this project should exist at all, how it fits the org, what strategic bet it represents).

### The actual gap

The gap between VISION and PRD is real but narrow. It's not about missing intermediate document types -- it's about one specific content layer that neither the current PRD nor the Roadmap captures well:

1. **Project thesis**: "We believe building X will achieve Y" -- the testable claim
2. **Org fit**: How this project relates to other projects in the org
3. **Strategic justification**: Why now, why us, why this approach over alternatives

A PRD's Problem Statement is scoped to a single feature's problem. A Roadmap sequences features but doesn't justify the project's existence. The VISION doc is where this content lives.

The question becomes: does a VISION doc *alone* carry all three, or does it need a companion?

### Assessment: VISION alone is sufficient, with the right sections

A single VISION document can carry thesis, org fit, and strategic justification if it's structured correctly. The intermediate artifacts (opportunity assessment, strategy brief, hypothesis doc) each capture one facet of what a well-designed VISION doc covers. Adding them as separate documents would create a pipeline of thin artifacts that nobody maintains.

The key insight: the content those intermediate artifacts represent is real and valuable, but the *form factor* of separate documents isn't justified at this org's scale. The content should be *sections within VISION*, not standalone files.

## Implications

1. **No new intermediate artifact types needed.** The VISION doc should be designed with sections that absorb the useful content from opportunity assessments (problem evidence, demand validation), strategy briefs (org fit, why now), and hypothesis documents (testable thesis). This keeps the artifact count manageable while capturing the content that matters.

2. **The VISION -> PRD transition is the critical design point.** If VISION captures the project-level thesis and PRD captures feature-level requirements, the handoff needs to be clear about what "done with VISION, ready for PRD" means. The PRD already has an `upstream` field -- it can point to a VISION doc the same way it points to a Roadmap.

3. **The /explore workflow's existing research output overlaps with opportunity assessments.** When /explore runs demand-validation leads and accumulates findings, it's producing opportunity assessment content. If /explore can route to VISION (in addition to PRD, Design Doc, etc.), the opportunity assessment content flows naturally from explore findings into VISION sections rather than requiring a separate document.

4. **A VISION doc sits above Roadmap in the hierarchy.** The current artifact hierarchy has Roadmap -> PRD -> Design Doc -> Plan. VISION sits above Roadmap: VISION -> Roadmap -> PRD -> Design Doc -> Plan. A VISION might spawn multiple Roadmaps or go directly to PRDs for simple projects.

5. **Strategic scope matters for VISION docs.** VISION docs are inherently strategic-scope artifacts. In tactical repos, a VISION doc would feel out of place -- the explore workflow should rarely recommend one when the scope is tactical. This aligns with the scope dimension already in the framework.

## Surprises

**The biggest surprise: the gap is narrower than expected.** The user suspected "maybe a VISION doc isn't enough," but examining six candidate intermediate types reveals that a well-structured VISION doc covers all the pre-PRD content that matters at this org's scale. The real risk isn't having too few artifacts between VISION and PRD -- it's designing a VISION doc that's too thin and forces the creation of companions to carry the missing content.

**Second surprise: /explore already does the work of an opportunity assessment.** The adversarial demand-validation lead, the discover-converge synthesis, and the crystallize scoring are essentially an opportunity assessment process. The missing piece isn't the assessment process -- it's having a permanent document type to receive the assessment's conclusions when the answer is "yes, proceed."

**Third surprise: project charters are strictly unnecessary here.** Charters solve a problem (who decides, who's accountable, what's the authority structure) that doesn't exist when the decision-maker and the implementer are the same person or tiny team. Every framework recommends charters, but they're solving a coordination problem this org doesn't have.

## Open Questions

1. **What sections should a VISION doc contain?** This lead establishes that VISION alone is sufficient, but the template design is a separate question. Should it have explicit "Org Fit" and "Thesis" sections, or is that over-structuring it?

2. **Can a VISION doc be produced directly by /explore, or does it need its own command?** The crystallize framework routes to PRD, Design Doc, Plan, etc. Adding VISION as a routing target changes the framework's signal tables. Alternatively, VISION could have its own command like /prd does.

3. **What's the VISION doc lifecycle?** PRDs go Draft -> Accepted -> In Progress -> Done. Does VISION follow the same pattern, or does it need different states (e.g., "Active" for a living document that spawns multiple PRDs over time)?

4. **How does VISION relate to the private vision repo?** The workspace has a `private/vision/` repository. Is that where VISION docs live (private by default), or can they also exist in public repos? The strategic content in a VISION doc (org fit, competitive positioning) may be more appropriate for private repos.

5. **Does every project need a VISION doc, or only multi-PRD efforts?** If a project is small enough that it's a single PRD with no roadmap, does a VISION doc add value or just add ceremony?

## Summary

A well-structured VISION document absorbs the useful content from opportunity assessments, strategy briefs, and hypothesis documents -- no separate intermediate artifacts are needed between VISION and PRD at this org's scale. The real design challenge is making the VISION template rich enough to carry project thesis, org fit, and strategic justification without requiring companion documents. The biggest open question is whether VISION should be a new routing target in the crystallize framework or a standalone command with its own entry point.
