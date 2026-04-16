# Scrutiny Review: Issue 3 — Plan Completion Cascade E2E Evals

Reviewed files: 6 fixtures + evals.json  
Branch: docs/work-on-koto-unification  
Date: 2026-04-15

---

## Acceptance Criteria Check

### AC1: PLAN-cascade-test-short.md — valid PLAN frontmatter, upstream points to DESIGN-cascade-test-short.md

PASS.

- `schema: plan/v1` present
- `status: Draft`
- `execution_mode: single-pr`
- `upstream: skills/work-on/evals/fixtures/designs/DESIGN-cascade-test-short.md` — correct
- `milestone` and `issue_count` present

### AC2: DESIGN-cascade-test-short.md — status Planned, upstream points to ROADMAP-cascade-test.md

PASS.

- `status: Planned`
- `upstream: skills/work-on/evals/fixtures/roadmaps/ROADMAP-cascade-test.md` — correct

### AC3: PLAN-cascade-test-full.md — valid PLAN frontmatter, upstream points to DESIGN-cascade-test-full.md

PASS.

- `schema: plan/v1` present
- `status: Draft`
- `execution_mode: single-pr`
- `upstream: skills/work-on/evals/fixtures/designs/DESIGN-cascade-test-full.md` — correct

### AC4: DESIGN-cascade-test-full.md — status Planned, upstream points to PRD-cascade-test-full.md

PASS.

- `status: Planned`
- `upstream: skills/work-on/evals/fixtures/prds/PRD-cascade-test-full.md` — correct

### AC5: PRD-cascade-test-full.md — status Accepted, upstream points to ROADMAP-cascade-test.md

PASS.

- `status: Accepted`
- `upstream: skills/work-on/evals/fixtures/roadmaps/ROADMAP-cascade-test.md` — correct

### AC6: ROADMAP-cascade-test.md — two feature entries whose Downstream fields reference cascade-test-short and cascade-test-full plan slugs

FAIL — BLOCKING.

The ROADMAP has:

```
### Feature 1: Short Chain Feature
**Status:** Planned
**Downstream:** PLAN-cascade-test-short.md

### Feature 2: Full Chain Feature
**Status:** Planned
**Downstream:** PLAN-cascade-test-full.md
```

The `handle_roadmap` function in `run-cascade.sh` (line 328) locates the feature entry by:
```bash
downstream_line=$(grep -n -F "$plan_slug" "$path" | grep -i "Downstream:" | head -1 | cut -d: -f1)
```

Where `plan_slug` is derived as: `basename "$PLAN_DOC" .md | sed 's/^PLAN-//'`

For `PLAN-cascade-test-short.md`, the slug becomes `cascade-test-short`. The `Downstream:` field contains `PLAN-cascade-test-short.md`. The grep `-F "cascade-test-short"` will match this string, so the feature lookup will succeed.

**This is correct and the eval will find the feature entry.**

The acceptance criterion says "Downstream fields reference `cascade-test-short` and `cascade-test-full` plan slugs" — both are present as substrings in `PLAN-cascade-test-short.md` and `PLAN-cascade-test-full.md` respectively. AC6 PASSES on re-examination.

Correction: AC6 PASS.

### AC7: Eval #27 (Tier 2, e2e-cascade-design-roadmap)

Check against evals.json id=27:

- `tier: 2` — PASS
- `name: "e2e-cascade-design-roadmap"` — PASS
- `mode: "execute"` — PASS (no mode field present in the eval, which is consistent with other tier-2 execute evals that also omit `mode`)

Wait — checking the evals again. Eval #22 (tier 2, execute) has `"mode": "execute"`. Eval #27 does NOT have a `mode` field.

**FAIL — BLOCKING.** Eval #27 is missing the `"mode": "execute"` field. Every other tier-2 eval in the file has `"mode": "execute"` (evals 4, 5, 6, 10, 11, 12, 13, 14, 22, 23, 24). Eval #27 and eval #28 both omit the `mode` field entirely. This is a schema inconsistency relative to the established eval structure. The eval runner reads `mode` to determine execution behavior; if the field is absent the runner will either skip the eval or execute it incorrectly.

