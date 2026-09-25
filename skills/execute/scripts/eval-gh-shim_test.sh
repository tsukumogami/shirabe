#!/usr/bin/env bash
# eval-gh-shim_test.sh — the execute evals' gh shim, and what its merge-step
# fixtures make the real scripts decide
# Part of the execute skill
#
# The merge-step eval scenarios assert on outcomes: `reason=head-moved`,
# `step=execute:ci-timeout`, exactly one `pr merge --squash`. Those outcomes
# come from the real merge scripts reading the shim's fixtures, so a fixture
# that drifted from what the scripts read would make an eval grade the wrong
# thing without anyone noticing. This harness runs the real owned-pr.sh,
# merge-verdict.sh, and merge-exec.sh against each scenario's fixtures through
# evals/fixtures/bin/gh and asserts the verdict each scenario's eval expects.
#
# It also pins the shim itself:
#   the older per-command arms answer the DIRTY scenario (plan-orchestrator)
#     byte-for-byte as before
#   every call is appended to GH_CALL_LOG
#   numbered fixtures answer the Nth call; a merge that exits 0 turns the
#     confirm read MERGED unless the scenario keeps the PR open
#   @HEAD_SHA@ is the commit checked out where gh runs
#   no fixture makes a merge call carry --admin or --auto
#
# Usage: eval-gh-shim_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
FIXTURES="$SCRIPT_DIR/../evals/fixtures"
SHIM_BIN="$FIXTURES/bin"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/eval-gh-shim-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# A checkout for @HEAD_SHA@ to name.
REPO="$WORK/repo"
mkdir -p "$REPO"
(cd "$REPO" && git init -q . && git -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init) >/dev/null 2>&1
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
R=eval-org/eval-repo
URL="https://github.com/eval-org/eval-repo/pull/42"

# Every call runs with only the shim's gh ahead of the real PATH. The shim
# directory also holds a koto shim; nothing here calls koto.
LOGN=0
shim() { # shim <scenario> <command...> — sets OUT, RC; a fresh call log per scenario run
    local sc="$1"
    shift
    OUT=$(cd "$REPO" && env EVAL_SCENARIO="$sc" GH_CALL_LOG="$LOG" PATH="$SHIM_BIN:$PATH" "$@" 2>/dev/null)
    RC=$?
}
new_log() { LOGN=$((LOGN + 1)); LOG="$WORK/calls.$LOGN.log"; rm -rf "$LOG" "$LOG.d"; : > "$LOG"; }

# --- the older arms, byte-for-byte --------------------------------------------

new_log
shim plan-orchestrator gh pr view --json mergeStateStatus --jq .mergeStateStatus
[ "$OUT" = DIRTY ] && [ "$RC" -eq 0 ] && pass "plan-orchestrator: pr view --jq .mergeStateStatus is still DIRTY" \
    || fail "plan-orchestrator pr view: [$OUT] $RC"
shim plan-orchestrator gh pr list --head impl/diamond-test --json number --jq '.[0].number // empty'
[ "$OUT" = 42 ] && pass "plan-orchestrator: pr list --jq still yields 42" || fail "plan-orchestrator pr list: [$OUT]"
shim plan-orchestrator gh pr checks 42 --json bucket --jq '[.[] | select(.bucket != "pass" and .bucket != "skipping")] | length == 0'
[ "$OUT" = true ] && pass "plan-orchestrator: the empty check list still reads length == 0" || fail "plan-orchestrator checks: [$OUT]"
if [ "$(wc -l < "$LOG" | tr -d ' ')" = 3 ] && grep -q '^pr view --json mergeStateStatus' "$LOG"; then
    pass "GH_CALL_LOG records every call's arguments, one line each"
else
    fail "call log: $(cat "$LOG")"
fi

# --- the verdict each merge-step scenario's fixtures produce -------------------

verdict() { # verdict <scenario> <merge> [expected-head] -> OUT
    local sc="$1" merge="$2" exp="${3:-$HEAD_SHA}"
    new_log
    shim "$sc" env EXECUTE_CI_WAIT_LIMIT_SECS="${LIMIT:-1800}" \
        bash "$SCRIPT_DIR/merge-verdict.sh" --repo "$R" --pr 42 --merge "$merge" --expected-head "$exp"
}
expect_verdict() { # expect_verdict <scenario> <merge> <verdict>
    verdict "$1" "$2"
    if [ "$OUT" = "$3" ]; then
        pass "$1 (--merge $2): $3"
    else
        fail "$1 (--merge $2): want [$3], got [$OUT]; calls: $(tr '\n' ';' < "$LOG")"
    fi
}

