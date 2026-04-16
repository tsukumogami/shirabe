# QA: run-cascade.sh Acceptance Criteria Validation

Date: 2026-04-15
Script: `skills/work-on/scripts/run-cascade.sh`

## Summary

All 5 automated scenarios pass. All 12 acceptance criteria verified — 10 pass cleanly, 2 have minor behavioral notes that are documented below.

## Automated Test Harness Results

Command: `bash skills/work-on/scripts/run-cascade_test.sh`

```
=== run-cascade.sh test harness ===

PASS: Scenario 1: DESIGN→ROADMAP
PASS: Scenario 2: DESIGN→PRD→ROADMAP
PASS: Scenario 3: Idempotency
PASS: Scenario 4: Missing upstream
PASS: Scenario 5: Partial chain

=== Results: 5 passed, 0 failed ===
```

**5/5 scenarios passed.**

## Acceptance Criteria Detail

### AC1: CLI accepts `[--push] <plan-doc-path>`, exits 1 with usage when no args

**Result: PASS**

Running the script with no arguments prints a full usage block to stderr and exits with code 1. The usage block correctly documents `[--push]`, the plan-doc-path positional argument, options, output format, and exit codes. Verified by direct invocation.

### AC2: Exits 0 and emits valid JSON for DESIGN→ROADMAP topology (no PRD)

**Result: PASS** (Scenario 1 in harness)

Verified: exit 0, valid JSON, `cascade_status: "completed"`, steps include `delete_plan`, `transition_design`, and `update_roadmap_feature`. No `transition_prd` step present.

### AC3: Exits 0 and emits valid JSON for DESIGN→PRD→ROADMAP topology

**Result: PASS** (Scenario 2 in harness)

Verified: exit 0, valid JSON, `cascade_status: "completed"`, all four actions present: `delete_plan`, `transition_design`, `transition_prd`, `update_roadmap_feature`. When all ROADMAP features are Done, `transition_roadmap` also appears.

### AC4: JSON schema — `cascade_status` + `steps[]` with correct fields

**Result: PASS**

Full chain output validated:
- `cascade_status` is always one of `completed`, `partial`, or `skipped`
- Each step contains: `action`, `target`, `found_in`, `status`, `detail`
- `action` values observed: `delete_plan`, `transition_design`, `transition_prd`, `update_roadmap_feature`, `transition_roadmap` — all match spec
- `status` values: `ok`, `skipped`, `failed` — all match spec
- `found_in` is `null` for the `delete_plan` step (correct — no upstream doc references it); a string path for all other steps
- `detail` is `null` when `status == "ok"`, a string when `status == "skipped"` or `"failed"` — correct

### AC5: `get_frontmatter_field` works correctly for typical YAML fields

**Result: PASS**

Tested inline with a representative PLAN frontmatter block:
- Plain string fields (`status`, `schema`, `upstream`): extracted correctly
- Quoted string fields (`milestone: "Test Milestone"`): quotes stripped, value returned without quotes
- Integer fields (`issue_count: 3`): returned as string `"3"`
- Non-existent field: returns empty string (no exit non-zero)

The `index()` approach correctly handles field names that could contain regex metacharacters.

### AC6: `validate_upstream_path` rejects non-existent files

**Result: PASS** (with one clarification on symlinks)

Tested:
- Non-existent path: rejected with "not a regular file"
- Path outside `$REPO_ROOT`: rejected with "outside repo root"
- Existing but untracked file: rejected with "not tracked by git"
- Tracked regular file: accepted
- Symlink: correctly rejected by the `[[ -L "$abs_path" ]]` branch of the condition at line 107

The condition `[[ ! -f "$abs_path" ]] || [[ -L "$abs_path" ]]` handles this correctly: `-f` follows symlinks (so a symlink to a regular file passes `-f`), but `-L` catches it as a symlink regardless.

### AC7: Without `--push`, changes are staged but not committed

**Result: PASS**

