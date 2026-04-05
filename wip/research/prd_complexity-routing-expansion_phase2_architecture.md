# Architecture Analysis: Complexity Routing Expansion (5 Levels)

## Lead 1: Signal Definitions for 5 Levels

### Current State

The /explore SKILL.md has a 3-level "Complexity-Based Routing" table:

| Level | Signals | Path |
|-------|---------|------|
| Simple | Clear requirements, few files, one person | /work-on or /prd then implement |
| Medium | Known approach, some integration risk | /design then /plan |
| Complex | Multiple unknowns, shape unclear | /explore to discover first |

The roadmap (ROADMAP-strategic-pipeline.md) defines the 5-level pipeline model
with entry points and diamond usage but provides no classification signals.

### Signal Design Principles

Signals must be:

1. **Observable from user input** -- an agent receiving a request must be able
   to classify it without running the full workflow first
2. **Mutually exclusive at the boundary** -- overlap between adjacent levels
   should be resolvable with a tiebreaker, not left ambiguous
3. **Grounded in pipeline artifacts** -- each level's signals should correspond
   to which diamonds the work will pass through

### Proposed Signal Definitions

#### Trivial

**Entry point:** /work-on (free-form, no issue)
**Diamonds:** 3 only

| Signal | Observable From |
|--------|----------------|
| No GitHub issue exists for this work | User says "just do X" without referencing an issue |
| Change is self-evident (typo fix, config tweak, version bump) | Request describes a single, concrete action |
| No acceptance criteria needed beyond "it works" | Scope fits in one sentence without conditions |
| One file or a handful of closely related files | User names the file or the change is obviously localized |
| No design decisions to make | There are no "should I do A or B?" questions |

**Key discriminator from Simple:** No issue exists, and the work doesn't warrant
creating one. Simple work has an issue (or should have one) because it carries
scope that benefits from tracking. Trivial work is fire-and-forget.

**Tiebreaker:** If someone could reasonably disagree about what "done" looks like,
it's not Trivial -- it's at least Simple.

#### Simple

**Entry point:** /work-on <issue>
**Diamonds:** 3 only

| Signal | Observable From |
|--------|----------------|
| A GitHub issue exists with clear scope | Issue body has a defined goal |
| Requirements are stated or obvious from context | No "what should we build?" ambiguity |
| Implementation approach is known (no competing options) | One obvious way to do it |
| One person can implement without coordination | No cross-team or cross-component dependencies |
| Few files touched (1-5), single component | Issue describes a bounded change |
| Testing strategy is straightforward (unit tests, existing patterns) | No new test infrastructure needed |

**Key discriminator from Trivial:** An issue exists (or should exist) because
the work has scope worth tracking -- acceptance criteria, a reviewer,
a record of what changed and why.

**Key discriminator from Medium:** No design decisions between competing
approaches. The "how" is as clear as the "what." If someone asks "but should
we use approach A or B?", it's Medium.

**Tiebreaker from Trivial:** Does the change need acceptance criteria? Yes ->
Simple. No -> Trivial.

**Tiebreaker from Medium:** Count the open questions. Zero -> Simple.
One or more about approach -> Medium.

#### Medium

**Entry point:** /design -> /plan
**Diamonds:** 2-3

| Signal | Observable From |
|--------|----------------|
| What to build is clear, but how to build it needs decision-making | Requirements exist but implementation approach isn't obvious |
| Multiple viable approaches exist with trade-offs | "Should we use X or Y?" questions arise |
| Integration risk: touches multiple components or APIs | Change spans packages, services, or boundaries |
| Architecture or structural decisions need documenting | Future contributors will ask "why was it done this way?" |
| New patterns or interfaces being introduced | Not just extending an existing pattern |
| Existing PRD or clear requirements available | The "what" is settled; the "how" is the question |

**Key discriminator from Simple:** The presence of genuine design decisions.
Medium work has at least one question where "it depends" is the honest answer
until trade-offs are analyzed.

**Key discriminator from Complex:** The problem space is known. You know what
you're building and roughly where it lives in the codebase. The unknowns are
about approach selection, not about what the problem even is.

**Tiebreaker from Simple:** Is there a design decision that a reasonable person
could disagree on? Yes -> Medium. No -> Simple.

