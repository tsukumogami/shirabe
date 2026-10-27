#!/usr/bin/env bash
# coordination-verdict_test.sh — the verdict a coordinated run ends on,
# table-driven
# Part of the execute skill
#
# coordination-verdict.sh recomputes where the run stands and prints the
# verdict coord_verdict routes on, with the pr, waiting, resume, reason, and
# step fields the terminals report, and `cascade=failed` when the loop
# stopped with the cascade still to run. It is read-only. Each case seeds a
# run record through the test helper and builds a GitHub model for the eval
# gh shim (see coord-test-helpers.sh), and asserts every field.
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
#                                     merge was not observed; a recorded head
#                                     the live PR moved off (head-moved)
#   dirty (-> done_blocked, ready-awaiting-merge) a DIRTY root
#   error (-> done_blocked)           the loop's own error (pr-adopt); a loop
#                                     that stopped early, with and without a
#                                     recognised --loop-line step; a loop that
#                                     stopped with the cascade still to run
#                                     (cascade=failed, and only then)
#   follow-ups (-> ready)             an open one with --merge false
#                                     (merge-not-requested), a closed one
#                                     (follow-up-closed:<url>), a draft one
#                                     (merge-state:DRAFT); a closed one behind
#                                     an earlier merge-not-requested still
#                                     names follow-up-closed:<url>
#   read-only                        no write-shaped gh call, no koto write
#
# Usage: coordination-verdict_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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

S=execute-t
PLANDIR="$CT_WORK/plan"
ct_plan "$PLANDIR"
PLAN2DIR="$CT_WORK/plan2"
ct_plan "$PLAN2DIR" two-repo
GONEDIR="$CT_WORK/gone"
mkdir -p "$GONEDIR"
NODES2=$(ct_nodes_of "$PLAN2DIR/docs/plans/PLAN-t.md")

COORD_URL="https://github.com/acme/repo-a/pull/10"
U11="https://github.com/acme/repo-a/pull/11"
U21="https://github.com/acme/repo-b/pull/21"

run_verdict() { # run_verdict <dir> [args...]
    local dir="$1"
    shift
    : > "$CASE/koto-calls.log"
    OUT=$(cd "$dir" && bash "$VERDICT" --session "$S" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" \
        --repos "acme/repo-a,acme/repo-b" --home-repo "$CT_REPO" --coord-branch "$CT_CB" "$@" 2>"$CASE/stderr")
    RC=$?
}

field() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }

# check <label> <verdict> <waiting> <resume> <reason> <step> [<cascade>]
check() {
    local label="$1" ok=1 k want got
    [ "$RC" -eq 0 ] || { fail "$label: exit $RC"; return; }
    for k in coord_verdict:"$2" pr:"$COORD_URL" waiting:"$3" resume:"$4" reason:"$5" step:"$6" cascade:"${7:-}"; do
        want="${k#*:}"
        got=$(field "${k%%:*}")
        if [ "$got" != "$want" ]; then
            fail "$label: ${k%%:*} expected [$want], got [$got]"
            ok=0
        fi
    done
    [ "$ok" -eq 1 ] && pass "$label: coord_verdict=$2${5:+ reason=$5}${6:+ step=$6}${7:+ cascade=$7}"
    if ct_calls | grep -Eq '^pr (create|edit|ready|merge|close)'; then
        fail "$label made a GitHub write"
    fi
    [ -n "$(ct_ctx_writes)" ] && fail "$label wrote koto context"
    return 0
}

# both_merged <case> -- both default nodes recorded and MERGED.
both_merged() {
    ct_case "$1"
    ct_record_setup
    ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
    ct_record_node "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
    ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
    ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
}

# --- merged -----------------------------------------------------------------------

ct_case merged
ct_record_setup
CT_COORD_STATE=MERGED
ct_write_db
run_verdict "$PLANDIR" --merge true
check "the coordination PR is MERGED" merged "" "" "" ""

