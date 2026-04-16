---
name: Architect review — run-cascade.sh
description: Structural fit, interface contracts, dependency direction findings for run-cascade.sh
type: reference
---

# Architect Review: run-cascade.sh

## Context

`run-cascade.sh` is the post-implementation lifecycle script for the `work-on` skill. It walks a PLAN → DESIGN → PRD → ROADMAP frontmatter chain and delegates each node's transition to the owning skill's `transition-status.sh`. It is the only consumer of those three transition scripts in this context.

---

## Findings

### 1. BLOCKING — Output contract mixes stdout (JSON) and git side-effects non-atomically

The script stages files with `git add` inside each handler, accumulates them in `STAGED_FILES[]`, and only commits at the end if `--push` is set. If the script is killed between two `git add` calls, the working tree is partially staged with no way for the caller to know which nodes completed. The output JSON does indicate which steps succeeded, but a caller that relies on exit code 0 + `cascade_status: completed` has no guarantee the git index matches the reported steps — partial staging is invisible in the JSON.

The transition scripts (`design/transition-status.sh`) also call `git mv` internally, meaning some index changes happen inside subshells with no coordination back to `STAGED_FILES`. If `handle_design` succeeds but the subsequent `git add "$new_path"` (line 278) fails silently (it is `|| true`), the design move is in the index but not in `STAGED_FILES`, so it won't appear in the dry-run log and the commit will include it unexpectedly.

**Fix:** Either (a) move all git staging out of handlers into a post-loop commit phase driven entirely by the JSON step results, or (b) document explicitly that the caller must treat any non-`--push` run as advisory-only and always verify with `git status` before committing.

---

### 2. BLOCKING — Dependency inversion: `run-cascade.sh` hard-codes knowledge of artifact types and their transition targets

The main dispatch loop (lines 572-603) hard-codes `DESIGN-* → transition_design`, `PRD-* → transition_prd`, `ROADMAP-* → update_roadmap_feature + transition_roadmap`. Adding a new artifact type (e.g., an `EPIC-*` layer) requires editing `run-cascade.sh` itself. The owning skill's `transition-status.sh` already encapsulates the transition logic — the orchestrator shouldn't also need to know the type mapping. This compounds: the same filename-prefix dispatch appears in both the main loop and the validation error block (lines 561-565), so a new type must be added in two places.

**Fix:** Define the dispatch table in one place (the `case` statement) and reference it from the error block by extracting `artifact_type` before the `if`/`elif` tree. For a longer-term fix, transition scripts could self-describe their artifact prefix via a `--describe` flag, removing the hard-coding from the orchestrator entirely.

---

### 3. BLOCKING — `handle_roadmap` modifies the file before checking whether all features are Done

The awk rewrites for Status and Downstream (lines 350-382) happen unconditionally. Only after both writes does the script check `all_done` (line 387) and potentially attempt the ROADMAP-level transition. If the ROADMAP transition then fails or is skipped (open issue guard), the feature entry has already been mutated. This is correct behavior in the success path, but it means a skipped `transition_roadmap` step leaves the ROADMAP in a partially-updated state (feature marked Done, Downstream updated) with no rollback and no indication in the step output that the file was modified.

The `add_step "update_roadmap_feature" ... "ok"` (line 384) fires before the all-done check and the potential `transition_roadmap` skip, so the caller sees `update_roadmap_feature: ok` + `transition_roadmap: skipped` but cannot tell that the ROADMAP file on disk differs from what git has staged.

**Fix:** Either stage the ROADMAP file only after all operations on it complete (move `git add "$path"` from line 432 to after the all-done block), or emit a distinct `update_roadmap_feature` step status that indicates partial completion when the roadmap-level transition was skipped.

---

### 4. ADVISORY — Caller contract for `--push` is ambiguous: "dry run" is a misnomer

The header comment says "Without this flag, the script stages changes and prints a per-file status summary but does not commit or push. Use --push for automated cascade; omit for dry-run." Staging changes is not a dry run — it modifies the git index. A caller who omits `--push` expecting no side-effects will be surprised that `git status` shows staged files. The flag should be described as "commit and push" vs. "stage only", not "push" vs. "dry-run".

This also means the script cannot be run in a true preview mode without a separate worktree or stash, which limits its use as a plan-phase inspection tool.

**Fix (advisory):** Rename the no-`--push` description to "stage-only mode" in the usage text and header comment, and add a `--dry-run` flag that performs all validation and JSON reporting without modifying any file or the git index.

---

### 5. ADVISORY — `check_issue_closed` validates origin URL but has no timeout or retry

The `gh issue view` call (line 160) is a network operation with no timeout. If the GitHub API is slow or `gh` is not authenticated, the cascade blocks indefinitely on ROADMAP-level transitions. Given that this script is invoked by an automated agent (as the skill description implies), an unbounded network call in the hot path is a reliability risk.

**Fix:** Wrap the `gh` call with a timeout (e.g., `timeout 15 gh issue view ...`) and treat timeout as `return 1` (issue assumed open / not closeable).

---

## Summary

| # | Severity | Description |
|---|----------|-------------|
| 1 | Blocking | Non-atomic git staging — partial index state invisible to caller |
| 2 | Blocking | Artifact type dispatch hard-coded in two places in the orchestrator |
| 3 | Blocking | ROADMAP file mutated before all-done guard; partial state not surfaced in step output |
| 4 | Advisory | `--push`-less mode described as "dry-run" but stages files |
| 5 | Advisory | Unbounded network call in `check_issue_closed` |
