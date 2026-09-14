#!/usr/bin/env bash
# pre-pr-evidence_test.sh — a placeholder must not satisfy an obligation.
#
# The state exists because prose asking for cleanup, a summary shape, a commit
# convention and a diagram update could not detect their own omission. The risk
# in replacing prose with evidence is replacing it with evidence that anything
# satisfies: koto's evidence schema has no way to constrain a string, so a
# `type: string` field is satisfied by "done" and the obligation is unenforced in
# substance while looking enforced in the record.
#
# So the cases that matter here are the placeholder ones. Each drives the SHIPPED
# state with a referent a careless run would write and requires it to fail.
#
# Usage: pre-pr-evidence_test.sh
# Exit codes: 0 all pass, 1 any failed, 0 with a skip notice when koto is absent.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { echo -e "${YELLOW}SKIP${NC}: $*"; }

TMPS=()
SESSIONS=()
cleanup() {
    for w in "${SESSIONS[@]:-}"; do [[ -n "$w" ]] && koto cancel "$w" >/dev/null 2>&1; done
    for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done
}
trap cleanup EXIT

if ! command -v koto >/dev/null 2>&1; then
    skip "koto not on PATH; the ladder cannot be driven without the engine"
    exit 0
fi
[[ -f "$TEMPLATE" ]] || { echo "template not found: $TEMPLATE"; exit 2; }