both_merged coord-not-observed
ct_record_cascade pushed "$CT_HEAD"
CT_COORD_DRAFT=false
ct_write_db
run_verdict "$GONEDIR" --merge true --attempts "coordination:merge-not-observed"
check "the coordination merge was called and not observed (the confirm read decides)" \
    merged "$COORD_URL:human" "" "" ""

# --- ready ------------------------------------------------------------------------

ct_case ready-roots
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
run_verdict "$PLAN2DIR" --merge false
check "independent mergeable roots without --merge" ready \
    "$U11:human,$U21:human,$COORD_URL:predecessor" "" "merge-not-requested" ""

both_merged ready-coord-review
ct_record_cascade pushed "$CT_HEAD"
CT_COORD_DRAFT=false
ct_write_db
jq '(.prs[] | select(.number == 10) | .reviewDecision) = "REVIEW_REQUIRED" | (.prs[] | select(.number == 10) | .mergeStateStatus) = "BLOCKED"' \
    "$CASE/scenario/gh/db.json" > "$CASE/db" && mv "$CASE/db" "$CASE/scenario/gh/db.json"
run_verdict "$GONEDIR" --merge true
check "the coordination PR awaiting review after the cascade" ready \
    "$COORD_URL:human" "" "merge-state:BLOCKED:review=REVIEW_REQUIRED" ""

# --- the merge refusals and a body the render couldn't post --------------------------

ct_case ready-refused
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
run_verdict "$PLAN2DIR" --merge true --attempts "pr-repo-a-default:merge-refused,pr-repo-b-default:merge-refused"
check "every root's merge refused" ready \
    "$U11:human,$U21:human,$COORD_URL:predecessor" "" "merge-refused" ""

both_merged ready-body-stale
ct_record_cascade pushed "$CT_HEAD"
ct_write_db
run_verdict "$GONEDIR" --merge true --attempts "coordination:body-stale"
check "a draft coordination PR whose body couldn't be posted" ready \
    "$COORD_URL:human" "" "merge-refused:body-stale" ""
run_verdict "$GONEDIR" --merge true --attempts "coordination:body-full"
check "a coordination PR whose body is over the cap" ready \
    "$COORD_URL:human" "" "merge-refused:body-full" ""

# The node's verdict is awaiting (its recorded head moved): a refused merge
# keeps the verdict's own reason.
ct_case refused-head-moved
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_OTHER"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_OTHER"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
run_verdict "$PLAN2DIR" --merge true --attempts "pr-repo-a-default:merge-refused"
check "a refused merge whose verdict is awaiting keeps head-moved" ready \
    "$U11:human,$U21:human,$COORD_URL:predecessor" "" "head-moved" ""

ct_case error-visibility
ct_record_setup
ct_write_db
run_verdict "$PLANDIR" --merge true --loop-line "error:execute:visibility"
check "a loop stopped on error:execute:visibility names the step" error "" "" "" "execute:visibility"

# --- paused -----------------------------------------------------------------------

ct_case paused
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
run_verdict "$PLANDIR" --merge false
check "a root awaiting a human, its successor waiting (no --merge)" paused \
    "$U11:human,$COORD_URL:predecessor" "/execute docs/plans/PLAN-t.md" "merge-not-requested" ""
run_verdict "$PLANDIR" --merge true --attempts "$CT_CORE:merge-not-observed"
check "a root whose merge was not observed (with --merge: resume carries it)" paused \
    "$U11:human,$COORD_URL:predecessor" "/execute docs/plans/PLAN-t.md --merge" "merge-not-observed" ""

ct_case head-moved
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_OTHER"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
run_verdict "$PLANDIR" --merge true
check "a recorded head the live PR moved off" paused \
    "$U11:human,$COORD_URL:predecessor" "/execute docs/plans/PLAN-t.md --merge" "head-moved" ""

# --- dirty ------------------------------------------------------------------------

ct_case dirty
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'mergeStateStatus="DIRTY"'
ct_write_db
run_verdict "$PLANDIR" --merge true
check "a DIRTY root" dirty "$U11:human,$COORD_URL:predecessor" "" "merge-state:DIRTY" ""

# --- error ------------------------------------------------------------------------

