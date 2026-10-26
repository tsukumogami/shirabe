#!/usr/bin/env bash
# coordinated-next_test.sh — the coordinated loop's next action, table-driven
# Part of the execute skill
#
# coordinated-next.sh is stateless and read-only: from the PLAN's nodes, the
# run record in the session, and live gh, it prints one action. Each case
# seeds a run record through the test helper (run-record.sh itself), builds a
# GitHub model for the eval gh shim (see coord-test-helpers.sh), runs the
# script, and asserts the one line it printed, and that it wrote nothing: no
# gh call that edits, readies, creates, merges, or closes, and no koto
# context write.
#
# Cases:
#   usage: missing --merge, --merge yes, a bad slug, a missing --session
#   error:execute:status-read no run record; the recorded coordination PR
#                            unreadable; a failing gh read
#   done:merged              the coordination PR is MERGED
#   dispatch:<root>          nothing recorded yet; a body index line alone
#                            records nothing
#   evaluate:<root>          a draft root PR with passing checks
#   error:execute:ci         a draft root PR with a failing check
#   error:execute:deferral-record
#                            a draft root PR, and a mergeable one with
#                            --merge true, whose work item's child deferred
#                            verification and whose body lacks the record
#                            (evaluate and merge once it has it; another
#                            node's deferral doesn't hold this one; a failed
#                            key read is status-read; with the PLAN gone the
#                            node's children come from koto's root sessions,
#                            an unreadable list is status-read; no deferral
#                            evaluates as before with no body read and no
#                            stderr)
#   evaluate:<root>          a ready root PR whose checks are pending
#   merge:<root>             a ready, mergeable root with --merge true, at the
#                            recorded head; a body index head= that differs
#                            changes nothing
#   pause                    the same root with --merge false (its successor
#                            waits); never a merge action
#   done:ready-awaiting-merge two independent mergeable roots, --merge false
#   dispatch:<successor>     the root is MERGED
#   pause                    the root's merge was called (merge-not-observed)
#                            and it is still OPEN: its successor stays blocked
#   pause / ready            a recorded head the live PR moved off: the
#                            verdict is awaiting, and a second run prints the
#                            same line (never a loop)
#   cascade                  every node MERGED, the PLAN still present; the
#                            PLAN gone with no run/cascade; the PLAN gone
#                            with a failed cascade
#   evaluate-coordination    the PLAN gone, the cascade pushed, the
#                            coordination PR a draft: every node from
#                            run/setup is read; one with no run/node key is
#                            status-read
#   merge-coordination       the coordination PR ready and mergeable, --merge,
#                            at run/cascade's head; a head that moved is
#                            ready-awaiting-merge
#   done:ready-awaiting-merge the coordination merge was not observed
#   --attempts               accepts merge-refused, body-stale, body-full
#   done:ready-awaiting-merge every mergeable root's merge refused
#                            (merge-refused), none printed as merge:<node>
#                            again; a coordination body the render couldn't
#                            post (body-stale on a draft, body-full on a
#                            mergeable one) prints neither
#                            evaluate-coordination nor merge-coordination; a
#                            live-state change alone writes nothing
#   error:execute:pr-adopt   a recorded PR by another author, another run, on
#                            the wrong head branch, or not the owned PR; a
#                            record naming another repository than the PLAN
#   error:execute:write-set  a recorded node naming a repository outside
#                            repos; a PLAN node outside repos
#   home outside --repos     a coordination PR in acme/repo-a over a PLAN whose
#                            nodes are all in acme/repo-b: dispatch, evaluate,
#                            cascade, evaluate-coordination, merge-coordination,
#                            done:merged; a node recorded in the home is
#                            refused
#   first-match order        an error beats a merge; a merge beats a dispatch
#   follow-ups               one whose node is open waits (the node merges
#                            first); one whose node is MERGED merges next
#                            (merge:<node>/follow-up-<n>), only with --merge;
#                            an open one holds the cascade and, with the PLAN
#                            gone, both coordination steps; MERGED, it lets
#                            them run; --attempts takes a follow-up id
#                            (follow-up-0 is a usage error); pending checks
#                            are evaluate:<id>; a draft or a closed one waits
#                            on a human without ending the run; removed, it
#                            is not read; a replacement holds the run until
#                            it merges; one in another repository than its
#                            node's is error:execute:write-set
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

