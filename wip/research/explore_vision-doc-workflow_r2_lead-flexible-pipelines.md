# Lead: How do established frameworks model flexible, non-linear pipelines?

## Research Question

The pipeline we're designing needs to handle: loops (explore then discover more), skips (simple features go straight to /work-on), branches (one vision spawns multiple PRDs), re-entry (resume partway through), and complexity-based routing. What can established product development frameworks teach us?

## Framework Analysis

### 1. Shape Up (Basecamp)

**How it works:** Three phases -- shaping, betting, building -- run in cycles (usually six weeks). Shaping produces "pitches" that describe problems, appetites (time budgets), and solutions. Bets are placed on pitches at the betting table. Teams build within the fixed time container.

**Loops/iteration:** Shaping is explicitly iterative. A pitch can go through multiple rounds of refinement before it reaches the betting table. The hill chart models progress non-linearly: the "uphill" phase (figuring out the approach) is full of unknowns and problem-solving; the "downhill" phase (execution) is about certainty. Dots on the hill chart can move backward -- acknowledging that progress isn't monotonic.

**Complexity routing:** Appetite is the mechanism. Small Batch projects (1-2 weeks for a designer + 1-2 programmers) get batched together in a cycle. Big Batch projects take a full six weeks for the same team. If something exceeds a six-week appetite, it's not given more time -- it's broken into independent pieces that ship across multiple cycles. This is "fixed time, variable scope" -- complexity doesn't change the timeline, it changes what gets shipped.

**Branching:** Not a first-class concept. Each pitch is atomic. If a broad idea spawns multiple pitches, those are separate bets evaluated independently.

**Skipping stages:** Implicit. If something is small and well-understood, it can go from a quick shaping pass directly to a Small Batch bet. No mandatory intermediate artifacts.

**Gate decisions:** The betting table is the only gate. Binary: bet or don't. No "conditional go." Pitches that don't make the cut are discarded, not queued -- there's no backlog.

**Key insight for our pipeline:** Appetite-as-routing. Classify work by how much time it deserves, not by how complex it is. This reframes complexity routing from "how hard is this?" to "how much investment does this warrant?" -- a more actionable question.

### 2. Dual Track Agile

**How it works:** Two parallel tracks run continuously. The Discovery track validates what to build (user research, prototyping, experiments). The Delivery track builds validated ideas. Outputs of discovery become inputs to delivery.

**Loops/iteration:** Both tracks run continuous feedback loops. Discovery produces validated backlog items; delivery produces shipped software that generates usage data; that data feeds back into discovery. Items can bounce between tracks -- a delivery finding (e.g., "this is technically harder than expected") sends the item back to discovery for re-scoping.

**Complexity routing:** Not explicit. The discovery track handles uncertainty reduction regardless of complexity. Simple, well-understood items pass through discovery quickly. Complex items require more discovery cycles (prototypes, experiments, user tests) before crossing to delivery.

**Branching:** Discovery naturally produces multiple backlog items from a single research initiative. One user study might yield five validated feature ideas that each enter the delivery track independently.

**Skipping stages:** Items with low uncertainty can skip deep discovery. If you already know the problem and solution, the discovery "phase" is just confirming that assumption -- which can be nearly instantaneous.

**Gate decisions:** Validation is the crossover criterion. An item crosses from discovery to delivery when it meets acceptance criteria: the problem is confirmed, the solution is validated, and the scope is clear. This isn't a formal gate meeting -- it's a continuous flow.

**Key insight for our pipeline:** Parallel tracks with validation as the handoff criterion. Instead of a linear pipeline where every item passes through every stage, items flow between two concurrent modes (understanding vs. implementing) based on their validation state.

### 3. Amazon Working Backwards (PR/FAQ)

**How it works:** Start by writing a press release for the finished product and a FAQ addressing hard questions. This forces clarity about customer value before any design or engineering work begins. The PR/FAQ is iterated until stakeholders agree it describes something worth building.

**Loops/iteration:** Highly iterative by design. The PR/FAQ goes through many revision cycles with diverse stakeholders. "If your PR doesn't require solving at least one complex problem with a new and innovative approach, return to the drawing board and keep iterating." The process is explicitly a funnel, not a tunnel -- many ideas enter, few survive.

