# Completeness Scrutiny: run-cascade.sh
## Issue 1 Acceptance Criteria Review

---

### AC1: `skills/work-on/scripts/run-cascade.sh` exists and is executable

- File exists: confirmed via Glob.
- Executable bit: not directly inspectable via Read tool, but the test harness
  checks `[[ ! -x "$CASCADE_SCRIPT" ]]` and would abort if not executable. The
  shebang (`#!/usr/bin/env bash`) is present. Cannot confirm mode bits from
  reading alone; assume handled at commit time.
- **Status: PASS (assumed)**

---

### AC2: Script accepts `[--push] <plan-doc-path>` as its CLI interface

- Lines 451–469: `while` loop parses `--push`, `--help/-h`, unknown flags
  (prints error + usage), and positional PLAN_DOC.
- Line 471–474: guards empty PLAN_DOC.
- **Status: PASS**

---

### AC3: Script exits 0 and emits valid JSON for DESIGN→ROADMAP topology (no PRD)

- Chain walk (lines 524–592) dispatches DESIGN-* to `handle_design`, then reads
  upstream of the design doc to reach ROADMAP-*, dispatches to `handle_roadmap`,
  then breaks. PRD step is skipped entirely.
- `emit_result` at lines 609–613 always produces valid JSON via `jq -n`.
- Exit code: `set -euo pipefail` but the main flow does not exit non-zero after
  the chain unless the initial PLAN validation fails. The final lines always
  reach `emit_result` and the script exits 0 by default.
- **Status: PASS**

---

### AC4: Script exits 0 and emits valid JSON for DESIGN→PRD→ROADMAP topology

- Same chain walk handles DESIGN-* then PRD-* (lines 569–572) then ROADMAP-*
  (lines 573–576).
- **Status: PASS**

---

### AC5: Emitted JSON schema — `cascade_status` + `steps` array with required fields

- `add_step` (lines 195–229) always sets `action`, `target`, `found_in`,
  `status`, `detail` (null when empty string passed).
- `emit_result` (lines 231–236) wraps in `{cascade_status, steps}`.
- `cascade_status` values used: `"completed"`, `"partial"`, `"skipped"` — all
  three prescribed values appear.
- **DEVIATION — `detail` field**: The AC specifies `detail` as a required
  field. `add_step` sets it to JSON `null` when the detail string is empty
  (lines 209–212). This means `ok` steps have `"detail": null` rather than an
  absent field or empty string. Whether `null` satisfies "required field present"
  is a matter of interpretation; the field key is always emitted.
- **Status: PASS** (null is a valid JSON value; field is always present)

---

### AC6: `get_frontmatter_field <field> <doc>` inlined — reads YAML frontmatter field, never exits non-zero

- Lines 62–77: `awk` reads between the first `---` pair.
- `2>/dev/null || true` at line 76 ensures the function never exits non-zero
  even if `awk` fails.
- Strips surrounding single and double quotes.
- **Status: PASS**

---

### AC7: `validate_upstream_path <path>` — rejects outside `$REPO_ROOT`, non-regular files, untracked files

- Lines 87–116:
  - `realpath -m` check + string comparison to `$REPO_ROOT` (line 98) covers
    path-traversal rejection.
  - `[[ ! -f "$abs_path" ]] || [[ -L "$abs_path" ]]` (line 104) covers
    non-regular files and symlinks.
  - `git ls-files --error-unmatch` (line 110) covers untracked files.
- **Status: PASS**

---

### AC8: `check_issue_closed <url>` — parses URL, validates owner/repo against origin, queries `gh issue view <N> --repo <owner/repo>`

- Lines 124–165:
  - `sed` extracts owner, repo, number (lines 130–132).
  - Empty-check on all three (lines 134–137).
  - `git remote get-url origin` (lines 141–143) retrieves origin URL.
  - Normalizes origin slug handling both https and ssh formats (lines 148–151).
  - Compares `$origin_slug` to `$owner/$repo` (lines 153–156).
  - `gh issue view "$number" --repo "$owner/$repo" --json state --jq '.state'`
    (line 159): matches the AC prescription exactly.
  - Returns 0 if `$state == "CLOSED"` (line 164).
- **Status: PASS**

---

### AC9: `strip_implementation_issues` — idempotent awk strip of `## Implementation Issues` section; no-op if absent

- Lines 172–190:
  - Guard check `grep -q '^## Implementation Issues'` (line 176): returns 0
    immediately if absent — no-op confirmed.
  - `awk` strips from `## Implementation Issues$` to (not including) the next
    `## ` heading, or EOF (lines 184–188).
  - Idempotent: the guard prevents rewriting the file if the section is already
    absent.
- **Status: PASS**

---

