---
complexity: testable
complexity_rationale: Behavior change to a shipping skill's user-facing gate — adds a new terminal verdict path with a new commit, new prompt copy, and a public-history disclaimer. Verifiable by structural grep of the phase reference plus a manual scripted walk; no secrets or auth surface touched.
---

## Goal

Extend `/prd` Phase 4 step 4.5 from a 2-option AskUserQuestion (Approve / Request changes) to a 3-option one whose third option is **Reject**, a terminal verdict that asks for a rationale, discards the Draft PRD via `git rm` + commit, and writes the rationale through `git commit -F` (never `-m "..."`) so the discard commit becomes the durable observable signal of rejection.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

`/scope` (the parent skill the design ships) detects child Reject verdicts by reading `git log` for a discard commit on the current branch (Component 7.7, design lines 1627–1651). For that observability mechanism to exist at all, `/prd`'s Phase 4 must actually produce that discard commit when the author rejects. This issue ships the producing side of the contract: the prompt extension, the rationale capture, and the discard commit itself.

Three design constraints shape the implementation:

1. **AC30c — in-chain / out-of-chain parity.** The Reject branch must behave identically whether `/prd` was invoked by `/scope` or directly by the author. The discard commit is the durable trace in both cases; `/scope` reads it from git log when in-chain, and the author reads the same commit from git log when out-of-chain. The phase reference does not need to know which context it's running in.

2. **Security mitigation 2 — git-commit rationale interpolation** (design lines 1939–1958). The rejection rationale is a free-form author-supplied string. It may contain quotes, backticks, dollar signs, or arbitrary shell metacharacters. `git commit -m "<rationale>"` would interpolate any of these through the shell. The mitigation requires the rationale be written via `git commit -F <tmpfile>` or `git commit -F -` (stdin), bypassing shell interpolation entirely.

3. **Security mitigation 5 — public-history disclaimer** (design lines 2049–2057). The rationale lands in the repository's permanent git history. Authors must be advised before they type. The prompt's literal text SHALL include the substring `"Rationale will be committed to git history"`.

The `/strategy` Phase 5 finalize reference (`skills/strategy/references/phases/phase-5-finalize.md` lines 81–154) is the in-repo precedent for the 3-option Approve / Request changes / Reject shape, including the second-confirmation step before deletion and the `docs(<artifact>): discard <ARTIFACT> draft for <topic>` commit message form. Mirror its conventions where applicable; deviate only where `/prd`'s context requires (the discard target is `docs/prds/PRD-<topic>.md`; the wip removals are `wip/prd_<topic>_*.md` and `wip/research/prd_<topic>_phase{2,4}_*.md`).

This issue edits one file (`skills/prd/references/phases/phase-4-validate.md`). It does NOT edit `/scope` itself (that ships in PR-3), and it does NOT edit `/design`'s symmetric Phase 6 step 6.7 (that ships separately as <<ISSUE:4>>).

## Acceptance Criteria

