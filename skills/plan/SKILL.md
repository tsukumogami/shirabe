---
name: plan
description: Implementation planning skill. Decomposes a design doc, PRD, roadmap, or directly-stated
  topic into atomic, sequenced issues with dependency graphs and complexity classifications.
  Use when given a DESIGN-*.md, PRD-*.md, or ROADMAP-*.md to plan, or when the user says "break
  this into issues", "plan the implementation", "create issues for this", "decompose this",
  "what tasks do we need", or "make a plan for X". Also use for direct topic planning without
  a source document. Produces either a self-contained PLAN doc (single-pr) or GitHub milestone
  and issues (multi-pr).
argument-hint: '<doc-path-or-topic> [--walking-skeleton|--no-skeleton] [--strategic|--tactical]'
---

@.claude/shirabe-extensions/plan.md
@.claude/shirabe-extensions/plan.local.md

# Plan Skill

Plans turn accepted designs into implementable work. They define the decomposition
strategy, issue sequencing, and dependency graph that guide implementation through
/work-on. When planning a roadmap, the output is planning issues
(one per feature) rather than code-level issues.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## PLAN Doc Structure

Plans live at `docs/plans/PLAN-<topic>.md`. See the full specification at
`references/quality/plan-doc-structure.md`.

Quick summary of required sections:

1. **Status** -- Draft, Active, or Done
2. **Scope Summary** -- 1-2 sentences on what the plan covers
3. **Decomposition Strategy** -- walking skeleton vs horizontal, with rationale
4. **Issue Outlines** -- structured outlines in single-pr mode
5. **Implementation Issues** -- issue table with links in multi-pr mode
6. **Dependency Graph** -- Mermaid diagram showing issue relationships
7. **Implementation Sequence** -- critical path and parallelization opportunities

Frontmatter includes `schema: plan/v1`, `status`, `execution_mode` (single-pr or
multi-pr), `milestone`, and `issue_count`. Optional `upstream` links to the source
document (design doc, PRD, or roadmap).

PLANs are ephemeral: when the work completes, the PLAN file is deleted
from the tree in the same commit set that transitions the upstream
BRIEF, PRD, and DESIGN to their terminal states. There is no
`docs/plans/done/` directory in the current lifecycle model — the
verify-then-delete terminal is the single forcing function. The
chain-aware `--lifecycle` check (`shirabe validate --lifecycle .`)
enforces this; the work-on cascade performs the atomic deletion
before `gh pr ready` fires (the DRAFT-vs-READY discipline). See
`docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md`
and `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`
for the strict-mode CLI flag and the cascade trigger rationale.

## Decomposition Strategies

### Walking Skeleton

A thin vertical slice that exercises the full pipeline end-to-end, followed by issues
that thicken each layer. Use walking skeleton when:

- The design spans multiple components that interact at runtime
- Integration risk is high (new APIs, new data flows, new infrastructure)
- Early feedback on the end-to-end path is more valuable than component depth
- The `--walking-skeleton` flag is passed

The skeleton issue comes first in the dependency graph. All thickening issues depend
on it. This forces integration problems to surface early.

### Horizontal Decomposition

Layer-by-layer implementation where each issue builds one component fully before
moving to the next. Use horizontal when:

- Components have clear, stable interfaces between them
- One component is a prerequisite for all others (parser before validator)
- The design describes independent modules with minimal runtime interaction
- The `--no-skeleton` flag is passed

Default behavior when neither flag is set: evaluate the design's component coupling.
Tightly coupled components with unclear interfaces favor walking skeleton. Loosely
coupled components with well-defined boundaries favor horizontal.

### Feature-by-Feature Planning (Roadmaps Only)

When the input is a roadmap (`input_type: roadmap`), the decomposition strategy is
fixed. Each feature in the roadmap becomes one planning issue. No strategy selection
step runs -- walking skeleton and horizontal don't apply to roadmap decomposition
because the issues track artifact creation rather than code implementation.

Planning issues are always `simple` complexity and carry a `needs_label` (needs-prd,
needs-design, needs-spike, or needs-decision) indicating what upstream artifact the
feature requires.

