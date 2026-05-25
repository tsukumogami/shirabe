---
complexity: testable
complexity_rationale: New behavior on an existing AskUserQuestion gate plus filesystem-mutating discard branch (git rm, wip cleanup, commit via stdin). Not security-critical at the auth/secrets level, but the rationale-interpolation mitigation and the post-commit ordering invariant must be verified — covered by a follow-on eval issue and a validation script here.
---

## Goal

Replace `/design` Phase 6 step 6.7's existing 2-option AskUserQuestion (Approved / Needs iteration) with a 3-option gate (Approved / Reject / Continue-revising), where the Reject branch prompts for a rationale, runs `git rm docs/designs/DESIGN-<topic>.md`, removes `wip/design_<topic>_*.md` and `wip/research/design_<topic>_*.md`, and commits `docs(design): discard DESIGN draft for <topic>` with the rationale supplied via `git commit -F -` (stdin), so direct-invocation `/design` authors get a first-class Reject verdict and the discard commit becomes the durable greppable trace `/scope` Phase 2 will observe in PR-4.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

The design's Component 8.2 (lines 1671-1683) and Decision 1 / Option A (lines 327-365, 341-348) settle the gate placement: the existing finalization step in `/design`'s Phase 6 grows a third option in parallel to the existing two, rather than gaining a new pre-gate step. This mirrors `/strategy` Phase 5.2's already-shipped 3-option gate (Approve / Request changes / Reject — see `skills/strategy/references/phases/phase-5-finalize.md`) and ships in parallel to <<ISSUE:3>>'s `/prd` Phase 4 step 4.5 edit. The Reject sub-shape on `/design` is the second half of R23 in `PRD-shirabe-scope-skill.md`; both must exist before `/scope` Phase 2 (delivered by <<ISSUE:11>>) can observe the discard commits as the in-chain Reject signal.

Two contract details specific to the `/design` side that diverge from `/prd`:

1. **Wip cleanup set is wider.** `/design` writes intermediate artifacts to BOTH `wip/design_<topic>_*.md` AND `wip/research/design_<topic>_*.md` (Phase 6 Quality Checklist references both). Reject must clean both, not just the top-level set.
2. **Post-commit ordering invariant.** Decision 1's rejected Option C (lines 379-391) is load-bearing here: `/design` Phase 6 commits the design BEFORE the approval prompt fires (the current step 6.6 Commit / 6.7 Approve ordering). The Reject gate MUST stay AFTER the commit step — the existing commit-then-approve ordering preserves the Draft as a durable artifact across interruptions, and adding `git rm` on Reject is the smaller cost than losing durability. The phase ordering and the durability invariant must both survive this edit.