expect_verdict merge-mergeable true "mergeable:squash:$HEAD_SHA"
expect_verdict merge-mergeable false "awaiting:merge-not-requested"
expect_verdict merge-review-required true "awaiting:merge-state:BLOCKED:review=REVIEW_REQUIRED"
expect_verdict merge-dirty true "awaiting:merge-state:DIRTY"
expect_verdict merge-failing-check true "error:execute:ci"
LIMIT=60 expect_verdict merge-pending-timeout true "error:execute:ci-timeout"
expect_verdict merge-draft-ready-fails true "error:execute:ready"
expect_verdict merge-unprotected true "awaiting:base-unprotected"
expect_verdict merge-no-checks true "awaiting:no-checks"
expect_verdict merge-head-moved true "awaiting:head-moved"
expect_verdict merge-review-rule true "awaiting:review"
expect_verdict merge-workflow-change true "awaiting:workflow-change"
expect_verdict merge-already-merged true "merged"
expect_verdict merge-already-merged false "merged"
expect_verdict scope-adopt true "error:execute:ready"
expect_verdict merge-files-unreadable true "error:execute:status-read"
expect_verdict merge-files-short true "error:execute:status-read"

verdict merge-mergeable true none
[ "$OUT" = "awaiting:head-moved" ] && pass "merge-mergeable with no expected-head record: awaiting:head-moved" \
    || fail "no record: [$OUT]"

# --- the ownership lookup -------------------------------------------------------

owned() { # owned <scenario> <head> -> OUT, RC
    new_log
    shim "$1" bash "$SCRIPT_DIR/owned-pr.sh" --repo "$R" --head "$2" --state all
}
owned merge-mergeable impl/merge-test
[ "$OUT" = "$URL" ] && pass "merge-mergeable: the owned PR resolves to #42" || fail "owned mergeable: [$OUT] $RC"
owned pr-adopt-fork impl/merge-test
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && pass "pr-adopt-fork: the fork's PR is not a survivor" || fail "fork: [$OUT] $RC"
owned pr-adopt-other-author impl/merge-test
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && pass "pr-adopt-other-author: another author's PR is not a survivor" || fail "other author: [$OUT] $RC"
owned scope-adopt docs/merge-test
[ "$OUT" = "$URL" ] && pass "scope-adopt: the owned draft on the /scope topic branch resolves" || fail "scope adopt: [$OUT] $RC"
owned scope-adopt impl/merge-test
[ -z "$OUT" ] && pass "scope-adopt: nothing is owned on impl/merge-test" || fail "scope adopt impl: [$OUT]"

# --- the merge call and the confirm read --------------------------------------

merge_then_confirm() { # merge_then_confirm <scenario> -> EXEC_OUT, CONFIRM_OUT (one call log)
    new_log
    shim "$1" bash "$SCRIPT_DIR/merge-exec.sh" "$R" 42 "$HEAD_SHA"
    EXEC_OUT="$OUT"
    shim "$1" env MERGE_CONFIRM_WAIT_SECS=0 \
        bash "$SCRIPT_DIR/merge-verdict.sh" --repo "$R" --pr 42 --merge true --expected-head "$HEAD_SHA" --confirm
    CONFIRM_OUT="$OUT"
}
merges() { grep -c '^pr merge' "$LOG"; }

merge_then_confirm merge-mergeable
if [ "$EXEC_OUT" = "merge-called:squash:$HEAD_SHA" ] && [ "$CONFIRM_OUT" = merged ] && [ "$(merges)" -eq 1 ] \
    && grep -qx "pr merge 42 --repo $R --squash --match-head-commit $HEAD_SHA" "$LOG"; then
    pass "merge-mergeable: exactly one pr merge --squash --match-head-commit <head>, then the confirm read is merged"
else
    fail "mergeable merge: exec [$EXEC_OUT] confirm [$CONFIRM_OUT]; $(grep '^pr merge' "$LOG")"
fi

merge_then_confirm merge-call-fails
if [ "$EXEC_OUT" = "merge-refused:not-merged:merge-call-failed" ] && [ "$(merges)" -eq 1 ] && [ "$CONFIRM_OUT" != merged ]; then
    pass "merge-call-fails: one pr merge, merge-refused:not-merged:merge-call-failed, never merged"
else
    fail "call fails: exec [$EXEC_OUT] confirm [$CONFIRM_OUT] merges $(merges)"
fi