## Execution Mode Decision (single-pr vs multi-pr)

This is a separate decision from the Decomposition Strategy above. Work-slicing
(walking skeleton vs horizontal) chooses how issues are shaped against the design;
execution mode chooses how the resulting work lands. Don't conflate the two: the
shape of the work and the shape of the delivery are different questions.

**Default: single-pr.** Reach for one PR. Anchored on principle P1 (usable value
is the unit of work) in
`${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md` -- every PR delivers
observable value on its own, and one PR is the lowest-ceremony shape that clears
that bar.

**Escape to multi-pr only when a named condition forces it:**

1. **A hard constraint forces multiple PRs.** Cross-repo landing order; a workflow
   that must reach main before it can be invoked; a merge gate between steps. The
   constraint must be named in the PLAN doc.
2. **Each PR is independently useful.** The split delivers genuine incremental
   value: every PR-shaped unit lands observable value on its own, not just a
   building block someone has to wait on. "Could be separate PRs" is not the test;
   "each PR is independently useful to a reader" is.

A roadmap input is always multi-pr -- not because the input is a roadmap, but
because each feature is a cohesive deliverable that lands observable incremental
value on its own (P1 again). The mechanism "the input is a roadmap" is not the
reason; the value the feature delivers is.

The value-confirmation step (Phase 3.5a) then checks each unit -- every feature for
a roadmap, each PR-shaped unit for a plan whose split delivers incremental value --
and can fail. A unit that isn't a standalone increment is named as a
mis-decomposition with the reason, not waved through. Under `--auto` the guard
records a decision block per `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md`
and continues; it never hard-stops. See `references/phases/phase-3-decomposition.md`
step 3.5a for the guard's procedure and step 3.6 for the mode finalization that
consumes the guard's output.

## Complexity Classification

Each issue gets a complexity (simple, testable, or critical) that determines its
acceptance criteria template. Assign during Phase 3; see `references/phases/phase-3-decomposition.md`
for the full criteria and AC templates.

## Placeholder Conventions

During decomposition, issues reference each other before GitHub numbers exist.
Use `<<ISSUE:N>>` placeholders where N is the local sequence number (1-based).

```
<<ISSUE:1>> -- first issue in the decomposition
<<ISSUE:2>> -- second issue, might depend on <<ISSUE:1>>
```

Phase 7 replaces these with actual GitHub issue numbers after creation. In single-pr
mode, placeholders map to outline headings in the PLAN doc's Issue Outlines section.

## Validation Rules by Consumer Phase

See `references/quality/consumer-validation-rules.md` for validation rules that consuming skills must apply to PLAN artifacts.

---

## Planning Workflow

When invoked as `/plan`, this skill drives decomposition of a source document into
implementable issues. The source can be a design doc, PRD, or roadmap. The workflow
produces either GitHub artifacts (multi-pr) or a self-contained PLAN document
(single-pr), depending on execution mode. Roadmaps produce planning issues (one per
feature) rather than code-level issues.

### Input Detection

From `$ARGUMENTS` (after stripping flags):

1. **Empty** -- ask the user what to plan (document path or topic)
2. **Path matching a known pattern** -- use it as the source document:
   - `docs/designs/DESIGN-*.md` -- design doc (input_type: design)
   - `docs/prds/PRD-*.md` -- PRD (input_type: prd)
   - `docs/roadmaps/ROADMAP-*.md` -- roadmap (input_type: roadmap)
3. **Anything else** -- treat as a direct topic (input_type: topic). No upstream
   document is required. Use when /explore produced a clear scope with no open
   decisions, or when planning a well-understood list of capabilities directly.

Store the detected `input_type` in the Phase 1 analysis artifact -- it gates
branching behavior in Phases 1, 3, and downstream phases.

### Context Resolution

#### 1. Parse Flags

Check `$ARGUMENTS` for flags before extracting the document path:

**Execution mode flags:**
- `--auto` -- non-interactive execution; follow `references/decision-protocol.md`
  at all decision points; create `wip/plan_<topic>_decisions.md`
