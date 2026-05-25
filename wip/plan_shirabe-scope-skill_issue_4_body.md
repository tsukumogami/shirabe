---
complexity: testable
complexity_rationale: Adds a new eval scenario JSON entry plus expectation assertions; verifiable by running scripts/run-evals.sh and grep-checking that the new scenario id/name is present with all required expectation strings.
---

## Goal

Add an eval scenario to `skills/prd/evals/evals.json` covering the new Phase 4 Reject contract (3-option AskUserQuestion + rationale capture + discard commit) so the contract introduced by <<ISSUE:3>> is locked in by an automated assertion suite.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

<<ISSUE:3>> ships the Phase-N Reject contract on `/prd` Phase 4 step 4.5, replacing the existing 2-option AskUserQuestion (Approved / Needs iteration) with a 3-option gate (Approved / Reject / Continue-revising). On Reject the child asks the author for a one-sentence rationale, writes the rationale to a tempfile, runs `git rm docs/prds/PRD-<topic>.md`, removes `wip/prd_<topic>_*.md`, and commits via `git commit -F <tmpfile>` (or stdin) with the subject `docs(prd): discard PRD draft for <topic>` and the rationale in the body. The commit-via-stdin discipline is a Security Considerations mitigation against command injection in author-supplied rationale text (Design lines 1939-1957).

The contract is observable end-to-end from the durable git history regardless of whether `/prd` runs in-chain under `/scope` or standalone (Design AC30c). `/scope` itself reads the discard-commit SHA via `git log` to write its rejection-sub-shape Decision Record; an out-of-chain reviewer running `/prd` directly sees the same discard commit as the durable trace.

This issue locks the contract by adding a single eval scenario to `skills/prd/evals/evals.json` so any future edit to `/prd`'s Phase 4 step 4.5 that breaks the 3-option shape, the rationale capture, the `git rm`, the `wip/` cleanup, or the commit message format will fail the eval. The scenario follows the format precedent established by the existing 10 scenarios in `skills/prd/evals/evals.json` and uses the structured `expectations` array (per scenarios 9 and 10) to enumerate fine-grained assertions.

The eval scenario covers both in-chain and out-of-chain Reject paths per AC30c: the assertions verify the literal contract surfaces (3-option prompt, "Reject" literal, rationale prompt, `git rm`, commit subject) regardless of caller. The in-chain-vs-out-of-chain distinction is observable from the durable git history (the discard commit on the current branch), so a single grep-checkable assertion against the discard commit covers both contexts.

## Acceptance Criteria

- [ ] A new eval scenario is appended to the `evals:` array in `skills/prd/evals/evals.json`
- [ ] The scenario's `id` is the next sequential integer (11) following the existing scenarios in the file
- [ ] The scenario's `name` is a kebab-case slug describing the Phase 4 Reject contract (e.g., `phase-4-reject-discards-draft`)
- [ ] The scenario's `prompt` invokes `/prd` against a topic that already has a Draft PRD on disk and drives the Phase 4 approval gate (the prompt must reach step 4.5; the topic name must conform to `^[a-z0-9-]+$`)
- [ ] The scenario's `expected_output` describes the Reject outcome in prose: 3-option prompt presents Approved / Reject / Continue-revising; on Reject the skill captures a rationale, runs `git rm docs/prds/PRD-<topic>.md`, removes `wip/prd_<topic>_*.md`, and commits `docs(prd): discard PRD draft for <topic>` with rationale in body via `git commit -F` (stdin or tempfile)
- [ ] The scenario's `expectations` array contains at least these assertions covering the contract surface:
  - [ ] Assertion verifying the Phase 4 step 4.5 prompt presents three options including the literal substring `Reject`
  - [ ] Assertion verifying that selecting Reject prompts the author for a rationale before any destructive action
  - [ ] Assertion verifying the rationale is persisted to the commit body via `git commit -F` (stdin or tempfile), NOT inlined into `git commit -m`
  - [ ] Assertion verifying the durable PRD artifact is removed via `git rm docs/prds/PRD-<topic>.md`
  - [ ] Assertion verifying a discard commit with subject `docs(prd): discard PRD draft for <topic>` lands on the current branch and is greppable via `git log`
  - [ ] Assertion verifying the prompt includes the public-history disclaimer substring `Rationale will be committed to git history` (per Design Security Mitigation 2, lines 2049-2057)