S=execute-t
PLANDIR="$CT_WORK/plan"
ct_plan "$PLANDIR"
PLAN2DIR="$CT_WORK/plan2"
ct_plan "$PLAN2DIR" two-repo
GONEDIR="$CT_WORK/gone"
mkdir -p "$GONEDIR"
NODES2=$(ct_nodes_of "$PLAN2DIR/docs/plans/PLAN-t.md")

# run_next <dir> [args...] -- run from <dir> with the standard arguments. The
# koto call log starts empty, so what the run itself called is what's there.
run_next() {
    local dir="$1"
    shift
    : > "$CASE/koto-calls.log"
    (cd "$dir" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" \
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

# wrote_nothing <label> -- no write-shaped gh call and no koto context write.
wrote_nothing() {
    if ct_calls | grep -Eq '^(pr (create|edit|ready|merge|close)|api -X|api --method)'; then
        fail "$1 made a GitHub write: $(ct_calls | grep -m1 -E '^pr (create|edit|ready|merge|close)')"
    elif [ -n "$(ct_ctx_writes)" ]; then
        fail "$1 wrote koto context: $(ct_ctx_writes | head -1)"
    else
        pass "$1 wrote nothing"
    fi
}

# --- usage ----------------------------------------------------------------------

ct_case usage
ct_write_db
out=$(cd "$PLANDIR" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" 2>/dev/null); rc=$?
if [ "$rc" -eq 64 ] && [ -z "$out" ] && [ ! -s "$GH_CALL_LOG" ]; then
    pass "a missing --merge is a usage error with no output and no gh call"
else
    fail "a missing --merge: rc=$rc out=[$out]"
fi
for bad in "--merge yes" "--merge TRUE" "--merge"; do
    # shellcheck disable=SC2086
    out=$(cd "$PLANDIR" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" $bad 2>/dev/null); rc=$?
    if [ "$rc" -eq 64 ] && [ -z "$out" ]; then
        pass "[$bad] is a usage error"
    else
        fail "[$bad]: rc=$rc out=[$out]"
    fi
done
out=$(cd "$PLANDIR" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug 'T;x' --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge false 2>/dev/null); rc=$?
[ "$rc" -eq 64 ] && pass "a slug outside ^[a-z0-9-]+\$ is a usage error" || fail "bad slug: rc=$rc"
out=$(cd "$PLANDIR" && bash "$NEXT" --plan docs/plans/PLAN-t.md --slug t --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge false 2>/dev/null); rc=$?
[ "$rc" -eq 64 ] && [ -z "$out" ] && pass "a missing --session is a usage error" || fail "missing --session: rc=$rc out=[$out]"
[ -s "$GH_CALL_LOG" ] && fail "a usage error made a gh call" || pass "no usage error made a gh call"

# --- the coordination PR ----------------------------------------------------------

ct_case no-record
ct_write_db
out=$(run_next "$PLANDIR" --merge false)
expect "no run record in the session" "error:execute:status-read" "$out"
if ct_calls | grep -q '^pr list'; then
    fail "with no record the coordination PR was looked up"
else
    pass "with no record no ownership lookup of the coordination PR is made"
fi

ct_case recorded-unreadable
ct_record_setup github 99
ct_write_db
out=$(run_next "$PLANDIR" --merge false)
expect "the recorded coordination PR can't be read" "error:execute:status-read" "$out"

ct_case read-fails
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
# A login the ownership filter can't use is a failed read.
jq '.login = null' "$CASE/scenario/gh/db.json" > "$CASE/db" && mv "$CASE/db" "$CASE/scenario/gh/db.json"
out=$(run_next "$PLANDIR" --merge false)
expect "a gh read failure" "error:execute:status-read" "$out"

ct_case coord-merged
ct_record_setup
CT_COORD_STATE=MERGED
ct_write_db
out=$(run_next "$PLANDIR" --merge false)
expect "the coordination PR is MERGED" "done:merged" "$out"
if ct_calls | grep -q '^pr list'; then
    fail "the coordination PR was found by a lookup, not by its recorded number"
else
    pass "the coordination PR is read by its recorded number, with no lookup"
fi

# --- nodes ------------------------------------------------------------------------

ct_case fresh
ct_record_setup
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "nothing recorded" "dispatch:$CT_CORE" "$out"
wrote_nothing "the fresh case"

ct_case index-only
ct_record_setup
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a body index line with no run/node key records nothing" "dispatch:$CT_CORE" "$out"

ct_case root-draft
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a draft root PR with passing checks" "evaluate:$CT_CORE" "$out"
wrote_nothing "the evaluate case"

ct_case root-draft-failing
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true' 'checks=[{"name":"build","bucket":"fail"}]'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a draft root PR with a failing check" "error:execute:ci" "$out"

# The verification deferral: the core node's work items are 1 and 2, children
# work-on-t-<node>-<item>; one holding verification_deferral deferred. An open
# node PR whose body doesn't record it is never evaluated (readied) or merged.
DREASON="host is in a measurement window until 02:40Z"
defer_child() { # defer_child <item> <reason>
    mkdir -p "$CASE/ctx/work-on-t-$CT_CORE-$1"
    printf '%s' "$2" > "$CASE/ctx/work-on-t-$CT_CORE-$1/verification_deferral"
}
RECORDED_BODY="body=\"x\\n\\n---\\n\\n## Verification\\n\\nLocal verification did not run: it was deferred to hosted CI.\\nReason: $DREASON\\nHosted CI is the build of record for this change.\\n\""
body_reads() { ct_calls | grep -Ec '^pr view .*--json body$'; }

ct_case defer-draft-unrecorded
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true'
ct_write_db
defer_child 2 "$DREASON"
out=$(run_next "$PLANDIR" --merge true)
expect "a draft node PR whose child deferred, its body without the record: no evaluate" "error:execute:deferral-record" "$out"
wrote_nothing "the deferral hold"
grep -qF "exactly: Reason: $DREASON" "$CASE/stderr" && pass "the hold names the missing reason on stderr" \
    || fail "the hold's stderr: [$(cat "$CASE/stderr")]"

ct_case defer-draft-recorded
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true' "$RECORDED_BODY"
ct_write_db
defer_child 2 "$DREASON"
out=$(run_next "$PLANDIR" --merge true)
expect "a draft node PR whose child deferred, the body recording it" "evaluate:$CT_CORE" "$out"

ct_case defer-mergeable-unrecorded
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
defer_child 1 "$DREASON"
out=$(run_next "$PLANDIR" --merge true)
expect "a ready, mergeable node PR (readied by hand) whose child deferred, no record: no merge" \
    "error:execute:deferral-record" "$out"
wrote_nothing "the merge hold"

ct_case defer-mergeable-recorded
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" "$RECORDED_BODY"
ct_write_db
defer_child 1 "$DREASON"
out=$(run_next "$PLANDIR" --merge true)
expect "a mergeable node PR whose child deferred, the body recording it" "merge:$CT_CORE" "$out"

ct_case defer-other-node
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true'
ct_write_db
mkdir -p "$CASE/ctx/work-on-t-$CT_CLI-3"
printf '%s' "$DREASON" > "$CASE/ctx/work-on-t-$CT_CLI-3/verification_deferral"
out=$(run_next "$PLANDIR" --merge true)
expect "another node's child deferred: this node's PR is evaluated as before" "evaluate:$CT_CORE" "$out"

ct_case defer-unreadable
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true'
ct_write_db
defer_child 2 "$DREASON"
out=$(KOTO_FAIL_EXISTS=verification_deferral run_next "$PLANDIR" --merge true)
expect "a child's key read that fails" "error:execute:status-read" "$out"

# The PLAN gone with a node PR still open (the cascade deletes it only after
# every node merged, so the PLAN went missing some other way): the node's
# children are found among koto's root sessions, and the hold still holds.
ct_case defer-plan-gone
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_record_node "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true'
ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
ct_write_db
defer_child 2 "$DREASON"
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone, an open draft node PR whose child deferred, no record" "error:execute:deferral-record" "$out"
out=$(KOTO_FAIL_WORKFLOWS=1 run_next "$GONEDIR" --merge true)
expect "the PLAN gone and koto's session list unreadable" "error:execute:status-read" "$out"
rm -rf "$CASE/ctx/work-on-t-$CT_CORE-2"
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone, no child session of the node" "evaluate:$CT_CORE" "$out"

ct_case defer-none
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'isDraft=true'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "no child deferred: the draft is evaluated as before" "evaluate:$CT_CORE" "$out"
[ "$(body_reads)" -eq 0 ] && pass "no child deferred: no node PR body read" \
    || fail "no deferral read a body: $(ct_calls | grep -E '^pr view .*--json body$')"
if grep -v '^\[plan-to-tasks\]' "$CASE/stderr" | grep -q .; then
    fail "no child deferred printed to stderr: [$(cat "$CASE/stderr")]"
else
    pass "no child deferred: nothing new on stderr"
fi

ct_case root-pending
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'checks=[{"name":"build","bucket":"pending"}]'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a ready root PR with a pending check" "evaluate:$CT_CORE" "$out"

ct_case root-mergeable
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a carried head the readiness check passes, with --merge true" "merge:$CT_CORE" "$out"
wrote_nothing "the merge case"

ct_case body-head-edited
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_OTHER"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a body index head= that differs from the record changes nothing" "merge:$CT_CORE" "$out"

ct_case root-mergeable-no-merge
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge false)
expect "the same root with --merge false (its successor waits)" "pause" "$out"
case "$out" in merge*) fail "--merge false printed a merge action" ;; *) pass "--merge false printed no merge action" ;; esac

ct_case two-roots-no-merge
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge false)
expect "two independent mergeable roots, --merge false" "done:ready-awaiting-merge" "$out"