- `--interactive` -- force interactive (default)

If no mode flag, read CLAUDE.md `## Execution Mode:` header.

**Scope flags:**
- `--strategic` -- force strategic scope
- `--tactical` -- force tactical scope

**Decomposition flags:**
- `--walking-skeleton` -- force walking skeleton decomposition
- `--no-skeleton` -- force horizontal decomposition

If conflicting flags are present (e.g., both `--strategic` and `--tactical`), error
and ask user to pick one. Remove flags from arguments before using the remainder as
the document path.

#### 2. Detect Visibility

Read the repo's CLAUDE.md (or CLAUDE.local.md) and look for:
```
## Repo Visibility: Private
```
or
```
## Repo Visibility: Public
```

If not found, infer from repo path:
- `private/` in path -- Private
- `public/` in path -- Public
- Unknown -- default to Private (safer)

Visibility is immutable -- public repos must never accidentally include private
references. Flags can't override it.

After detecting visibility, load the appropriate content governance skill:
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

#### 3. Detect Default Scope

If no scope flag was provided, read default from CLAUDE.md:
```
## Default Scope: Strategic
```
or
```
## Default Scope: Tactical
```

If not found, default to Tactical.

#### 4. Determine Effective Scope

```
Effective Scope = Flag Override (if present) OR Default Scope
```

#### 5. Log Effective Context

Output before proceeding:
```
Planning in [Strategic|Tactical] scope with [Private|Public] visibility...
```

### Handoff Validation

Only plan documents with the right status: Accepted designs/PRDs, Active roadmaps.
Phase 1 (`references/phases/phase-1-analysis.md`) has the full validation table
with error messages per status. Direct topics skip status validation.

### Resume Logic

Resume is based on topic-scoped wip/ artifacts. Topic is derived from the source
document filename: `DESIGN-foo-bar.md` produces topic `foo-bar`, `ROADMAP-foo-bar.md`
produces topic `foo-bar`.

```
parent_orchestration sentinel in wip/scope_<topic>_state.md or wip/charter_<topic>_state.md
                                              -> see references/fixes/sub-agent-dispatch.md
if GitHub issues exist for this design        -> Resume at Phase 7 (verify/complete)
if wip/plan_<topic>_review.md exists          -> Resume at Phase 7
if wip/plan_<topic>_dependencies.md exists    -> Resume at Phase 6
if wip/plan_<topic>_manifest.json exists      -> Resume at Phase 5
if wip/plan_<topic>_decomposition.md exists   -> Resume at Phase 4
if wip/plan_<topic>_milestones.md exists      -> Resume at Phase 3
if wip/plan_<topic>_analysis.md exists        -> Resume at Phase 2
else                                          -> Start at Phase 1
```

Phase 0 detection: if the parent-chain sentinel is present in
`wip/scope_<topic>_state.md` (tactical) or `wip/charter_<topic>_state.md`
(strategic), see `references/fixes/sub-agent-dispatch.md` for the
fallback shape that applies. Behavior under direct invocation is
unchanged when the sentinel is absent.

To check for existing GitHub issues:
```bash
gh issue list --search "Design: <design-doc-path>" --json number,title,state
```

For roadmap input, populating the roadmap's reserved Implementation Issues
and Dependency Graph sections is owned by `/roadmap populate` (which calls
the `shirabe roadmap populate` subcommand), not by this workflow. The plan
workflow accepts a roadmap as input when the author wants a PLAN document
for a roadmap-scoped slice; it no longer rewrites the roadmap document
itself.

When resuming, read the existing artifact to restore context before continuing.

### Workflow Phases

