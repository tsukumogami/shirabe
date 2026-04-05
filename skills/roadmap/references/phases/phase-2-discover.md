# Phase 2: Discover

Three specialist agents investigate candidate features, dependencies, and sequencing
from Phase 1.

## Goal

Deepen understanding of the roadmap's feature list, dependency graph, and sequencing
by sending three specialist agents to investigate. Return with findings that inform
the ROADMAP draft in Phase 3.

## Resume Check

If `wip/research/roadmap_<topic>_phase2_*.md` files exist, summarize their findings
and skip to Phase 3.

## Approach: Three Fixed Agent Roles

Launch all 3 agents to investigate candidate features from
`wip/roadmap_<topic>_scope.md`. All three roles always run -- no selection heuristic.

### 2.1 Launch Agents

Read `wip/roadmap_<topic>_scope.md` and launch all 3 agents in parallel using the
Agent tool with `run_in_background: true`.

Each agent receives:
- The scope document (`wip/roadmap_<topic>_scope.md`)
- Their role description and investigation focus
- Output instructions

### Role Descriptions and Agent Prompts

#### Feature Completeness Analyst

```
You are investigating a roadmap's feature list for completeness and granularity from
the perspective of a feature completeness analyst.

## Context
[Contents of wip/roadmap_<topic>_scope.md]

## Instructions
1. Read relevant code, docs, existing artifacts, and any available evidence
2. Investigate:
   - Are there gaps in the feature list? Work that fits the theme but wasn't listed?
   - Is each feature at the right granularity? Too broad (should be split) or too
     narrow (should be merged)?
   - Is each feature independently describable at PRD level?
   - Are there at least 2 features? If not, flag this as a blocking issue.
3. For each finding, capture: what you found, implications for the roadmap,
   open questions

## Output
Write your full findings to `wip/research/roadmap_<topic>_phase2_feature-completeness.md`
using the Write tool.

Format:
# Phase 2 Research: Feature Completeness Analyst

## Feature List Assessment
### Current Features
<assessment of each candidate feature: granularity, clarity, PRD-readiness>

### Gaps Identified
<features that fit the theme but are missing>

### Granularity Issues
<features that should be split or merged, with rationale>

## Implications for Roadmap
<what the roadmap should account for>

## Open Questions
<things that need human input>

## Summary
<2-3 sentences: key findings and their impact on the roadmap>

Return only the summary to this conversation.
```

#### Dependency Validator

```
You are investigating a roadmap's dependency claims from the perspective of a
dependency validator.

## Context
[Contents of wip/roadmap_<topic>_scope.md]

## Instructions
1. Read relevant code, docs, existing artifacts, and any available evidence
2. Investigate:
   - Are the stated dependencies between features accurate? Trace each one.
   - Are there hidden dependencies not captured in the scope? Check for shared
     infrastructure, APIs, or data formats that create coupling.
   - Are there external dependencies outside this roadmap that could block features?
   - Could any stated dependencies be removed by changing the approach?
3. For each finding, capture: what you found, implications for the roadmap,
   open questions

## Output
Write your full findings to `wip/research/roadmap_<topic>_phase2_dependency-validator.md`
using the Write tool.

Format:
# Phase 2 Research: Dependency Validator

## Stated Dependencies
<assessment of each dependency from scope: confirmed, questionable, or incorrect>

## Hidden Dependencies
<dependencies not in scope that should be>

## External Dependencies
<blockers outside this roadmap>

## Removable Dependencies
<dependencies that could be eliminated by changing approach>

## Implications for Roadmap
<what the roadmap should account for>

## Open Questions
<things that need human input>

## Summary
<2-3 sentences: key findings and their impact on the roadmap>

Return only the summary to this conversation.
```

#### Sequencing Analyst

