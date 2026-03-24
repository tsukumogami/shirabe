# Phase 1: Scope Gate (Category A)

This phase evaluates whether the plan's issue count and complexity are appropriate
for the source design's scope. A plan with too few issues may leave components
unimplemented; a plan with too many may fragment work beyond what the design warrants.

## Inputs

Read the following from Phase 0 context:

- Issue count (from `wip/plan_<topic>_decomposition.md`)
- Complexity breakdown — simple / testable / critical counts
- Decomposition strategy (`walking-skeleton` or `horizontal`)
- Input type (gates behavior below)
- For `roadmap` input: roadmap item count (from the roadmap source document)
- For `design` or `prd` input: full source document (the upstream design doc or PRD)

## Behavior by Input Type

| Input type | Behavior |
|------------|----------|
| `design` | Full check — evaluate issue count and complexity against design component count |
| `prd` | Full check — evaluate issue count and complexity against PRD feature count |
| `roadmap` | Restricted check — verify issue count matches roadmap item count; no scope depth evaluation |
| `topic` | Full check — evaluate issue count and complexity against the stated topic scope |

For `roadmap` input, the expected issue count is one per roadmap item (planning issue
per feature). If the plan has a different count, produce a finding with `category: "A"`
describing the mismatch. Skip all other checks for roadmap input.

## Full Scope Gate Check (design, prd, topic)

Run the following checks:

### 1. Issue Count Range

Count the design's top-level components (for design/prd) or the stated deliverables
(for topic). Compare to the plan's issue count:

- **Too few**: issue count is less than half the component count — each component
  needs at least some coverage; a severe undercount suggests entire components are
  unaddressed.
- **Too many**: issue count is more than 5× the component count — indicates
  micro-fragmentation that produces implementation friction without design-justified
  benefit.

These are heuristic thresholds, not hard rules. A plan with 8 issues for a 3-component
design warrants scrutiny; a plan with 6 issues for a 5-component design does not.

### 2. Complexity Coverage

Check that critical-complexity issues exist for components that the design identifies
as high-risk or architecturally significant. A plan where every issue is `simple`
complexity for a design with multiple integration points is a scope signal.

### 3. Missing Components

Scan the design's component list against the issue set. If a named component from
the design appears in no issue title and no issue body, produce a finding — the
component may be unimplemented.

This check does not require perfect one-to-one mapping; one issue may cover multiple
small components. The check triggers when a component appears nowhere in the issue set.

## Finding Criteria

Produce a `critical_finding` with `category: "A"` when:

- Roadmap input: issue count does not match roadmap item count
- Full check: issue count is outside the heuristic range for the design's scope
- Full check: a named design component appears in no issue body
- Full check: critical-complexity issues are absent for architecturally significant components

Do NOT produce a finding for minor count variations within normal range. The scope
gate is looking for structural mismatches, not stylistic preferences.

## Output Format

Findings use the `review_result` `critical_findings` format:

```yaml
- category: "A"
  description: "..."       # specific component or count issue
  affected_issue_ids: []   # sequence numbers of issues involved; [] for plan-level gaps
  correction_hint: ""      # always empty for Category A
```

The `correction_hint` field is left empty for all Category A findings — corrections
require re-running Phase 3 (Decomposition), not changing issue body content.

If no findings: return `critical_findings: []` for this category.

## Loop-Back Target

Category A findings → `loop_target: 3` (Decomposition)
