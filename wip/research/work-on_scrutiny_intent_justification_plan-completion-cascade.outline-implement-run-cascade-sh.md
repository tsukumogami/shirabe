# Scrutiny Review: run-cascade.sh
# Reviewers: Justification + Intent (combined)
# Script: skills/work-on/scripts/run-cascade.sh
# Design: docs/designs/DESIGN-completion-cascade.md

---

## JUSTIFICATION REVIEW

### Blocking

#### J1 — `HANDLE_DESIGN_NEW_PATH` global: comment explains mechanism but not why the return value matters to the chain walk [Advisory]

The global is explained at line 45 (`# return value from handle_design (avoids subshell capture)`) and at line 281 (`# Set global return value so caller can continue chain from new path without a subshell`). The mechanism is documented. However, neither comment explains *what goes wrong if you remove this* — i.e., that `handle_design` calls `add_step`, which appends to `STEPS_JSON` (another global), and a subshell would silently discard those mutations. The next person will understand the "how" (subshell isolation) but not immediately connect it to the specific globals that would be lost. This is advisory: the comment is present and correct; the consequence requires one more mental step.

**Verdict: Advisory.**

#### J2 — Reading `upstream` before `git rm` is correct but the comment understates why it's ordering-critical [Blocking]

Lines 496–511:
```bash
# Read upstream chain before deleting the file
UPSTREAM=$(get_frontmatter_field "upstream" "$PLAN_DOC") || true

# ── Step 1: Delete PLAN doc ─────────────────
log_info "Deleting PLAN doc: $PLAN_DOC"
if git rm "$PLAN_DOC" ...
```

The comment says "Read upstream chain before deleting the file" — accurate, but it reads as a mild sequencing note. The next person will think: "sure, we read it first" but won't know that `git rm` with `set -euo pipefail` in effect would destroy the file *immediately*, making a subsequent `get_frontmatter_field` call return empty. If the next person reorders these two blocks — e.g., to log "deleting" before reading — they will get an empty `UPSTREAM` and a silent cascade of `skipped` steps with no error, because the function never exits non-zero. The comment needs to make the causal dependency explicit: reading after `git rm` silently breaks the entire upstream chain walk. **Blocking.**

#### J3 — ROADMAP Downstream field update: designed behavior differs from implemented behavior, without explanation [Blocking]

The design doc specifies (Section "ROADMAP text substitution"):
> Update the feature's `**Status:**` to `Done` and `**Downstream:**` to include the DESIGN doc at Current status, using `awk` with `ENVIRON` for literal-safe substitution.

The `handle_roadmap` function (lines 352–372) updates `**Status:**` correctly. But the `**Downstream:**` update is entirely absent. Lines 363–370 read the DESIGN path and compute `design_ref`, then do nothing with `design_ref`. There is no `awk` or `sed` call that modifies the `**Downstream:**` field. The variable `CASCADE_PLAN_SLUG` is exported (line 347) but never read by any `awk` block via `ENVIRON`. This is dead code wrapping a missing step. The design explicitly calls this out in its architecture section and the security section ("`awk` with `ENVIRON["varname"]` ... fully prevents backslash interpretation"); the implementation silently skips it. The next person will read `design_ref=$(basename ...)` and assume the downstream update happened. **Blocking.**

#### J4 — `ANY_FAILED=true` set on `update_roadmap_feature` skipped steps, but `cascade_status: partial` is the advertised outcome for skipped [Advisory]

Lines 328–331: when the feature is not found in ROADMAP, the code sets `ANY_FAILED=true` and records `status: skipped`. The design says "logs a warning, sets `cascade_status: partial`" for this case — which matches (since `ANY_FAILED=true` drives `partial`). But recording `skipped` status while setting `ANY_FAILED=true` is a semantics mismatch a future reader will notice: the step says it was skipped (implying optional/expected), but the cascade outcome says partial (implying something went wrong). The design's error message table lists this under its own failure class, separate from hard failures. The code correctly implements the design's intent, but the `ANY_FAILED=true` on a `skipped` step will confuse whoever tries to distinguish "couldn't find feature" from "script crashed." This is advisory: the design chose this behavior explicitly, but the code doesn't explain that skipped-with-failure is intentional.

**Verdict: Advisory.**

#### J5 — `awk -v fline=...` used to pass line number, but `ENVIRON` pattern specified in design for all substitutions [Advisory]