**Tiebreaker from Complex:** Can you list the decision questions right now? Yes
-> Medium. No (too many unknowns to even frame questions) -> Complex.

#### Complex

**Entry point:** /explore -> full pipeline
**Diamonds:** 1-2-3

| Signal | Observable From |
|--------|----------------|
| Multiple unknowns: what to build AND how to build it | User can't clearly state requirements or approach |
| Problem shape is unclear -- exploration needed before commitment | "I'm not sure where to start" or "I don't know what I need" |
| Cross-cutting concerns span the codebase | Touches multiple systems with unclear boundaries |
| Risk of building the wrong thing without research | The cost of starting wrong is high |
| Scope is contested or ambiguous | Multiple valid interpretations of what "done" means |
| Existing approaches may need to be reconsidered | Not just adding to the system but potentially reshaping it |

**Key discriminator from Medium:** Medium has known requirements and unknown
implementation. Complex has unknown requirements OR unknown problem shape. The
exploration exists to discover what the right artifact type even is.

**Key discriminator from Strategic:** Complex is bounded to a single feature or
capability within an existing project. Strategic involves multiple features,
project-level direction, or new project inception.

**Tiebreaker from Medium:** Does the user know what artifact they need (PRD,
design doc, plan)? Yes -> Medium (go directly to that skill). No -> Complex
(explore first).

**Tiebreaker from Strategic:** Is this about one feature or about the project's
direction? One feature -> Complex. Project direction or multi-feature -> Strategic.

#### Strategic

**Entry point:** VISION -> Roadmap -> per-feature pipeline
**Diamonds:** 1-2-3 with branching

| Signal | Observable From |
|--------|----------------|
| Work involves project inception ("should this project exist?") | No codebase yet, or questioning whether one should exist |
| Multiple features need sequencing and prioritization | Not one capability but a set of related capabilities |
| Organizational or strategic justification required | "Why here?" or "why now?" questions need answering |
| Thesis validation is the primary question | Before requirements, the premise needs to be validated |
| Roadmap-level coordination needed | Features have dependencies that affect delivery order |
| Target audience or value proposition isn't defined | Pre-PRD: the "who" and "why" are still open |
| Work will branch into per-feature sub-pipelines | Each feature in the roadmap will independently enter the pipeline |

**Key discriminator from Complex:** Strategic work produces artifacts that
sit upstream of PRDs -- VISIONs and Roadmaps. Complex work might produce a PRD
or design doc. The artifact type is the clearest signal: if the right answer
is "write a VISION first," it's Strategic.

**Tiebreaker from Complex:** Does the exploration need to determine whether
the project should exist, or which features to build? Yes -> Strategic.
Is the exploration about one specific capability? -> Complex.

### Signal Overlap Matrix

The most likely confusion points between adjacent levels:

| Boundary | Overlap Risk | Resolution |
|----------|-------------|------------|
| Trivial / Simple | Small fix that someone filed an issue for | If an issue exists, it's Simple. The issue's existence is the signal. |
| Simple / Medium | Issue exists but implementation has one ambiguous aspect | Count design decisions. Zero -> Simple. One+ -> Medium. |
| Medium / Complex | Clear requirements but many integration unknowns | Can you list decision questions? Yes -> Medium. Too vague -> Complex. |
| Complex / Strategic | Large feature that might reshape the project | Single feature -> Complex. Multiple features or project direction -> Strategic. |

### Detection Algorithm

For an agent classifying incoming work:

```
1. Does the user reference a VISION, Roadmap, or "project direction"?
   YES -> Strategic

2. Does the user say "I don't know what I need" or can't state requirements?
   YES -> Complex

3. Does the user have clear requirements but competing implementation approaches?
   YES -> Medium

4. Does a GitHub issue exist with defined scope?
   YES -> Simple

5. Is the work self-evident and doesn't need an issue?
   YES -> Trivial

6. Default -> Simple (create an issue and proceed)
```

The algorithm runs top-down: higher complexity levels are checked first because
Strategic and Complex are less likely to be misclassified downward than Trivial
is to be misclassified upward.

## Lead 2: How Other Skills Reference Complexity

### Findings

