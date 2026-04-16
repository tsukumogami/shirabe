# Pragmatic Review: Issue 3 — Add E2E Evals for plan_completion Cascade

## Scope

6 new fixture files and 3 new/updated evals (ids 26, 27, 28) in
`skills/work-on/evals/`.

---

## Fixture Files

### PLAN-cascade-test-short.md / PLAN-cascade-test-full.md

Minimum viable PLAN fixtures. Content is correct: both have the required
`schema`, `status`, `execution_mode`, `upstream`, and `milestone` frontmatter
fields. The `upstream` paths resolve to real tracked files in the fixtures
tree. Plan slugs derived by the script (`cascade-test-short`,
`cascade-test-full`) match what the ROADMAP `**Downstream:**` fields
contain. No excess content.

### DESIGN-cascade-test-short.md / DESIGN-cascade-test-full.md

Both have `status: Planned` and a valid `upstream` pointer. Correct for the
cascade path (script transitions DESIGN → Current). No excess content.

### PRD-cascade-test-full.md

Has `status: Accepted` and `upstream` pointing at the ROADMAP. Correct for
the full chain. No excess content.

### ROADMAP-cascade-test.md

Has two feature entries that reference the plan slugs via `**Downstream:**`.
Both features have `**Status:** Planned` — correct pre-cascade state. Script
uses `grep -F "$plan_slug"` on the `**Downstream:**` line and walks up to the
`### Feature` heading; the ROADMAP structure matches exactly what the script
expects.

One subtle concern: the ROADMAP's `Status` frontmatter field is `Active`, not
`Planned`. The `transition_roadmap` step (all features Done) calls
`skills/roadmap/scripts/transition-status.sh`. In evals 27 and 28, only one
feature is being completed per eval run, so the "all features Done" guard will
not fire — the other feature stays `Planned`. This means the ROADMAP
transition guard is never exercised by either eval. The evals' expectations do
not assert it either, so there is no false pass risk here. However, there is
also no test for the ROADMAP-level transition — that is a coverage gap, not an
over-engineering finding (out of this issue's scope).

### Scenario stub directories (e2e-cascade-short, e2e-cascade-full)

Both contain only a `{}` `.keep` file. The cascade evals are `execute` mode
but they invoke the real `run-cascade.sh` against the fixture files; they do
not stub `koto` or `gh` responses the way other execute-mode scenarios do.
The `.keep` files exist only to satisfy whatever the eval runner expects for a
`scenario` directory. This is fine — no dead content.

---

## Evals

### Eval 26 — `plan-completion-cascade` (tier 1, plan_only)

**Correct.** Verifies the agent delegates to `run-cascade.sh` rather than
hand-rolling cascade steps. Expectations are precise and non-redundant.

One observation: the prompt is a prose question ("After CI passes…") rather
than a `/work-on` invocation. Tier 1 `plan_only` evals throughout the file
use imperative `/work-on …` prompts. This is inconsistent but not
over-engineered — it is testing a different entry point (the agent's
understanding of a specific state, not the full invocation path). Advisory
only.

### Eval 27 — `e2e-cascade-design-roadmap` (tier 2, execute)

**Correct.** Files array lists exactly the four fixture paths the cascade
touches. Expectations are tight.

One gap: the `expected_output` says "file may move to `current/`" but no
expectation asserts the file's new location. The corresponding expectation
("DESIGN-cascade-test-short.md is transitioned to Current (status field
updated, file may move to current/)") leaves the path ambiguous. Whether the
file moves depends on `transition-status.sh` behavior, which is outside this
eval's fixture set. This is an existing ambiguity in the skill's design, not
introduced by this PR. No action needed here.

### Eval 28 — `e2e-cascade-design-prd-roadmap` (tier 2, execute)

**Correct.** Files array is complete (PLAN, DESIGN, PRD, ROADMAP). Expectations
cover all four documents the cascade acts on, including the PRD transition.

---

## Findings

**Advisory — eval 26 prompt style inconsistency**

`evals.json:432` — eval 26's prompt is a prose question, not a `/work-on`
invocation. All other tier 1 `plan_only` evals use imperative commands. Low
risk (the grader can still evaluate the response), but it departs from the
established convention. Rewrite as `/work-on -- plan_completion state: what
does the agent do?` or similar.

No blocking findings. No dead code, no speculative generality, no impossible
error paths.

---

## Summary

Fixture files are minimum viable — no over-engineering. Eval assertions
correctly target the observable outputs of `run-cascade.sh` (cascade_status,
specific artifact transitions). The shared ROADMAP fixture supporting both
evals 27 and 28 is the right call (avoids duplication). One advisory on eval
26 prompt style.
