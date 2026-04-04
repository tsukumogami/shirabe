# Lead: How should the crystallize framework be extended?

## Findings

### Current Framework Structure

The crystallize framework (`crystallize-framework.md`) scores five supported types (PRD, Design Doc, Plan, No Artifact, Rejection Record) and lists five deferred types (Spike Report, Decision Record, Competitive Analysis, Prototype, Roadmap). Each type has a signal/anti-signal table. The scoring procedure: count signals minus anti-signals, demote any type with anti-signals below all types without, apply tiebreakers for close scores, fall back if nothing scores above 0.

### What Makes an Exploration "Vision-Shaped"

After analyzing the existing PRD signals and the gap described in the scope document, VISION-shaped explorations have a fundamentally different core question. PRD asks "what should we build and why?" -- it assumes the project exists and needs requirements. VISION asks "should this project exist, and what would it offer?" -- it questions whether the project itself is justified.

Key distinguishing characteristics of vision-shaped explorations:

1. **The project doesn't exist yet.** No repo, no codebase, no team. PRD assumes something is being built; VISION questions whether it should be built.

2. **Org fit is the primary question.** Does this project belong in this org? Does it align with what the org already does? PRD takes org fit as given.

3. **The thesis needs validation, not the requirements.** The exploration is testing "is this worth doing?" not "what exactly should it do?"

4. **Multiple projects or directions are still competing.** The exploration hasn't converged on a single project -- it's still comparing fundamentally different approaches to a space.

5. **Success metrics are organizational, not feature-level.** Success is measured in adoption, ecosystem fit, strategic positioning -- not "user can do X."

6. **No users yet.** The target audience may not be well-defined. PRD requires specific user roles for user stories.

### Proposed VISION Signal/Anti-Signal Table

| Signals | Anti-Signals |
|---------|-------------|
| Project doesn't exist yet (no repo, no codebase, no prior art in the org) | Project already exists and the question is about its next feature |
| Exploration centered on "should we build this?" not "what should it do?" | Requirements or user stories emerged during exploration |
| Org fit, strategic alignment, or ecosystem positioning was the core question | The "what to build" is already clear and accepted |
| Thesis validation or falsification was the exploration's primary output | A PRD, design doc, or roadmap already covers this topic |
| Multiple fundamentally different project directions are still viable | Single coherent feature emerged (route to PRD) |
| Target audience or user base is not yet well-defined | Specific users and their needs are already identified |
| The core question is "should this project exist and what would it offer?" | |
| Exploration produced strategic justification or positioning arguments | |

### Proposed Disambiguation Rules

**VISION vs PRD -- the boundary question:**

The cleanest discriminator is *project existence*. If the project exists (has a repo, has prior work, has users) and the exploration produced new feature requirements, that's a PRD. If the project doesn't exist yet and the exploration validated (or invalidated) whether it should, that's a VISION.

Secondary discriminator: *what did the exploration produce?* If findings center on user stories, acceptance criteria, and functional requirements -- PRD. If findings center on thesis arguments, org fit analysis, strategic justification, and audience definition -- VISION.

**VISION vs PRD tiebreaker rule (for Step 3):**

> **VISION vs PRD:** If the project doesn't exist yet (no repo, no codebase, no prior implementation in the org), favor VISION -- requirements are premature when the project's existence is unjustified. If the project exists and exploration surfaced what it should do next, favor PRD -- the strategic question is settled, the requirements question is not. The distinguishing question: does the project exist yet? No -> VISION. Yes -> PRD.

**VISION vs Roadmap:**

VISION answers "should this project exist?" Roadmap answers "what's next for this existing project?" If the exploration produced a sequenced set of features for a project that already exists, that's a Roadmap. If it produced a strategic case for why a new project should be created, that's a VISION.

**VISION vs Rejection Record:**

If the exploration actively concluded the project should NOT exist (with cited evidence), that's a Rejection Record, not a VISION. VISION captures affirmative strategic justification. However, a VISION can include a section on risks and reasons it might fail -- the distinction is whether the overall conclusion is "proceed" vs "don't proceed."

**VISION vs No Artifact:**

If the exploration was short, validated a thesis quickly, and one person can act on it without coordination, No Artifact may suffice. But if the strategic case needs to be documented for others to evaluate (multiple stakeholders, budget implications, org-level decision), favor VISION. The distinguishing question: does anyone else need to see the strategic argument? Yes -> VISION. No -> No artifact.

### Disambiguation Rule for the Framework (new entry)

**Exploration surfaced both strategic justification AND feature requirements.** If the exploration produced both "why this project should exist" AND "what it should do," the VISION comes first. Strategic justification must be accepted before requirements are worth writing. Recommend VISION with a note that a PRD should follow once the VISION is accepted. The VISION's `downstream` field would point to the eventual PRD.

### Where VISION Fits in the Evaluation Procedure

VISION should be a **supported type**, not a deferred type. The rationale:

1. The whole point of the exploration that prompted this research is to produce pre-PRD artifacts. If VISION is deferred, there's no path to produce it.
2. VISION is the most common output for directional explorations (the scope document's topic type is "Directional").
3. Unlike Spike Report or Prototype, VISION doesn't require special tooling -- it's a document, like PRD or Design Doc.

VISION would need a Phase 5 produce handler, similar to how PRD routes to `/prd` and Design Doc routes to `/design`. This could be a new `/vision` command or a template-based production within Phase 5.

### Scoring Step Changes

Step 1 would expand from five supported types to six. The deferred types list stays the same (VISION moves out of it -- it was never listed there, but it's the kind of type that would have been).

Step 3 tiebreaker section would gain new entries: VISION vs PRD, VISION vs Roadmap, VISION vs No Artifact.

The disambiguation rules section would gain the "strategic justification AND feature requirements" rule.

### Extension Pattern for Future Pre-PRD Types

If additional pre-PRD types emerge (Opportunity Assessment, Project Charter), they should follow the same pattern:

1. Define the core question the type answers
2. Build a signal/anti-signal table with at least 2 anti-signals that create clear exclusion zones
3. Add tiebreaker rules against the nearest neighboring types (especially VISION and PRD)
4. Add disambiguation rules for common ambiguous patterns

The anti-signals are more important than signals for new types, because they prevent the new type from being recommended when it shouldn't be. A type with only signals and no anti-signals will score too easily.

## Implications

1. **VISION should be a supported type, not deferred.** It needs the same first-class treatment as PRD and Design Doc. This means adding it to the Supported Types section, updating Step 1 to score six types, and building a produce handler in Phase 5.

2. **The project-existence test is the sharpest discriminator.** Most tiebreaker rules and disambiguation come back to one question: does the project already exist? This is easy to evaluate and hard to get wrong.

3. **VISION creates a new lifecycle stage.** The artifact pipeline becomes VISION -> PRD -> Design Doc -> Plan. The crystallize framework's evaluation procedure doesn't need structural changes (it's already type-agnostic), but the recommendation format should note this pipeline relationship when VISION is recommended.

4. **Anti-signals matter more than signals for new types.** The demotion rule means a single anti-signal knocks a type below all clean-scoring types. VISION's anti-signals are its primary defense against being recommended when a PRD is the right call.

5. **The six-type framework may need a two-pass approach.** With six types, scoring all of them may produce more ties. Consider whether the first pass should separate "pre-project" types (VISION, Rejection Record) from "within-project" types (PRD, Design Doc, Plan, No Artifact) before scoring, rather than scoring all six in a flat list. This is an optional optimization -- the existing flat-scoring approach still works.

## Surprises

1. **The existing framework handles this better than expected.** The scoring mechanism, demotion rule, and tiebreaker structure are all type-agnostic. Adding VISION requires no structural changes to the evaluation procedure -- just new table entries and tiebreaker rules.

2. **VISION vs Rejection Record is a genuinely tricky edge case.** Both deal with "should this exist?" but with opposite conclusions. The anti-signal "exploration reached an active rejection conclusion" in Rejection Record handles this somewhat, but VISION also needs an explicit anti-signal for negative conclusions.

3. **The "Directional" topic type in the scope document is a strong pre-signal.** Explorations tagged as "Directional" are much more likely to produce VISIONs than explorations tagged as feature-specific. The crystallize framework doesn't currently use topic type as an input, but it could serve as a tiebreaker hint.

## Open Questions

1. **Should VISION be the only new supported type, or should Opportunity Assessment also be promoted?** The scope document asks about "any new pre-PRD types." VISION covers the strategic case, but an Opportunity Assessment (lighter-weight, focused on feasibility and market size) might be a distinct artifact. Is one enough, or are there two pre-PRD layers?

2. **How does VISION interact with private vs public visibility?** Strategic justification often includes competitive analysis, market positioning, and business rationale -- content that may not be appropriate for public repos. Should VISION be visibility-restricted, or should it have public and private variants?

3. **What does the VISION produce handler look like?** PRD routes to `/prd`, Design Doc to `/design`. Does VISION route to a new `/vision` command, or is it produced inline in Phase 5 with a template? The former is more consistent; the latter is faster to implement.

4. **Should the crystallize framework use topic type as an input?** "Directional" explorations are VISION-biased. "Feature-specific" explorations are PRD-biased. This isn't currently a scoring input, but it could be a tiebreaker hint or a pre-filter.

5. **What's the VISION lifecycle?** PRD has Draft -> Accepted -> In Progress -> Done. VISION likely needs something similar but with a "Validated" or "Greenlit" state that means "proceed to write a PRD." What triggers the transition?

## Summary

The crystallize framework's type-agnostic scoring mechanism handles VISION without structural changes -- it needs a signal/anti-signal table, three tiebreaker rules (vs PRD, Roadmap, No Artifact), and one new disambiguation rule, all following existing patterns. The sharpest discriminator between VISION and PRD is project existence: if the project doesn't exist yet and the exploration validated whether it should, that's a VISION; if the project exists and exploration produced feature requirements, that's a PRD. The biggest open question is whether VISION alone covers the pre-PRD layer or whether a lighter-weight artifact (Opportunity Assessment) is also needed for cases where full strategic justification is overkill.