**Complexity routing:** The PR/FAQ itself acts as a filter. Simple extensions of existing products might need only a lightweight PR/FAQ. Entirely new product categories require extensive FAQ sections addressing technical feasibility, market risk, and organizational capability gaps.

**Branching:** The FAQ section naturally surfaces sub-problems that may become independent workstreams. A single PR/FAQ for a complex product might spawn multiple technical design docs, each addressing a different hard problem identified in the FAQ.

**Skipping stages:** The process is the same regardless of complexity, but the depth varies. A small feature might need a one-page PR/FAQ; a new product line might need twenty pages. The structure stays constant; the rigor scales.

**Gate decisions:** Leadership review of the PR/FAQ is the gate. The document must be "ready" -- meaning it clearly articulates the customer benefit, the approach, and the answers to hard questions. The gate is subjective and qualitative, not checklist-based.

**Key insight for our pipeline:** Single artifact type, variable depth. Rather than routing to different artifact types based on complexity, use one artifact format and let the depth of content scale with the complexity of the work. This reduces routing decisions.

### 4. Toyota Set-Based Concurrent Engineering (SBCE)

**How it works:** Instead of picking one solution early and refining it (point-based design), Toyota explores sets of possible solutions in parallel and gradually narrows the set based on evidence. Three principles: (1) map the design space broadly by functional expertise, (2) integrate by finding intersections of mutually acceptable solutions, (3) establish feasibility before commitment.

**Loops/iteration:** Narrowing is the iteration model. Teams don't loop back to the start -- they progressively eliminate options as constraints emerge. This is fundamentally different from "iterate on one solution." The iteration is about which options to keep, not how to fix one option.

**Complexity routing:** Implicit in the breadth of the initial set. Simple problems start with a small set (maybe 2-3 options). Complex problems start with a larger set and take longer to narrow. The process shape is the same; the width varies.

**Branching:** First-class. The entire methodology is about branching. Multiple design alternatives coexist until evidence forces convergence. This is the opposite of "pick one approach and go."

**Skipping stages:** Not really applicable. Every design goes through the narrowing process. But simple designs narrow quickly (the feasible set is obvious), making the process self-adjusting.

**Gate decisions:** Feasibility constraints are the gates. Options are eliminated when they fail feasibility checks (technical, manufacturing, cost). There's no single "go/no-go" moment -- it's continuous narrowing based on accumulated evidence.

**Key insight for our pipeline:** Defer commitment by carrying options. Instead of forcing a routing decision early ("is this simple or complex?"), let multiple potential paths coexist and narrow based on what emerges during exploration.

### 5. Stage-Gate (Cooper)

**How it works:** Projects pass through a series of stages (work phases) separated by gates (decision points). Classic five stages: Scoping, Business Case, Development, Testing, Launch. Each gate has defined criteria and possible outcomes.

**Loops/iteration:** The "Recycle" gate decision sends a project back to a previous stage for rework. This is the formal loop mechanism. Stages themselves may contain iterative work (especially when combined with Agile sprints within stages).

**Complexity routing:** Modern Stage-Gate variants (Stage-Gate Lite, Stage-Gate XPress) use different process configurations for different project types. Low-complexity projects use a streamlined 3-stage version. High-complexity projects use the full 5-stage version. This is explicit complexity-based routing.

**Branching:** Not a first-class concept in classic Stage-Gate. Each project is independent. However, "platform projects" can spawn multiple "derivative projects" at later stages.

**Skipping stages:** Stage-Gate Lite and XPress explicitly skip or combine stages for lower-risk projects. Some organizations allow "fast-track" gates where the gate review is simplified or delegated.

**Gate decisions:** Five possible outcomes: Go, Kill, Hold, Recycle, Conditional Go. This is the most nuanced gate vocabulary of any framework studied. "Conditional Go" (proceed if specific criteria are met within a timeframe) is particularly useful for pipeline flexibility.

**Key insight for our pipeline:** Named gate decisions. Having explicit vocabulary for "go," "recycle," "skip," and "conditional go" makes pipeline behavior predictable and debuggable. This is better than implicit routing logic.

### 6. Double Diamond (Design Council)