The gate fires identically in-chain (via `/scope`) and out-of-chain (direct `/design <topic>` invocation) per AC30c. On in-chain Reject, control returns to `/scope`, which writes a rejection-sub-shape Decision Record per Component 7.7 referencing the discard commit SHA (not the absent artifact). On out-of-chain Reject, the discard commit alone is the durable trace and no Decision Record is written. This issue ships only the `/design`-side contract; the `/scope`-side write of the Decision Record is downstream (<<ISSUE:11>> via Component 7's in-chain Reject handling).

Two Security Considerations mitigations bind directly to this issue:

1. **Command injection — git-commit rationale interpolation** (Security Considerations / lines 1939-1957). The author-supplied rejection rationale is a free-form string and MUST be passed via `-F <tmpfile>` or stdin (`git commit -F -`), never inlined into `git commit -m "..."`. Inlining is unsafe because shell metacharacters (quotes, backticks, dollar signs) in the rationale would reach the shell.
2. **Visibility-boundary binding and Decision Record content disclosure / Mitigation 2 — rationale-field public-history disclaimer** (lines 2049-2057). The Reject prompt's literal text MUST include the substring "Rationale will be committed to git history" so authors are advised the rationale becomes part of the repository's permanent git history.

## Acceptance Criteria

- [ ] `skills/design/references/phases/phase-6-final-review.md` step 6.7 ("Present for Approval") is edited so the AskUserQuestion offers three options: **Approved**, **Reject**, **Continue-revising** (the existing "Needs iteration" branch is renamed to "Continue-revising" but preserves identical behavior; the existing "Approved" branch is unchanged).
- [ ] The Reject option's prompt text (or accompanying step description) contains the literal substring `Rationale will be committed to git history` so authors are advised the rationale becomes part of permanent git history.
- [ ] A new step 6.8 "If Reject" handler (or equivalent sub-section under the existing approval handling) documents the Reject branch with these exact mechanics, in order:
  1. Ask the author for a one-sentence rejection rationale (free-form string).
  2. Run `git rm docs/designs/DESIGN-<topic>.md` against the durable artifact.
  3. Remove `wip/design_<topic>_*.md` AND `wip/research/design_<topic>_*.md` (both sets).
  4. Commit with the message `docs(design): discard DESIGN draft for <topic>` and the rationale as the commit body; the commit body MUST be passed via `git commit -F -` (stdin) or `git commit -F <tmpfile>`, NEVER via `git commit -m "..."` with the rationale inlined into a shell-interpreted argument.
  5. Exit the phase (no status flip to Accepted, no Planned → Current move, no PR creation beyond the discard commit itself).
- [ ] The Reject branch fires AFTER the existing step 6.6 Commit step. The current ordering (commit-then-approve) is preserved so the Draft artifact remains durable across session interruptions; the new step MUST NOT reorder 6.6 and 6.7 (Decision 1 Option C is explicitly rejected for the durability reason).
- [ ] The existing 6.8 "Handle Approval / If approved" handler is left structurally intact; the renamed "Continue-revising" branch is the existing "Needs iteration" branch with identical behavior (loop back to the relevant phase, re-run Phase 6 when changes complete).
- [ ] The existing 6.9 "Clean Up wip/ Artifacts" step is NOT moved or reordered; the Reject branch performs its own wip cleanup inline because no Phase 6.9 path runs after Reject (Reject exits the phase immediately after the discard commit).
- [ ] The 3-option gate behaves identically whether `/design` is invoked directly or via `/scope` (AC30c). The phase reference MUST NOT add in-chain-only branching; the discard commit is the contract surface both invocation modes observe.
- [ ] No reference to `/scope`-side Decision Record writing in this issue's edits — that is `/scope`'s responsibility (delivered by <<ISSUE:11>>). The `/design` side stops at the discard commit.
- [ ] No `wip/...` paths leak into the design body or any committed prose beyond the phase reference's documentation of the cleanup commands themselves (wip-hygiene rule: quoted statements OF the cleanup commands are acceptable; path-shaped references that survive cleanup are not).
- [ ] No reference to private repos, internal resources, or pre-announcement features (shirabe is public).
- [ ] Markdown lints clean per repo conventions; no emojis; no AI attribution lines on the commit produced by the edit itself.
- [ ] Must deliver: a Reject branch on `/design` Phase 6 step 6.7 that produces the canonical discard commit message `docs(design): discard DESIGN draft for <topic>` with the rationale body via stdin (required by <<ISSUE:6>> for eval scenarios and by <<ISSUE:11>> for `/scope` Phase 2's `git log` observation of the discard signal).
- [ ] Tests pass (run project's test command).
- [ ] CI green.

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

PHASE_FILE="skills/design/references/phases/phase-6-final-review.md"

# The phase reference exists.
test -f "$PHASE_FILE"

# Three-option gate literals are present in step 6.7's vicinity.
grep -q 'Approved' "$PHASE_FILE"
grep -q 'Reject' "$PHASE_FILE"
grep -q 'Continue-revising' "$PHASE_FILE"

# Public-history disclaimer is present (Security Considerations mitigation 2).
grep -q 'Rationale will be committed to git history' "$PHASE_FILE"

# The git rm target uses the design path.
grep -qE 'git rm[[:space:]]+docs/designs/DESIGN-' "$PHASE_FILE"

# Both wip cleanup sets are documented (design-side asymmetry vs /prd).
grep -qE 'wip/design_' "$PHASE_FILE"
grep -qE 'wip/research/design_' "$PHASE_FILE"

# The discard commit message is the canonical one.
grep -qE 'docs\(design\): discard DESIGN draft for' "$PHASE_FILE"

# The rationale-via-stdin mitigation is documented; the unsafe inline form
# MUST NOT appear in the Reject handler.
grep -qE 'git commit -F' "$PHASE_FILE"
if grep -nE 'git commit -m[[:space:]]+"[^"]*\$' "$PHASE_FILE"; then
  echo "ERROR: phase reference shows unsafe 'git commit -m \"...\"' with shell-interpolated rationale"
  exit 1
fi

# The existing approval step (6.7) and commit step (6.6) ordering is preserved:
# step 6.6 (Commit and PR) must appear textually before step 6.7 in the file.
commit_line=$(grep -nE '^### 6\.6 ' "$PHASE_FILE" | head -1 | cut -d: -f1)
approve_line=$(grep -nE '^### 6\.7 ' "$PHASE_FILE" | head -1 | cut -d: -f1)
if [ -z "$commit_line" ] || [ -z "$approve_line" ]; then
  echo "ERROR: could not locate steps 6.6 and 6.7 in the phase reference"
  exit 1
fi
if [ "$commit_line" -ge "$approve_line" ]; then
  echo "ERROR: step 6.6 (Commit) must appear before step 6.7 (Approval) to preserve Draft durability"
  exit 1
fi

# wip-hygiene: no wip/ path-shaped references appear in committed design docs
# under docs/designs/ (the phase reference itself is allowed to name wip/
# paths because it documents the cleanup commands).
if git grep -nE '\bwip/' -- 'docs/designs/*.md' 2>/dev/null; then
  echo "ERROR: wip/ path leaked into a committed design doc"
  exit 1
fi

echo "All validations passed"
```

## Dependencies

None — this issue is the first half of PR-3 and has no upstream blockers. The design treats this as parallel to <<ISSUE:3>> (`/prd` Phase 4 Reject), and both can ship independently.

## Downstream Dependencies

- <<ISSUE:6>> — `test(design): add Phase 6 Reject contract eval scenario`. The eval scenario in `skills/design/evals/evals.json` exercises the 3-option gate this issue ships: Approve / Reject / Continue-revising outcomes, the discard commit message format, the `git rm` of `docs/designs/DESIGN-<topic>.md`, both wip cleanup sets (`wip/design_*` and `wip/research/design_*`), and the rationale-via-stdin behavior. <<ISSUE:6>> grep-asserts against the file artifacts this issue produces.
- <<ISSUE:11>> — `feat(scope): add /scope phase reference files (Phase 0-4)`. The `/scope` Phase 2 chain-orchestration phase reference observes the discard commit (`docs(design): discard DESIGN draft for <topic>`) via `git log` as the in-chain Reject signal from `/design`, then writes a rejection-sub-shape Decision Record per Component 7.7. The discard commit produced by this issue is the contract surface <<ISSUE:11>> reads; without this issue's edits, `/scope`'s in-chain Reject path has no signal to observe.
