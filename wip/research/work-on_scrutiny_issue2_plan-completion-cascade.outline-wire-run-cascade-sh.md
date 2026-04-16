# Scrutiny Review: Issue 2 — Wire plan_completion to run-cascade.sh

**Files reviewed:**
- `skills/work-on/koto-templates/work-on-plan.md`
- `skills/work-on/SKILL.md`

---

## AC Evaluation

### AC1: `plan_completion` directive invokes `run-cascade.sh --push {{PLAN_DOC}}` as its primary action

**Met.**

Line 219 of `work-on-plan.md`:
```bash
RESULT=$(${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/run-cascade.sh --push {{PLAN_DOC}})
```
The invocation uses `--push`, passes `{{PLAN_DOC}}`, and is the first and only action in the directive code block.

---

### AC2: Directive reads JSON output and uses `cascade_status` to determine what to submit to koto

**Met with a qualification.**

Line 220 extracts `cascade_status` from `$RESULT`:
```bash
CASCADE_STATUS=$(echo "$RESULT" | jq -r '.cascade_status')
```

The prose at lines 225-229 enumerates what each value means. The submission is instructed via prose ("Submit `cascade_status` from the JSON output") rather than a literal `koto next` call, but this is consistent with every other directive in the template — `orchestrator_setup`, `pr_finalization`, `ci_monitor`, and `escalate` all use the same prose-instruction-only pattern. Only `spawn_and_await` shows a literal `koto next` call.

The qualification: `$CASCADE_STATUS` is extracted but never referenced in the code block or prose after extraction. The agent must connect the variable to the submission by reading the subsequent prose. This is implicit but consistent with the template's existing idiom.

---

### AC3: A comment points maintainers to `run-cascade.sh`

**Met.**

Line 214: "Run the completion cascade using `run-cascade.sh` (see `skills/work-on/scripts/run-cascade.sh`)."

---

### AC4: All three `cascade_status` values handled and route to `done`

**Met.**

YAML schema (lines 116-125): all three values (`completed`, `partial`, `skipped`) declared in the enum. Single unconditional `- target: done` transition. Prose at lines 225-229 confirms meaning of each. Lines 229: "All three values route to `done`."

---

### AC5: `SKILL.md` Completion Cascade section references `run-cascade.sh` rather than manual steps

**Met.**

`SKILL.md` lines 131-135:
- Names `skills/work-on/scripts/run-cascade.sh --push {{PLAN_DOC}}` explicitly
- Describes what the script does (walks `upstream` frontmatter chain)
- References `cascade_status` JSON field
- No manual cascade steps listed

---

### AC6: No other changes to `work-on-plan.md` beyond the `plan_completion` directive

**Cannot fully verify without a diff** (no prior version available in this review). The rest of the file — `orchestrator_setup`, `spawn_and_await`, `pr_finalization`, `ci_monitor`, `escalate`, `done`, `done_blocked` — appears structurally intact and consistent with the SKILL.md prose descriptions. No evidence of extraneous modification, but this cannot be confirmed as a hard guarantee without git diff.

---

## Findings

### ADVISORY: `cascade_detail` accepted field has no downstream consumer

**Location:** `work-on-plan.md` lines 120-122 (schema) and line 223 (directive prose)

**Finding:** `cascade_detail` is declared as an accepted field in `plan_completion` but has no downstream consumer. The single unconditional transition routes to `done` (a bare terminal state). No `context_assignments` propagates it, no transition gate reads it, and `done` has no directive that references it.

Compare with `rationale` in `ci_monitor` (line 94), which IS consumed: it appears in a `context_assignments` expression at line 111. `cascade_detail` has no equivalent consumer.

The field is accessible via koto's own state inspection (`koto status`), which partially mitigates the issue for human debugging. But within the template contract, it is a declared field with no structural reader.

**Why advisory and not blocking:** This field is a human-readable summary — a diagnostic aid, not a routing signal. The routing signal (`cascade_status`) does have a consumer (the transition enum). The `cascade_detail` pattern doesn't compound: `done` is terminal and no other state reads from it. Fixing it later requires only adding `context_assignments` to the `plan_completion` transition or removing the field — neither change touches other files.

**Options:**
1. Remove `cascade_detail` from the schema if no consumer is planned.
2. Add a `context_assignments` entry to the `plan_completion` → `done` transition to preserve it in context for post-run inspection.

---

## Role Summaries

### Completeness (AC coverage)
ACs 1, 3, 4, 5 are fully met. AC2 is met under the template's established prose-instruction idiom. AC6 cannot be verified without a diff but shows no visible violations.

### Justification (structural soundness)
The `cascade_detail` field is accepted by the schema but has no consumer in the template contract. Every other narrative field used for diagnostics in this template is either consumed via `context_assignments` (like `rationale`) or explicitly not accepted (terminal states have no `accepts` block). `cascade_detail` is the only accepted-but-unread field.

### Intent (alignment with design)
The directive correctly reflects the intended design: script does the work, JSON drives the evidence, all outcomes route to `done`. The `CASCADE_STATUS` variable extraction is correct even though it isn't explicitly used in a submission command (consistent with the template idiom). The SKILL.md narrative accurately describes the template behavior.

---

## Summary

| Criterion | Result |
|-----------|--------|
| AC1: invokes run-cascade.sh --push | Met |
| AC2: reads JSON, uses cascade_status | Met (consistent with template idiom) |
| AC3: comment points to script | Met |
| AC4: all three values → done | Met |
| AC5: SKILL.md references run-cascade.sh | Met |
| AC6: no other changes | Cannot verify (no diff) |

**Blocking findings:** 0
**Advisory findings:** 1 (`cascade_detail` accepted with no downstream consumer)
