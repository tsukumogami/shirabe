# Decision Report: Roadmap Creation Workflow Phases

## Context

The /roadmap skill follows the same 4-phase pattern as /vision and /prd (Scope, Discover, Draft, Validate). Roadmaps have distinct concerns: they sequence multiple features rather than defining a single one. This report specifies the roadmap-specific content for each phase, grounded in the existing patterns from `/vision` and `/prd` and the roadmap format spec in `SKILL.md`.

## Phase 1: Scope -- Coverage Dimensions

VISION tracks 6 dimensions (thesis clarity, audience, org fit, success criteria, scope boundaries, value proposition). PRD tracks 6 dimensions (who is affected, current situation, what's missing, why now, scope boundaries, success criteria). Roadmaps need dimensions tuned to multi-feature sequencing.

### Chosen: 6 roadmap-specific coverage dimensions

| Dimension | What to understand |
|-----------|-------------------|
| Theme clarity | What initiative ties these features together? Why do they need coordinated sequencing rather than independent delivery? |
| Feature identification | What features belong in this roadmap? Can the user list at least 2? Are there features they're not mentioning that belong to the same capability area? |
| Dependency awareness | Which features depend on each other? Are there shared infrastructure needs, data dependencies, or user-facing ordering constraints? |
| Sequencing constraints | What drives the ordering? Hard technical blockers vs. soft preferences. Where can features run in parallel? |
| Downstream artifact state | For each feature: does a PRD exist? A design? Or does the feature need upstream work first? This feeds the `needs-*` annotations. |
| Scope boundaries | What's in this roadmap vs. adjacent work that's deliberately excluded? Is this one initiative or a grab-bag? |

**Rationale**: These map directly to the roadmap format's required sections (Theme, Features, Sequencing Rationale, Progress) and quality guidance. Theme clarity and scope boundaries prevent the "too broad" pitfall. Feature identification ensures the minimum of 2. Dependency awareness and sequencing constraints feed directly into the Sequencing Rationale section. Downstream artifact state enables accurate `needs-*` annotations from the start.

**Scope document template** (`wip/roadmap_<topic>_scope.md`):

```markdown
# /roadmap Scope: <topic>

## Theme Direction
<1-2 sentences: what initiative, why coordinated sequencing matters>

## Feature Sketch
- <Feature 1>: <1 sentence>
- <Feature 2>: <1 sentence>
[minimum 2]

## Known Dependencies
- <Feature X> depends on <Feature Y> because <reason>
- (or: no known dependencies yet)

## Sequencing Constraints
- <hard constraint or soft preference>

## Downstream State
- <Feature 1>: needs-prd | needs-design | needs-spike | needs-decision | ready
- <Feature 2>: ...

## Research Leads
1. <lead>: <rationale>

## Coverage Notes
<gaps to resolve in Phase 2>
```

---

## Phase 2: Discover -- Agent Roles

VISION uses 2-4 agents from a pool of 5 strategic roles (audience validator, value proposition analyst, org fit researcher, competitive landscape analyst, success criteria researcher). PRD uses 2-3 agents from a pool of 7 tactical roles (user researcher, codebase analyst, UX/ops/architecture perspective, current-state analyst, maintainer perspective).

Roadmaps need roles that investigate multi-feature coordination questions, not single-feature requirements or strategic positioning.

### Chosen: 4-role pool, select 2-3 per roadmap

**Feature completeness analyst**: Investigates whether the feature list covers the capability area or has gaps. Reads existing code, docs, issues, and the codebase to find work that belongs to the same initiative but isn't listed. Asks: are there missing features that would leave the capability half-built? Are any listed features actually sub-features of another (too granular)?

**Dependency validator**: Investigates whether stated dependencies are real and whether hidden dependencies exist. Reads the codebase to trace technical relationships between features. Checks shared infrastructure, data models, APIs, and configuration that create coupling. Asks: could Feature B actually ship before Feature A? Does Feature C have an unstated dependency on Feature D's output?

**Sequencing analyst**: Investigates whether the proposed ordering is justified or arbitrary. Evaluates whether hard dependencies are genuinely blocking or just assumed. Identifies opportunities for parallel execution. Considers risk-reduction ordering (build the risky thing first) and value-delivery ordering (ship user value early). Asks: what's the cost of getting the order wrong? What would change if we reordered?

**Downstream artifact assessor**: Investigates what each feature needs before it can be planned. Reads existing docs (PRDs, designs, spikes) to determine what already exists. For features without upstream artifacts, evaluates what type of work is needed: requirements gathering (needs-prd), technical design (needs-design), feasibility investigation (needs-spike), or a pending decision (needs-decision). Asks: is the `needs-*` annotation accurate given what already exists?

### Role selection heuristic

| Roadmap type | Recommended roles |
|-------------|------------------|
| New capability area (no existing code) | Feature completeness, Sequencing analyst, Downstream artifact assessor |
| Extension of existing system | Feature completeness, Dependency validator, Downstream artifact assessor |
| Refactoring/migration | Dependency validator, Sequencing analyst, Feature completeness |

Always include at least one of Feature completeness or Dependency validator -- these catch the most common roadmap problems (gaps and hidden coupling).

### Agent prompt template adaptation

Each agent receives:
- The scope document (`wip/roadmap_<topic>_scope.md`)
- Their assigned research leads
- Their role description
- Output instructions

Output goes to `wip/research/roadmap_<topic>_phase2_<role>.md`.

The synthesis step (2.4) specifically looks for:
- **Cross-agent agreement on missing features** -- multiple agents flagging the same gap is high confidence
- **Dependency contradictions** -- one agent says X depends on Y, another says they're independent
- **Sequencing disagreements** -- different orderings recommended by different agents signal a real trade-off worth surfacing to the user

---

## Phase 4: Validate -- Jury Roles

VISION uses 3 fixed jury roles (thesis quality, content boundary, section guidance). PRD uses 3 fixed roles (completeness, clarity, testability). Roadmaps need jury roles that validate what makes a roadmap specifically good, per the quality guidance in SKILL.md.

### Chosen: 3 fixed jury roles

#### 1. Theme Coherence Reviewer

Evaluates whether the roadmap holds together as a single initiative.

**Checks:**
1. Are all features part of the same capability area, or is this a grab-bag of unrelated work?
2. Does the theme explain why coordination matters (shared infrastructure, user-facing story, risk dependencies)?
3. Is each feature independently describable in 1-2 sentences, or are some vague or overlapping?
4. Does feature granularity match the PRD level (one feature = one PRD)? Flag features that are too granular (should be issues in a plan) or too broad (should be multiple features).
5. Are there at least 2 features? (Validation rule from SKILL.md.)

**Verdict criteria:** FAIL if features don't share a coherent theme, if any feature can't be described independently, or if fewer than 2 features exist.

**Output:** `wip/research/roadmap_<topic>_phase4_theme-coherence.md`

#### 2. Sequencing and Dependency Reviewer

Evaluates whether the ordering is justified and dependencies are complete.

**Checks:**
1. Are dependencies between features explicit, not implied? Every dependency should state what the downstream feature needs from the upstream one.
2. Are there circular dependencies? (A depends on B depends on A.)
3. Does the Sequencing Rationale explain ordering constraints, not just list the order?
4. Does it distinguish hard dependencies (technical blockers) from soft preferences (nice-to-have ordering)?
5. Does it acknowledge where parallel execution is possible?
6. Could the ordering be justified independently (someone unfamiliar could read the rationale and agree), or does it rely on unstated assumptions?

**Verdict criteria:** FAIL if dependencies are implied rather than explicit, if the rationale is just "Feature 1 comes before Feature 2" without explaining why, or if obvious parallelization opportunities are ignored without acknowledgment.

**Output:** `wip/research/roadmap_<topic>_phase4_sequencing-deps.md`

#### 3. Annotation and Boundary Reviewer

Evaluates whether `needs-*` annotations are accurate and content stays within roadmap boundaries.

**Checks:**
1. Does each feature's `needs-*` annotation match its description? A feature described as "architecture undecided" should be `needs-design`, not `needs-prd`.
2. Are features without `needs-*` annotations genuinely ready for direct implementation?
3. Does the roadmap contain content that belongs in downstream artifacts? Detailed requirements belong in PRDs. Technical architecture belongs in design docs. Issue breakdowns belong in plans.
4. Does the roadmap include dates or time estimates? (Content boundary violation per SKILL.md.)
5. Does the frontmatter `status` match the Status section in the body?
6. Are all 5 required sections present and in order?

**Verdict criteria:** FAIL if annotations don't match feature descriptions, if the roadmap contains downstream artifact content (requirements, architecture, issue lists), or if structural validation rules are violated.

**Output:** `wip/research/roadmap_<topic>_phase4_annotation-boundary.md`

### Process Feedback (4.3)

Same consensus table as /vision and /prd:

| Outcome | Action |
|---------|--------|
| All 3 pass | Proceed to finalization |
| 1-2 fail with minor issues | Fix issues, show fixes to user, proceed |
| Any fail with significant issues | Present to user, incorporate fixes, re-validate if substantial |
| Agents disagree | Present both perspectives, let user decide |

**Minor for roadmaps:** Sharpening a feature description, adding an explicit dependency that was implied, adjusting an annotation from needs-prd to needs-design.

**Significant for roadmaps:** Features that don't belong to the theme, missing features that leave the capability incomplete, ordering that contradicts stated dependencies, annotations that are systematically wrong.

---

## Alternatives Considered

### Phase 2: Single "roadmap analyst" role instead of a pool

Rejected. A single role can't simultaneously investigate feature completeness, dependency validity, and sequencing trade-offs with the same depth. The pool pattern from /vision and /prd exists because independent investigation from different perspectives catches more issues than a single broad pass.

### Phase 2: Reuse PRD roles (user researcher, codebase analyst, etc.)

Rejected. PRD roles investigate single-feature concerns (user needs, implementation constraints, UX implications). Roadmap research questions are about multi-feature relationships: gaps in the feature list, hidden dependencies between features, and ordering trade-offs. Reusing PRD roles would miss the roadmap-specific questions entirely.

### Phase 4: Add a 4th jury role for "progress accuracy"

Rejected for creation workflow. At creation time, all features are "Not started" -- there's nothing to validate in Progress. A progress accuracy reviewer would add value in a future /roadmap update workflow but not during initial creation.

### Phase 4: Combine annotation and boundary review into theme coherence

Rejected. Annotation accuracy (do `needs-*` labels match descriptions?) is a mechanical check that's distinct from theme coherence (do features belong together?). Combining them risks one concern drowning out the other. The /vision pattern keeps content boundary review separate from thesis quality review for the same reason.

## Summary

The roadmap creation workflow adapts the 4-phase pattern to multi-feature coordination concerns:

- **Phase 1** tracks 6 dimensions focused on theme, features, dependencies, sequencing, downstream state, and scope boundaries.
- **Phase 2** uses a 4-role pool (feature completeness, dependency validation, sequencing analysis, downstream assessment) with 2-3 selected per roadmap.
- **Phase 4** uses 3 fixed jury roles (theme coherence, sequencing/dependencies, annotation/boundaries) that map directly to the roadmap format's quality guidance.

Each role and check traces back to specific quality criteria or validation rules in the roadmap SKILL.md, ensuring the jury evaluates what actually makes a roadmap good rather than applying generic document quality checks.
