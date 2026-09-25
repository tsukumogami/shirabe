#!/usr/bin/env bash
# coord-merge_test.sh — a coordinated PR merges only through merge-exec.sh, at
# the index's head=, and a merge that didn't land is recorded
# Part of the execute skill
#
# Each case runs coord-merge.sh against the eval gh shim's repository model,
# the koto stub, and a shirabe stub (see coord-test-helpers.sh), with the real
# merge-exec.sh and merge-verdict.sh behind it.
#
# Cases:
#   a mergeable node                     one pr merge with --match-head-commit
#     <index head=>, no --admin or --auto; the confirm read prints merged;
#     nothing recorded
#   a merge accepted but still OPEN      not-merged:merge-not-observed;
#     merge_attempts records <node>:merge-not-observed
#   a merge call that fails              merge-refused:not-merged:merge-call-failed,
#     recorded; exactly one pr merge
#   no head= on the node's line          refused before any merge call
#   an index head= the PR no longer has  merge-exec.sh refuses: no pr merge
#   an index entry by another author     exit 73, no pr merge
#   the coordination PR                  the merge-last gate runs first, over
#     every indexed PR but the coordination PR itself; a gate that doesn't
#     pass refuses the merge
#   merge_attempts keeps one entry per node
#
# Usage: coord-merge_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
MERGE="$SCRIPT_DIR/coord-merge.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

S=execute-t

