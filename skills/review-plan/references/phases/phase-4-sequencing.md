# Phase 4: Sequencing / Priority Integrity (Category D)

This phase checks whether must-run QA scenarios have been deprioritized or deferred
in a way that removes end-to-end validation before implementation starts. A plan
that defers its only integration or QA issue to the end of the dependency graph
removes the safety net that catches cross-component failures.

## Inputs

Read the following from Phase 0 context:

- All issue body files (already read in Phase 0)
- Full dependency graph (from `wip/plan_<topic>_dependencies.md`)
- Complexity breakdown — critical count and which issues are critical
- Decomposition strategy (`walking-skeleton` or `horizontal`)
- Input type (gates behavior below)

## Behavior by Input Type

| Input type | Behavior |
|------------|----------|
| `design` | Full check |
| `prd` | Full check |
| `topic` | Full check |
| `roadmap` | Returns empty findings immediately (`critical_findings: []`) |

For `roadmap` input types, this phase returns empty findings immediately.

## Full Sequencing Check (design, prd, topic)

Run the following checks:

### 1. QA Scenario Deprioritization (Structural Deferral)

Identify issues that are explicitly QA-focused: issues with "test", "validate",
"verify", "scenario", or "QA" in their title, or issues whose acceptance criteria
describe integration or end-to-end validation behavior.

For each such issue, check its position in the dependency graph:

- If the QA issue is a leaf node (nothing depends on it) AND all implementation
  issues are complete before it runs, this is acceptable — the plan validates after
  building.
- If the QA issue has no dependencies on the implementation issues it is meant to
  validate, or if it is classified as `simple` or low-priority when it is the *only*
  integration validation in the plan, flag this as structural deferral.

**Key signal**: a plan where the only QA or integration issue carries `simple`
complexity and sits at the end of a chain where all implementation issues precede it
is not a structural deferral — the QA issue runs last but validates what precedes it.
A plan where the QA issue has no dependency relationship with the code it validates
is a structural deferral regardless of position.

### 2. Dependency Ordering Errors

Check the dependency graph for ordering violations that would allow an issue to
be implemented before its actual prerequisites are in place:

- Issue B declares it depends on Issue A, but Issue B's acceptance criteria require
  a component that Issue A does not produce.
- Issue C has no declared dependency on Issue D, but Issue C's AC references behavior
  that Issue D is responsible for implementing.

These are dependency ordering errors — the dependency graph is wrong, not the
complexity classification.

**Distinguish from structural deferral**: a structural deferral is about QA priority
classification; a dependency ordering error is about a missing or incorrect dependency
edge in the graph.

## Finding Criteria

Produce a `critical_finding` with `category: "D"` when:

**Structural deferral** (routes to Phase 3):
- A QA or integration issue has no dependency relationship with the issues it validates
- A QA issue is classified `simple` and it is the only integration validation in the plan
  where a `critical` or `testable` classification is warranted

**Dependency ordering errors** (routes to Phase 5):
- An issue's ACs reference behavior from another issue with no declared dependency
- The dependency graph would allow parallel execution of issues that share a critical
  state dependency

## Output Format

Findings use the `review_result` `critical_findings` format:

```yaml
- category: "D"
  description: "..."          # name the specific issue and the sequencing problem
  affected_issue_ids: [3, 4]  # sequence numbers of the missequenced issues
  correction_hint: ""         # always empty for Category D
```

The `correction_hint` field is left empty for all Category D findings — corrections
require re-running an earlier phase (which phase depends on the finding subtype —
see loop_target mapping below), not changing issue body content.

If no findings: return `critical_findings: []` for this category.

## Loop-Back Targets for Category D Findings

Category D has two subtypes with different loop targets:

- Dependency ordering errors → `loop_target: 5` (Dependencies)
- Structural deferral (must-run QA classified as low-priority) → `loop_target: 3` (Decomposition)

When a single verdict includes both subtypes, the earliest phase wins: structural
deferral (Phase 3) takes precedence over dependency ordering errors (Phase 5).
