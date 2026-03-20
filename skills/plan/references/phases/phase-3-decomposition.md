# Phase 3: Issue Decomposition

Break the source document into atomic issues based on effective scope and decomposition strategy.

## Table of Contents

- [Resume Check](#resume-check)
- [Prerequisites](#prerequisites)
- [Goal](#goal)
- [Input Type Branching](#input-type-branching)
- [Standard Decomposition](#standard-decomposition-input_type-design-or-prd): Strategy Decision, Scope-Aware Decomposition, Steps 3.1-3.5
- [Roadmap Decomposition](#roadmap-decomposition-input_type-roadmap): Steps 3.R1-3.R4
- [Execution Mode Selection](#execution-mode-selection-all-input-types): Step 3.6

## Resume Check

If `wip/plan_<topic>_decomposition.md` exists, read it and skip to Phase 4. The artifact contains the decomposition strategy decision and issue outlines.

## Prerequisites

Read:
- `wip/plan_<topic>_analysis.md` - Components/features and scope (includes `input_type`)
- `wip/plan_<topic>_milestones.md` - Milestone groupings
- The original source document

Parse the `Input Type` field from the analysis artifact to determine which branch to follow.

## Goal

Create issue specifications that are:
- **Atomic**: One focused deliverable per issue
- **Independent**: Can be worked on without other pending issues (except explicit blockers)
- **Complete**: Delivers working functionality, not partial implementation

## Input Type Branching

Read `input_type` from `wip/plan_<topic>_analysis.md`:

- **design** or **prd**: Follow the standard decomposition flow (steps 3.0 through 3.6)
- **roadmap**: Follow the roadmap decomposition flow (steps 3.R1 through 3.R4), then skip to step 3.6

---

## Standard Decomposition (input_type: design or prd)

### Decomposition Strategy Decision

#### 3.0 Determine Strategy

Before decomposing, decide whether to use walking skeleton or horizontal decomposition.

**Check for explicit flags** (from command arguments):
- `--walking-skeleton` -> Use walking skeleton
- `--no-skeleton` -> Use horizontal

**Check design doc frontmatter**:
```yaml
decomposition: walking-skeleton  # or: horizontal
```

**If no explicit directive**, determine based on design content:

**Walking Skeleton** - Use when:
- Design describes a new feature with clear end-to-end flow
- Design mentions "incremental refinement", "walking skeleton", or "vertical slice"
- Feature has multiple layers (CLI, core logic, output) that should integrate early
- Decomposition would produce 3+ issues

**Horizontal** - Use when:
- Design describes refactoring existing code
- Design is primarily documentation or configuration
- Design is in a strategic-scope repository
- Feature is simple enough that layer-by-layer makes sense
- Decomposition would produce only 1-2 issues

**If ambiguous**, use AskUserQuestion:
```
This design could use either decomposition strategy:

Walking Skeleton: Issue #1 creates minimal e2e flow with stubs, subsequent issues refine
Horizontal: Issues created layer-by-layer (data model, then API, then UI)

Which approach fits this design better?
```

Record your decision with rationale.

### Scope-Aware Decomposition

Use the effective scope from Context Resolution to determine decomposition approach:

#### Strategic Scope

Extract issues from the "Required Tactical Designs" section of the design document:
- Each row in the Required Tactical Designs table becomes one issue
- Issue title format: `docs(<target-repo>): design <purpose>`
- Issues get `needs-design` label
- Issues describe WHAT needs to be designed, not implementation details
- Target repo is specified in the issue body
- Issue body must include `Design: \`<parent-design-doc-path>\`` -- the path to the design doc being planned. This enables locating the parent design doc when accepting a child design.

#### Tactical Scope

Break down the "Solution Architecture" and "Implementation Approach" sections:
- Each component or distinct change becomes one issue
- Issue title format: `<type>(<scope>): <description>`
- Issues describe implementation work
- No `needs-design` label

#### Walking Skeleton Mode (Tactical Only)

If using walking skeleton decomposition:

**Issue #1 - Skeleton Issue:**
- Goal: Create minimal e2e flow with stubs
- Type: `skeleton`
- Complexity: Always `testable`
- Template: Reference `walking-skeleton-issue.md`
- Dependencies: None

**Issues #2-N - Refinement Issues:**
- Each refines one aspect of the skeleton
- Type: `refinement`
- Must include AC: "E2E flow still works"
- Dependencies: Blocked by Issue 1 (and possibly other refinements)

**Dependency Models:**
- **Serial**: Each refinement depends on previous (e.g., layer-based CLI commands)
- **Parallel after skeleton**: All refinements depend only on skeleton (e.g., independent features)

### Steps

#### 3.1 Decompose by Component

For each component from Phase 1, determine:
- Can it be a single issue?
- Should it be split into multiple issues?

**Split when:**
- Multiple independent deliverables
- Different skills/expertise needed
- Natural break points exist (skill vs command using it)

**Combine when:**
- Changes are tightly coupled
- Split would create trivial issues

#### 3.2 Draft Issue Outlines

For each issue, create an outline:

```markdown
### Issue N: <conventional-commits-title>
- **Type**: skeleton | refinement | standard
- **Complexity**: simple | testable | critical (agent will finalize)
- **Goal**: <One sentence describing what this accomplishes>
- **Section**: <Design doc section this implements>
- **Milestone**: <Milestone from Phase 2>
- **Dependencies**: None | Issue 1 | Issue 1, 2
```

#### 3.3 Validate Issue Quality

For each issue, check:
- [ ] Title follows conventional commits format
- [ ] Title uses imperative mood, lowercase
- [ ] Goal is one clear sentence
- [ ] Design section referenced
- [ ] Dependencies identified

#### 3.4 Order Issues

Arrange issues in implementation order:
1. Skeleton issue first (if walking skeleton)
2. Skills before commands that use them
3. Core functionality before extensions
4. Infrastructure before features

#### 3.5 Write Artifact

Create `wip/plan_<topic>_decomposition.md` (Write tool):

```yaml
---
design_doc: <path-to-doc>
input_type: <design|prd>
decomposition_strategy: walking-skeleton  # or: horizontal
strategy_rationale: "<one sentence explaining why this strategy>"
confirmed_by_user: false  # true if user was prompted
issue_count: <number>
execution_mode: <single-pr or multi-pr>  # set in step 3.6
---
```

```markdown
# Plan Decomposition: <doc-name>

## Strategy: <Walking Skeleton | Horizontal>

<Brief explanation of how issues will be structured>

## Issue Outlines

### Issue 1: <type>(<scope>): <title>
- **Type**: skeleton
- **Complexity**: testable
- **Goal**: <goal>
- **Section**: Solution Architecture
- **Milestone**: <milestone>
- **Dependencies**: None

### Issue 2: <type>(<scope>): <title>
- **Type**: refinement
- **Complexity**: <complexity>
- **Goal**: <goal>
- **Section**: <section>
- **Milestone**: <milestone>
- **Dependencies**: Issue 1

### Issue 3: ...
```

Then proceed to step 3.6 (Execution Mode Selection).

---

## Roadmap Decomposition (input_type: roadmap)

When the source document is a roadmap, skip the strategy selection step entirely.
Roadmaps use a fixed "feature-by-feature planning" strategy that maps each feature
1:1 to a planning issue. These are not code-level issues -- they're issues that
track the creation of upstream artifacts (PRDs, designs, spikes, decisions).

### 3.R1 Map Features to Planning Issues

For each feature in the analysis artifact's "Features Identified" section:

1. Create one planning issue per feature
2. Issue title format: `docs(<scope>): <feature-name>`
   - `<scope>` reflects what the feature needs (e.g., `prd`, `design`, `spike`, `decision`)
3. Carry the `needs_label` from the analysis artifact onto the issue outline
4. All planning issues are classified as `simple` complexity (they produce artifacts,
   not code)
5. Type: `planning`

**Example mapping:**

| Feature | needs_label | Issue Title |
|---------|-------------|-------------|
| User authentication | needs-prd | `docs(prd): user authentication` |
| Plugin architecture | needs-design | `docs(design): plugin architecture` |
| WebSocket performance | needs-spike | `docs(spike): WebSocket performance` |

### 3.R2 Preserve Roadmap Dependencies

Copy feature dependencies from the analysis artifact's "Cross-Feature Dependencies"
section. These become issue-level dependencies:

- Hard dependencies (technical blockers from Sequencing Rationale) become `Blocked by`
  edges
- Soft dependencies (ordering preferences) become notes in the issue outline, not
  hard blockers

Phase 5 will refine these further.

### 3.R3 Validate Planning Issues

For each planning issue, check:
- [ ] Title follows `docs(<scope>): <feature-name>` format
- [ ] `needs_label` is a valid label from your project's label vocabulary (see `## Label Vocabulary` in your CLAUDE.md)
- [ ] Goal references the feature from the roadmap
- [ ] Dependencies match the roadmap's Sequencing Rationale

### 3.R4 Write Artifact

Create `wip/plan_<topic>_decomposition.md` (Write tool):

```yaml
---
design_doc: <path-to-roadmap>
input_type: roadmap
decomposition_strategy: feature-by-feature-planning
strategy_rationale: "Roadmap features map 1:1 to planning issues with per-feature needs-* labels"
confirmed_by_user: false
issue_count: <number>
execution_mode: <single-pr or multi-pr>  # set in step 3.6
---
```

```markdown
# Plan Decomposition: <roadmap-name>

## Strategy: Feature-by-Feature Planning

Each roadmap feature becomes one planning issue. Issues track the creation of upstream
artifacts (PRDs, designs, spikes, decisions) rather than code-level implementation.

## Issue Outlines

### Issue 1: docs(<scope>): <feature-name>
- **Type**: planning
- **Complexity**: simple
- **Goal**: <Produce the required upstream artifact for this feature>
- **Feature**: <Feature name from roadmap>
- **needs_label**: <needs-prd|needs-design|needs-spike|needs-decision>
- **Milestone**: <milestone>
- **Dependencies**: None | Issue N

### Issue 2: docs(<scope>): <feature-name>
- **Type**: planning
- **Complexity**: simple
- **Goal**: <goal>
- **Feature**: <Feature name from roadmap>
- **needs_label**: <needs-prd|needs-design|needs-spike|needs-decision>
- **Milestone**: <milestone>
- **Dependencies**: Issue 1

### Issue 3: ...
```

Then proceed to step 3.6 (Execution Mode Selection).

---

## Execution Mode Selection (All Input Types)

### 3.6 Execution Mode Selection

After writing the decomposition artifact, evaluate the decomposition to recommend an execution mode. The execution mode determines how subsequent phases produce artifacts: single-pr mode yields lighter outlines and a PLAN doc, while multi-pr mode produces full issue bodies and GitHub milestone+issues.

#### Heuristic Signals: multi-pr

| Signal | Strength |
|--------|----------|
| Cross-repo changes mentioned in design | Strong |
| CI/CD dependencies (merge-then-trigger patterns) | Strong |
| Multiple independently-shippable features | Moderate |
| Design specifies sequential deployment steps | Moderate |
| Roadmap input (planning issues need GitHub tracking) | Moderate |

#### Heuristic Signals: single-pr

| Signal | Strength |
|--------|----------|
| All changes in one repo | Moderate |
| No merge gates between steps | Strong |
| Linear sequence with shared branch possible | Moderate |
| Issue count <= ~8 | Weak (suggestive, not decisive) |

#### Procedure

1. Scan the decomposition artifact for the signals above.
2. Tally signal strengths. A single Strong signal toward either mode outweighs multiple Weak/Moderate signals for the opposite mode.
3. Formulate a recommendation with a one-sentence rationale.
4. Present the recommendation to the user using AskUserQuestion:

```
Based on the decomposition, I recommend **<single-pr|multi-pr>** execution mode.

Reasoning: <one-sentence rationale citing the strongest signal(s)>

- **single-pr**: Phase 4 agents produce lighter structured outlines. Phase 7 writes a PLAN doc without GitHub artifacts.
- **multi-pr**: Phase 4 agents produce full issue bodies. Phase 7 creates a GitHub milestone and issues.

Use <recommended mode>, or override?
```

5. Record the user's selection in the decomposition artifact's YAML frontmatter:

```yaml
execution_mode: single-pr  # or multi-pr
```

If the frontmatter was already written in step 3.5 or 3.R4 with a placeholder, update the file to reflect the confirmed mode.

## Quality Checklist

Before proceeding:
- [ ] Decomposition strategy decided and recorded (or "feature-by-feature-planning" for roadmaps)
- [ ] All components (design/prd) or features (roadmap) covered by issues
- [ ] Each issue is atomic and complete
- [ ] Titles follow appropriate format (conventional commits for design/prd, `docs(<scope>):` for roadmap)
- [ ] For roadmaps: each issue has a valid `needs_label`
- [ ] Issues roughly ordered
- [ ] Execution mode selected and recorded in YAML frontmatter
- [ ] `wip/plan_<topic>_decomposition.md` written with YAML frontmatter

## Next Phase

Proceed to Phase 4: Agent Generation (`phase-4-agent-generation.md`)