ct_case two-roots-merge
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "two roots in two repositories, --merge true" "merge:pr-repo-a-default" "$out"

ct_case root-merged
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "the root is MERGED" "dispatch:$CT_CLI" "$out"

ct_case merge-called-not-merged
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true --attempts "$CT_CORE:merge-not-observed")
expect "a predecessor whose merge was called but is still OPEN" "pause" "$out"

# A carried head the readiness check refuses: reported, and the run stops
# there on every pass, never looping back into a merge.
ct_case head-moved
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_OTHER"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a recorded head the live PR moved off (its successor waits)" "pause" "$out"
out=$(run_next "$PLANDIR" --merge true)
expect "the same recorded head on a second run" "pause" "$out"
ct_calls | grep -q '^pr merge' && fail "a moved head reached a merge call" || pass "a moved head made no merge call"

ct_case head-moved-ready
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_OTHER"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_OTHER"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "two roots whose recorded heads both moved" "done:ready-awaiting-merge" "$out"
out=$(run_next "$PLAN2DIR" --merge true)
expect "the same, on a second run" "done:ready-awaiting-merge" "$out"

# --- after every node merged ------------------------------------------------------

# both_merged <case> -- a case with both default nodes recorded and MERGED.
both_merged() {
    ct_case "$1"
    ct_record_setup
    ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
    ct_record_node "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
    ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
    ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
}