extract_state() {
    local name="$1"
    awk -v want="  $name:" '
        $0 == want { found=1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

PRE_PR=$(extract_state pre_pr_evidence)
[[ -n "$PRE_PR" ]] || { echo "pre_pr_evidence not found in $TEMPLATE"; exit 2; }

# The commit_convention gate runs git against the working directory. Stubbing it
# would remove the only case that exercises a real command, so instead each run
# happens in a throwaway repository whose tip subject the case chooses.
build_fixture() {
    local dir="$1"
    cat > "$dir/fixture.md" <<FIXTURE
---
name: pre-pr-evidence-fixture
version: "1.0"
description: Fixture exercising the pre-PR obligation ladder.
initial_state: start
states:
  start:
    transitions:
      - target: pre_pr_evidence
$PRE_PR
  pr_precheck:
    terminal: true
  done_blocked:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
---

## start
Stand-in for finalization.

## pre_pr_evidence
Record the pre-PR obligations.

## pr_precheck
Stub terminal standing in for the pull-request path.

## done_blocked
Blocked.
FIXTURE
}

# land <session> <commit-subject> <summary-body> <pre_pr-body> <evidence-json>
land() {
    local session="$1" subject="$2" summary="$3" prepr="$4" data="$5"
    local repo; repo=$(mktemp -d); TMPS+=("$repo")
    build_fixture "$repo"
    (
        cd "$repo" || exit 1
        git init -q .
        git config user.email t@example.invalid
        git config user.name t
        echo x > f.txt
        git add -A
        git commit -qm "$subject"
    ) >/dev/null 2>&1
    (
        cd "$repo" || exit 1
        koto init "$session" --template "$repo/fixture.md" >/dev/null 2>&1 || exit 1
        printf '%s\n' "$summary" | koto context add "$session" summary.md >/dev/null 2>&1
        printf '%s\n' "$prepr" | koto context add "$session" pre_pr.md >/dev/null 2>&1
        koto next "$session" >/dev/null 2>&1 || true
        koto next "$session" --with-data "$data" 2>/dev/null
    )
    SESSIONS+=("$session")
}

GOOD_SUMMARY='# Summary

## What Was Implemented
A thing.

## Changes Made
- `f.txt`: added

## Key Decisions
- none'
GOOD_PREPR='cleanup_commit: 4f2a91c8d3b6e5a7f0c1d2e3a4b5c6d7e8f9a0b1
design_diagram: docs/designs/DESIGN-thing.md'
GOOD_EVIDENCE='{"pre_pr_status":"recorded","cleanup_done":"removed","design_diagram":"updated"}'

# Case 1 — everything in order reaches the pull-request path.
OUT=$(land "prepr-ok-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" "$GOOD_PREPR" "$GOOD_EVIDENCE" || true)
if echo "$OUT" | grep -q '"state":"pr_precheck"'; then
    pass "a complete record reaches pr_precheck"
else
    fail "complete record: expected pr_precheck, got: $(echo "$OUT" | head -c 300)"
fi

# ---------------------------------------------------------------------------
# Case 2 — THE PLACEHOLDER CASE. "done" is what a careless run writes where a
# commit belongs, and it is exactly what a `type: string` field would accept.
# ---------------------------------------------------------------------------
OUT=$(land "prepr-placeholder-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: done
design_diagram: docs/designs/DESIGN-thing.md' "$GOOD_EVIDENCE" || true)
if echo "$OUT" | grep -q '"state":"done_blocked"'; then
    pass "a placeholder where the cleanup commit belongs fails the state"
elif echo "$OUT" | grep -q '"state":"pr_precheck"'; then
    fail "a placeholder cleanup referent satisfied the state — the obligation is unenforced in substance"
else
    fail "placeholder case: unexpected result: $(echo "$OUT" | head -c 300)"
fi

# Case 3 — the same for the diagram: "yes" is neither a path nor a stated reason.
OUT=$(land "prepr-diagram-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: 4f2a91c8d3b6e5a7f0c1d2e3a4b5c6d7e8f9a0b1
design_diagram: yes' "$GOOD_EVIDENCE" || true)
if echo "$OUT" | grep -q '"state":"done_blocked"'; then
    pass "a placeholder where the diagram referent belongs fails the state"
else
    fail "diagram placeholder: expected done_blocked, got: $(echo "$OUT" | head -c 300)"
fi

# Case 4 — not-applicable is accepted, but only WITH a reason after it. An
# obligation that does not apply is a legitimate answer; "not-applicable" alone
# is the same placeholder problem wearing a different word.
OUT=$(land "prepr-na-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: 4f2a91c8d3b6e5a7f0c1d2e3a4b5c6d7e8f9a0b1
design_diagram: not-applicable: no design document is touched' \
    '{"pre_pr_status":"recorded","cleanup_done":"none_found","design_diagram":"not_applicable"}' || true)
if echo "$OUT" | grep -q '"state":"pr_precheck"'; then
    pass "not-applicable with a stated reason is accepted"
else
    fail "not-applicable case: expected pr_precheck, got: $(echo "$OUT" | head -c 300)"
fi

# Case 5 — a summary without the required section stops the run.
OUT=$(land "prepr-summary-$$" "feat(work-on): add a thing" '# Summary

Some prose and no sections.' "$GOOD_PREPR" "$GOOD_EVIDENCE" || true)
if echo "$OUT" | grep -q '"state":"done_blocked"'; then
    pass "a summary missing its required section fails the state"
else
    fail "summary case: expected done_blocked, got: $(echo "$OUT" | head -c 300)"
fi

# Case 6 — a tip commit that is not a Conventional Commits subject stops the run.
OUT=$(land "prepr-subject-$$" "fixed some stuff" "$GOOD_SUMMARY" "$GOOD_PREPR" "$GOOD_EVIDENCE" || true)
if echo "$OUT" | grep -q '"state":"done_blocked"'; then
    pass "a non-conventional commit subject fails the state"
else
    fail "subject case: expected done_blocked, got: $(echo "$OUT" | head -c 300)"
fi

# Case 7 — blocked is a first-class answer, not something to fake a referent for.
OUT=$(land "prepr-blocked-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" "$GOOD_PREPR" \
    '{"pre_pr_status":"blocked","cleanup_done":"none_found","design_diagram":"not_applicable"}' || true)
if echo "$OUT" | grep -q '"state":"done_blocked"'; then
    pass "an explicitly blocked run stops without opening a pull request"
else
    fail "blocked case: expected done_blocked, got: $(echo "$OUT" | head -c 300)"
fi

# Case 8 — the evidence is required. Submitting none must not advance, since the
# state would otherwise be satisfied by silence.
OUT=$(land "prepr-empty-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" "$GOOD_PREPR" '{}' || true)
if echo "$OUT" | grep -qE '"state":"pr_precheck"|"state":"done_blocked"'; then
    fail "a submission with no evidence advanced"
else
    pass "a submission with no evidence does not advance"
fi

echo
echo "pre-pr-evidence_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
