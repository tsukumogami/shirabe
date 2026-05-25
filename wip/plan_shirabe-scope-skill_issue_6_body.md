---
complexity: testable
complexity_rationale: Adds eval scenarios that verify behavioral contracts (3-option gate, discard commit message format, git rm of durable artifact, wip cleanup including wip/research/design_*, rationale-via-stdin) — testable additions to `skills/design/evals/evals.json` with grep-checkable surface and a validation script.
---

## Goal

Add eval scenarios to `skills/design/evals/evals.json` covering the Approve / Reject / Continue-revising outcomes of `/design`'s Phase 6 step 6.7 3-option gate, verifying the discard commit message format, the `git rm` of the durable DESIGN artifact, the `wip/design_<topic>_*` and `wip/research/design_<topic>_*` cleanup, the rationale-via-stdin behavior, and both in-chain and out-of-chain Reject paths per AC30c.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

`/scope` ships as the second parent skill in shirabe (Solution Architecture / Component 5). Its terminal-child PLAN exit and its re-evaluation Decision Record exits depend on `/prd` and `/design` having a Phase-N Reject finalization contract (R23). `<<ISSUE:5>>` ships that contract for `/design` (Component 8.2 — replaces Phase 6 step 6.7's existing 2-option AskUserQuestion with a 3-option gate; on Reject runs `git rm docs/designs/DESIGN-<topic>.md`, removes `wip/design_<topic>_*.md` and `wip/research/design_<topic>_*.md`, commits `docs(design): discard DESIGN draft for <topic>` via `git commit -F -`).

This issue ships the eval coverage for `<<ISSUE:5>>`'s contract. Without an eval scenario, the contract's behavioral surface is only ratified by reviewer reading — `scripts/run-evals.sh design` would pass even if the implementation silently regressed the Reject branch or skipped the wip cleanup. The Implementation Approach / Phase B section of the design names eval coverage as the second deliverable for each child-side contract extension; this issue closes that gap for `/design`.

The eval scenarios sit parallel to `<<ISSUE:4>>`'s `/prd` Phase 4 Reject coverage. The two scenarios diverge in three behaviors specific to `/design`:

1. The discarded artifact path is `docs/designs/DESIGN-<topic>.md` (not `docs/prds/PRD-<topic>.md`).
2. The wip cleanup set includes both `wip/design_<topic>_*.md` AND `wip/research/design_<topic>_*.md` — the `/design` skill produces research artifacts at `wip/research/design_<topic>_phase<N>_<role>.md` that `/prd` does not, so the Reject branch must remove both prefixes.
3. The gate fires AFTER `/design`'s existing commit step (preserving Draft durability across interruptions per D1 Option C rejection rationale) — the eval scenario must verify the commit-then-reject ordering, not commit-after-reject.

The discard commit format (`docs(design): discard DESIGN draft for <topic>` with the rationale in the body), the rationale-via-stdin discipline (`git commit -F -`, never `-m "..."`), the Reject-prompt disclaimer substring (`Rationale will be committed to git history`), and the 3-option Approve / Reject / Continue-revising prompt shape are uniform across both children.

The AC30c in-chain vs out-of-chain distinction is observable but not in this issue's scope to verify end-to-end against `/scope`: `/scope` doesn't exist yet (Components 5/6/7 land in PR-4). The eval scenarios here verify the child-side contract behavior — the discard commit IS the durable trace that an eventual in-chain run reads via `referenced_artifact:` in the Decision Record per Component 7.7 + D5's frozen-snapshot rule. The out-of-chain case is the steady-state behavior the eval exercises directly.

## Acceptance Criteria

- [ ] `skills/design/evals/evals.json` gains one new eval scenario covering the 3-option gate behavior at `/design` Phase 6 step 6.7
- [ ] The new scenario's `name` field is a kebab-case identifier reflecting the Reject contract (e.g., `phase-6-reject-contract` or similar)
- [ ] The new scenario's `prompt` field exercises a path that reaches Phase 6 step 6.7 (e.g., `/design --auto <topic>` followed by selecting the Reject branch, or an equivalent invocation pattern consistent with adjacent design evals)
- [ ] The new scenario's `expected_output` field names all five required behaviors literally:
  - [ ] 3-option AskUserQuestion (Approved / Reject / Continue-revising) replaces the prior 2-option gate
  - [ ] On Reject: `git rm docs/designs/DESIGN-<topic>.md` runs against the durable artifact
  - [ ] On Reject: `wip/design_<topic>_*.md` AND `wip/research/design_<topic>_*.md` are both removed (literal mention of both prefixes)
  - [ ] On Reject: a discard commit is created with the exact message format `docs(design): discard DESIGN draft for <topic>` and the rationale in the commit body
  - [ ] On Reject: the rationale reaches `git commit` via `-F -` (stdin), never via `-m "..."` (Security Considerations / Command injection — git-commit rationale interpolation)
- [ ] The new scenario's `expected_output` notes the Reject prompt's literal disclaimer substring `Rationale will be committed to git history`
- [ ] The new scenario's `expected_output` notes the gate fires AFTER `/design`'s existing commit step (the Draft artifact is on disk and tracked when the gate fires, which is why `git rm` is required) — distinguishes Phase 6's commit-then-approve ordering from any commit-after-approve variant
- [ ] The new scenario's `expected_output` notes the contract fires identically in-chain (under `/scope`) and out-of-chain (direct `/design` invocation) per AC30c
- [ ] The new scenario is appended to the `evals` array in `skills/design/evals/evals.json`; existing scenarios (ids 1-9) are not modified
- [ ] The new scenario's `id` is unique within the file (next available integer)
- [ ] `skills/design/evals/evals.json` is valid JSON after the edit
- [ ] Must deliver: an eval scenario file that `scripts/run-evals.sh design` consumes and the `/skill-creator` grading agent can match against the implementation `<<ISSUE:5>>` ships — no separate downstream issue depends on this leaf, but the eval is the verification surface for the entire PR-3 contract before PR-3 merges
- [ ] CI green

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

EVALS=skills/design/evals/evals.json

# JSON validity
python3 -m json.tool "$EVALS" >/dev/null

# Scenario count grew by at least one (was 9 — ids 1-9 — before this issue)
COUNT=$(python3 -c "import json,sys; print(len(json.load(open('$EVALS'))['evals']))")
test "$COUNT" -ge 10

# A new scenario explicitly references the Reject branch behavior
grep -q 'docs(design): discard DESIGN draft' "$EVALS"
grep -q 'git rm docs/designs/DESIGN' "$EVALS"
grep -q 'wip/design_' "$EVALS"
grep -q 'wip/research/design_' "$EVALS"
grep -q 'git commit -F' "$EVALS"
grep -q 'Rationale will be committed to git history' "$EVALS"

# 3-option gate vocabulary is named
grep -q 'Approved' "$EVALS"
grep -q 'Reject' "$EVALS"
grep -q 'Continue-revising' "$EVALS"

# AC30c surface is named (in-chain vs out-of-chain)
grep -qE 'in-chain|out-of-chain|AC30c' "$EVALS"

# Phase 6 step 6.7 is named
grep -qE 'Phase 6|step 6\.7|6\.7' "$EVALS"

# Distinct id (no duplicates after addition)
python3 -c "
import json
ids = [e['id'] for e in json.load(open('$EVALS'))['evals']]
assert len(ids) == len(set(ids)), f'duplicate ids: {ids}'
"

echo "All validations passed"
```

## Dependencies

Blocked by <<ISSUE:5>>

`<<ISSUE:5>>` ships the actual 3-option Reject contract in `/design` Phase 6 step 6.7. The eval scenario describes the contract's expected behavior; until the contract exists, the eval cannot pass against the implementation. Both issues land together in PR-3 per the decomposition.

## Downstream Dependencies

None — this is a leaf issue inside PR-3. The completed eval is the verification surface for the PR-3 contract; `/scope`'s Component 7.7 in-chain Reject integration (which lands in PR-4) reads the discard commit SHA as the durable trace for the rejection-sub-shape Decision Record per D5's frozen-snapshot rule, and that PR-4 integration is independently verified by `/scope`'s own eval suite covering US-1 through US-6 (per R18, AC24b).
