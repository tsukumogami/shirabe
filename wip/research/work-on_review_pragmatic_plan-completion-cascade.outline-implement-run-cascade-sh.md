---
name: Pragmatic review — run-cascade.sh
description: YAGNI/KISS findings for skills/work-on/scripts/run-cascade.sh
type: reference
---

# Pragmatic Review: run-cascade.sh

## Findings

### 1. BLOCKING — Dead else-branch on symlink check (line 555)

```
elif [[ -L "$next_path" ]] || [[ ! -f "$next_path" ]]; then
```

The condition `[[ ! -f "$next_path" ]]` on this branch is unreachable: the preceding `if [[ ! -f "$next_path" ]]` on line 553 already handled the missing-file case and fell through; if we reach `elif`, the file _does_ exist, so `! -f` is always false. The whole elif resolves to just `[[ -L "$next_path" ]]`, but that case is also already caught by `validate_upstream_path` (which checks for symlinks and would have returned 1, setting ANY_FAILED=true and breaking). This branch will never fire, and its error message ("resolves outside the repository root") is misleading for what it would actually catch. Delete lines 555-557 and merge the symlink/escape message into the else.

**Fix:** Collapse the three-way if/elif/else into two branches: file-not-found and catch-all (untracked or other).

---

### 2. BLOCKING — Global mutable return value instead of process substitution (line 45, 283)

`HANDLE_DESIGN_NEW_PATH` is a global variable used as a return channel from `handle_design` to avoid a subshell. This pattern is non-standard, creates hidden state, and will silently produce wrong results if `handle_design` is ever called in a loop or from two call sites. The script already uses `set -euo pipefail`; a helper that prints its result to stdout and is called with `result=$(...)` is safe here because the git staging side-effect is the only reason to avoid the subshell — and that side-effect could be returned as part of the stdout JSON or handled by the caller. The global works now but is a trap for the next person who adds a second DESIGN node to the chain.

**Fix:** Return the new path via stdout and capture with `new_path=$(handle_design ...)`, staging the file inside the caller after capture; or at minimum rename to `_HANDLE_DESIGN_RETURN_PATH` and add a comment that it is a return-value slot, not state.

---

### 3. ADVISORY — `CASCADE_DESIGN_PATH` global set in loop, consumed in handler (lines 46, 578, 365)

`CASCADE_DESIGN_PATH` is set by the main loop after `handle_design` runs, then read inside `handle_roadmap` via `${CASCADE_DESIGN_PATH:-}`. This is an implicit contract across two scopes with no local parameter. It works correctly for chains where DESIGN always precedes ROADMAP, but the coupling is invisible. If a ROADMAP-* node appears without a prior DESIGN-* (valid: a plan that has no design and links straight to a ROADMAP), `CASCADE_DESIGN_PATH` will be empty and the Downstream update will silently no-op.

**Fix:** Pass `CASCADE_DESIGN_PATH` as an explicit argument to `handle_roadmap`; change its signature to `handle_roadmap <path> <found-in> <plan-slug> <design-path-or-empty>`.

---

### 4. ADVISORY — `export` of `CASCADE_FEATURE_LINE` / `CASCADE_DOWNSTREAM_LINE` into environment (lines 345-346)

These two variables are exported to let awk read them via `ENVIRON[]`. Exporting process-local scratch variables into the environment is a side-effect that can leak into child processes (including the `bash "$script"` calls that follow in the same function). Using awk `-v` for numeric values and a here-doc or pipe for strings avoids the export entirely. The comment "not -v" suggests there was a specific reason, but numeric line numbers have no quoting issues with `-v`.

**Fix:** Replace `export CASCADE_FEATURE_LINE` and use `awk -v fline="$feature_line"` directly; same for `CASCADE_DOWNSTREAM_LINE`. Remove the export.

---

### 5. ADVISORY — Script locates `transition-status.sh` via two fallback strategies only for DESIGN (lines 255-259)

`handle_design` has a two-path script resolution (`$(dirname "$(dirname "$0")")/../../skills/design/scripts/transition-status.sh` first, then `$REPO_ROOT/...`). `handle_prd` and `handle_roadmap` use only `$REPO_ROOT/...`. The DESIGN path is the odd one out and the primary path looks incorrect (`dirname dirname $0` backs up two levels from `scripts/`, which gives `skills/work-on`, not the repo root). In practice the fallback always fires. The primary path is dead.

**Fix:** Remove the primary path discovery in `handle_design` (lines 255-258) and align with the `$REPO_ROOT/...` pattern used by the other two handlers.

---

## Summary

| # | Severity | Description |
|---|----------|-------------|
| 1 | Blocking | Dead/unreachable elif branch with misleading error message |
| 2 | Blocking | Global variable as function return channel — silent wrong-result trap |
| 3 | Advisory | Implicit cross-scope coupling via `CASCADE_DESIGN_PATH` global |
| 4 | Advisory | Unnecessary environment export of scratch variables for awk |
| 5 | Advisory | Dead primary path in `handle_design` script resolution |