The design's security section states: "all substitutions use `awk` with `ENVIRON["varname"]` to read values from the environment rather than `-v`, which fully prevents backslash interpretation." The `**Status:** Done` substitution at line 352 uses `-v fline="$feature_line"` (a line number integer — not a user-controlled string, so the risk is zero). The design's rationale for `ENVIRON` is specifically about strings with backslashes, not integers. This is not a real risk, but it looks like the implementation didn't follow the design's prescription. A future maintainer adding a new substitution might not know which pattern to follow. **Advisory** (cosmetic divergence, no real security exposure for a line number).

---

### Summary — Justification

- **J2** (Blocking): "Read before `git rm`" comment is too weak — the consequence of reordering is silent cascade failure with no error output.
- **J3** (Blocking): `**Downstream:**` field update specified in design is entirely absent in implementation; `design_ref` is computed and discarded.
- **J1** (Advisory): `HANDLE_DESIGN_NEW_PATH` global comment explains mechanism but not the specific globals that a subshell would lose.
- **J4** (Advisory): `ANY_FAILED=true` set on `skipped` steps will confuse future readers distinguishing soft skips from hard failures.
- **J5** (Advisory): `awk -v` used for integer line number despite design prescribing `ENVIRON` for all substitutions.

---

## INTENT REVIEW

### Blocking

#### I1 — `**Downstream:**` update is unimplemented: Issue 2 and Issue 3 will test behavior that doesn't exist [Blocking]

The design's `handle_roadmap` specification (step 2) says: "Update the feature's `**Status:**` to `Done` and `**Downstream:**` to include the DESIGN doc at Current status." Only `**Status:**` is updated. The `design_ref` variable is computed but never written to the ROADMAP. Issue 3 (evals) will create a fixture with a `**Downstream:**` field and assert it was updated — those assertions will fail. Issue 2 (wiring into plan_completion) will expose this to users. This is not a missing optional enhancement; it's a specified step that silently does nothing. **Blocking.**

#### I2 — Issue URL check scope is wrong: checks only the current feature's issues, but "all features Done" guard uses all issues in the document [Blocking]

Lines 385–416: when all features are Done, the script checks for open issues before transitioning the ROADMAP to Done. Line 391:
```bash
issue_urls=$(sed -n "${feature_line},/^###/p" "$path" | grep -oE '...')
```
This extracts URLs only from the current feature entry. But the condition being guarded is "all features are Done" — meaning other features' issue URLs are equally relevant to whether the ROADMAP should be transitioned. A ROADMAP with features A (Done, issue closed) and B (Done, issue open) will be incorrectly transitioned to Done because B's issue URLs are not checked. The design says "Guard the ROADMAP Done transition: call `check_issue_closed` on any open issue URLs referenced in the feature entry" (singular), which is ambiguous — but the intent of the guard is clearly to prevent transitioning a ROADMAP whose work is not fully done. Checking only one feature's issues breaks the guard for the most common real case. **Blocking.**

#### I3 — The dry-run summary does not print before-status/after-status per the design's security spec [Advisory]

Lines 600–605 (dry-run path):
```bash
log_info "Staged (dry run — pass --push to commit):"
for f in "${STAGED_FILES[@]}"; do
    log_info "  $f"
done
```
The design's security section says: "The summary must list each file that will be staged with its before-status and after-status (e.g., `docs/designs/DESIGN-foo.md: Planned → Current`). A vague 'cascade completed' message turns the gate into theater." The implementation prints only file paths. This weakens the dry-run gate for Issue 2 callers who use the --push-less mode to verify what will happen. The design explicitly calls this "theater" if only the file list is printed. **Advisory** for Issue 2 (the wiring will work), but the dry-run safety feature is degraded.

#### I4 — `set -euo pipefail` + `git add` without `|| true` in `handle_prd` will abort the script if staging fails [Advisory]

Line 306:
```bash
git add "$path"
```
In `handle_prd`, unlike `handle_design` (line 277: `git add "$new_path" 2>/dev/null || git add "$path" 2>/dev/null || true`), there is no `|| true`. Under `set -euo pipefail`, if `git add` fails (e.g., the path was already removed, or a permissions issue), the script exits abruptly with no JSON output. Issue 3 evals will run the full chain with a PRD node; if the test environment has any git staging hiccup, the eval will get no JSON and fail in an opaque way. This is a latent issue that will surface in evals. **Advisory** (the case is unlikely but the inconsistency is a trap).

#### I5 — Chain walk reads `upstream` from `current_doc` after DESIGN handler, but `current_doc` assignment uses `HANDLE_DESIGN_NEW_PATH` only when file exists — if transition-status.sh moves the file and `git add` gets the new path, but `current_doc` stays at old path, the chain walk reads a deleted file [Advisory]