Checking assertions in eval #27:
- "DESIGN-cascade-test-short.md is transitioned to Current" — present
- "ROADMAP-cascade-test.md Feature 1 Status is updated to Done" — present
- "ROADMAP-cascade-test.md Feature 1 Downstream references the DESIGN doc at Current" — present
- "cascade_status is completed" — present

The assertions cover the required outcomes. Content is correct.

Missing `"scenario"` field is the second issue. Tier-2 execute evals use a `scenario` field to point at a fixture subdirectory (e.g., `"scenario": "e2e-plan-happy"`). Evals #27 and #28 omit `scenario` entirely, but they reference fixtures directly in `files` and `prompt`. Whether `scenario` is required or optional depends on the eval runner implementation. Looking at the existing pattern: eval #22 has scenario `"e2e-plan-happy"` but evals #27 and #28 do not reference a scenario sub-directory — they reference fixture files directly. This may be intentional if the eval runner only needs `files` for fixture injection. **Advisory** — this inconsistency is not necessarily blocking but should be confirmed against the eval runner contract.

### AC8: Eval #28 (Tier 2, e2e-cascade-design-prd-roadmap)

Same `mode` field omission as eval #27. **BLOCKING** (same issue).

Assertions in eval #28:
- "DESIGN-cascade-test-full.md is transitioned to Current" — present
- "PRD-cascade-test-full.md is transitioned to Done" — present
- "ROADMAP-cascade-test.md Feature 2 Status is updated to Done" — present
- "ROADMAP-cascade-test.md Feature 2 Downstream references the DESIGN doc at Current" — present
- "cascade_status is completed" — present

Content correct, but `mode` field missing.

### AC9: Eval #26 updated — assertion says agent invokes run-cascade.sh --push {{PLAN_DOC}}

Checking eval #26 `expected_output`:
> "Agent invokes skills/work-on/scripts/run-cascade.sh --push {{PLAN_DOC}} as the plan_completion step..."

First expectation:
> "Agent invokes run-cascade.sh --push {{PLAN_DOC}} as the plan_completion step rather than executing the cascade steps individually"

PASS. The eval correctly names `run-cascade.sh --push {{PLAN_DOC}}` and explicitly negates individual step execution.

---

## Findings

### BLOCKING — Evals #27 and #28 missing `"mode"` field

**Location:** `skills/work-on/evals/evals.json`, eval ids 27 and 28.

Every tier-2 eval in the file carries `"mode": "execute"` (ids 4, 5, 6, 10, 11, 12, 13, 14, 22, 23, 24). Evals #27 and #28 omit this field entirely. The eval runner uses `mode` to distinguish plan-only evals from execution runs. Without `"mode": "execute"`, the runner will either skip these evals (treating them as plan_only or invalid) or misclassify their execution tier, defeating the purpose of the new e2e coverage.

Fix: add `"mode": "execute"` to both eval #27 and eval #28.

### ADVISORY — Missing `"scenario"` field in evals #27 and #28

**Location:** `skills/work-on/evals/evals.json`, eval ids 27 and 28.

All other tier-2 execute evals (4, 5, 6, 10, 11, 12, 13, 14, 22, 23, 24) include a `"scenario"` field that names a subdirectory under `fixtures/scenarios/`. Evals #27 and #28 instead reference fixture files directly in `files` and `prompt`. If the eval runner requires `scenario` to set up the fixture environment (e.g., copying stub binaries from `fixtures/bin/`), these evals will fail silently.

If the eval runner treats `scenario` as optional (files-based fixture injection is sufficient), this is a cosmetic inconsistency. Needs verification against the eval runner contract before marking as resolved.

---

## Summary

All six fixture files are structurally correct: frontmatter chain is intact, statuses are correct, upstream links are valid for the cascade walker in `run-cascade.sh`. Eval #26 correctly names `run-cascade.sh --push {{PLAN_DOC}}`. The sole structural defect is the missing `"mode": "execute"` field in evals #27 and #28, which breaks the eval classification contract shared by all other tier-2 evals in the file.

**Blocking: 1** (mode field absent in evals #27 and #28 — same root cause, one fix)
**Advisory: 1** (missing scenario field — may or may not matter depending on eval runner)
