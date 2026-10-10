# Phase 5: Verdict Synthesis

This phase collects findings from all four review categories (A, B, C, D) and
synthesizes them into a single `review_result` YAML block written to one of two
verdict keys in `plan-<topic>`.

## Inputs

- All category findings collected after running phases 1–4
- `round` value from args (if called as sub-operation) or `review_rounds + 1` from
  key `work/analysis.md` (if called standalone; 0 with no plan session)
- `confidence` signals from each category phase (missing docs, empty issue bodies,
  ambiguous ACs, or roadmap input type)
- `topic` string (for the session name, `plan-<topic>`)

## Verdict Rules

**`verdict: "proceed"`** — no critical findings across all four categories. The
`critical_findings` array is empty. The `loop_target` field is omitted (set to null).

**`verdict: "loop-back"`** — one or more critical findings exist across any category.
The `critical_findings` array contains all findings. The `loop_target` is set
according to the mapping in `references/templates/review-result-schema.md`.

## Loop Target Selection

Use the deterministic category-to-phase mapping from the schema. Earliest phase wins,
so when a verdict has both D subtypes, D-structural (Phase 3) takes precedence over
D-dependency (Phase 5).

Read the schema reference for the full table:
`references/templates/review-result-schema.md`

## Confidence

Set `confidence` based on signals from category phases:

| Signal | Confidence impact |
|--------|------------------|
| Upstream design doc was unavailable for Category B | Lower to `"low"` |
| One or more issue body files were missing | Lower to `"medium"` (or `"low"` if multiple missing) |
| Input type is `roadmap` (B, C, D return empty findings) | Lower to `"low"` |
| All artifacts present and complete, no anomalies | `"high"` |

Category C findings carry one more signal, stated under `confidence` in
`references/templates/review-result-schema.md`: acceptance criteria that could be
read more than one way also lower confidence.

When multiple signals are present, use the lowest resulting level.

## Output: Proceed

Write key `work/review.md` (`koto context add plan-<topic> work/review.md`, the
content on stdin):

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

This key triggers Phase 7 in `/plan`'s resume logic — its presence is the signal
to proceed to issue creation.

## Output: Loop-back

Write key `work/review_loopback.md` (`koto context add plan-<topic>
work/review_loopback.md`, the content on stdin):

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

## Do Not Write Both Keys

Write exactly one key per review run. If the verdict is "proceed", do not write
`work/review_loopback.md`. If the verdict is "loop-back", do not write
`work/review.md`.

If a previous run's verdict key exists with the other name, leave it in place
(the `/plan` resume logic reads whichever variant is present).

## Decider Shadow

Once the verdict key is written, run the decider shadow once:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-shadow/review-shadow.py" site review-plan --topic <topic> >/dev/null 2>&1 || true
```

It reads the plan's issue outlines and this verdict key itself, asks the
decider category C's transition-coverage question per issue when the user has
opted in, and records both verdicts side by side outside the repository.
Nothing reads its result: it changes no verdict, loop target or file here, and
a failure or a missing key changes nothing either.

## Closing

When Phase 0 opened `plan-<topic>` itself (no plan session existed), close it
now, whatever the verdict, since this run opened it:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close plan-<topic> done
```

The verdict key stays readable after the close. With no plan keys there is
nothing to loop back to, so Phase 6 does not run; the loop-back verdict is the
report. When `/plan` runs this skill, or a plan was in flight, or `adopt`
matched a parent, close nothing: the session is `/plan`'s, or the parent's.