Verified with a full DESIGN→ROADMAP run without `--push`:
- `git diff --cached --name-only` shows staged files after the run (DESIGN move, PLAN deletion, ROADMAP update)
- `git log --oneline` shows only the pre-existing fixture commit — no new commit created
- Script exits 0 and emits valid JSON

### AC8: With `--push`, changes are committed with message `chore(cascade): post-implementation artifact transitions`

**Result: PASS (commit message correct)**

The commit is created with the exact message `chore(cascade): post-implementation artifact transitions`. Verified via `git log -1 --format="%s"`.

**Behavioral note:** If `git push` fails (e.g., no remote configured, push rejected), the script exits non-zero (exit code 128) due to `set -euo pipefail` at line 35. In this case, the commit has already been created but `emit_result` at line 627 is never reached, so no JSON is written to stdout — instead, git commit's progress output lands on stdout. This is a minor robustness gap: the commit succeeds but the caller receives no JSON status. The cascade itself ran correctly; only the status report is lost. This warrants a note but does not block the feature.

### AC9: `cascade_status: skipped` when no `upstream` field in PLAN

**Result: PASS** (Scenario 4 in harness)

When the PLAN doc has no `upstream` field, `UPSTREAM` is empty. Lines 530-534 emit `cascade_status: "skipped"` and exit 0. The `delete_plan` step is still recorded before this early return (the PLAN deletion runs before the upstream check).

Wait — checking the code order more carefully: `delete_plan` step is recorded at line 521-526, and the `if [[ -z "$UPSTREAM" ]]` check is at line 530. So the `skipped` output does include the `delete_plan` step. The test harness only checks `cascade_status == "skipped"` and that passes.

### AC10: `cascade_status: partial` when upstream file missing

**Result: PASS** (Scenario 5 in harness)

When the upstream file referenced in the PLAN does not exist, `validate_upstream_path` returns non-zero, `ANY_FAILED=true` is set, and a failed step is added. At the end of the script (line 625-628), `ANY_FAILED=true` causes `emit_result "partial"`. The failed step includes a descriptive `detail` message.

### AC11: VISION-* terminates chain without a step entry

**Result: PASS**

Tested with a chain: PLAN → DESIGN → VISION-test.md. Output:
- `cascade_status: "completed"` (no failures recorded)
- Steps: only `delete_plan` and `transition_design` — no step for the VISION node
- Verified: `[.steps[] | select(.target | contains("VISION"))] | length == 0`

The VISION branch at lines 594-596 calls only `log_info` and `break` with no `add_step` call, which is the correct behavior per the acceptance criterion.

### AC12: Unknown prefix emits `partial` status

**Result: PASS**

Tested with a PLAN whose `upstream` points to `docs/unknown/UNKNOWN-test.md` (tracked by git, exists). Output:
- `cascade_status: "partial"`
- A `transition_design` step with `status: "failed"` and detail: `"...which has an unrecognized filename prefix — expected DESIGN-*, PRD-*, ROADMAP-*, or VISION-*; stopping chain walk here"`

Note: the action name for an unknown prefix is `transition_design` (line 601), not a new action type. This is consistent with the spec's action list (which doesn't include an "unknown" action).

## Issues Found

**Minor robustness gap (AC8):** When `--push` is specified and `git push` fails, the script exits non-zero before `emit_result` is called. The commit was already created, so the cascade changes are present but the caller receives no JSON output. Callers relying on stdout JSON in automated pipelines with `--push` will see a non-zero exit and no parseable JSON if the push step fails.

This is an edge case that only manifests when the push itself fails (network issue, branch protection, etc.) and doesn't affect the primary happy-path behavior. It's worth flagging but not a blocker.

## Overall Result

| Category | Count |
|----------|-------|
| Scenarios run (automated) | 5 |
| Scenarios passed | 5 |
| Scenarios failed | 0 |
| Additional ACs verified by code inspection + targeted runs | 7 |
| Issues found | 1 minor behavioral note (AC8 push failure path) |
