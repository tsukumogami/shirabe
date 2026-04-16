---
name: Maintainer review — run-cascade.sh
description: Understandability, naming, and implicit contract findings for run-cascade.sh
type: reference
---

# Maintainer Review: run-cascade.sh

## Findings

### 1. BLOCKING — `HANDLE_DESIGN_NEW_PATH` and `CASCADE_DESIGN_PATH` are indistinguishable by name

Both are globals. `HANDLE_DESIGN_NEW_PATH` is a return-value slot from `handle_design` to its immediate caller (the main loop). `CASCADE_DESIGN_PATH` is set by the main loop and consumed later by `handle_roadmap`. A future developer reading `handle_roadmap` has no way to know that `CASCADE_DESIGN_PATH` is populated by a sibling branch of the same loop, not by `handle_roadmap` itself. The comment on line 46 helps but is easy to miss. The naming does not distinguish "this is a return slot" from "this is cross-handler shared state".

**Fix:** Rename `HANDLE_DESIGN_NEW_PATH` to `_RETURN_design_new_path` (or a similar convention that signals it's a one-way return channel) and add an assertion in the main loop that resets it before each `handle_design` call, so stale values from a prior iteration don't silently propagate.

---

### 2. BLOCKING — `get_frontmatter_field` uses awk with shell-interpolated single-quote escaping (line 72)

```awk
gsub(/^'"'"'|'"'"'$/, "")
```

This is the standard `'"'"'` trick to embed a literal single quote inside a single-quoted shell string, but it is visually opaque. Anyone maintaining the awk block will not immediately know whether the pattern is correct. More importantly, the `count == 1 && $0 ~ "^" field ": "` match (line 69) uses dynamic regex construction with an unescaped user-supplied `field` value. If a field name ever contains regex metacharacters (e.g., `upstream+v2`), the awk regex will silently mismatch or error. The function is called for all frontmatter fields in the cascade.

**Fix:** Use `index($0, field ": ") == 1` (literal prefix match) instead of `$0 ~ "^" field ": "` to avoid regex injection; and replace the escaped single-quote awk literal with a `gsub(/^['"]|['"]$/, "")` approach using double-quoted awk string, or a simpler `sub(/^'/, ""); sub(/'$/, "")` pair outside awk.

---

### 3. BLOCKING — The implicit chain termination rule is undocumented at the call site

The main `while` loop (line 537) terminates when:
- `current_upstream` is empty (normal end of chain)
- `ROADMAP-*` is reached (explicit `break`)
- `VISION-*` is reached (explicit `break`)
- an unrecognized prefix is reached (explicit `break`)
- `validate_upstream_path` fails (explicit `break`)

None of these termination conditions are summarized anywhere. A developer adding a new artifact type (e.g., `EPIC-*`) must infer that they need to add both a `case` branch and decide whether to `break` or `continue`. The fact that ROADMAP is always terminal is architecturally significant (it closes the chain) but is buried in a comment on line 589 and is not reflected in the loop structure.

**Fix:** Add a two-line block comment above the `while` loop naming all termination conditions explicitly. Consider extracting a `is_terminal_node()` helper that documents the terminal set.

---

### 4. ADVISORY — `strip_implementation_issues` uses `mktemp` + `mv` without a trap

`strip_implementation_issues` creates a temp file (line 184) and moves it over the original. If the script is killed between `awk ... > "$tmp"` and `mv "$tmp" "$doc"`, the temp file is leaked and the original is intact — that's fine. But there is no `trap ... EXIT` to clean up `$tmp` on exit, so temp files accumulate in `$TMPDIR` on repeated failures. The same pattern repeats in `handle_roadmap` (lines 350, 369). The test harness creates a new `mktemp -d` repo per scenario and `rm -rf`s it, so tests don't catch the leak.

**Fix (advisory):** Add a single `trap 'rm -f "$tmp"' EXIT` inside each function that uses `mktemp`, or use a shared cleanup trap at the top level.

---

### 5. ADVISORY — `add_step` requires callers to pass `"null"` as a string literal for absent `found_in`

The function signature (line 196-200) says `pass "null" for no found_in`, and callers do this (`add_step "delete_plan" "$PLAN_DOC" "null" ...`). This is a convention that must be known; passing an empty string instead would produce `""` in the JSON rather than `null`. There is no guard. A future caller who passes `""` will produce structurally different JSON than documented in the header.

**Fix:** Accept an empty string as sentinel and normalize inside `add_step`: `if [[ -z "$found_in" || "$found_in" == "null" ]]; then found_in_json="null"; fi`.

---

### 6. ADVISORY — Commit message is hard-coded and non-descriptive (line 613)

```bash
git commit -m "chore(cascade): post-implementation artifact transitions"
```

This message will be identical for every cascade run across every PLAN. A maintainer running `git log` after several merged plans will see a string of identical commits with no traceability back to which PLAN triggered each. Including the plan slug in the message costs one interpolation.

**Fix:** `git commit -m "chore(cascade): post-implementation transitions for $PLAN_SLUG"`.

---

## Summary

| # | Severity | Description |
|---|----------|-------------|
| 1 | Blocking | Global naming doesn't distinguish return-slot from cross-handler state |
| 2 | Blocking | Dynamic regex in `get_frontmatter_field` is fragile and visually unreadable |
| 3 | Blocking | Chain termination rules undocumented — new artifact types require inference |
| 4 | Advisory | `mktemp` files not cleaned up on failure |
| 5 | Advisory | `add_step` requires magic string `"null"` with no guard for empty string |
| 6 | Advisory | Hard-coded commit message loses traceability across plan runs |
