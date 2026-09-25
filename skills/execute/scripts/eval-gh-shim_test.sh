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
#   the repository model the coordinated scenarios use (gh/db.json): a PR
#     created at the checked-out commit, found by branch, readied, edited,
#     merged (or left open by a stays-open merge), the merge gate's state
#     read, no issue call, and the unlogged mark-merged hook
#   the first action each coordinated scenario makes the real
#     coordinated-next.sh print (skipped without a shirabe binary that has
#     `plan outlines`, which the outline PLANs need)
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

# --- the repository model (gh/db.json) ------------------------------------------
#
# The coordinated scenarios' shim state: a PR created, found by its branch,
# readied, edited, and merged; a merge that stays open or fails; no issue
# call; the scenario's own mark-merged hook, unlogged.

MODEL="$WORK/model"
mkdir -p "$MODEL/gh"
cp "$FIXTURES/scenarios/coord-outline-one-repo/gh/db.json" "$MODEL/gh/db.json"
mshim() { # mshim <command...> -- against the model scenario, sets OUT, RC
    OUT=$(cd "$REPO" && env EVAL_SCENARIO=model EVAL_SCENARIO_DIR="$MODEL" GH_CALL_LOG="$LOG" \
        PATH="$SHIM_BIN:$PATH" "$@" 2>/dev/null)
    RC=$?
}
new_log
BR=$(git -C "$REPO" symbolic-ref --short HEAD)
mshim gh pr list --repo "$R" --head "$BR" --state all --json url,state,isCrossRepository,author,baseRefName,headRefName --limit 100
if [ "$(printf '%s' "$OUT" | jq -r '.[0].url')" = "https://github.com/eval-org/eval-repo/pull/10" ]; then
    pass "model: @BRANCH@ is the branch checked out where the shim first runs (the coordination PR is found on it)"
else
    fail "model: coordination PR lookup [$OUT]"
fi
printf 'node body\n' > "$WORK/body.md"
mshim gh pr create --repo "$R" --draft --base main --head impl/x-pr-eval-repo-core --title "feat(x): pr-eval-repo-core" --body-file "$WORK/body.md"
NEWURL="$OUT"
mshim gh pr view 11 --repo "$R" --json state,isDraft,headRefOid,body
if [ "$NEWURL" = "https://github.com/eval-org/eval-repo/pull/11" ] \
    && [ "$(printf '%s' "$OUT" | jq -r '.isDraft')" = true ] \
    && [ "$(printf '%s' "$OUT" | jq -r '.headRefOid')" = "$HEAD_SHA" ] \
    && [ "$(printf '%s' "$OUT" | jq -r '.body')" = "node body" ]; then
    pass "model: pr create opens a draft PR at the checked-out commit and prints its URL"
else
    fail "model: create [$NEWURL] view [$OUT]"
fi
mshim gh pr ready 11 --repo "$R"
mshim gh pr view 11 --repo "$R" --json isDraft --jq .isDraft
[ "$OUT" = false ] && pass "model: pr ready clears isDraft" || fail "model: ready [$OUT]"
printf 'edited\n' > "$WORK/body2.md"
mshim gh pr edit 10 --repo "$R" --body-file "$WORK/body2.md"
mshim gh pr view 10 --repo "$R" --json body --jq .body
[ "$OUT" = edited ] && pass "model: pr edit --body-file replaces the body" || fail "model: edit [$OUT]"
mshim gh api "repos/$R/issues/11"
[ "$(printf '%s' "$OUT" | jq -r .state)" = open ] && pass "model: the merge gate's state read is open before a merge" || fail "model: issues [$OUT]"
mshim gh pr merge 11 --repo "$R" --squash --match-head-commit "$HEAD_SHA"
mshim gh pr view 11 --repo "$R" --json state
if [ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r .state)" = MERGED ]; then
    pass "model: a merge with merge ok leaves the PR MERGED"
else
    fail "model: merge [$OUT]"
fi
mshim gh api "repos/$R/issues/11"
[ "$(printf '%s' "$OUT" | jq -r .state)" = closed ] && pass "model: ... and the merge gate's state read closed" || fail "model: issues after merge [$OUT]"
mshim gh issue view 3
[ "$RC" -ne 0 ] && pass "model: an issue call fails" || fail "model: issue view succeeded"
BEFORE=$(wc -l < "$LOG" | tr -d ' ')
mshim gh shim-mark-merged "$R" 10
AFTER=$(wc -l < "$LOG" | tr -d ' ')
mshim gh pr view 10 --repo "$R" --json state --jq .state
if [ "$OUT" = MERGED ] && [ "$BEFORE" = "$AFTER" ]; then
    pass "model: shim-mark-merged marks a PR MERGED and is not logged"
