#!/usr/bin/env bash
# coordinated-next_test.sh — the coordinated loop's next action, table-driven
# Part of the execute skill
#
# coordinated-next.sh is stateless and read-only: from the PLAN's nodes, the
# coordination PR's index, and live gh, it prints one action. Each case builds
# a GitHub model for the eval gh shim (see coord-test-helpers.sh), runs the
# script, and asserts the one line it printed, and that it wrote nothing: no
# gh call that edits, readies, creates, merges, or closes, and no koto call.
#
# Cases:
#   usage: missing --merge, --merge yes, a bad slug, a home repo outside repos
#   error:execute:pr-adopt   no coordination PR
#   error:execute:status-read a failing gh read
#   done:merged              the coordination PR is MERGED
#   dispatch:<root>          nothing indexed yet
#   evaluate:<root>          a draft root PR with passing checks
#   error:execute:ci         a draft root PR with a failing check
#   evaluate:<root>          a ready root PR whose checks are pending
#   merge:<root>             a ready, mergeable root with --merge true
#   pause                    the same root with --merge false (its successor
#                            waits); never a merge action
#   done:ready-awaiting-merge two independent mergeable roots, --merge false
#   dispatch:<successor>     the root is MERGED
#   pause                    the root's merge was called (merge-not-observed)
#                            and it is still OPEN: its successor stays blocked
#   pause                    a head that moved: the verdict is awaiting
#   cascade                  every node MERGED, the PLAN still present
#   evaluate-coordination    the PLAN gone, the coordination PR a draft
#   merge-coordination       the coordination PR ready and mergeable, --merge
#   done:ready-awaiting-merge the coordination merge was not observed
#   error:execute:pr-adopt   an index entry by another author
#   error:execute:pr-adopt   an index entry on the wrong head branch
#   error:execute:write-set  an index entry naming a repository outside repos
#   first-match order        an error beats a merge; a merge beats a dispatch
#
# Usage: coordinated-next_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
NEXT="$SCRIPT_DIR/coordinated-next.sh"

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

# run_next <dir> [args...] -- run from <dir> with the standard arguments.
run_next() {
    local dir="$1"
    shift
    (cd "$dir" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" \
        --repos "acme/repo-a,acme/repo-b" --home-repo "$CT_REPO" --coord-branch "$CT_CB" "$@" 2>"$CASE/stderr")
}

# expect <label> <want> <got>
expect() {
    if [ "$3" = "$2" ]; then
        pass "$1: $2"
    else
        fail "$1: expected [$2], got [$3]"
        sed 's/^/    /' "$CASE/stderr" 2>/dev/null | tail -5
    fi
}

# wrote_nothing <label> -- no write-shaped gh call and no koto call.
wrote_nothing() {
    if ct_calls | grep -Eq '^(pr (create|edit|ready|merge|close)|api -X|api --method)'; then
        fail "$1 made a GitHub write: $(ct_calls | grep -E '^pr (create|edit|ready|merge|close)' | head -1)"
    elif [ -s "$CASE/koto-calls.log" ]; then
        fail "$1 called koto"
    else
        pass "$1 wrote nothing"
    fi
}

# --- usage ----------------------------------------------------------------------

ct_case usage
ct_write_db
out=$(cd "$PLANDIR" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" 2>/dev/null); rc=$?
if [ "$rc" -eq 64 ] && [ -z "$out" ] && [ ! -s "$GH_CALL_LOG" ]; then
    pass "a missing --merge is a usage error with no output and no gh call"
else
    fail "a missing --merge: rc=$rc out=[$out]"
fi
for bad in "--merge yes" "--merge TRUE" "--merge"; do
    # shellcheck disable=SC2086
    out=$(cd "$PLANDIR" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" $bad 2>/dev/null); rc=$?
    if [ "$rc" -eq 64 ] && [ -z "$out" ]; then
        pass "[$bad] is a usage error"
    else
        fail "[$bad]: rc=$rc out=[$out]"
    fi
done
out=$(cd "$PLANDIR" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug 'T;x' --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge false 2>/dev/null); rc=$?
[ "$rc" -eq 64 ] && pass "a slug outside ^[a-z0-9-]+\$ is a usage error" || fail "bad slug: rc=$rc"
out=$(cd "$PLANDIR" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug t --repos "acme/repo-b" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge false 2>/dev/null); rc=$?
[ "$rc" -eq 64 ] && pass "a home repo outside --repos is a usage error" || fail "home outside repos: rc=$rc"
[ -s "$GH_CALL_LOG" ] && fail "a usage error made a gh call" || pass "no usage error made a gh call"

# --- the coordination PR ----------------------------------------------------------

ct_case no-coord
ct_write_db
out=$(cd "$PLANDIR" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch docs/elsewhere --merge false 2>"$CASE/stderr")
expect "no owned coordination PR" "error:execute:pr-adopt" "$out"

ct_case read-fails
CT_LOGIN=null
ct_write_db
# A login the ownership filter can't use is a failed read.
jq '.login = null' "$CASE/scenario/gh/db.json" > "$CASE/db" && mv "$CASE/db" "$CASE/scenario/gh/db.json"
out=$(run_next "$PLANDIR" --merge false)
expect "a gh read failure" "error:execute:status-read" "$out"

ct_case coord-merged
CT_COORD_STATE=MERGED
ct_write_db
out=$(run_next "$PLANDIR" --merge false)
expect "the coordination PR is MERGED" "done:merged" "$out"

# --- nodes ------------------------------------------------------------------------

ct_case fresh
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "nothing indexed" "dispatch:$CT_CORE" "$out"
wrote_nothing "the fresh case"

ct_case root-draft
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a draft root PR with passing checks" "evaluate:$CT_CORE" "$out"
wrote_nothing "the evaluate case"

ct_case root-draft-failing
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true' 'checks=[{"name":"build","bucket":"fail"}]'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a draft root PR with a failing check" "error:execute:ci" "$out"

ct_case root-pending
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'checks=[{"name":"build","bucket":"pending"}]'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a ready root PR with a pending check" "evaluate:$CT_CORE" "$out"

ct_case root-mergeable
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a mergeable root with --merge true" "merge:$CT_CORE" "$out"
wrote_nothing "the merge case"

ct_case root-mergeable-no-merge
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge false)
expect "the same root with --merge false (its successor waits)" "pause" "$out"
case "$out" in merge*) fail "--merge false printed a merge action" ;; *) pass "--merge false printed no merge action" ;; esac