both_merged cascade
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "every node MERGED, the PLAN present" "cascade" "$out"

both_merged evaluate-coordination
ct_record_cascade pushed "$CT_HEAD"
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone, the cascade pushed, the coordination PR a draft" "evaluate-coordination" "$out"
if ct_calls | grep -q "pr view 11 --repo $CT_REPO" && ct_calls | grep -q "pr view 12 --repo $CT_REPO"; then
    pass "with the PLAN gone, every node of run/setup's list was read"
else
    fail "with the PLAN gone, not every node was read: $(ct_calls | grep '^pr view' | tr '\n' ';')"
fi
wrote_nothing "the evaluate-coordination case"

ct_case gone-node-unrecorded
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_record_cascade pushed "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone and a run/setup node with no run/node key" "error:execute:status-read" "$out"

both_merged gone-no-cascade
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone, but no run/cascade (not-run)" "cascade" "$out"

both_merged gone-cascade-failed
ct_record_cascade failed execute:cascade
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone, a failed cascade: the cascade runs again" "cascade" "$out"

both_merged merge-coordination
ct_record_cascade pushed "$CT_HEAD"
CT_COORD_DRAFT=false
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the coordination PR ready and mergeable, --merge true" "merge-coordination" "$out"
out=$(run_next "$GONEDIR" --merge false)
expect "the same, --merge false" "done:ready-awaiting-merge" "$out"
out=$(run_next "$GONEDIR" --merge true --attempts "coordination:merge-not-observed")
expect "the coordination merge was not observed" "done:ready-awaiting-merge" "$out"

