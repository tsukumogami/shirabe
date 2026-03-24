# Phase 2: Design Fidelity (Category B)

Implementation is added in Issue 2.

This phase checks whether the plan has inherited contradictions from the upstream
design doc — for example, two sections of the design specifying different method
names for the same purpose, producing issues with mutually exclusive behaviors.

Requires reading the upstream design doc path from `wip/plan_<topic>_analysis.md`.
For `topic` input types (no upstream doc), this phase returns empty findings.
For `roadmap` input types, this phase returns empty findings immediately.

Findings use the `review_result` `critical_findings` format with `category: "B"`.
The `correction_hint` field is left empty for all Category B findings — corrections
require re-running Phase 1 (Analysis), not changing issue body content.

Loop-back target for Category B findings: `loop_target: 1`