### AC10: `handle_design` calls `strip_implementation_issues` then `skills/design/scripts/transition-status.sh <path> Current`, stages result

- Lines 242–283:
  - `strip_implementation_issues "$path"` called first (line 250).
  - `bash "$script" "$path" Current` (line 261) where `$script` resolves to
    `skills/design/scripts/transition-status.sh` via two paths (lines 253–258).
  - `git add "$new_path" ...` stages the result (line 277).
- **Status: PASS**

---

### AC11: `handle_prd` calls `skills/prd/scripts/transition-status.sh <path> Done`, stages file

- Lines 289–309:
  - `local script="$REPO_ROOT/skills/prd/scripts/transition-status.sh"` (line 295).
  - `bash "$script" "$path" Done` (line 297).
  - `git add "$path"` (line 306).
- **Status: PASS**

---

### AC12: `handle_roadmap` — locates feature via `grep -F <plan-slug>` on `**Downstream:**` fields; updates `**Status:**` and `**Downstream:**` using `awk ENVIRON`; guards ROADMAP Done via `check_issue_closed`; records `skipped` with prescribed message when feature not found

- Feature location (lines 323–343): `grep -n -F "$plan_slug"` on the path piped
  through `grep -i "Downstream:"`. This is `grep -F` on the plan slug, matching
  on lines that also contain "Downstream:" — matches AC12's requirement.
- `skipped` with prescribed message when not found: lines 328–333 and 340–343
  both record `skipped` with the text "searched $path for a feature whose
  Downstream: field references plan slug '$plan_slug'... but no matching feature
  entry was found — ROADMAP feature status was not updated".

- **`**Status:**` update (lines 352–360)**: uses `awk -v fline="$feature_line"`;
  this is `-v` not `ENVIRON`. Checks AC13 below.

- **`**Downstream:**` update**: AC12 requires updating `**Downstream:**` using
  `awk ENVIRON`. Looking at lines 363–371, the script reads `design_ref` but
  **does not perform any awk substitution on the `**Downstream:**` field**. The
  `design_ref` variable is computed but never used to rewrite the roadmap file.
  The `**Downstream:**` field is never modified.
  - **BLOCKING: AC12 partially unimplemented** — the `**Downstream:**` update
    is not performed. The AC says "updates `**Status:**` and `**Downstream:**`
    using `awk ENVIRON`"; only the Status update occurs.

- `check_issue_closed` guard (lines 385–417): iterates `issue_urls`, calls
  `check_issue_closed`, records `skipped` with the prescribed message when open.
  Calls `skills/roadmap/scripts/transition-status.sh "$path" Done` when all
  closed.
- **Status: PARTIAL — Downstream update missing (blocking)**

---

### AC13: All ROADMAP text substitutions use `awk` with `ENVIRON["varname"]` (not `-v`)

- The `**Status:**` substitution in `handle_roadmap` (lines 352–360) uses
  `awk -v fline="$feature_line"`. This is `-v`, not `ENVIRON`.
- No substitution in `handle_roadmap` uses `ENVIRON["varname"]`.
- The `CASCADE_PLAN_SLUG` export at line 347 (`export CASCADE_PLAN_SLUG`) sets
  up `ENVIRON` access, but no `awk` block in the script actually reads
  `ENVIRON["CASCADE_PLAN_SLUG"]` or any other env var via `ENVIRON`.
- **BLOCKING: AC13 not implemented** — the `awk -v` pattern is used instead of
  `ENVIRON["varname"]` for the Status substitution, and no `ENVIRON` substitution
  is present anywhere in the roadmap handling.

---

### AC14: Without `--push`, script stages changes and prints per-file before/after status summary; does not commit or push

- Lines 600–605: when `PUSH=false` and staged files exist, prints each file via
  `log_info "  $f"`.