both_merged coordination-head-moved
ct_record_cascade pushed "$CT_OTHER"
CT_COORD_DRAFT=false
ct_write_db
out=$(run_next "$GONEDIR" --merge true)
expect "the coordination PR moved off run/cascade's head" "done:ready-awaiting-merge" "$out"

# --- refused merges and a coordination body that couldn't be posted ---------------

ct_case attempts-values
ct_record_setup
ct_write_db
for v in merge-refused body-stale body-full; do
    (cd "$PLANDIR" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" --repos "acme/repo-a,acme/repo-b" \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge true --attempts "coordination:$v" >/dev/null 2>&1)
    [ $? -eq 0 ] && pass "--attempts accepts coordination:$v" || fail "--attempts refused coordination:$v"
done

# Two independent roots, so neither has a successor waiting on it: a refused
# merge is not printed again, and the run ends ready-awaiting-merge.
ct_case merge-refused
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true --attempts "pr-repo-a-default:merge-refused")
expect "a root whose merge was refused is not merged again; the other root is" "merge:pr-repo-b-default" "$out"
out=$(run_next "$PLAN2DIR" --merge true --attempts "pr-repo-a-default:merge-refused,pr-repo-b-default:merge-refused")
expect "every mergeable node refused, none waited on" "done:ready-awaiting-merge" "$out"
wrote_nothing "the merge-refused case"

both_merged coordination-body-stale
ct_record_cascade pushed "$CT_HEAD"
ct_write_db
out=$(run_next "$GONEDIR" --merge true --attempts "coordination:body-stale")
expect "a draft coordination PR whose body the render couldn't post: no evaluate-coordination again" "done:ready-awaiting-merge" "$out"
CT_COORD_DRAFT=false
ct_write_db
rm -rf "$GH_CALL_LOG.d"
out=$(run_next "$GONEDIR" --merge true --attempts "coordination:body-full")
expect "a mergeable coordination PR whose body is over the cap: no merge-coordination" "done:ready-awaiting-merge" "$out"
out=$(run_next "$GONEDIR" --merge true --attempts "coordination:merge-refused")
expect "a coordination merge that was refused is not called again" "done:ready-awaiting-merge" "$out"
# A live change the body doesn't show (checks finishing) makes no write: the
# loop never posts the body; the renderer does, and only on a difference.
jq '(.prs[] | select(.number == 10) | .checks) = [{name: "build", bucket: "pass"}, {name: "lint", bucket: "pass"}]' \
    "$GH_CALL_LOG.d/db.json" > "$CASE/db.tmp" && mv "$CASE/db.tmp" "$GH_CALL_LOG.d/db.json"
out=$(run_next "$GONEDIR" --merge true)
expect "after a live-state change alone" "merge-coordination" "$out"
wrote_nothing "a live-state change alone"

# --- ownership and the write set --------------------------------------------------

ct_case foreign-author
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'author="someone-else"'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a recorded PR authored by someone else" "error:execute:pr-adopt" "$out"
wrote_nothing "the foreign-author case"