run_merge() { # run_merge <node>
    mkdir -p "$CASE/ctx/$S"
    OUT=$(bash "$MERGE" --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" --node "$1" 2>"$CASE/stderr")
    RC=$?
}
merges() { ct_calls | grep -c '^pr merge'; }
attempts() { cat "$CASE/ctx/$S/merge_attempts" 2>/dev/null; }

node_case() { # node_case <name> [pr key=json ...]
    local name="$1"
    shift
    ct_case "$name"
    ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
    ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" "$@"
    ct_write_db
}

# --- a mergeable node -------------------------------------------------------------

node_case mergeable
run_merge "$CT_CORE"
MLINE=$(ct_calls | grep '^pr merge')
if [ "$RC" -eq 0 ] && [ "$OUT" = "merge-called:squash:$CT_HEAD
merged" ]; then
    pass "a mergeable node: merge-called, then a confirm read of merged"
else
    fail "mergeable: rc=$RC out=[$OUT]"; tail -3 "$CASE/stderr"
fi
if [ "$(merges)" -eq 1 ] && [ "$MLINE" = "pr merge 11 --repo $CT_REPO --squash --match-head-commit $CT_HEAD" ]; then
    pass "exactly one pr merge, with --match-head-commit equal to the index head="
else
    fail "the merge calls: [$MLINE]"
fi
if printf '%s' "$MLINE" | grep -Eq -- '--admin|--auto'; then fail "the merge carries --admin or --auto"; else pass "no --admin or --auto"; fi
[ -z "$(attempts)" ] && pass "a landed merge records no attempt" || fail "recorded [$(attempts)]"

# --- accepted but still OPEN ------------------------------------------------------

node_case stays-open 'merge="stays-open"'
run_merge "$CT_CORE"
if [ "$OUT" = "merge-called:squash:$CT_HEAD
not-merged:merge-not-observed" ] && [ "$(attempts)" = "$CT_CORE:merge-not-observed" ]; then
    pass "a merge still OPEN after the call reads not-merged:merge-not-observed and is recorded"
else
    fail "stays-open: out=[$OUT] attempts=[$(attempts)]"
fi
case "$OUT" in *"
merged"*|merged) fail "a merge that did not land printed merged" ;; *) pass "merge-called is never read as merged" ;; esac

# --- a failing merge call ---------------------------------------------------------

node_case call-fails 'merge="fail"'
run_merge "$CT_CORE"
if [ "$OUT" = "merge-refused:not-merged:merge-call-failed" ] && [ "$(merges)" -eq 1 ] \
    && [ "$(attempts)" = "$CT_CORE:merge-call-failed" ]; then
    pass "a failing merge call is refused, recorded, and not retried"
else
    fail "call-fails: out=[$OUT] merges=$(merges) attempts=[$(attempts)]"
fi

# --- one entry per node -------------------------------------------------------------

printf '%s' "other-node:merge-call-failed,$CT_CORE:merge-call-failed" > "$CASE/ctx/$S/merge_attempts"
jq '(.prs[] | select(.number == 11) | .merge) = "stays-open"' "$GH_CALL_LOG.d/db.json" > "$CASE/db" && mv "$CASE/db" "$GH_CALL_LOG.d/db.json"
run_merge "$CT_CORE"
[ "$(attempts)" = "other-node:merge-call-failed,$CT_CORE:merge-not-observed" ] \
    && pass "merge_attempts keeps one entry per node, the latest result" || fail "attempts: [$(attempts)]"

# --- the head -----------------------------------------------------------------------

ct_case no-head
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
run_merge "$CT_CORE"
if [ "$OUT" = "merge-refused:awaiting:head-moved" ] && [ "$(merges)" -eq 0 ]; then
    pass "a line with no head= is refused before any merge call"
else
    fail "no-head: out=[$OUT] merges=$(merges)"
fi

ct_case head-moved
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_OTHER"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
run_merge "$CT_CORE"
if [ "$OUT" = "merge-refused:awaiting:head-moved" ] && [ "$(merges)" -eq 0 ]; then
    pass "an index head= the PR no longer has: merge-exec.sh refuses, no pr merge"
else
    fail "head-moved: out=[$OUT] merges=$(merges)"
fi

# --- ownership ------------------------------------------------------------------------

node_case foreign 'author="someone-else"'
run_merge "$CT_CORE"
if [ "$RC" -eq 73 ] && [ "$(merges)" -eq 0 ] && [ -z "$OUT" ]; then
    pass "an index entry by another author exits 73 with no pr merge"
else
    fail "foreign: rc=$RC out=[$OUT] merges=$(merges)"
fi

# --- the coordination PR -------------------------------------------------------------

coord_case() { # coord_case <name>
    ct_case "$1"
    ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
    ct_index_line "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
    ct_index_line coordination "$CT_REPO" 10 "$CT_HEAD"
    ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
    ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
    CT_COORD_DRAFT=false
    ct_write_db
}

coord_case coord
run_merge coordination
GATE=$(grep -- '--merge-gate' "$CASE/shirabe-calls.log")
if [ "$OUT" = "merge-called:squash:$CT_HEAD
merged" ] && [ "$(merges)" -eq 1 ]; then
    pass "the coordination PR merges last through merge-exec.sh"
else
    fail "coordination: out=[$OUT]"; tail -3 "$CASE/stderr"
fi
case "$GATE" in
    *"--mode=ready"*"--pr acme/repo-a:docs/plans/PLAN-t.md#11"*"--pr acme/repo-a:docs/plans/PLAN-t.md#12"*)
        case "$GATE" in
            *"#10"*) fail "the merge gate was given the coordination PR itself: [$GATE]" ;;
            *) pass "the merge gate runs over every indexed PR but the coordination PR itself" ;;
        esac
        ;;
    *) fail "the merge gate call: [$GATE]" ;;
esac

coord_case coord-gate-fails
export CT_GATE_FAIL=1
run_merge coordination
unset CT_GATE_FAIL
if [ "$OUT" = "merge-refused:merge-gate" ] && [ "$(merges)" -eq 0 ]; then
    pass "a merge gate that doesn't pass refuses the coordination merge"
else
    fail "gate fails: out=[$OUT] merges=$(merges)"
fi

# --- usage ------------------------------------------------------------------------------

ct_case usage
ct_write_db
for args in "--session $S --slug t --home-repo $CT_REPO --coord-branch $CT_CB" \
            "--session $S --slug t --home-repo $CT_REPO --coord-branch $CT_CB --node Bad" \
            "--session $S --slug t --home-repo a/b/c --coord-branch $CT_CB --node x"; do
    # shellcheck disable=SC2086
    bash "$MERGE" $args >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 64 ] && pass "usage [$args] exits 64" || fail "usage [$args]: rc=$rc"
done
[ -s "$GH_CALL_LOG" ] && fail "a usage error made a gh call" || pass "no usage error made a gh call"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