- Does not call `git commit` or `git push` in this branch.
- **DEVIATION — "before/after status summary"**: The script prints a list of
  staged files but not a before/after status summary per file (no "was Planned,
  now Current" style output). The AC says "per-file before/after status summary".
  The current output is just the file path.
  - **ADVISORY**: The script stages and does not commit/push (core requirement
    met). The before/after detail is missing but is a display-only concern.

---

### AC15: With `--push`, commits and pushes with message `chore(cascade): post-implementation artifact transitions`

- Lines 596–599:
  - `git commit -m "chore(cascade): post-implementation artifact transitions"` —
    exact message match.
  - `git push` called immediately after.
- **Status: PASS**

---

### AC16: Each `failed` or `skipped` step includes a `detail` message matching the error contract

- All `add_step` calls with `"failed"` or `"skipped"` status pass a non-empty
  detail string.
- Scanning `handle_roadmap` skipped steps (lines 328–333, 340–343, 397–400),
  `handle_design` failed step (line 265–267), `handle_prd` failed step
  (line 301–303), `handle_roadmap` failed roadmap transition (line 410–412),
  chain validation failure (lines 541–553), unknown prefix (lines 584–586).
- All paths pass descriptive detail strings.
- **Status: PASS**

---

### AC17: VISION-* nodes terminate the chain without emitting a step entry

- Lines 578–581:
  ```bash
  VISION-*)
      log_info "VISION node encountered — stopping chain walk (no action)"
      break
      ;;
  ```
  No `add_step` call in this branch. Chain stops.
- **Status: PASS**

---

### AC18: Unknown filename prefix emits `partial` status with prescribed message and stops chain walk

- Lines 583–587 emit a `failed` step (not `partial`) with a message, then
  `break`.
- The overall `cascade_status` is set to `"partial"` because `ANY_FAILED=true`
  is set on line 584 and the final emit at line 611 emits `"partial"`.
- The AC says "emits `partial` status with the prescribed message". If "partial
  status" refers to `cascade_status`, this is satisfied. The step itself is
  `"failed"`, which is correct per the step schema (the cascade overall becomes
  `partial`).
- **Status: PASS** (cascade_status becomes partial; step is failed which is
  the expected step-level status)

---

### AC19: `skills/work-on/scripts/run-cascade_test.sh` exists and is executable

- File exists: confirmed via Glob.
- Executable bit: not inspectable via Read; shebang present. Assumed handled at
  commit time same as AC1.
- **Status: PASS (assumed)**

---

### AC20: Test harness covers all 5 scenarios

- `scenario_design_roadmap` — DESIGN→ROADMAP (AC3)
- `scenario_design_prd_roadmap` — DESIGN→PRD→ROADMAP (AC4)
- `scenario_idempotency` — second run after PLAN is gone
- `scenario_missing_upstream` — PLAN with no upstream field
- `scenario_partial_chain` — upstream file missing (partial/failed)
- All 5 called in main (lines 536–548).
- **Status: PASS**

---

### AC21: All 5 test scenarios pass when `run-cascade_test.sh` is executed

- Cannot execute the harness in this context. However, Scenario 1
  (`scenario_design_roadmap`) will exercise the ROADMAP handler, which has the
  `**Downstream:**` update gap (AC12) and the `awk ENVIRON` gap (AC13). Those
  gaps affect internal state of the roadmap file but the test assertions only
  check the JSON output (cascade_status and step statuses), not the file
  content. So the test assertions themselves may pass even though the file
  content is wrong.
- Scenario 3 (`scenario_idempotency`): the PLAN doc is deleted in the first run
  via `git rm`. On the second run it won't exist, so the script exits 1 and the
  test accepts either `exit_code == 1` or any exit (lines 405–411 — both
  branches call `pass`). This scenario always passes regardless.
- No scenario directly tests VISION-* node behavior or unknown prefix behavior
  (ACs 17–18).
- **ADVISORY**: The test coverage is adequate for the happy paths checked by the
  AC text. The gap scenarios (VISION-* node, unknown prefix) are not covered by
  any of the 5 scenarios.
- Whether all 5 pass at runtime depends on the `awk ENVIRON` and Downstream
  update bugs surfacing through the test assertions — they likely won't since
  tests check JSON output not file mutations.
- **Status: LIKELY PASS for test assertions; runtime not verifiable here**

---

## Summary

### Blocking findings (2)

**B1 — AC12 partial: `**Downstream:**` field in ROADMAP not updated**
`handle_roadmap` computes `design_ref` (lines 363–371) but never writes it back
to the roadmap file. The `**Downstream:**` field is left unmodified after the
cascade. The AC requires updating both `**Status:**` and `**Downstream:**`.

**B2 — AC13: ROADMAP `awk` substitutions use `-v` not `ENVIRON`**
`handle_roadmap` lines 352–360 use `awk -v fline=...` for the Status
substitution. The `CASCADE_PLAN_SLUG` env var is exported (line 347) but no
`awk` block reads `ENVIRON["CASCADE_PLAN_SLUG"]`. The AC explicitly requires
`ENVIRON["varname"]` and not `-v`. This is a contract violation that also
affects AC12's missing Downstream update (which would need to be added using
`ENVIRON`).

### Advisory findings (2)

**A1 — AC14: dry-run output lacks before/after status per file**
When `--push` is omitted, the script lists staged file paths. The AC says
"per-file before/after status summary". No old/new status strings are printed.

**A2 — AC21: no test scenario covers VISION-* termination or unknown prefix**
5 scenarios exist but none exercise AC17 (VISION-* no-op) or AC18 (unknown
prefix → partial). Runtime correctness of those paths is unverified by the
test harness.
