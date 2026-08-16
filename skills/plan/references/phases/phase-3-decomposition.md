# Phase 3: Issue Decomposition

Break the source document into atomic issues based on effective scope and decomposition strategy.

This phase carries two separately named decisions:

- **Decomposition strategy** (walking skeleton vs horizontal vs feature-by-feature
  planning) -- this phase's primary decision, made in step 3.0 (or fixed by input
  type for roadmaps). Governs how issues are shaped against the design.
- **Execution mode** (single-pr vs multi-pr) -- finalized in step 3.6 against the
  surfaced rule on the plan SKILL surface, after the value-confirmation guard in
  step 3.5a has checked each unit. Governs how the resulting work lands.

The two decisions are independent and must not be conflated: a walking-skeleton
decomposition can land single-pr or multi-pr; a horizontal decomposition can land
either; the choice of one doesn't force the other. The work-slicing question is
"how do we cut this against the design?"; the execution-mode question is "how does
this land as PRs?"

## Table of Contents

- [Resume Check](#resume-check)
- [Prerequisites](#prerequisites)
- [Goal](#goal)
- [Input Type Branching](#input-type-branching)
- [Standard Decomposition](#standard-decomposition-input_type-design-or-prd): Strategy Decision, Scope-Aware Decomposition, Steps 3.1-3.5
- [Roadmap Decomposition](#roadmap-decomposition-input_type-roadmap): Steps 3.R1-3.R4
- [Value Confirmation](#value-confirmation-all-input-types): Step 3.5a
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

### Decomposition Strategy Decision (separate from execution mode)

This is the work-slicing decision: walking skeleton vs horizontal. It is named
explicitly here as separate from the single-pr/multi-pr execution-mode decision
finalized in step 3.6 -- the two are different questions and must not be
conflated.

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

**If ambiguous**, use AskUserQuestion, following the pattern in
`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`. Recommend the strategy
whose criteria the design matches on more counts, and cite the specific design
content behind each match:
```
This design could use either decomposition strategy. I recommend
**<Walking Skeleton|Horizontal>**: <one sentence citing the design content that
decided it -- the layers it names, the refactor it describes, the issue count the
decomposition produces>.

Walking Skeleton (Recommended): Issue #1 creates minimal e2e flow with stubs, subsequent issues refine
Horizontal: Issues created layer-by-layer (data model, then API, then UI)
  -- ranks lower here because <reason>

Use <recommended strategy>, or override?
```

If the design matches both lists equally, say so, still recommend one, and name
the tiebreaker (issue count is the usual one: 3+ issues favors walking skeleton,
1-2 favors horizontal).

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

#### 3.1a Docs-Coverage Emit (user-visible surface)

After component decomposition, determine whether the source adds user-visible
surface and, when it does, ensure the decomposition carries documentation work.
This guarantee is owned by `/plan` because it is the only layer that reads the
full design body (where the signal lives) and produces the issue set (where a
docs item can be added). `/execute` carries no equivalent content gate -- its
inspection contract is metadata-only.

**Detection contract** (two-step, flag-authoritative + prose fallback):

1. If the source's frontmatter has `user_visible_surface: true` ->
   user-visible surface is **present** (authoritative).
2. Else if `user_visible_surface` is **absent** AND the source body references
   a `docs/guides/*` path -> user-visible surface is **present** (prose
   fallback, for designs authored before the field existed).
3. Else (`user_visible_surface: false`, or absent with no `docs/guides/*`
   reference) -> **no** user-visible surface; skip the emit.

The flag is authoritative: an explicit `user_visible_surface: false` ends the
check and the prose fallback is NOT consulted. The fallback runs only when the
field is absent. This applies to design and PRD inputs; topic inputs have no
frontmatter to read, so they fall through to "no signal -> skip" and docs
coverage falls to author judgment.

**Emit rule.** When user-visible surface is present, the decomposition MUST
include at least one issue whose work covers the user-facing documentation --
either a dedicated `**Type**: docs` issue, or an explicit docs deliverable
folded into a covering issue's acceptance criteria. The `**Type**: docs`
annotation rides the existing machinery: `plan-to-tasks.sh` maps it to
`ISSUE_TYPE=docs` and `/work-on` routes it to the docs path; no new routing is
introduced. Record which issue carries docs coverage in the decomposition
artifact (step 3.5). When no user-visible surface is detected, do not force a
docs item.

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

Then proceed to step 3.5a (Value Confirmation), and on from there to step 3.6
(Execution Mode Selection).

---

## Roadmap Decomposition (input_type: roadmap)

When the source document is a roadmap, skip the strategy selection step entirely.
Roadmaps use a fixed "feature-by-feature planning" strategy that maps each feature
1:1 to a planning issue. These are not code-level issues -- they're issues that
track the creation of upstream artifacts (PRDs, designs, spikes, decisions).

A roadmap input also lands multi-pr at step 3.6 -- not because the input is a
roadmap, but because each feature is a cohesive deliverable that lands observable
incremental value on its own (the usable-value principle on the plan SKILL
surface). The value-confirmation guard at step 3.5a then checks each feature
against that standard; a feature that isn't a standalone increment is flagged as a
mis-decomposition by name, not waved through.

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

Then proceed to step 3.5a (Value Confirmation), and on from there to step 3.6
(Execution Mode Selection).

---

## Value Confirmation (All Input Types)

### 3.5a Value Confirmation

After writing the decomposition artifact and before finalizing the execution mode
(step 3.6), confirm each unit delivers observable incremental value on its own.
This is the value-confirmation guard the surfaced rule on the plan SKILL surface
points at; it implements the usable-value principle (P1) in
`${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md`.

#### What the guard checks

For each unit, evaluate the question **"if this unit landed alone, would a reader
observe value, or only a building block someone has to wait on?"**

The unit depends on input type:

- **Roadmap input.** Each feature is a unit. The feature passes if, landed on its
  own, a reader of the roadmap or its downstream artifacts observes value (a usable
  feature, a shipped capability, a deliverable).
- **Plan input (design or PRD or topic) the author intends to split.** Each
  PR-shaped unit is a unit. The unit passes if, landed on its own, a reader of the
  PR observes value -- not "step 3 of 5" or "the parser before the validator," but
  a usable, reviewable, end-to-end increment. A plan the author intends to land in
  a single PR has one unit (the whole plan) and that unit passes by construction.

Apply this check whether or not a hard constraint also forces the split. A hard
constraint can force multi-pr without overriding the value question; both
justifications can hold (the spike-before-reconciliation gate AND each PR landing
value). What the guard refuses to wave through is multi-pr by mechanism alone
("could be separate PRs," "the input is a roadmap") with no value rationale.

#### Three outcomes

For each unit, classify into one of three buckets:

1. **Pass.** Clear standalone increment. State the value it lands in one sentence
   for the record.
2. **Ambiguous.** The guard cannot clearly classify the unit either way -- the
   value the unit lands depends on context the guard doesn't have, or two readers
   could reasonably disagree.
3. **Fail.** Not a standalone increment. The unit is a building block, a partial
   step, or otherwise depends on a later unit to land observable value. Name the
   specific unit and the reason it failed the value test.

#### Interactive mode

Present each non-passing unit to the user via AskUserQuestion with the reason and
the recommended action (re-scope the unit or merge with a neighbor). A failing
unit is a flagged mis-decomposition: the author confirms a re-scope, accepts the
unit as-is despite the flag, or returns to step 3.1 / 3.R1 to redo the
decomposition. The guard never silently passes a failing unit.

#### --auto mode

Under `--auto` the guard does not hard-stop. Per
`${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md`, write a decision block
per unit into the decomposition artifact and append an entry to
`wip/plan_<topic>_decisions.md`:

- **Pass** -> `status="confirmed"`. The block records the value the unit lands.
- **Ambiguous** -> `status="assumed"` at high review priority.
- **Fail** -> `status="assumed"` at high review priority. Both non-pass outcomes
  route to the same recorded outcome on purpose: both are units the author must
  review, neither is waved through.

High review priority surfaces in the terminal summary at the end of the run and
in the PR body (per
`${CLAUDE_PLUGIN_ROOT}/references/decision-block-format.md`). The block names the
unit and the reason. Then continue to step 3.6.

If the decision is judged practically irreversible (a rare case), the escalation
path remains: write `status="escalated"` and spawn `/decision`. Escalation is
itself non-blocking under `--auto` -- `/decision` records its result and the run
continues.

#### Quality checklist

Before proceeding to step 3.6:

- [ ] Every unit (every feature for a roadmap, every PR-shaped unit for a split
      plan) classified as pass / ambiguous / fail
- [ ] Every fail and every ambiguous unit named with its reason
- [ ] Under interactive mode: every non-pass unit reviewed by the author
- [ ] Under `--auto`: every non-pass unit recorded as a high-review-priority
      `assumed` block in `wip/plan_<topic>_decisions.md`

---

## Execution Mode Selection (All Input Types)

### 3.6 Execution Mode Selection

After the value-confirmation guard (step 3.5a) has classified each unit, finalize
the execution mode against the surfaced rule on the plan SKILL surface. The
SKILL-surface rule is the authoritative statement; this section is the procedure
for applying it.

**The surfaced rule** (`skills/plan/SKILL.md`, section "Execution Mode Decision"):

- Default to as few PRs as the repository's resolved Delivery Preference permits;
  `consolidated` (the default) means single-pr.
- Escape only on a named branch from the plan profile of
  `${CLAUDE_PLUGIN_ROOT}/references/split-triggers.md`: **Hard Constraint**,
  **Incremental Value**, or **Stated Preference**.
- A roadmap input is multi-pr under Incremental Value, because each feature is a
  cohesive deliverable that lands observable value -- the value principle, not the
  input mechanism.

The branch this step selects is not bookkeeping: it is written into the produced
PLAN's `split_rationale` frontmatter field and checked by `L09`, so a step that
recommends a mode without naming its branch leaves the plan unable to satisfy that
check.

#### Procedure

1. **Check the surfaced rule.** Read the rule on `skills/plan/SKILL.md` and apply
   it to this decomposition.
2. **Read the value-guard output (step 3.5a).** Every unit passed cleanly, or
   some were recorded as `assumed` (failing or ambiguous).
3. **Resolve the Delivery Preference** on the `flag > CLAUDE.md ## Delivery
   Preference: header > consolidated` stack. This is the default the next step
   departs from, so it is resolved before a mode is recommended, not after.
4. **Recommend a mode, and select the branch that produced it.** Every
   non-default outcome carries exactly one branch name:
   - **Roadmap input** -> multi-pr, branch **Incremental Value** (each feature is
     a cohesive deliverable, per the surfaced rule).
   - **Plan input with a named hard constraint** (cross-repo, merge gate between
     steps, a workflow that must reach the default branch before it can be
     invoked) -> multi-pr, branch **Hard Constraint**, with the constraint named.
   - **Plan input with each PR independently useful** -> multi-pr, branch
     **Incremental Value**, with the rationale stated.
   - **Plan input under an `atomic` preference whose decomposition permits a
     split** -> multi-pr, branch **Stated Preference**. Do not restate this as an
     incremental-value claim; the branch exists so the real reason can be given.
   - **Plan input under `consolidated`, no branch fires** -> single-pr, no branch,
     no record.
   - **Plan input under `atomic` that stays single-pr anyway** -> single-pr, but
     it departed from the preference, so it still owes a branch naming why.
5. **Record the selected branch** in the decomposition artifact's frontmatter
   alongside `execution_mode`, so Phase 7 can write it into the PLAN's
   `split_rationale` without re-deriving the judgment:

   ```yaml
   execution_mode: multi-pr
   split_branch: Hard Constraint
   split_rationale: |
     Hard Constraint. The reusable workflow added in unit 1 must reach the
     default branch before unit 2's workflow_dispatch invocation resolves.
   ```

   Omit both fields when the outcome is `single-pr` under `consolidated` — the
   no-branch case records nothing.

6. **Present the recommendation to the user using AskUserQuestion** (interactive
   mode):

```
Based on the decomposition and the value-confirmation guard, I recommend
**<single-pr|multi-pr>** execution mode.

Reasoning: <one-sentence rationale citing the branch that fired -- Hard
Constraint, Incremental Value, or Stated Preference -- or the default>

- **single-pr**: the work lands in one pull request. Phase 4 agents produce
  lighter structured outlines.
- **multi-pr**: the work lands in several. Phase 4 agents produce full issue
  bodies.

This choice is about how the code lands, not about what gets tracked on
GitHub. The resolved tracking level decides whether Phase 7 files issues and
a milestone, and it is a separate question asked separately.

Use <recommended mode>, or override?
```

7. **Under `--auto`** follow the recommendation and record a `confirmed` decision
   block in `wip/plan_<topic>_decisions.md` if the rationale is clear, or
   `assumed` at high review priority if multi-pr was chosen without a hard
   constraint or a clear incremental-value rationale for every unit.

8. **Record the confirmed selection** in the decomposition artifact's YAML
   frontmatter:

```yaml
execution_mode: single-pr  # or multi-pr
```

If the frontmatter was already written in step 3.5 or 3.R4 with a placeholder,
update the file to reflect the confirmed mode.

Step 5 wrote the branch fields against the *recommendation*. If the user
overrode it here, those fields are now stale and must be brought in line with
what was confirmed: an override to `single-pr` under `consolidated` removes
`split_branch` and `split_rationale`, and an override that keeps a split still
owes the branch that justifies the mode actually chosen. Leaving a rationale
behind that argues for a mode the plan no longer uses is the failure `L09` is
least able to catch -- the field is present and names a branch, so the check
passes while the document misleads.

#### No mode-scoped prerequisite check runs here

This step is where a skill with mode-scoped tool requirements would verify
them -- the load-time check evaluates only the `always` records in
`skills/<name>/requires.tsv`, because at load the mode has not been chosen, and
this is the step that chooses it. `/plan` makes no such call, and the reason is
recorded here rather than left as an absence a later reader has to re-derive:

**`skills/plan/requires.tsv` carries no `mode:` record, and correctly so.**
Every record in it is `always`. `gh` is always-required because Resume Logic
searches for existing issues with `gh issue list --search` on every run, before
the execution mode is known -- so multi-pr cannot be what makes `gh` needed.
Phase 7 does reach more `gh` subcommands (issue creation, labelling, milestone
work), but the mode is not what takes it there -- the resolved tracking level
is, and a `multi-pr` PLAN at `tracking_level: none` reaches none of them while a
`single-pr` PLAN at `issues` reaches all but the milestone. Either way `gh` has
an independent release cadence, so its record names the tool alone and is
satisfied identically. The rest -- `shirabe transition`, `shirabe validate`,
`jq`, `git` -- back scripts and steps every run reaches.

A mode-scoped record exists only where a mode changes which tool is needed, or
changes a first-party subcommand or flag. Neither happens here, so there is
nothing for a `--mode multi-pr` run to evaluate and no call to make. The rule
is in `${CLAUDE_PLUGIN_ROOT}/references/tool-declaration-policy.md` under
"Verifying a mode-scoped record"; if a future change gives multi-pr a tool or a
first-party subcommand that single-pr doesn't need, the record and the call both
land here in the same change.

## Quality Checklist

Before proceeding:
- [ ] Decomposition strategy decided and recorded (or "feature-by-feature-planning" for roadmaps)
- [ ] All components (design/prd) or features (roadmap) covered by issues
- [ ] Docs-coverage emit (step 3.1a) evaluated: when the source signals
      user-visible surface, an issue carries docs coverage and is recorded in
      the artifact; when it does not, no docs item is forced
- [ ] Each issue is atomic and complete
- [ ] Value-confirmation guard (step 3.5a) ran and classified every unit
- [ ] Execution mode finalized against the SKILL-surface rule, with rationale recorded

## Next Phase

Proceed to Phase 4: Agent Generation (`phase-4-agent-generation.md`)