merge_then_confirm merge-not-observed
if [ "$EXEC_OUT" = "merge-called:squash:$HEAD_SHA" ] && [ "$CONFIRM_OUT" = "not-merged:merge-not-observed" ]; then
    pass "merge-not-observed: the call exits 0, the PR stays OPEN, the confirm read is merge-not-observed"
else
    fail "not observed: exec [$EXEC_OUT] confirm [$CONFIRM_OUT]"
fi

merge_then_confirm merge-other-pr-evidence
[ "$CONFIRM_OUT" = "not-merged:merge-not-observed" ] && pass "merge-other-pr-evidence: the owned PR stays OPEN" \
    || fail "other-pr evidence: confirm [$CONFIRM_OUT]"

merge_then_confirm merge-method-squash
grep -q -- "^pr merge 42 --repo $R --squash " "$LOG" && pass "merge-method-squash: squash and merge allowed -> --squash" \
    || fail "method squash: $(grep '^pr merge' "$LOG")"
merge_then_confirm merge-method-rebase
grep -q -- "^pr merge 42 --repo $R --rebase " "$LOG" && pass "merge-method-rebase: only rebase allowed -> --rebase" \
    || fail "method rebase: $(grep '^pr merge' "$LOG")"

for sc in merge-review-required merge-head-moved merge-unprotected merge-workflow-change merge-failing-check; do
    new_log
    shim "$sc" bash "$SCRIPT_DIR/merge-exec.sh" "$R" 42 "$HEAD_SHA"
    if [ "$(merges)" -eq 0 ] && [ "${OUT#merge-refused:}" != "$OUT" ]; then
        pass "$sc: merge-exec.sh refuses and makes no pr merge ($OUT)"
    else
        fail "$sc: merge-exec made a merge call or did not refuse: [$OUT]"
    fi
done

# --- the ready call's failing variant, and the numbered and default answers ---

new_log
shim merge-draft-ready-fails gh pr ready 42 --repo "$R"
[ "$RC" -eq 1 ] && pass "merge-draft-ready-fails: gh pr ready fails" || fail "pr ready: rc $RC"
new_log
shim merge-mergeable gh pr ready 42 --repo "$R"
[ "$RC" -eq 0 ] && pass "gh pr ready succeeds by default" || fail "default pr ready: rc $RC"
new_log
shim merge-mergeable gh api user
[ "$(printf '%s' "$OUT" | jq -r .login)" = eval-user ] && pass "gh api user answers eval-user" || fail "api user: [$OUT]"
new_log
shim merge-mergeable gh repo view --json nameWithOwner --jq .nameWithOwner
[ "$OUT" = "$R" ] && pass "gh repo view --jq applies the filter" || fail "repo view: [$OUT]"
new_log
shim merge-mergeable gh api "repos/$R/pulls/42/files" --paginate
[ "$(printf '%s' "$OUT" | jq -r '.[0].filename')" = src/merge.go ] && pass "the paginated files read is served" || fail "files: [$OUT]"

# A numbered fixture answers the Nth call. Run against a copy of the shim and
# one scenario, so the shipped fixtures are never written to.
mkdir -p "$WORK/fx/scenarios"
cp -R "$SHIM_BIN" "$WORK/fx/bin"
cp -R "$FIXTURES/scenarios/merge-mergeable" "$WORK/fx/scenarios/numbered"
printf '{"state":"CLOSED"}\n' > "$WORK/fx/scenarios/numbered/gh/pr-view-state.2.json"
new_log
FIRST=$(cd "$REPO" && env EVAL_SCENARIO=numbered GH_CALL_LOG="$LOG" PATH="$WORK/fx/bin:$PATH" \
    gh pr view 42 --repo "$R" --json state 2>/dev/null)
SECOND=$(cd "$REPO" && env EVAL_SCENARIO=numbered GH_CALL_LOG="$LOG" PATH="$WORK/fx/bin:$PATH" \
    gh pr view 42 --repo "$R" --json state 2>/dev/null)
if [ -z "$FIRST" ] && [ "$(printf '%s' "$SECOND" | jq -r .state)" = CLOSED ]; then
    pass "a numbered fixture answers the Nth call to its key"
else
    fail "numbered: first [$FIRST], second [$SECOND]"
fi

# --- no merge call carries --admin or --auto ------------------------------------

if grep -h '^pr merge' "$WORK"/calls.*.log | grep -Eq -- '--admin|--auto'; then
    fail "a pr merge call carried --admin or --auto"
else
    pass "no pr merge call in any call log carries --admin or --auto"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