ct_case error-adopt
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'author="someone-else"'
ct_write_db
run_verdict "$PLANDIR" --merge true
check "a recorded PR by another author" error "" "" "" "execute:pr-adopt"

# An open node PR whose work item deferred verification and whose body
# doesn't record it: the verdict names the step, never status-read.
ct_case error-deferral-record
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true'
ct_write_db
mkdir -p "$CASE/ctx/work-on-t-$CT_CORE-1"
printf '%s' "CI only" > "$CASE/ctx/work-on-t-$CT_CORE-1/verification_deferral"
run_verdict "$PLANDIR" --merge true --loop-line "error:execute:deferral-record"
check "a node PR missing its deferral record" error "" "" "" "execute:deferral-record"

ct_case error-early
ct_record_setup
ct_write_db
run_verdict "$PLANDIR" --merge true
check "a loop that stopped with a node still to dispatch" error "" "" "" "execute:coord-loop"
run_verdict "$PLANDIR" --merge true --loop-line "error:execute:dispatch"
check "the same, the loop reporting a failed dispatch" error "" "" "" "execute:dispatch"
run_verdict "$PLANDIR" --merge true --loop-line "error:execute:made-up"
check "the same, a loop line outside the step set" error "" "" "" "execute:coord-loop"

both_merged cascade-failed
ct_write_db
run_verdict "$PLANDIR" --merge true --loop-line "error:execute:cascade"
check "a loop that stopped with the cascade still to run" error "" "" "" "execute:cascade" failed

both_merged cascade-failed-gone
ct_record_cascade failed execute:cascade
ct_write_db
run_verdict "$GONEDIR" --merge true --loop-line "error:execute:status-read"
check "the cascade still to run after a failed one, the PLAN gone" error "" "" "" "execute:status-read" failed

# --- follow-ups ---------------------------------------------------------------------

UF21="https://github.com/acme/repo-a/pull/21"
UF22="https://github.com/acme/repo-b/pull/22"

both_merged fu-open
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 21
ct_write_db
run_verdict "$PLANDIR" --merge false
check "an open follow-up of a node GitHub reports MERGED, --merge false" ready \
    "$UF21:human,$COORD_URL:predecessor" "" merge-not-requested ""

both_merged fu-closed
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 21 'state="CLOSED"'
ct_write_db
run_verdict "$PLANDIR" --merge true
check "a follow-up closed unmerged" ready "$UF21:human,$COORD_URL:predecessor" "" "follow-up-closed:$UF21" ""

both_merged fu-draft
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 21 'isDraft=true'
ct_write_db
run_verdict "$PLANDIR" --merge true
check "a draft follow-up" ready "$UF21:human,$COORD_URL:predecessor" "" "merge-state:DRAFT" ""

# Only the first human reason is reported, so a closed follow-up behind an
# earlier merge-not-requested would never be named: its reason comes first.
ct_case fu-closed-first
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_record_follow_up pr-repo-b-default acme/repo-b 22
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default 'state="MERGED"'
ct_follow_up_pr acme/repo-b 22 'state="CLOSED"'
ct_write_db
run_verdict "$PLAN2DIR" --merge false
check "a closed follow-up after a merge-not-requested node" ready \
    "$U11:human,$UF22:human,$COORD_URL:predecessor" "" "follow-up-closed:$UF22" ""

# --- usage ------------------------------------------------------------------------

ct_case usage
ct_write_db
OUT=$(cd "$PLANDIR" && bash "$VERDICT" --session "$S" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" 2>/dev/null); RC=$?
if [ "$RC" -eq 64 ] && [ -z "$OUT" ] && [ ! -s "$GH_CALL_LOG" ]; then
    pass "a missing --merge is a usage error with no output and no gh call"
else
    fail "a missing --merge: rc=$RC out=[$OUT]"
fi
OUT=$(cd "$PLANDIR" && bash "$VERDICT" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge true 2>/dev/null); RC=$?
[ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "a missing --session is a usage error" || fail "missing --session: rc=$RC out=[$OUT]"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
