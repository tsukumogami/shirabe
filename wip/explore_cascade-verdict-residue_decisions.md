# Exploration Decisions: cascade-verdict-residue

## Round 1
- Reverting `update_roadmap_feature` to `skipped` is ruled out as a recommendation. It breaks the "partial iff some step failed" rule the suite pins, it leaves `execute.md`'s `failed`-only halt filter with nothing to print, and it needs edits to a file this worker may not touch.
- `failed` is kept as the vocabulary for "asked to do X and couldn't". `skipped` means nothing to do, couldn't verify, or deliberately deferred. This matches every arm in the script on 7cd13d1.
- The no-op awk rewrites and `git add ... || true` shapes are treated as covered by #362 and are not re-reported as new.
- #355, #356 and #357 stay out of scope. They were mentioned only where they were encountered.
- Amending the design's vocabulary doesn't wait on the ROADMAP lookup decision. The step status is `failed` whatever mechanism locates the feature.
- The ROADMAP lookup gap (a `Downstream:` field the format lacks and no skill writes, plus the unanchored slug match) is handed off. The coordinator is filing it as a separate issue, and this worker doesn't file it. Any ROADMAP behaviour the #354 docs fix describes has to be the current behaviour, citing that issue.
- Crystallize after round 1 (coordinator verdict). The evidence answers the core question.
</content>