- [ ] `skills/prd/references/phases/phase-4-validate.md` step 4.5 lists three options in the AskUserQuestion: **Approve**, **Request changes**, **Reject** (in that order, matching `/strategy` Phase 5 precedent)
- [ ] The Reject option's description in step 4.5 names that this is a terminal verdict — the Draft PRD will be deleted and the author exits the workflow
- [ ] Step 4.5's prompt copy literally contains the substring `Rationale will be committed to git history` (security mitigation 5 — verbatim disclaimer required)
- [ ] A new sub-step (e.g., 4.6.3 "If Reject" or a new step block inside 4.6 "Handle Approval") describes the rejection-handling flow with these ordered actions: (1) confirm the rejection with the user a second time before destruction, (2) prompt for the rationale string, (3) write the rationale to a tmpfile, (4) `git rm docs/prds/PRD-<topic>.md`, (5) `rm -f wip/prd_<topic>_*.md` and `rm -f wip/research/prd_<topic>_phase{2,4}_*.md`, (6) `git commit -F <tmpfile>` with the message subject `docs(prd): discard PRD draft for <topic>`, (7) exit the workflow
- [ ] The rationale-write instruction in the rejection sub-step uses `git commit -F <tmpfile>` (or `git commit -F -` via stdin) — the file MUST NOT instruct authors to use `git commit -m "<rationale>"` or any other form that pipes the rationale through shell argument parsing (security mitigation 2)
- [ ] The commit message subject string matches the regex `^docs\(prd\): discard PRD draft for <topic>$` so `/scope`'s git-log search in Component 7.7 (design lines 1632–1635) finds the commit
- [ ] Existing step 4.6 "Handle Approval" continues to work end-to-end for the Approve and Request changes branches (no regression in either non-Reject path)
- [ ] Cleanup step 4.7's `rm -f` block remains correct for the Approve path: rejection clean-up happens inside the Reject branch and need not duplicate inside 4.7
- [ ] The file passes `grep -q 'Rationale will be committed to git history' skills/prd/references/phases/phase-4-validate.md`
- [ ] The file passes `grep -q 'git commit -F' skills/prd/references/phases/phase-4-validate.md`
- [ ] The file passes `! grep -E 'git commit -m "[^"]*\$\{?rationale' skills/prd/references/phases/phase-4-validate.md` (no unsafe `-m`-style interpolation of the rationale variable)
- [ ] The file passes `grep -q 'docs(prd): discard PRD draft for <topic>' skills/prd/references/phases/phase-4-validate.md`
- [ ] No other phase reference (`phase-1-scope.md`, `phase-2-discover.md`, `phase-3-draft.md`) is modified by this issue
- [ ] Must deliver: a Phase 4 step 4.5 emitting one of three terminal verdicts (Approve / Request changes / Reject), where Reject produces a discoverable discard commit on the current branch (required by <<ISSUE:4>> and <<ISSUE:11>>)
- [ ] Must deliver: the literal commit-subject convention `docs(prd): discard PRD draft for <topic>` (required by <<ISSUE:11>> — `/scope`'s Component 7.7 git-log search reads this exact string)
- [ ] CI green

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

PHASE_FILE="skills/prd/references/phases/phase-4-validate.md"

# 1. File still exists and is non-empty
test -s "$PHASE_FILE"

# 2. Three-option contract: all three verdict labels present in 4.5
grep -q '\*\*Approve\*\*' "$PHASE_FILE"
grep -q '\*\*Request changes\*\*' "$PHASE_FILE"
grep -q '\*\*Reject\*\*' "$PHASE_FILE"

# 3. Public-history disclaimer text appears verbatim (security mitigation 5)
grep -q 'Rationale will be committed to git history' "$PHASE_FILE"

# 4. git commit uses -F file/stdin path, never -m with the rationale (security mitigation 2)
grep -q 'git commit -F' "$PHASE_FILE"

# 5. Discard commit subject matches the contract /scope's git-log search reads
grep -q 'docs(prd): discard PRD draft for <topic>' "$PHASE_FILE"

# 6. git rm of the canonical PRD path appears in the Reject branch
grep -q 'git rm docs/prds/PRD-<topic>.md' "$PHASE_FILE"

# 7. Negative check: rationale is never inlined into a -m argument
if grep -nE 'git commit -m[^F]*rationale' "$PHASE_FILE"; then
  echo "FAIL: unsafe 'git commit -m' pattern referencing rationale found"
  exit 1
fi

# 8. wip cleanup names the prd_ and research/ paths in the Reject branch
grep -q 'wip/prd_<topic>_' "$PHASE_FILE"
grep -q 'wip/research/prd_<topic>_' "$PHASE_FILE"

# 9. No accidental edits to sibling phases
for sibling in phase-1-scope.md phase-2-discover.md phase-3-draft.md; do
  test -s "skills/prd/references/phases/$sibling"
done

# 10. The skill's frontmatter / SKILL.md is untouched by this issue
if [ -n "$(git diff --name-only origin/main -- 'skills/prd/SKILL.md' 2>/dev/null || true)" ]; then
  echo "WARN: skills/prd/SKILL.md modified — confirm this is intended for this issue"
fi

echo "All validations passed"
```

## Dependencies

None — this issue edits a single phase reference inside `/prd` and has no upstream blockers.

## Downstream Dependencies

This issue is consumed by two downstream issues:

- **<<ISSUE:4>>** — symmetric edit on `/design` Phase 6 step 6.7. <<ISSUE:4>> mirrors this issue's structure for `/design`. By landing the `/prd` shape first, <<ISSUE:4>> can adopt the same prompt copy, the same `git commit -F` pattern, the same disclaimer substring, and the same `docs(<artifact>): discard <ARTIFACT> draft for <topic>` subject convention. The artifacts <<ISSUE:4>> needs from here are: (a) the literal disclaimer substring text, (b) the `git commit -F` write pattern, (c) the second-confirmation prompt copy, (d) the ordered-action sequence inside the Reject branch. <<ISSUE:4>> can copy these verbatim and substitute "PRD" → "DESIGN" / "prd" → "design" / `docs/prds` → `docs/designs`.

- **<<ISSUE:11>>** — `/scope` Component 7.7 git-log reading. <<ISSUE:11>> implements `/scope`'s Phase-N Reject detector, which searches `git log` on the current branch for `docs(prd): discard PRD draft for <topic>` (and the `/design` symmetric subject). <<ISSUE:11>> depends on this issue locking in the commit-subject string `docs(prd): discard PRD draft for <topic>` exactly — any drift in subject wording breaks the detector. The rationale-in-commit-body delivery (via `-F`) also means <<ISSUE:11>> can read the rationale back from the commit object when writing the rejection-sub-shape Decision Record, without needing `/prd` to surface it through any other channel.