Seven sequential phases, plus an execution mode selection between Phases 3 and 4.

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 1. Analysis | Understand source document scope and components/features | `wip/plan_<topic>_analysis.md` |
| 2. Milestone | Derive milestone from source document | `wip/plan_<topic>_milestones.md` |
| 3. Decomposition | Break into atomic issues | `wip/plan_<topic>_decomposition.md` |
| 3.5a. Value Confirmation | Check each unit delivers observable incremental value; can fail | Recorded in decomposition artifact (and `wip/plan_<topic>_decisions.md` under `--auto`) |
| 3.5. Execution Mode | Select single-pr or multi-pr mode | Recorded in decomposition artifact |
| 4. Generation | Generate rich issue bodies via agents | `wip/plan_<topic>_issue_*.md` + `wip/plan_<topic>_manifest.json` |
| 5. Dependencies | Sequence tasks, identify blockers | `wip/plan_<topic>_dependencies.md` |
| 6. Review | AI validates completeness + sequencing | `wip/plan_<topic>_review.md` |
| 7. Creation | Create PLAN doc (+ optional GitHub artifacts) | `docs/plans/PLAN-<topic>.md` |

#### Value Confirmation and Execution Mode Selection (between Phase 3 and Phase 4)

After decomposition completes, the workflow runs the value-confirmation guard (step
3.5a) and then finalizes the execution mode (step 3.6). The guard checks each unit
delivers observable incremental value -- every feature for a roadmap, each PR-shaped
unit for a plan whose split delivers incremental value -- and can fail, naming any
mis-decomposed unit and the reason it failed the value test. The mode finalization
then chooses single-pr or multi-pr based on the surfaced rule above.

Under `--auto`, the guard records a decision block per
`${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` (`confirmed` on a clear pass,
`assumed` at high review priority on a failing or ambiguous unit) and continues; it
never hard-stops. The selection logic, the guard procedure, and the heuristic signals
are defined in the Phase 3 reference file.

- **single-pr**: Phase 4 agents produce structured outlines (not full issue bodies).
  Phase 7 writes them into the PLAN doc's Issue Outlines section. No GitHub issues or
  milestone created. PLAN status stays at Draft.
- **multi-pr**: Phase 4 agents produce full issue body files. Phase 7 creates GitHub
  milestone and issues, populates Implementation Issues table. PLAN status set to Active.

### Phase Execution

Execute phases sequentially by reading the corresponding phase file. Use the effective
scope from Context Resolution throughout.

1. **Analysis**: Understand source document scope and components/features
   - Read: `references/phases/phase-1-analysis.md`
   - Artifact: `wip/plan_<topic>_analysis.md`

2. **Milestone**: Derive milestone from source document
   - Read: `references/phases/phase-2-milestone.md`
   - Artifact: `wip/plan_<topic>_milestones.md`

3. **Decomposition**: Break into atomic issues, then value confirmation (3.5a) + execution mode selection (3.6)
   - Read: `references/phases/phase-3-decomposition.md`
   - Artifact: `wip/plan_<topic>_decomposition.md` (includes value-guard result and execution mode decision)

4. **Generation**: Generate rich issue bodies via parallel agents
   - Read: `references/phases/phase-4-agent-generation.md`
   - Artifact: `wip/plan_<topic>_issue_*.md` + `wip/plan_<topic>_manifest.json`

5. **Dependencies**: Map issue dependencies and sequencing
   - Read: `references/phases/phase-5-dependencies.md`
   - Artifact: `wip/plan_<topic>_dependencies.md`

6. **Review**: AI validates completeness, sequencing, and complexity assignments
   - Read: `references/phases/phase-6-review.md`
   - Artifact: `wip/plan_<topic>_review.md`

7. **Creation**: Create PLAN doc and optional GitHub artifacts
   - Read: `references/phases/phase-7-creation.md`
   - Artifact: `docs/plans/PLAN-<topic>.md`
   - multi-pr: GitHub milestone + issues
   - single-pr: PLAN doc with Issue Outlines, no GitHub artifacts
   - Design doc status transitions: Accepted -> Planned (status field only, no body edits); skip for topic input
   - Cleanup: delete `wip/plan_<topic>_*.md` and `wip/plan_<topic>_*.json` files

### Critical Requirements

- **Atomic Issues**: each issue should be independent and completable in one session
- **Topic Scoping**: all wip/ artifacts include `<topic>` in the filename
- **Input Type**: store the detected `input_type` in the Phase 1 analysis artifact -- it gates branching in subsequent phases