MINE=0123456789abcdef0123456789abcdef
OTHER=fedcba9876543210fedcba9876543210
ct_case foreign-run
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" "index=\"$OTHER\""
ct_write_db
out=$(run_next "$PLANDIR" --merge true --run-id "$MINE")
expect "--run-id: a recorded PR another run recorded last in its index" "error:execute:pr-adopt" "$out"
wrote_nothing "the foreign-run case"

ct_case own-run
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" "index=\"$MINE\""
ct_write_db
out_own=$(run_next "$PLANDIR" --merge true --run-id "$MINE")
out_hand=$(run_next "$PLANDIR" --merge true)
expect "--run-id: the run's own indexed node PR reads as it does by hand" "$out_hand" "$out_own"

ct_case bad-run-id
ct_write_db
(cd "$PLANDIR" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" --repos "acme/repo-a,acme/repo-b" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge false --run-id XYZ >/dev/null 2>&1)
[ $? -eq 64 ] && pass "a malformed --run-id is a usage error" || fail "a malformed --run-id was accepted"

ct_case wrong-branch
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "feature/elsewhere"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a recorded PR whose head branch is not impl/<slug>-<node-id>" "error:execute:pr-adopt" "$out"

ct_case not-the-owned-pr
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 12 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a recorded PR number that isn't the owned PR on the branch" "error:execute:pr-adopt" "$out"

ct_case record-repo-differs
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-b 11 "$CT_HEAD"
ct_pr acme/repo-b 11 impl/t-pr-repo-a-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "a record naming another repository than the PLAN's for the node" "error:execute:pr-adopt" "$out"

ct_case out-of-set
CT_RECORD_REPOS="acme/repo-a,acme/stranger"
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_record_node pr-stranger-default acme/stranger 31 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a recorded node naming a repository outside the write set" "error:execute:write-set" "$out"
if ct_calls | grep -q 'acme/stranger'; then
    fail "the out-of-set repository was read"
else
    pass "the out-of-set repository was never read"
fi

ct_case out-of-set-plan
ct_record_setup
ct_write_db
out=$(cd "$PLANDIR" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug t --repos "acme/repo-a" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge true 2>"$CASE/stderr")
expect "a PLAN whose nodes are all in --repos (control)" "dispatch:$CT_CORE" "$out"
out=$(cd "$PLAN2DIR" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug t --repos "acme/repo-a" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge true 2>"$CASE/stderr")
expect "a PLAN **Repo** outside --repos" "error:execute:write-set" "$out"

# --- the coordination PR's home outside the write set -------------------------------
#
# The coordination PR (#10) lives in acme/repo-a, and every node of the PLAN
# lands in acme/repo-b: --repos is acme/repo-b alone. The loop drives the nodes
# and then the coordination PR, which the record holds by number.

REMOTEDIR="$CT_WORK/remote"
ct_plan "$REMOTEDIR" remote
NODESR=$(ct_nodes_of "$REMOTEDIR/docs/plans/PLAN-t.md")
RCORE=pr-repo-b-core
RCLI=pr-repo-b-cli
run_remote() {
    local dir="$1"
    shift
    : > "$CASE/koto-calls.log"
    (cd "$dir" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" \
        --repos acme/repo-b --home-repo "$CT_REPO" --coord-branch "$CT_CB" "$@" 2>"$CASE/stderr")
}

ct_case home-outside-fresh
ct_record_setup github 10 "$NODESR"
ct_write_db
out=$(run_remote "$REMOTEDIR" --merge true)
expect "home outside --repos, nothing recorded" "dispatch:$RCORE" "$out"
wrote_nothing "the home-outside dispatch"

ct_case home-outside-draft
ct_record_setup github 10 "$NODESR"
ct_record_node "$RCORE" acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-b 21 "impl/t-$RCORE" 'isDraft=true'
ct_write_db
out=$(run_remote "$REMOTEDIR" --merge true)
expect "home outside --repos, a draft node PR" "evaluate:$RCORE" "$out"

ct_case home-outside-merge-node
ct_record_setup github 10 "$NODESR"
ct_record_node "$RCORE" acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-b 21 "impl/t-$RCORE"
ct_write_db
out=$(run_remote "$REMOTEDIR" --merge true)
expect "home outside --repos, a mergeable node PR" "merge:$RCORE" "$out"

# home_outside_done <case> -- both remote nodes recorded and MERGED, in a fresh
# case (the shim seeds its model once per case).
home_outside_done() {
    ct_case "$1"
    ct_record_setup github 10 "$NODESR"
    ct_record_node "$RCORE" acme/repo-b 21 "$CT_HEAD"
    ct_record_node "$RCLI" acme/repo-b 22 "$CT_HEAD"
    ct_pr acme/repo-b 21 "impl/t-$RCORE" 'state="MERGED"'
    ct_pr acme/repo-b 22 "impl/t-$RCLI" 'state="MERGED"'
}
home_outside_done home-outside-cascade
ct_write_db
out=$(run_remote "$REMOTEDIR" --merge true)
expect "home outside --repos, every node MERGED" "cascade" "$out"

home_outside_done home-outside-coordination
ct_record_cascade pushed "$CT_HEAD"
ct_write_db
out=$(run_remote "$GONEDIR" --merge true)
expect "home outside --repos, the cascade pushed, a draft" "evaluate-coordination" "$out"
wrote_nothing "the home-outside evaluate-coordination"

home_outside_done home-outside-coord-ready
ct_record_cascade pushed "$CT_HEAD"
CT_COORD_DRAFT=false
ct_write_db
out=$(run_remote "$GONEDIR" --merge true)
expect "home outside --repos, the coordination PR ready" "merge-coordination" "$out"
home_outside_done home-outside-coord-merged
CT_COORD_STATE=MERGED
ct_write_db
out=$(run_remote "$GONEDIR" --merge true)
expect "home outside --repos, the coordination PR MERGED" "done:merged" "$out"

ct_case home-outside-node-in-home
CT_RECORD_REPOS="acme/repo-a,acme/repo-b"
ct_record_setup github 10 "$NODESR"
ct_record_node "$RCORE" "$CT_REPO" 21 "$CT_HEAD"
ct_pr "$CT_REPO" 21 "impl/t-$RCORE"
ct_write_db
out=$(run_remote "$REMOTEDIR" --merge true)
expect "home outside --repos, a node recorded in the home" "error:execute:write-set" "$out"

# --- first-match order ------------------------------------------------------------

ct_case order-error-first
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/t-pr-repo-a-default
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default 'author="someone-else"'
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "an error on a later node beats a merge on an earlier one" "error:execute:pr-adopt" "$out"

ct_case order-merge-before-dispatch
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "a merge beats a dispatch" "merge:pr-repo-b-default" "$out"

ct_case order-dispatch-before-evaluate
ct_record_setup github 10 "$NODES2"
ct_record_node pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-b 21 impl/t-pr-repo-b-default 'isDraft=true'
ct_write_db
out=$(run_next "$PLAN2DIR" --merge true)
expect "a dispatch beats an evaluate" "dispatch:pr-repo-a-default" "$out"

# --- follow-ups ----------------------------------------------------------------------

FU21="$CT_CORE/follow-up-21"

# A follow-up waits on its node: with the node open and mergeable, the node
# merges first.
ct_case fu-node-open
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_follow_up_pr "$CT_REPO" 21
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a follow-up whose node is open: the node merges first" "merge:$CT_CORE" "$out"

# One recorded against a node GitHub reports MERGED merges next, before the
# next node's dispatch, and only with --merge.
ct_case fu-mergeable
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_follow_up_pr "$CT_REPO" 21
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a follow-up whose node is MERGED, --merge true" "merge:$FU21" "$out"
wrote_nothing "the follow-up merge case"

both_merged fu-no-merge
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 21
ct_write_db
out=$(run_next "$PLANDIR" --merge false)
expect "every node MERGED, an open follow-up, --merge false: no cascade" "done:ready-awaiting-merge" "$out"
out=$(run_next "$PLANDIR" --merge true)
expect "the same with --merge true, the PLAN present: the follow-up, never the cascade" "merge:$FU21" "$out"
ct_record_cascade pushed "$CT_HEAD"
out=$(run_next "$GONEDIR" --merge true)
expect "the PLAN gone and the cascade pushed: the follow-up, before any coordination step" "merge:$FU21" "$out"
out=$(run_next "$GONEDIR" --merge false)
expect "the same with --merge false: no evaluate-coordination" "done:ready-awaiting-merge" "$out"
out=$(run_next "$GONEDIR" --merge true --attempts "$FU21:merge-refused")
expect "--attempts with a follow-up id: a refused follow-up merge is not printed again" "done:ready-awaiting-merge" "$out"
out=$(cd "$PLANDIR" && bash "$NEXT" --session "$S" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" --repos "$CT_REPO" \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --merge true --attempts "$CT_CORE/follow-up-0:merge-refused" 2>/dev/null); rc=$?
[ "$rc" -eq 64 ] && [ -z "$out" ] && pass "--attempts with follow-up-0 is a usage error" || fail "follow-up-0 attempts: rc=$rc out=[$out]"

both_merged fu-merged
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 21 'state="MERGED"'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "every node and the follow-up MERGED, the PLAN present" "cascade" "$out"
ct_record_cascade pushed "$CT_HEAD"
out=$(run_next "$GONEDIR" --merge true)
expect "the same, the cascade pushed" "evaluate-coordination" "$out"

both_merged fu-pending
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 21 'checks=[{"name":"build","bucket":"pending"}]'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a follow-up whose checks are pending: a wait" "evaluate:$FU21" "$out"

both_merged fu-draft
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 21 'isDraft=true'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a draft follow-up waits on a human, never error:execute:ready" "done:ready-awaiting-merge" "$out"

both_merged fu-closed
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 21 'state="CLOSED"'
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a follow-up closed unmerged holds the cascade, never error:execute:pr-closed" "done:ready-awaiting-merge" "$out"
ct_record_cascade pushed "$CT_HEAD"
out=$(run_next "$GONEDIR" --merge true)
expect "the same with the cascade pushed: no coordination step" "done:ready-awaiting-merge" "$out"
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21 "$CT_HEAD" true
out=$(run_next "$GONEDIR" --merge true)
expect "the closed follow-up removed: the coordination step runs" "evaluate-coordination" "$out"
: > "$GH_CALL_LOG"
out=$(run_next "$GONEDIR" --merge true)
ct_calls | grep -q "pr view 21 " && fail "a removed follow-up was read" || pass "a removed follow-up is not read"

# A replacement recorded and the closed one removed: the run holds while the
# replacement is open and passes once it merges.
both_merged fu-replaced
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21 "$CT_HEAD" true
ct_record_follow_up "$CT_CORE" "$CT_REPO" 22
ct_follow_up_pr "$CT_REPO" 21 'state="CLOSED"'
ct_follow_up_pr "$CT_REPO" 22
ct_write_db
out=$(run_next "$PLANDIR" --merge false)
expect "the replacement open, --merge false" "done:ready-awaiting-merge" "$out"
out=$(run_next "$PLANDIR" --merge true)
expect "the replacement open, --merge true" "merge:$CT_CORE/follow-up-22" "$out"
jq '(.prs[] | select(.number == 22) | .state) = "MERGED"' "$CASE/scenario/gh/db.json" > "$CASE/db" \
    && mv "$CASE/db" "$CASE/scenario/gh/db.json"
rm -rf "$GH_CALL_LOG.d"
out=$(run_next "$PLANDIR" --merge true)
expect "the replacement MERGED" "cascade" "$out"

ct_case fu-write-set
CT_RECORD_REPOS="acme/repo-a,acme/repo-b"
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_record_follow_up "$CT_CORE" acme/repo-b 21
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_follow_up_pr acme/repo-b 21
ct_write_db
out=$(run_next "$PLANDIR" --merge true)
expect "a follow-up in another repository than its node's" "error:execute:write-set" "$out"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