- [ ] The added JSON is valid (parses with `jq`) and the file as a whole still passes `jq empty`
- [ ] Eval suite runs end-to-end against the new scenario via `scripts/run-evals.sh prd` (delegated to an agent with `/skill-creator` loaded per `CLAUDE.md` "Skill Evals" section); the new scenario's assertions pass against `/prd` as delivered by <<ISSUE:3>>
- [ ] Must deliver: a passing eval scenario named `phase-4-reject-discards-draft` (or equivalent kebab-case slug) that locks the Phase 4 Reject contract for PR-2 (required by PR-2 merge gate)
- [ ] CI green
- [ ] E2E flow still works (do not break existing `/prd` evals 1-10)

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

EVALS_FILE="skills/prd/evals/evals.json"

# 1. File exists and is valid JSON
test -f "$EVALS_FILE"
jq empty "$EVALS_FILE"

# 2. The new scenario is present with a Phase 4 Reject focus
jq -e '.evals | map(select(.name | test("phase-4-reject|reject.*discard|discard.*draft"))) | length >= 1' "$EVALS_FILE" > /dev/null

# 3. The scenario id is sequential (max existing id + 1)
MAX_ID=$(jq '[.evals[].id] | max' "$EVALS_FILE")
test "$MAX_ID" -ge 11

# 4. The scenario has an expectations array (per scenarios 9 and 10 precedent)
jq -e '.evals[] | select(.name | test("phase-4-reject|reject.*discard|discard.*draft")) | .expectations | length >= 6' "$EVALS_FILE" > /dev/null

# 5. The expectations cover the required contract surfaces (grep against the JSON file string content)
grep -q 'Reject' "$EVALS_FILE"
grep -q 'rationale' "$EVALS_FILE"
grep -q 'git rm' "$EVALS_FILE"
grep -q 'git commit -F\|git commit.*-F\|stdin\|tempfile' "$EVALS_FILE"
grep -q 'docs(prd): discard PRD draft' "$EVALS_FILE"
grep -q 'git log' "$EVALS_FILE"
grep -q 'Rationale will be committed to git history' "$EVALS_FILE"

# 6. Existing scenarios 1-10 are still present (do not break the existing eval surface)
for id in 1 2 3 4 5 6 7 8 9 10; do
  jq -e --argjson id "$id" '.evals | map(select(.id == $id)) | length == 1' "$EVALS_FILE" > /dev/null
done

# 7. The scenario count grew by exactly the new entry
SCENARIO_COUNT=$(jq '.evals | length' "$EVALS_FILE")
test "$SCENARIO_COUNT" -ge 11

echo "All validations passed"
```

## Dependencies

Blocked by <<ISSUE:3>>

<<ISSUE:3>> ships the actual Phase 4 step 4.5 3-option Reject contract on `/prd`. The eval scenario in this issue asserts that contract end-to-end; without <<ISSUE:3>> the scenario has no contract to assert against (the assertions would fail because `/prd` still ships the 2-option Approved / Needs iteration prompt).

## Downstream Dependencies

None — this is a leaf issue inside PR-2.

The eval scenario closes PR-2's verification loop: PR-2 ships the contract (<<ISSUE:3>>) plus the eval that locks it (this issue). Future PRs that touch `/prd` Phase 4 step 4.5 will run this eval as part of `scripts/run-evals.sh prd` and any regression in the 3-option shape, rationale capture, `git rm`, commit format, or stdin-commit discipline will surface as a failing assertion.
