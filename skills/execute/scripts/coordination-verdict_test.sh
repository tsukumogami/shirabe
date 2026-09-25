#!/usr/bin/env bash
# coordination-verdict_test.sh — the verdict a coordinated run ends on,
# table-driven
# Part of the execute skill
#
# coordination-verdict.sh recomputes where the run stands and prints the
# verdict coord_verdict routes on, with the pr, waiting, resume, reason, and
# step fields the terminals report. It is read-only. Each case builds a GitHub
# model for the eval gh shim (see coord-test-helpers.sh) and asserts every
# field.
#
# Cases, one or more per route:
#   merged (-> coord_merge_confirm)   the coordination PR MERGED; a coordination
#                                     merge called and not observed
#   ready (-> ready_awaiting_merge)   independent roots, --merge false
#                                     (merge-not-requested on each open PR); the
#                                     coordination PR awaiting review after the
#                                     cascade
#   paused (-> paused_awaiting_merges) a root awaiting a human, its successor
#                                     waiting; resume carries --merge exactly
#                                     when this invocation had it; a root whose
#                                     merge was not observed
#   dirty (-> done_blocked, ready-awaiting-merge) a DIRTY root
#   error (-> done_blocked)           the loop's own error (pr-adopt); a loop
#                                     that stopped early, with and without a
#                                     recognised --loop-line step
#   read-only                         no write-shaped gh call, no koto call
#
# Usage: coordination-verdict_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
VERDICT="$SCRIPT_DIR/coordination-verdict.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

PLANDIR="$CT_WORK/plan"
ct_plan "$PLANDIR"
PLAN2DIR="$CT_WORK/plan2"
ct_plan "$PLAN2DIR" two-repo
GONEDIR="$CT_WORK/gone"
mkdir -p "$GONEDIR"

COORD_URL="https://github.com/acme/repo-a/pull/10"
U11="https://github.com/acme/repo-a/pull/11"
U21="https://github.com/acme/repo-b/pull/21"

run_verdict() { # run_verdict <dir> [args...]
    local dir="$1"
    shift
    OUT=$(cd "$dir" && bash "$VERDICT" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" \
        --repos "acme/repo-a,acme/repo-b" --home-repo "$CT_REPO" --coord-branch "$CT_CB" "$@" 2>"$CASE/stderr")
    RC=$?
}

field() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }

# check <label> <verdict> <waiting> <resume> <reason> <step>
check() {
    local label="$1" ok=1 k want got
    [ "$RC" -eq 0 ] || { fail "$label: exit $RC"; return; }
    for k in coord_verdict:"$2" pr:"$COORD_URL" waiting:"$3" resume:"$4" reason:"$5" step:"$6"; do
        want="${k#*:}"
        got=$(field "${k%%:*}")
        if [ "$got" != "$want" ]; then
            fail "$label: ${k%%:*} expected [$want], got [$got]"
            ok=0
        fi
    done
    [ "$ok" -eq 1 ] && pass "$label: coord_verdict=$2${5:+ reason=$5}${6:+ step=$6}"
    if ct_calls | grep -Eq '^pr (create|edit|ready|merge|close)'; then
        fail "$label made a GitHub write"
    fi
    [ -s "$CASE/koto-calls.log" ] && fail "$label called koto"
    return 0
}

# --- merged -----------------------------------------------------------------------

ct_case merged
CT_COORD_STATE=MERGED
ct_write_db
run_verdict "$PLANDIR" --merge true
check "the coordination PR is MERGED" merged "" "" "" ""

ct_case coord-not-observed
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_index_line coordination "$CT_REPO" 10 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
CT_COORD_DRAFT=false
ct_write_db
run_verdict "$GONEDIR" --merge true --attempts "coordination:merge-not-observed"
check "the coordination merge was called and not observed (the confirm read decides)" \
    merged "$COORD_URL:human" "" "" ""

# --- ready ------------------------------------------------------------------------

ct_case ready-roots
ct_index_line pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_index_line pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
run_verdict "$PLAN2DIR" --merge false
check "independent mergeable roots without --merge" ready \
    "$U11:human,$U21:human,$COORD_URL:predecessor" "" "merge-not-requested" ""

ct_case ready-coord-review
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_index_line coordination "$CT_REPO" 10 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
CT_COORD_DRAFT=false
ct_write_db
jq '(.prs[] | select(.number == 10) | .reviewDecision) = "REVIEW_REQUIRED" | (.prs[] | select(.number == 10) | .mergeStateStatus) = "BLOCKED"' \
    "$CASE/scenario/gh/db.json" > "$CASE/db" && mv "$CASE/db" "$CASE/scenario/gh/db.json"
run_verdict "$GONEDIR" --merge true
check "the coordination PR awaiting review after the cascade" ready \
    "$COORD_URL:human" "" "merge-state:BLOCKED:review=REVIEW_REQUIRED" ""

# --- paused -----------------------------------------------------------------------

ct_case paused
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
run_verdict "$PLANDIR" --merge false
check "a root awaiting a human, its successor waiting (no --merge)" paused \
    "$U11:human,$COORD_URL:predecessor" "/execute docs/plans/PLAN-t.md" "merge-not-requested" ""
run_verdict "$PLANDIR" --merge true --attempts "$CT_CORE:merge-not-observed"
check "a root whose merge was not observed (with --merge: resume carries it)" paused \
    "$U11:human,$COORD_URL:predecessor" "/execute docs/plans/PLAN-t.md --merge" "merge-not-observed" ""

# --- dirty ------------------------------------------------------------------------

ct_case dirty
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'mergeStateStatus="DIRTY"'
ct_write_db
run_verdict "$PLANDIR" --merge true
check "a DIRTY root" dirty "$U11:human,$COORD_URL:predecessor" "" "merge-state:DIRTY" ""

# --- error ------------------------------------------------------------------------

ct_case error-adopt
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'author="someone-else"'
ct_write_db
run_verdict "$PLANDIR" --merge true
check "an index entry by another author" error "" "" "" "execute:pr-adopt"

ct_case error-early
ct_write_db
run_verdict "$PLANDIR" --merge true
check "a loop that stopped with a node still to dispatch" error "" "" "" "execute:coord-loop"
run_verdict "$PLANDIR" --merge true --loop-line "error:execute:dispatch"
check "the same, the loop reporting a failed dispatch" error "" "" "" "execute:dispatch"
run_verdict "$PLANDIR" --merge true --loop-line "error:execute:made-up"
check "the same, a loop line outside the step set" error "" "" "" "execute:coord-loop"

# --- usage ------------------------------------------------------------------------

ct_case usage
ct_write_db
OUT=$(cd "$PLANDIR" && bash "$VERDICT" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" 2>/dev/null); RC=$?
if [ "$RC" -eq 64 ] && [ -z "$OUT" ] && [ ! -s "$GH_CALL_LOG" ]; then
    pass "a missing --merge is a usage error with no output and no gh call"
else
    fail "a missing --merge: rc=$RC out=[$OUT]"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