ct_case two-roots-no-merge
ct_index_line pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_index_line pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge false)
expect "two independent mergeable roots, --merge false" "done:ready-awaiting-merge" "$out"

ct_case two-roots-merge
ct_index_line pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_index_line pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "two roots in two repositories, --merge true" "merge:pr-repo-a-default" "$out"

ct_case root-merged
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "the root is MERGED" "dispatch:$CT_CLI" "$out"

ct_case merge-called-not-merged
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true --attempts "$CT_CORE:merge-not-observed")
expect "a predecessor whose merge was called but is still OPEN" "pause" "$out"

ct_case head-moved
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_OTHER"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "an index head= that differs from the live head" "pause" "$out"

ct_case no-head
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "an index entry with no head= field" "pause" "$out"

# --- after every node merged ------------------------------------------------------

ct_case cascade
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "every node MERGED, the PLAN present" "cascade" "$out"

ct_case evaluate-coordination
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_index_line coordination "$CT_REPO" 10 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone, the coordination PR a draft" "evaluate-coordination" "$out"

ct_case gone-no-record
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone, but no coordination head= record" "cascade" "$out"

ct_case merge-coordination
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_index_line coordination "$CT_REPO" 10 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
CT_COORD_DRAFT=false
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the coordination PR ready and mergeable, --merge true" "merge-coordination" "$out"
out=$(run_next "$GONEDIR" --merge false)
expect "the same, --merge false" "done:ready-awaiting-merge" "$out"
out=$(run_next "$GONEDIR" --merge true --attempts "coordination:merge-not-observed")
expect "the coordination merge was not observed" "done:ready-awaiting-merge" "$out"

# --- index control ----------------------------------------------------------------

ct_case foreign-author
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'author="someone-else"'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "an index entry authored by someone else" "error:execute:pr-adopt" "$out"
wrote_nothing "the foreign-author case"

ct_case wrong-branch
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "feature/elsewhere"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "an index entry whose head branch is not impl/<slug>-<node-id>" "error:execute:pr-adopt" "$out"

ct_case out-of-set
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line pr-stranger-default acme/stranger 31 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "an index entry naming a repository outside the write set" "error:execute:write-set" "$out"
if ct_calls | grep -q 'acme/stranger'; then
    fail "the out-of-set repository was read"
else
    pass "the out-of-set repository was never read"
fi

ct_case out-of-set-plan
ct_write_db
out=$(cd "$PLANDIR" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug t --repos "acme/repo-a" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge true 2>"$CASE/stderr")
expect "a PLAN whose nodes are all in --repos (control)" "dispatch:$CT_CORE" "$out"
out=$(cd "$PLAN2DIR" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug t --repos "acme/repo-a" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge true 2>"$CASE/stderr")
expect "a PLAN **Repo** outside --repos" "error:execute:write-set" "$out"

# --- first-match order ------------------------------------------------------------

ct_case order-error-first
ct_index_line pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_index_line pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default 'author="someone-else"'
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "an error on a later node beats a merge on an earlier one" "error:execute:pr-adopt" "$out"

ct_case order-merge-before-dispatch
ct_index_line pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "a merge beats a dispatch" "merge:pr-repo-b-default" "$out"

ct_case order-dispatch-before-evaluate
ct_index_line pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default 'isDraft=true'
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "a dispatch beats an evaluate" "dispatch:pr-repo-a-default" "$out"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