Lines 561–567:
```bash
if [[ -n "$HANDLE_DESIGN_NEW_PATH" ]] && [[ -f "$HANDLE_DESIGN_NEW_PATH" ]]; then
    current_doc="$HANDLE_DESIGN_NEW_PATH"
else
    current_doc="$next_path"
```
Then line 591:
```bash
current_upstream=$(get_frontmatter_field "upstream" "$current_doc") || true
```
If the DESIGN was moved (e.g., from `docs/designs/planned/DESIGN-foo.md` to `docs/designs/current/DESIGN-foo.md`) and `git rm` was used under the hood, the original `next_path` no longer exists on disk. The `[[ -f "$HANDLE_DESIGN_NEW_PATH" ]]` guard should correctly pick up the new path. However, `HANDLE_DESIGN_NEW_PATH` is initialized to `"$path"` (line 247) and only updated at line 282 on success. If `handle_design` returns 1 (failure), `HANDLE_DESIGN_NEW_PATH` is still the old path. On failure, `current_doc` would be the original path (possibly deleted), and the subsequent `get_frontmatter_field` call would return empty due to `2>/dev/null || true` — silently stopping the chain walk without recording why. This is an edge case but it will appear in eval coverage when transition-status.sh is stubbed to fail. **Advisory.**

---

### Coherence with Issue 2 (plan_completion wiring)

The script's CLI contract matches the design's interface specification: exit codes, `--push` flag, stdout JSON. Issue 2 can wire this as `run-cascade.sh --push {{PLAN_DOC}}` and read the JSON result. The JSON schema (cascade_status, steps array, action/target/found_in/status/detail fields) is fully implemented.

One gap: the design says the `plan_completion` directive should read the `steps` array to determine whether any `failed` or `skipped` steps require follow-up. With I1 blocking (Downstream field not updated), Issue 2's wiring will pass a cascade that missed a required step, and the agent will see `cascade_status: partial` (because `ANY_FAILED=true`) but the step record will say `skipped` — not the right signal for a missing implementation step.

### Coherence with Issue 3 (evals)

The eval fixtures include ROADMAP docs with `**Downstream:**` fields. When eval `e2e-cascade-design-roadmap` asserts that ROADMAP feature status updated, that assertion will pass. When it asserts the `**Downstream:**` field was updated to reflect the DESIGN at Current status, that assertion will fail. Issue 3 deliverables are blocked on I1 being fixed.

The eval `e2e-cascade-design-prd-roadmap` will exercise `handle_prd`, hitting the bare `git add` without `|| true` (I4). In a clean test environment this is unlikely to fail, but the inconsistency is noted.

The issue URL scope bug (I2) will not be caught by the proposed eval fixtures (which only need one feature Done to transition). Evals would need a multi-feature ROADMAP with a mix of issue states to surface this.

---

## COMBINED FINDINGS SUMMARY

### Blocking Issues (4 total)

| ID | Reviewer | Location | Issue |
|----|----------|----------|-------|
| J2 | Justification | Lines 499–511 | "Read before git rm" comment too weak — reordering silently breaks chain walk |
| J3/I1 | Both | Lines 362–370 | `**Downstream:**` update: designed, computed, then discarded — step is unimplemented |
| I2 | Intent | Lines 385–402 | Issue URL check scoped to one feature but ROADMAP Done guard requires all features' issues |

### Advisory Issues (5 total)

| ID | Reviewer | Location | Issue |
|----|----------|----------|-------|
| J1 | Justification | Line 45, 281 | `HANDLE_DESIGN_NEW_PATH` comment explains mechanism not consequence |
| J4 | Justification | Lines 328–331 | `ANY_FAILED=true` on `skipped` steps conflates soft-skip with hard failure |
| J5 | Justification | Line 352 | `awk -v` for integer despite design prescribing `ENVIRON` for all substitutions |
| I3 | Intent | Lines 600–605 | Dry-run prints only file paths, not before/after status — design calls this "theater" |
| I4 | Intent | Line 306 | `git add` without `|| true` in `handle_prd` under `set -euo pipefail` |

---

## NOTES ON CLEAN CODE

The rest of the script is clear. The `validate_upstream_path` security chain (realpath, symlink check, git-tracked check) is well-reasoned and directly maps to the design's threat model. The JSON output pattern using `jq` throughout is consistent and handles quoting correctly. The error message strings match the design's prescribed format table precisely for all cases except J3. The `VISION-*` terminal case emits no step entry, matching the design's specification. The `ROADMAP-*` as a chain-terminator (`break` after `handle_roadmap`) correctly matches the design's loop pseudocode.
