# Phase 6: AI Review

Invoke `/review-plan` as a sub-operation against the current plan artifacts and
act on the structured verdict it produces.

## Resume Check

```
if wip/plan_<topic>_review.md exists          → read it; skip to Phase 7
if wip/plan_<topic>_review_loopback.md exists → execute loop-back (see below)
else                                           → run /review-plan
```

Read both file paths before proceeding. If `_review.md` exists, proceed to Phase 7
unchanged. If `_review_loopback.md` exists, execute the loop-back sequence instead
of re-running the review.

## Infinite-Loop Guard

Before invoking `/review-plan`, read `review_rounds` from
`wip/plan_<topic>_analysis.md` (field defaults to `0` if absent).

If `review_rounds` has reached the maximum (default: `3`), stop and report:

```
Phase 6 error: review loop limit reached (review_rounds = <N>).
The plan has required loop-back in every review round. Manual intervention is needed.
Review the latest loopback findings in wip/plan_<topic>_review_loopback.md and
address the root cause before re-running /plan.
```

Do not invoke `/review-plan` when the limit is reached.

## Invoke /review-plan

Call `/review-plan` as a sub-operation:

```
/review-plan <topic>
  args:
    plan_topic: <topic>
    round: <review_rounds + 1>
    mode: fast-path
```

`/review-plan` will:
1. Read all plan artifacts from `wip/plan_<topic>_*.md` / `.json`
2. Run all four review categories (A, B, C, D) in fast-path mode
3. Write the verdict to either `wip/plan_<topic>_review.md` (proceed)
   or `wip/plan_<topic>_review_loopback.md` (loop-back)

Wait for `/review-plan` to complete before reading the verdict.

## Read Verdict

After `/review-plan` completes, check which file was written:

```
if wip/plan_<topic>_review.md exists     → verdict is "proceed"; go to Phase 7
if wip/plan_<topic>_review_loopback.md exists → verdict is "loop-back"; execute below
```

Read the `review_result` YAML block from the verdict file. Log the verdict and summary:

```
Phase 6 review complete
  verdict:    <proceed | loop-back>
  round:      <N>
  confidence: <high | medium | low>
  summary:    <summary text>
```

## On "proceed"

Proceed to Phase 7: Creation. No additional steps.

## On "loop-back"

Execute the loop-back sequence defined in `/review-plan`'s phase-6-loop-back.md:

```
skills/review-plan/references/phases/phase-6-loop-back.md
```

The loop-back phase:
1. Reads `loop_target` and `correction_hint` values from the loopback file
2. Deletes wip/ artifacts back to `loop_target` (keeping the loopback file)
3. Increments `review_rounds` in `wip/plan_<topic>_analysis.md`
4. Re-enters `/plan` at `loop_target`

After deletion, `/plan`'s resume logic will detect the earliest remaining artifact
and re-enter at the corresponding phase naturally.

## Next Phase

Proceed to Phase 7: Creation (`phase-7-creation.md`) when verdict is "proceed".
