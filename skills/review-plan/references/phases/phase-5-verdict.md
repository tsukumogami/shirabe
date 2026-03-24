# Phase 5: Verdict Synthesis

Implementation is added in Issue 4.

This phase collects findings from all four review categories (A, B, C, D) and
synthesizes them into a single `review_result` YAML block written to one of two
verdict artifact files.

**Verdict rules:**
- `verdict: "proceed"` — no critical findings across all categories
- `verdict: "loop-back"` — one or more critical findings exist

**Loop target selection** (when verdict is loop-back):
Uses the deterministic category-to-phase mapping; earliest phase wins when multiple
categories have findings. See `references/templates/review-result-schema.md` for the
full mapping table.

**Output:**
- `verdict: "proceed"` → writes `wip/plan_<topic>_review.md` only
- `verdict: "loop-back"` → writes `wip/plan_<topic>_review_loopback.md` only

Both files use the schema from `references/templates/review-result-schema.md`.
