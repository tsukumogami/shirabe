# Phase 5: Verdict Synthesis

This phase collects findings from all five review categories (A, B, C, D, E)
and synthesizes them into a single `review_result` YAML block written to one of
two verdict keys in `plan-<topic>`.

## Inputs

- All category findings collected after running phases 1–4 and 4b
- The plan version (`plan/v1` or `plan/v2`) from Phase 0
- `round` value from args (if called as sub-operation) or `review_rounds + 1` from
  key `work/analysis.md` (if called standalone; 0 with no plan session)
- `confidence` signals from each category phase (missing docs, empty issue bodies,
  ambiguous ACs, or roadmap input type)
- `topic` string (for the session name, `plan-<topic>`)

## Verdict Rules

**`verdict: "proceed"`** — no critical findings across all five categories. The
`critical_findings` array is empty. The `loop_target` field is omitted (set to null).

**`verdict: "loop-back"`** — one or more critical findings exist across any category.
The `critical_findings` array contains all findings. The `loop_target` is set
according to the mapping in `references/templates/review-result-schema.md`.

## Category E by Plan Version

Category E (Functional Shape, Phase 4b) returns its findings already split by
plan version; keep that split here:

- **`plan/v2`**: a layer-shaped plan or a first step that is not a walking
  skeleton loops back, to Phase 3, like any critical finding. So do a
  file-shaped criterion on a detailed step (Phase 4) and, when `/plan` ran the
  review, more than two detailed steps (Phase 3). Each goes in
  `critical_findings`.
- **`plan/v1`**: the same findings are advisory. Record every one in
  `advisory_findings` and leave it out of `critical_findings`, so a `plan/v1`
  plan is flagged without being sent back. A `plan/v1` plan whose only findings
  are Category E gets `verdict: "proceed"`.

## Loop Target Selection

Use the deterministic category-to-phase mapping from the schema. Earliest phase wins,
so when a verdict has both D subtypes, D-structural (Phase 3) takes precedence over
D-dependency (Phase 5), and a Category E finding on the plan's cut (Phase 3) takes
precedence over a file-shaped criterion (Phase 4). Advisory findings set no loop
target.

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
  advisory_findings: []   # Category E findings on a plan/v1 plan, if any
  summary: "<1-2 sentence summary>"
---

# Plan Review: <topic>

Round <N> review result: proceed.

<summary sentence>

<one line per advisory finding, if any>
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
    - category: "<A|B|C|D|E>"
      description: "..."
      affected_issue_ids: [...]
      correction_hint: "..."
  advisory_findings: []   # Category E findings on a plan/v1 plan, if any
  summary: "<1-2 sentence summary>"
---

# Plan Review: <topic>

Round <N> review result: loop-back at Phase <loop_target>.

<summary sentence>
```

Include all critical findings from all categories in `critical_findings`. Do not
filter or deduplicate — `/plan` needs the full list to determine which issues to
regenerate. Advisory findings stay in `advisory_findings` under either verdict.

## Summary Field

Write a 1–2 sentence human-readable summary suitable for display in `/plan` status
output. Examples:

- `"Review passed. No critical findings across all five categories."`
- `"Review passed with advisory Category E findings: the plan/v1 plan is cut into layers (types, compiler, CLI, tests, plugin templates) and has file-shaped criteria, listed as advisory findings."`
- `"Loop-back required at Phase 3. Step 1 of the plan/v2 plan adds types only and its check is a unit test, so it is not a walking skeleton."`
- `"Loop-back required at Phase 4. Issue 3 has fixture-anchored ACs (pattern 1) that would pass for an incorrect implementation; correction hint provided."`
- `"Loop-back required at Phase 1. Design contradiction in sections 3.2 and 5.1 must be resolved before issue bodies can be regenerated."`

## Recording the Round

Each category ended its findings with a `review-verdicts` block (its phase
file's Verdict Block). Write each category's block, as returned, to its file in
`<verdicts-dir>` from Phase 0 with the Write tool: `category-a.md` (Scope
Gate), `category-b.md` (Design Fidelity), `category-c.md` (AC
Discriminability), `category-d.md` (Sequencing) and `category-e.md`
(Functional Shape). In adversarial mode, write the block that matches the
category's final findings after cross-examination. A category that returned no
block gets no file. Then record the blocks and the verdict as telemetry, and
remove the directory:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" verdicts --skill plan --topic <topic> --doc <plan-doc> --dir <verdicts-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" decision --skill plan --topic <topic> --doc <plan-doc> --decision <proceed|loop_back>
rm -rf -- <verdicts-dir>
```

`proceed` for a proceed verdict, `loop_back` for a loop-back. Both calls
always exit 0 and change nothing about the verdict
(`${CLAUDE_PLUGIN_ROOT}/references/review-verdicts.md`).

## Do Not Write Both Keys

Write exactly one key per review run. If the verdict is "proceed", do not write
`work/review_loopback.md`. If the verdict is "loop-back", do not write
`work/review.md`.

If a previous run's verdict key exists with the other name, leave it in place
(the `/plan` resume logic reads whichever variant is present).

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
