# Review Result Schema

The `review_result` YAML block is the machine-readable verdict produced by Phase 5
and written to either `wip/plan_<topic>_review.md` (proceed) or
`wip/plan_<topic>_review_loopback.md` (loop-back). Both files use the same schema.

## Schema

```yaml
review_result:
  verdict: "proceed | loop-back"
  loop_target: 1 | 3 | 4 | 5
  round: 1
  confidence: "high | medium | low"
  critical_findings:
    - category: "A | B | C | D"
      description: "..."
      affected_issue_ids: [1, 2, 3]
      correction_hint: "..."
  summary: "..."
```

## Field Reference

### `verdict`

**Type:** string enum — `"proceed"` or `"loop-back"`

Whether the plan passed review. `"proceed"` means all categories produced no
critical findings and `/plan` can continue to Phase 7. `"loop-back"` means at least
one critical finding requires the plan to be reworked before issues are created.

### `loop_target`

**Type:** integer — `1`, `3`, `4`, or `5`

The earliest `/plan` phase that must re-run to address the critical findings.
Only set when `verdict` is `"loop-back"`. Omit or set to `null` when verdict
is `"proceed"`.

Loop target is determined by finding category using a deterministic mapping:

| Finding category | Loop target | Phase name |
|-----------------|------------|-----------|
| B (Design Fidelity) | 1 | Analysis |
| A (Scope Gate) | 3 | Decomposition |
| C (AC Discriminability) | 4 | Agent Generation |
| D — dependency ordering error | 5 | Dependencies |
| D — structural deferral (must-run QA deprioritized) | 3 | Decomposition |

Category D has two subtypes with different loop targets. Structural deferral
(a QA scenario classified as low-priority or deferred to the end of the plan)
maps to Phase 3 because it is a decomposition sequencing decision. Dependency
ordering errors (correct issues in the wrong order) map to Phase 5.

When multiple categories have findings, the earliest phase wins:
```
if B findings exist                         → loop_target: 1
elif A findings or D-structural exist       → loop_target: 3
elif C findings exist                       → loop_target: 4
elif D-dependency-ordering findings exist   → loop_target: 5
```

### `round`

**Type:** integer, minimum 1

The review round number. Monotonically increasing per topic.

**Authoritative source**: `args.round` when called as a sub-operation (passed in by
`/plan`). When called standalone, derive as `review_rounds + 1` from
`wip/plan_<topic>_analysis.md`. **Never compute from `review_rounds + 1` when
`args.round` is present** — `/plan` increments `review_rounds` in Phase 6 loop-back,
so on a second review call the file-derived value and the args value can diverge.

This field is informational — it provides context to the review skill and to anyone
reading the artifact. `/plan` tracks the authoritative round counter independently
in `wip/plan_<topic>_analysis.md` as `review_rounds`.

### `confidence`

**Type:** string enum — `"high"`, `"medium"`, or `"low"`

The review skill's confidence in the verdict. Factors that lower confidence:

- Upstream design doc was unavailable (Category B ran with limited context)
- Issue body files were missing or incomplete
- Ambiguous ACs that could be read multiple ways (Category C)
- Roadmap input type (B, C, D return empty findings regardless of plan quality)

### `critical_findings`

**Type:** array of finding objects. Empty array (`[]`) when `verdict` is `"proceed"`.

Each entry in `critical_findings` represents one finding from a review category.

#### `critical_findings[].category`

**Type:** string enum — `"A"`, `"B"`, `"C"`, or `"D"`

Which review category produced this finding.

#### `critical_findings[].description`

**Type:** string

A human-readable description of the finding. Should identify the specific issue(s),
the problem observed, and why it would allow an incorrect implementation to pass
review. Be specific — vague descriptions don't give Phase 4 agents enough to fix.

#### `critical_findings[].affected_issue_ids`

**Type:** array of integers

The sequence numbers (from the decomposition, 1-based) of the issues affected by
this finding. Used by `/plan` to know which issue bodies to regenerate on loop-back.

Empty array (`[]`) for findings that apply globally (e.g., a plan-level scope
violation in Category A that doesn't map to specific issues).

#### `critical_findings[].correction_hint`

**Type:** string

A brief description of what a corrected issue body should include to fix this
finding. **Only populated for Category C (AC Discriminability) findings.**

For Categories A, B, and D: leave as empty string `""`. The correction is
addressed by re-running earlier phases, not by changing issue body content directly.

For Category C: describe what a discriminating AC should check. The hint gives
Phase 4 regeneration agents positive direction without generating replacement ACs
(which risks encoding the same design contradictions that caused the failure).

Example: `"Add a clean-state scenario — empty the registry before running the command
and verify the table is empty, then populate and verify it contains the expected rows."`

### `summary`

**Type:** string

A 1–2 sentence human-readable summary of the review outcome. Suitable for display
in `/plan` status output and for reading without parsing the full YAML block.

Examples:
- `"Review passed. No critical findings across all four categories."`
- `"Loop-back required at Phase 4. Issue 3 has fixture-anchored ACs that would pass
  for an incorrect implementation; correction hint provided."`

## Example: Proceed

```yaml
review_result:
  verdict: "proceed"
  loop_target: null
  round: 1
  confidence: "high"
  critical_findings: []
  summary: "Review passed. No critical findings across all four categories."
```

## Example: Loop-back (Category C)

```yaml
review_result:
  verdict: "loop-back"
  loop_target: 4
  round: 1
  confidence: "high"
  critical_findings:
    - category: "C"
      description: "Issue 3, AC 2: fixture-anchored. The binaries table check passes
        when the registry is pre-populated with fixture data, meaning a wrong
        implementation that skips initialization still satisfies the criterion."
      affected_issue_ids: [3]
      correction_hint: "Add a clean-state scenario — empty the registry before running
        the command and verify the table is empty, then populate and verify it contains
        the expected rows."
  summary: "Loop-back required at Phase 4. Issue 3 has a fixture-anchored AC (pattern 1)
    that would pass for an incorrect implementation. Correction hint provided."
```

## Example: Loop-back (Multiple Categories)

```yaml
review_result:
  verdict: "loop-back"
  loop_target: 1
  round: 2
  confidence: "medium"
  critical_findings:
    - category: "B"
      description: "The design doc specifies conflicting method names for the registry
        lookup in sections 3.2 and 5.1. Issues 2 and 4 each implement one variant,
        producing mutually exclusive behavior."
      affected_issue_ids: [2, 4]
      correction_hint: ""
    - category: "C"
      description: "Issue 5, AC 1: existence-without-correctness. 'The config file
        exists' does not verify file content; an implementation that creates an empty
        file satisfies the criterion."
      affected_issue_ids: [5]
      correction_hint: "Verify specific keys in the config file, not just its existence.
        For example: assert that 'registry.url' is set to the expected value."
  summary: "Loop-back required at Phase 1. Design contradiction in sections 3.2 and 5.1
    must be resolved before issue bodies can be regenerated correctly."
```
