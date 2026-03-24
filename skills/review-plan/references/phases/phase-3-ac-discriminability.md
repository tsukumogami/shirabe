# Phase 3: AC Discriminability (Category C)

Implementation is added in Issue 3.

This phase checks whether each acceptance criterion would pass for a plausible wrong
implementation. It runs in two passes:

1. **Pattern pass** — scans AC text for automatable signals (patterns 1, 3, 7 from
   the taxonomy). Matches are flagged immediately without further reasoning.
2. **Adversarial pass** — for each AC that didn't match in the pattern pass, prompts
   the review agent to reason taxonomically using patterns 2, 4, 5, and 6.

The taxonomy is defined in `references/templates/ac-discriminability-taxonomy.md`.

For `roadmap` input types, this phase returns empty findings immediately.

Findings use the `review_result` `critical_findings` format with `category: "C"`.
Unlike other categories, **Category C findings must include a non-empty
`correction_hint`** — a brief description of what a discriminating AC should check.
This hint is injected into Phase 4 regeneration agent prompts on loop-back.

Loop-back target for Category C findings: `loop_target: 4`
