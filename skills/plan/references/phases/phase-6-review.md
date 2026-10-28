# Phase 6: AI Review

Invoke `/review-plan` as a sub-operation against the current plan artifacts and
act on the structured verdict it produces.

## Resume Check

```
if key work/review.md exists in plan-<topic>          → read it; skip to Phase 7
if key work/review_loopback.md exists in plan-<topic> → execute loop-back (see below)
else                                                   → run /review-plan
```

## Plan Version v2

A `v2` run hands `/review-plan` a step plan: entries are `### Step <N>:`
blocks, steps from 3 on are one-line outlines by design, and nothing is filed.
An outline step's missing criteria are not a finding; the plan's owner details
it later. Judge the detailed steps' criteria and checks as the review would
judge an issue's.

## Infinite-Loop Guard

Before invoking `/review-plan`, read `review_rounds` from key
`work/analysis.md` (field defaults to `0` if absent).

If `review_rounds` has reached the maximum (default: `3`), stop and report:

```
Phase 6 error: review loop limit reached (review_rounds = <N>).
The plan has required loop-back in every review round. Manual intervention is needed.
Review the latest loopback findings (key work/review_loopback.md in plan-<topic>)
and address the root cause before re-running /plan.
```

Do not invoke `/review-plan` when the limit is reached.

## Invoke /review-plan

Before the call, run the document check at the review moment
(`${CLAUDE_PLUGIN_ROOT}/references/doc-check-steps.md`). No PLAN is written yet, so every rule
comes back not ready and the check exits 0; it records that the review ran
before the PLAN existed:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-check.sh" --doc docs/plans/PLAN-<topic>.md --format plan --moment pre_jury --phase 6 --topic <topic> --skill plan
```

Call `/review-plan` as a sub-operation:

```
/review-plan <topic>
  args:
    plan_topic: <topic>
    round: <review_rounds + 1>
    mode: fast-path
```

`/review-plan` will:
1. Read all plan keys from `plan-<topic>` (the session this run holds open;
   `/review-plan` opens and closes nothing here)
2. Run all five review categories (A to E) in fast-path mode; Category E
   (Functional Shape) checks the horizon only here, as `/plan`'s sub-operation
3. Write the verdict as key `work/review.md` (proceed) or
   `work/review_loopback.md` (loop-back) in `plan-<topic>`

Wait for `/review-plan` to complete before reading the verdict.

## Read Verdict

After `/review-plan` completes, check which key was written:

```
if key work/review.md exists           → verdict is "proceed"; go to Phase 7
if key work/review_loopback.md exists  → verdict is "loop-back"; execute below
```

Read the `review_result` YAML block from the verdict key. Log the verdict and summary,
and every entry of `advisory_findings` (absent or empty means none):

```
Phase 6 review complete
  verdict:    <proceed | loop-back>
  round:      <N>
  confidence: <high | medium | low>
  summary:    <summary text>
  advisory:   <none, or one line per advisory finding: its category and description>
```

Advisory findings change neither the verdict nor the loop target, so nothing below
acts on them; this log is where the plan's reader sees them. Under `plan/v1` they
are Category E's notes on a plan cut into layers, a first issue that is not a
walking skeleton, or a file-shaped criterion.

## On "proceed"

Proceed to Phase 7: Creation. No additional steps.

## On "loop-back"

Execute the loop-back sequence defined in `/review-plan`'s phase-6-loop-back.md:

```
skills/review-plan/references/phases/phase-6-loop-back.md
```

The loop-back phase:
1. Reads `loop_target` and `correction_hint` values from the loopback key
2. Removes `/plan`'s keys back to `loop_target` (keeping the loopback key)
3. Increments `review_rounds` in key `work/analysis.md`
4. Re-enters `/plan` at `loop_target`

After the removal, `/plan`'s resume logic will detect the earliest remaining key
and re-enter at the corresponding phase naturally.

## Next Phase

Proceed to Phase 7: Creation (`phase-7-creation.md`) when verdict is "proceed".
