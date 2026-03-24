# Phase 1: Scope Gate (Category A)

Implementation is added in Issue 2.

This phase evaluates whether the plan's issue count and complexity are appropriate
for the source design's scope. A plan with too few issues may leave components
unimplemented; a plan with too many may fragment work beyond what the design warrants.

For `roadmap` input types, this phase checks issue count against roadmap item count
only. For `design` and `prd` input types, the full scope gate check runs.

Findings use the `review_result` `critical_findings` format with `category: "A"`.
The `correction_hint` field is left empty for all Category A findings — corrections
require re-running Phase 3 (Decomposition), not changing issue body content.

Loop-back target for Category A findings: `loop_target: 3`