**How it works:** Two diamonds, each consisting of a diverge phase followed by a converge phase. First diamond: Discover (diverge to understand the problem) then Define (converge on the right problem). Second diamond: Develop (diverge to explore solutions) then Deliver (converge on the right solution).

**Loops/iteration:** Movement back and forth within and between diamonds is expected. If testing contradicts assumptions, you loop back. The model was recently reframed as an "infinity loop" -- continuous diverge-converge cycles rather than a linear two-diamond sequence.

**Complexity routing:** Not explicit. Simple problems may need only the second diamond (the problem is already defined). Complex, novel problems need both diamonds with extensive divergence phases.

**Branching:** Divergence is branching. Each diverge phase generates multiple options (problem framings or solution candidates). Convergence is the selection mechanism.

**Skipping stages:** If the problem is already well-defined, you can skip the first diamond entirely and go straight to Develop/Deliver. This is a natural skip for well-understood work.

**Gate decisions:** Convergence points are implicit gates. The transition from Discover to Define is gated by "do we understand the problem space enough?" The transition from Define to Develop is gated by "have we framed the right problem?"

**Key insight for our pipeline:** Diverge-converge as the fundamental unit. Every stage in a pipeline is either diverging (exploring options) or converging (making decisions). Recognizing this helps design stages that don't fight their natural mode.

## Synthesis: Principles for a Flexible Artifact Pipeline

From these six frameworks, seven principles emerge:

### Principle 1: Investment-Based Routing (from Shape Up)

Route work by how much investment it warrants, not by an abstract complexity score. "How many rounds of exploration does this need?" is more actionable than "is this simple, medium, or complex?" The appetite determines the process, not the other way around.

### Principle 2: Validation as the Universal Gate (from Dual Track Agile)

The transition between any two stages should be "is this validated enough to proceed?" rather than "have we completed the required artifacts?" Validation is continuous, not checkpoint-based. Items that arrive pre-validated can skip stages.

### Principle 3: Named Transition Decisions (from Stage-Gate)

Every transition point should support explicit decisions: Advance (move to next stage), Recycle (return to a previous stage with new information), Skip (bypass stages when validation is already sufficient), Hold (pause for external input), and Kill (abandon this path). Implicit routing is harder to understand and debug.

### Principle 4: Parallel Options Over Sequential Commitment (from SBCE)

When uncertainty is high, carry multiple options forward rather than forcing early commitment. Exploration should naturally support "I'm considering three approaches" rather than requiring a single path selection upfront. Narrowing happens as evidence accumulates.

### Principle 5: Diverge-Converge as the Atomic Unit (from Double Diamond)

Each stage in the pipeline should be understood as either diverging (generating options, exploring space) or converging (selecting, deciding, committing). Stages that try to do both simultaneously create confusion. The pipeline is a sequence of diverge-converge pairs, not a sequence of artifact-production steps.

### Principle 6: Variable Depth, Consistent Structure (from Working Backwards)

Rather than many artifact types for different complexities, prefer fewer artifact types with variable depth. A lightweight version of the same artifact is better than a completely different artifact for simple cases. This reduces routing decisions and makes the pipeline more learnable.

### Principle 7: Funnel, Not Tunnel (from Working Backwards + Stage-Gate)

The pipeline should accept many inputs and progressively filter. Not every idea that enters exploration should produce a PRD. Not every PRD should produce a design doc. The pipeline should make it cheap to start and natural to stop. Kill/abandon should be a first-class outcome at every stage.

## Proposed Pipeline Model

Based on these principles, here's a model for the strategic-to-tactical pipeline:

### Core Concept: Stages as Diverge-Converge Pairs

```
EXPLORE (diverge)  -->  CRYSTALLIZE (converge)  -->  SPECIFY (diverge)  -->  SCOPE (converge)  -->  IMPLEMENT (diverge)  -->  SHIP (converge)
```

Each pair forms a "diamond":
- Diamond 1: Explore/Crystallize -- understand the problem space, converge on what artifact to produce
- Diamond 2: Specify/Scope -- produce the artifact (PRD, Design, etc.), converge on what to build
- Diamond 3: Implement/Ship -- build it, converge on what to release

### Transition Decisions at Each Boundary

At every convergence point, five decisions are available:

| Decision | Meaning | Example |
|----------|---------|---------|
| **Advance** | Move to next diverge phase | Crystallize picked "PRD" -- advance to Specify |
| **Recycle** | Return to current or previous diverge phase | Specify revealed new unknowns -- recycle to Explore |
| **Skip** | Jump ahead past one or more diamonds | Crystallize says "simple task" -- skip to Implement |
| **Hold** | Pause, waiting for external input | Specify needs stakeholder input before Scope can begin |
| **Kill** | Abandon this work item | Crystallize revealed no real demand -- kill |

### Investment-Based Routing (Not Complexity Labels)

Instead of classifying work as Simple/Medium/Complex, classify by investment level:

| Investment | Diamonds Used | Example |
|------------|---------------|---------|
| **Quick** | Diamond 3 only (Implement/Ship) | Bug fix, config change |
| **Standard** | Diamonds 2-3 (Specify through Ship) | Feature with known requirements |
| **Deep** | All three diamonds | Novel feature, new project, org-level initiative |

The investment level isn't decided by an abstract assessment -- it emerges from the Crystallize convergence. If Explore produces clear requirements and a known solution, Crystallize naturally routes to Standard or Quick. If Explore surfaces unknowns, Crystallize routes to Deep.

### Branching: One-to-Many at Convergence Points

Branching happens at convergence points when one input produces multiple outputs:

- Crystallize might produce a roadmap (one explore -> multiple PRDs)
- Scope might break a large PRD into multiple implementation plans
- Each branch becomes an independent pipeline instance

Branches are independent after creation. They can progress at different speeds through remaining diamonds.

### Re-entry: State-Based Resume

Each work item carries its state: which diamond it's in, which phase (diverge/converge), and what artifacts exist. Re-entry means loading this state and continuing from where it stopped. No special "resume" mechanism needed -- just read the state and enter the appropriate phase.

### How This Maps to Existing Skills

| Pipeline Phase | Existing Skill | Role |
|----------------|---------------|------|
| Explore (diverge) | /shirabe:explore Phases 1-4 | Multi-round discovery |
| Crystallize (converge) | /shirabe:explore Phase 5 | Artifact type selection |
| Specify (diverge) | /shirabe:prd, /shirabe:design | Produce the specification artifact |
| Scope (converge) | /shirabe:plan | Break into implementable issues |
| Implement (diverge) | /shirabe:work-on | Build each issue |
| Ship (converge) | /shirabe:release | Package and release |

The model doesn't require new skills -- it provides a mental model for how the existing skills connect and when to use each transition decision.

## Sources

- [Shape Up (Basecamp)](https://basecamp.com/shapeup)
- [Set Boundaries - Shape Up](https://basecamp.com/shapeup/1.2-chapter-03)
- [Show Progress - Shape Up](https://basecamp.com/shapeup/3.4-chapter-13)
- [Dual-Track Agile - Productboard](https://www.productboard.com/glossary/dual-track-agile/)
- [Dual-Track Agile - The Product Consortium](https://www.theproductconsortium.com/articles/product-101-dual-track-agile)
- [Working Backwards PR/FAQ Process](https://workingbackwards.com/concepts/working-backwards-pr-faq-process/)
- [Working Backwards - ProductStrategy](https://productstrategy.co/working-backwards-the-amazon-prfaq-for-product-innovation/)
- [Putting Amazon's PR/FAQ to Practice - Commoncog](https://commoncog.com/putting-amazons-pr-faq-to-practice/)
- [Toyota's Principles of Set-Based Concurrent Engineering - MIT Sloan](https://sloanreview.mit.edu/article/toyotas-principles-of-setbased-concurrent-engineering/)
- [Set-Based Concurrent Engineering - Targeted Convergence](https://www.targetedconvergence.com/set-based-concurrent-engineering)
- [Stage-Gate Model Overview](https://www.stage-gate.com/blog/the-stage-gate-model-an-overview/)
- [Stage Gate Process - TCGen](https://www.tcgen.com/product-development/stage-gate-process/)
- [Double Diamond - Wikipedia](https://en.wikipedia.org/wiki/Double_Diamond_(design_process_model))
- [Double Diamond - Fountain Institute](https://www.thefountaininstitute.com/blog/what-is-the-double-diamond-design-process)
