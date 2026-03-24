# Phase 4: Sequencing / Priority Integrity (Category D)

Implementation is added in Issue 2.

This phase checks whether must-run QA scenarios have been deprioritized or deferred
in a way that removes end-to-end validation before implementation starts. A plan
that defers its only integration or QA issue to the end of the dependency graph
removes the safety net that catches cross-component failures.

For `roadmap` input types, this phase returns empty findings immediately.

Findings use the `review_result` `critical_findings` format with `category: "D"`.
The `correction_hint` field is left empty for all Category D findings — corrections
require re-running Phase 5 (Dependencies), not changing issue body content.

Loop-back targets for Category D findings:
- Dependency ordering errors → `loop_target: 5`
- Structural deferral (must-run QA classified as low-priority) → `loop_target: 3`