else
    fail "model: mark-merged [$OUT], log $BEFORE -> $AFTER"
fi

new_log
cp "$FIXTURES/scenarios/coord-merge-not-observed/gh/db.json" "$MODEL/gh/db.json"
mshim gh pr create --repo "$R" --draft --base main --head impl/x-y --title t --body-file "$WORK/body.md"
mshim gh pr merge 11 --repo "$R" --squash --match-head-commit "$HEAD_SHA"
RC1=$RC
mshim gh pr view 11 --repo "$R" --json state --jq .state
[ "$RC1" -eq 0 ] && [ "$OUT" = OPEN ] && pass "model: a stays-open merge exits 0 and the PR stays OPEN" \
    || fail "model: stays-open rc=$RC1 state=[$OUT]"

# The verdict each coordinated scenario makes coordinated-next.sh reach, from a
# checkout holding the scenario's PLAN. The outline PLANs need the shirabe
# binary (plan-to-tasks.sh's outline path); without one these cases skip.
SHIRABE_FOR_OUTLINES="${SHIRABE_BIN:-}"
if [ -z "$SHIRABE_FOR_OUTLINES" ]; then
    # This checkout's own build first: an installed shirabe can predate the
    # outline envelope's repo and group keys.
    for cand in "$SCRIPT_DIR/../../../target/release/shirabe" "$SCRIPT_DIR/../../../target/debug/shirabe" \
                "$(command -v shirabe || true)"; do
        [ -n "$cand" ] && [ -x "$cand" ] && { SHIRABE_FOR_OUTLINES="$cand"; break; }
    done
fi
if [ -n "$SHIRABE_FOR_OUTLINES" ] && "$SHIRABE_FOR_OUTLINES" plan outlines --help >/dev/null 2>&1; then
    COORD="$WORK/coord"
    mkdir -p "$COORD/docs/plans"
    cp "$FIXTURES/plans/PLAN-coord-outline-test.md" "$FIXTURES/plans/PLAN-coord-multi-test.md" "$COORD/docs/plans/"
    (cd "$COORD" && git init -q . && git -c user.email=t@example.com -c user.name=t add docs \
        && git -c user.email=t@example.com -c user.name=t commit -q -m plan && git checkout -q -b docs/coord) >/dev/null 2>&1
    SCENARIO_LOGS=""
    scenario_next() { # scenario_next <scenario> <plan-slug> <repos> <merge> <want>
        new_log
        SCENARIO_LOGS="$SCENARIO_LOGS $LOG"
        local out
        out=$(cd "$COORD" && env EVAL_SCENARIO="$1" GH_CALL_LOG="$LOG" PATH="$SHIM_BIN:$PATH" \
            SHIRABE_BIN="$SHIRABE_FOR_OUTLINES" MERGE_CONFIRM_WAIT_SECS=0 \
            bash "$SCRIPT_DIR/coordinated-next.sh" --plan "docs/plans/PLAN-$2.md" --slug "$2" --repos "$3" \
            --home-repo eval-org/eval-repo --coord-branch docs/coord --merge "$4" 2>/dev/null)
        if [ "$out" = "$5" ]; then
            pass "$1: coordinated-next.sh prints $5"
        else
            fail "$1: coordinated-next.sh printed [$out], the eval expects [$5]"
        fi
    }
    scenario_next coord-outline-one-repo coord-outline-test eval-org/eval-repo true dispatch:pr-eval-repo-core
    scenario_next coord-multi-repo coord-multi-test eval-org/eval-app,eval-org/eval-repo true dispatch:pr-eval-repo-default
    scenario_next coord-merge-not-observed coord-outline-test eval-org/eval-repo true dispatch:pr-eval-repo-core
    scenario_next coord-coordination-not-observed coord-outline-test eval-org/eval-repo true cascade
    scenario_next coord-head-moved coord-outline-test eval-org/eval-repo true pause
    scenario_next coord-head-missing coord-outline-test eval-org/eval-repo true pause
    scenario_next coord-index-foreign-author coord-outline-test eval-org/eval-repo true error:execute:pr-adopt
    scenario_next coord-index-wrong-branch coord-outline-test eval-org/eval-repo true error:execute:pr-adopt
    scenario_next coord-index-out-of-set coord-outline-test eval-org/eval-repo true error:execute:write-set
    # shellcheck disable=SC2086
    if cat $SCENARIO_LOGS | grep -q '^issue'; then
        fail "a coordinated scenario made a gh issue call"
    else
        pass "no coordinated scenario makes a gh issue call"
    fi
else
    echo "SKIP: no shirabe binary with 'plan outlines' -- the coordinated scenarios' first actions were not checked"
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