### Output

Final artifacts depend on execution mode:

**multi-pr mode (design/prd/topic input):**
- `docs/plans/PLAN-<topic>.md` with status Active
- GitHub milestone (1:1 with the plan)
- GitHub issues with complexity labels, acceptance criteria, and milestone assignment
- Source design doc status updated to "Planned"

**multi-pr mode (roadmap input):**
- Roadmap enriched directly -- Implementation Issues table and Dependency Graph
  written into the roadmap's reserved sections (no separate PLAN doc)
- GitHub milestone + per-feature planning issues with `needs-*` labels
- Table uses `Feature | Issues | Dependencies | Status` format from `roadmap-format.md`
- Roadmap stays Active (no status transition)

**single-pr mode:**
- `docs/plans/PLAN-<topic>.md` with status Draft
- Issue Outlines section populated with structured outlines (goal, AC, dependencies)
- No GitHub issues or milestone created
- Source design doc status updated to "Planned"
- Not available for roadmap input (roadmap mode is always multi-pr)

### Begin

1. Parse flags from arguments
2. Detect input type from path pattern (design, prd, roadmap, or topic)
3. If document input: read the source document and verify status
4. If topic input: proceed without a source document
5. Resolve context (visibility and scope)
6. Check for existing artifacts (resume logic)
7. Start at appropriate phase

---

## Team Shape

`/plan`'s team shape is declared in [`team.yaml`](./team.yaml) as the
machine-readable contract surface. The child layer spawns one worker
peer role: `decomposer` (worker, upper_bound 20, phase-4-agent-
generation), one decomposer per outline emitted by Phase 3. `/plan`'s
Phase 6 also invokes `/review-plan` as a sub-skill via inline
Skill-tool dispatch; this is a CHILD invocation under the Dispatch
Contract, NOT a peer, and is therefore not declared in team.yaml.

See [Dispatch Contract](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) for v1 parent-side consumption rules.

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-1-analysis.md` | Phase 1 |
| `references/phases/phase-2-milestone.md` | Phase 2 |
| `references/phases/phase-3-decomposition.md` | Phase 3 + execution mode selection |
| `references/phases/phase-4-agent-generation.md` | Phase 4 |
| `references/phases/phase-5-dependencies.md` | Phase 5 |
| `references/phases/phase-6-review.md` | Phase 6 |
| `references/phases/phase-7-creation.md` | Phase 7 |
| `references/templates/agent-prompt.md` | Phase 4 agent spawning (design/prd) |
| `references/templates/agent-prompt-planning.md` | Phase 4 agent spawning (roadmap) |
| `references/templates/ac-critical.md` | Phase 4 critical complexity |
| `references/templates/ac-simple.md` | Phase 4 simple complexity |
| `references/templates/ac-testable.md` | Phase 4 testable complexity |
| `references/templates/walking-skeleton-issue.md` | Phase 4 walking skeleton |
| `references/quality/plan-doc-structure.md` | Phase 7 PLAN doc construction |
| `references/quality/plan-doc-examples.md` | Phase 7 (if examples needed) |
| `references/quality/consumer-validation-rules.md` | When implementing a consuming skill that must validate PLAN artifacts |
| `${CLAUDE_SKILL_DIR}/scripts/build-dependency-graph.sh` | Phase 5 |
| `${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh` | Phase 7 multi-pr (**stable sub-operation** via `${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/create-issues-batch.sh`) |
| `${CLAUDE_SKILL_DIR}/scripts/create-issue.sh` | Phase 7 multi-pr (**stable sub-operation** via `${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/create-issue.sh`) |
| `${CLAUDE_SKILL_DIR}/scripts/plan-to-tasks.sh` | When emitting koto task-entry JSON from a PLAN doc (**stable sub-operation** via `${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh`) |
| `${CLAUDE_SKILL_DIR}/scripts/render-template.sh` | Phase 4 |
| `${CLAUDE_SKILL_DIR}/scripts/apply-complexity-label.sh` | Phase 7 multi-pr |