**Complexity is primarily an /explore concern today.** The 3-level routing
table lives only in /explore's SKILL.md. Other skills reference complexity in
different, narrow ways:

- **/plan** has its own complexity classification for issues (simple, testable,
  critical) -- this is per-issue granularity, not workflow-level routing.
  Plan also has a "Simple/Complex" assessment for recommending next steps after
  /design completes (files to modify, new tests, API changes, cross-package).
  These are orthogonal to the 5-level pipeline model.

- **/design** has an output complexity assessment (Simple vs Complex) that
  determines whether to recommend /plan or manual implementation. This is
  about the design's implementation scope, not about routing into /design.

- **/prd** mentions "Simple or medium" and "Complex" in its output next-steps
  table, but doesn't define these levels. It just says simple/medium -> plan,
  complex -> design. These implicitly match the pipeline model's Medium and
  Complex levels but aren't formalized.

- **/work-on** has no complexity classification. It receives work that's already
  classified as Simple or Trivial (by the user's decision to invoke it directly).

- **/vision** has no complexity classification. It's inherently Strategic-level.

### Implications for the PRD

1. **The 5-level model should live in /explore's SKILL.md** since that's where
   routing happens. Other skills don't need to know about all 5 levels -- they
   only need to know about their own output complexity for next-step recommendations.

2. **Existing per-issue complexity in /plan should not be confused with pipeline
   complexity.** The plan skill's simple/testable/critical classification is about
   issue sizing, not about which diamonds the work passes through. The PRD should
   note this distinction explicitly.

3. **The /prd and /design output tables should reference the 5-level model by
   name** rather than using ad-hoc "simple or medium" / "complex" labels. This
   is a consistency improvement but could be deferred to Feature 6 (Pipeline Docs).

4. **No skill changes are needed outside /explore for Feature 4.** The scope
   document already states this: "Out of Scope: Changes to /work-on, /implement,
   or other downstream skills." The architecture confirms this is correct.

### Artifact-Type Mapping

Each complexity level naturally produces certain artifact types from the
crystallize framework:

| Level | Natural Artifacts | Framework Entry |
|-------|------------------|-----------------|
| Trivial | No artifact | "No Artifact" -- simple enough to act directly |
| Simple | No artifact or Plan | "No Artifact" or "Plan" if decomposition needed |
| Medium | Design Doc, Plan | "Design Doc" then "Plan" |
| Complex | Any of the 10 types | Full crystallize scoring |
| Strategic | VISION, Roadmap | "VISION" or "Roadmap" then per-feature cascade |

This mapping is informational -- the crystallize framework still scores all types.
But the pipeline level constrains which artifact types are likely. An agent
classifying at Trivial level would never run the full crystallize framework; it
would skip directly to implementation.

## Edge Cases

### Escalation During Execution

Work classified as Simple may reveal Medium-level complexity during /work-on's
analysis phase. The current /work-on koto template handles this via the
`task_validation` step (for free-form) and the analysis phase (for issue-backed).
If analysis surfaces design questions, the agent should recommend pausing
implementation and running /design first.

The PRD should specify whether the 5-level classification is a one-time routing
decision or can be revised mid-execution. Recommendation: one-time for initial
routing, with individual skills responsible for escalation when they discover
the work is more complex than expected.

### De-escalation

A user might invoke /explore (Complex-level) for work that turns out to be Simple.
The crystallize framework already handles this: it can recommend "No Artifact"
with a suggestion to "just do it." The 5-level model doesn't prevent this --
it just means the user took a longer path than necessary. No architectural
issue here.

### Strategic Without VISION

A user might have multi-feature work that logically belongs at the Strategic
level but doesn't need a VISION document (the project already exists and has
clear direction). In this case, the entry point is /roadmap directly, skipping
VISION. The signal is: "I know why this project exists, I need to sequence
multiple features." The 5-level table should show VISION as optional at the
Strategic level, with Roadmap as the minimum entry point.

### Trivial That Grows

Someone starts with "fix this typo" (Trivial) but realizes the file has
structural problems that need a broader fix. This is handled by /work-on's
existing flow: the analysis phase can recommend creating an issue and expanding
scope. No special handling needed in the routing table.
