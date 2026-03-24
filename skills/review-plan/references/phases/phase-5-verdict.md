# Phase 5: Verdict Synthesis

This phase collects findings from all four review categories (A, B, C, D) and
synthesizes them into a single `review_result` YAML block written to one of two
verdict artifact files.

## Inputs

- All category findings collected after running phases 1–4
- `round` value from args (if called as sub-operation) or `review_rounds + 1` from
  `wip/plan_<topic>_analysis.md` (if called standalone)
- `confidence` signals from each category phase (missing docs, empty issue bodies,
  ambiguous ACs, or roadmap input type)
- `topic` string (for artifact file paths)

## Verdict Rules

**`verdict: "proceed"`** — no critical findings across all four categories. The
`critical_findings` array is empty. The `loop_target` field is omitted (set to null).

**`verdict: "loop-back"`** — one or more critical findings exist across any category.
The `critical_findings` array contains all findings. The `loop_target` is set
according to the mapping below.

## Loop Target Selection

Use the deterministic category-to-phase mapping from the schema. Earliest phase wins:

```
if B findings exist                         → loop_target: 1
elif A findings or D-structural exist       → loop_target: 3
elif C findings exist                       → loop_target: 4
elif D-dependency-ordering findings exist   → loop_target: 5
```

Read the schema reference for the full table:
`references/templates/review-result-schema.md`

When a single verdict contains both D-structural and D-dependency findings, the
D-structural finding (Phase 3) takes precedence over D-dependency (Phase 5).

## Confidence

Set `confidence` based on signals from category phases:

| Signal | Confidence impact |
|--------|------------------|
| Upstream design doc was unavailable for Category B | Lower to `"low"` |
| One or more issue body files were missing | Lower to `"medium"` (or `"low"` if multiple missing) |
| Input type is `roadmap` (B, C, D return empty findings) | Lower to `"low"` |
| All artifacts present and complete, no anomalies | `"high"` |

When multiple signals are present, use the lowest resulting level.

## Output: Proceed

Write `wip/plan_<topic>_review.md`:

```markdown
---
review_result:
  verdict: "proceed"
  loop_target: null
  round: <N>
  confidence: "high | medium | low"
  critical_findings: []
  summary: "<1-2 sentence summary>"
---

# Plan Review: <topic>

Round <N> review result: proceed.

<summary sentence>
```

This file triggers Phase 7 in `/plan`'s resume logic — its presence is the signal
to proceed to issue creation.

## Output: Loop-back

Write `wip/plan_<topic>_review_loopback.md`:

```markdown
---
review_result:
  verdict: "loop-back"
  loop_target: <1 | 3 | 4 | 5>
  round: <N>
  confidence: "high | medium | low"
  critical_findings:
    - category: "<A|B|C|D>"
      description: "..."
      affected_issue_ids: [...]
      correction_hint: "..."
  summary: "<1-2 sentence summary>"
---

# Plan Review: <topic>

Round <N> review result: loop-back at Phase <loop_target>.

<summary sentence>
```

Include all findings from all categories in `critical_findings`. Do not filter or
deduplicate — `/plan` needs the full list to determine which issues to regenerate.

## Summary Field

Write a 1–2 sentence human-readable summary suitable for display in `/plan` status
output. Examples:

- `"Review passed. No critical findings across all four categories."`
- `"Loop-back required at Phase 4. Issue 3 has fixture-anchored ACs (pattern 1) that would pass for an incorrect implementation; correction hint provided."`
- `"Loop-back required at Phase 1. Design contradiction in sections 3.2 and 5.1 must be resolved before issue bodies can be regenerated."`

## Do Not Write Both Files

Write exactly one file per review run. If the verdict is "proceed", do not write
`_review_loopback.md`. If the verdict is "loop-back", do not write `_review.md`.

If a previous run's verdict file exists with a different name, leave it in place
(the `/plan` resume logic reads whichever variant is present).
