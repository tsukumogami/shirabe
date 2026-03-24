# Phase 6: Loop-back

Implementation is added in Issue 4.

This phase executes only when the verdict artifact is `wip/plan_<topic>_review_loopback.md`.
It reads the loop-back findings, deletes wip/ artifacts back to the loop target, and
signals `/plan` to re-enter at the target phase.

**Steps (high level):**

1. Read `wip/plan_<topic>_review_loopback.md` and extract `loop_target` and any
   Category C `correction_hint` values
2. Delete wip/ artifacts from `loop_target` forward — the exact deletion sequence
   is per `loop_target` value (1, 3, 4, or 5); do not delete the loopback file itself
3. Increment `review_rounds` in `wip/plan_<topic>_analysis.md`
4. Signal `/plan` to re-enter at `loop_target` (the existing resume logic handles
   re-entry naturally once artifacts back to that phase are deleted)

**Loopback file lifecycle — important:**

The loopback file is NOT deleted during Phase 6 execution. It persists through
Phase 4 regeneration so agents can read correction hints directly from it.

The `/plan` resume logic distinguishes "loop-back needs to run" from "loop-back
already ran" by checking whether the manifest still exists:

```
if loopback file exists AND manifest exists   → execute loop-back (Phase 6 has not run yet)
if loopback file exists AND manifest is gone  → loop-back already ran; resume from
                                                 the earliest artifact that still exists
```

After Phase 6 runs, it deletes the manifest (and other artifacts per `loop_target`).
The loopback file remains. When `/plan` re-enters at `loop_target`, it does not
re-trigger Phase 6 because the manifest is absent.

The loopback file is eventually overwritten (not explicitly deleted) when the next
review run writes its verdict — either a new `_review.md` (proceed) or a new
`_review_loopback.md` (another loop-back round).

Full artifact deletion sequences per loop_target are specified in Issue 4.