```
You are investigating a roadmap's sequencing and annotation accuracy from the
perspective of a sequencing analyst.

## Context
[Contents of wip/roadmap_<topic>_scope.md]

## Instructions
1. Read relevant code, docs, existing artifacts, and any available evidence
2. Investigate:
   - Is the proposed ordering justified? For each sequencing constraint, is it a
     hard blocker or a soft preference?
   - What can run in parallel? Are there features with no mutual dependencies that
     could be worked simultaneously?
   - Are the needs-* annotations accurate? Check downstream artifact state for
     each feature against what actually exists (PRDs, designs, implementations).
   - Does the sequencing account for risk? Should high-risk features come earlier
     to surface problems sooner?
3. For each finding, capture: what you found, implications for the roadmap,
   open questions

## Output
Write your full findings to `wip/research/roadmap_<topic>_phase2_sequencing-analyst.md`
using the Write tool.

Format:
# Phase 2 Research: Sequencing Analyst

## Ordering Assessment
<assessment of each sequencing constraint: justified, questionable, or unnecessary>

## Parallelization Opportunities
<features that could run simultaneously>

## Annotation Accuracy
<assessment of needs-* labels against actual downstream artifact state>

## Risk Sequencing
<features that should move earlier or later based on risk>

## Implications for Roadmap
<what the roadmap should account for>

## Open Questions
<things that need human input>

## Summary
<2-3 sentences: key findings and their impact on the roadmap>

Return only the summary to this conversation.
```

### 2.2 Synthesize Findings

After all agents complete, synthesize their findings:

1. Read the summary from each agent
2. Identify themes across agents (multiple agents noticing the same signal = high
   confidence)
3. Identify contradictions (agents disagreeing = needs human input)
4. List feature additions, dependency corrections, or sequencing changes surfaced
   by the research

When research reveals competing approaches or sequencing trade-offs where evidence
points toward one direction, record the decision. Note what was decided, what
alternatives existed, and what evidence drove the choice.

Present the synthesis to the user:
- Key findings (what we learned)
- Feature list adjustments (additions, splits, merges suggested by research)
- Dependency corrections (hidden dependencies found, stated ones invalidated)
- Sequencing changes (reordering, parallelization opportunities)
- New questions (things we need the user to decide)

### 2.3 Loop Back Decision

After presenting findings, present the loop decision using AskUserQuestion following
the pattern in `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`.

**Recommendation heuristic:** If findings give enough evidence to draft the roadmap
and no major feature or dependency gaps remain, recommend proceeding. If new features
emerged or critical dependencies were missed, recommend looping. If unsure, recommend
proceeding -- Phase 3's review will catch remaining gaps.

**Options (order by recommendation heuristic):**
1. "Proceed to Phase 3 (Recommended)" -- when feature list and dependencies are
   solid enough to draft
2. "Investigate further" -- new features emerged or critical dependencies need
   another round of investigation
3. "Restart scoping (Phase 1)" -- research revealed the theme or feature list was
   fundamentally wrong

**Description field:** Ground the recommendation in the synthesis -- cite which
findings support the feature list or which gaps suggest more investigation.

If the user picks "Investigate further," launch another round of agents for the
new findings only.

If the user picks "Restart scoping," delete `wip/roadmap_<topic>_scope.md` before
returning to Phase 1 so the resume check doesn't skip re-scoping.

## Quality Checklist

Before proceeding:
- [ ] All 3 agents completed their investigation
- [ ] Findings synthesized and presented to user
- [ ] Feature list adjustments discussed with user
- [ ] User agrees feature list and dependencies are solid enough to draft

## Artifact State

After this phase:
- Scope document still at `wip/roadmap_<topic>_scope.md`
- Research findings at `wip/research/roadmap_<topic>_phase2_feature-completeness.md`
- Research findings at `wip/research/roadmap_<topic>_phase2_dependency-validator.md`
- Research findings at `wip/research/roadmap_<topic>_phase2_sequencing-analyst.md`
- No ROADMAP draft yet

## Next Phase

Proceed to Phase 3: Draft (`phase-3-draft.md`)
