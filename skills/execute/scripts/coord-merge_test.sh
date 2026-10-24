#!/usr/bin/env bash
# coord-merge_test.sh — a coordinated PR merges only through merge-exec.sh, at
# the head the run record holds, and a merge that didn't land is recorded
# Part of the execute skill
#
# Each case runs coord-merge.sh against the eval gh shim's repository model,
# the koto stub, and a shirabe stub (see coord-test-helpers.sh), with the real
# merge-exec.sh and merge-verdict.sh behind it, and a run record seeded
# through the test helper.
#
# Cases:
#   a mergeable node                     one pr merge with --match-head-commit
#     <the recorded head>, no --admin or --auto; the confirm read prints
#     merged; nothing recorded
#   the body's head= edited              the merge still passes the recorded
#     head to --match-head-commit
#   a merge accepted but still OPEN      not-merged:merge-not-observed;
#     merge_attempts records <node>:merge-not-observed
#   a merge call that fails              merge-refused:not-merged:merge-call-failed,
#     recorded; exactly one pr merge
#   no run/node key for the node         exit 73 before any merge call
#   a recorded head the PR no longer has merge-refused:awaiting:head-moved,
#     no pr merge
#   a recorded PR by another author      exit 73, no pr merge
#   the coordination PR                  pinned to run/cascade's head; the
#     merge-last gate runs first, over every indexed PR but the coordination
#     PR itself; a gate that doesn't pass refuses the merge; no pushed
#     cascade (absent or failed) is refused head-moved with no merge; with
#     a hook putting back a body with no index line before every gh call,
#     the gate still runs over the index the render just posted, and the
#     merge lands
#   the coordination PR's own visibility, read live: a public home's gate
#     runs without --visibility, a private home's with --visibility private,
#     and a failed read exits 72 with no gate call and no merge
#   merge_attempts keeps one entry per node
#   the squash message                   every pr merge (node, coordination)
#     carries --subject <title> and --body-file holding Part 1; the
#     coordination message holds no index, merge order, run lines or
#     marker; a rebase-only repository's merge carries neither; an empty
#     Part 1, a title spanning lines, or an attribution line is
#     merge-refused:squash-message with no pr merge, recorded merge-refused;
#     the message file is removed after the merge
#   every refusal recorded               the merge-last gate, a missing
#     head, and merge-exec.sh's own refusal record <node>:merge-refused
#   the body around a merge              a node merge posts the body (the
#     node observed merged); a render that can't post before the
#     coordination merge is merge-refused:body-stale (an oversize body
#     merge-refused:body-full), recorded, with no pr merge; the
#     coordination merge posts nothing after it lands
#   follow-ups                           --node <node>/follow-up-<n> with its
#     node MERGED merges at the recorded head with --subject and --body-file
#     and records its merged head; with the node open it is
#     merge-refused:predecessor-unmerged, recorded under the full id; one a
#     person already merged prints merged, then the render's observed= and
#     body=posted lines, with no merge call; another
#     author is merge-refused:follow-up-author; a moved head is
#     merge-refused:awaiting:head-moved; a removed or absent one exits 73; the
#     coordination merge's gate carries both follow-ups; follow-up-x is a
#     usage error
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
    mkdir -p "$CASE/ctx/$S" "$CASE/tmp"
    OUT=$(TMPDIR="$CASE/tmp" bash "$MERGE" --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" --node "$1" 2>"$CASE/stderr")
    RC=$?
}
# A hook that keeps the message each pr merge carries: the --body-file's
# contents, copied before the shim runs.
cat > "$CT_WORK/keep-message.sh" <<'HOOK'
[ "$1 $2" = "pr merge" ] || exit 0
prev=""
for a in "$@"; do
    if [ "$prev" = --body-file ]; then cp "$a" "$KOTO_STORE/merge-message.txt"; fi
    prev="$a"
done
exit 0
HOOK
merges() { ct_calls | grep -c '^pr merge'; }
attempts() { cat "$CASE/ctx/$S/merge_attempts" 2>/dev/null; }

node_case() { # node_case <name> [pr key=json ...]
    local name="$1"
    shift
    ct_case "$name"
    ct_record_setup
    ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
    ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" "$@"
    ct_write_db
}

# --- a mergeable node -------------------------------------------------------------

node_case mergeable
run_merge "$CT_CORE"
MLINE=$(ct_calls | grep '^pr merge')
MSHA=$(printf 'merge %s#%s' "$CT_REPO" 11 | git hash-object --stdin)
if [ "$RC" -eq 0 ] && [ "$OUT" = "merge-called:squash:$CT_HEAD
merged
observed=$CT_CORE:$MSHA
body=posted" ]; then
    pass "a mergeable node: merge-called, a confirm read of merged, then the body records and shows the merge"
else
    fail "mergeable: rc=$RC out=[$OUT]"; tail -3 "$CASE/stderr"
fi
case "$MLINE" in
    "pr merge 11 --repo $CT_REPO --squash --match-head-commit $CT_HEAD --subject feat(t): impl/t-$CT_CORE --body-file "*)
        [ "$(merges)" -eq 1 ] && pass "exactly one pr merge, at the recorded head, with --subject <title> and --body-file" \
            || fail "merges: $(merges)" ;;
    *) fail "the merge calls: [$MLINE]" ;;
esac
[ "$(ct_calls | grep -c '^pr edit 10 ')" = 1 ] && [ "$(cat "$CASE/ctx/$S/run/node/$CT_CORE" | jq -r .merged_head)" = "$MSHA" ] \
    && pass "a node observed merged posts the body, its merged head recorded first" \
    || fail "the post after a node merge: $(ct_calls | grep -c '^pr edit 10 ') edits"
if [ -z "$(find "$CASE/tmp" -name 'merge-message*' -print)" ]; then
    pass "the message file is removed after the merge"
else
    fail "a message file was left: $(find "$CASE/tmp" -name 'merge-message*' -print)"
fi
if grep -Eq -- '--admin|--auto' <<<"$MLINE"; then fail "the merge carries --admin or --auto"; else pass "no --admin or --auto"; fi
[ -z "$(attempts)" ] && pass "a landed merge records no attempt" || fail "recorded [$(attempts)]"

# --- the body's head= edited -----------------------------------------------------------

ct_case body-head-edited
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_OTHER"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
run_merge "$CT_CORE"
MLINE=$(ct_calls | grep '^pr merge')
if [ "$RC" -eq 0 ] && [ "${MLINE%% --subject *}" = "pr merge 11 --repo $CT_REPO --squash --match-head-commit $CT_HEAD" ]; then
    pass "with the body's head= edited, the merge passes the recorded head to --match-head-commit"
else
    fail "body-head-edited: rc=$RC merge=[$MLINE] out=[$OUT]"
fi

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

ct_case no-record
ct_record_setup
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
run_merge "$CT_CORE"
if [ "$RC" -eq 73 ] && [ "$(merges)" -eq 0 ]; then
    pass "a node with no run/node key exits 73 before any merge call (a body line is not a record)"
else
    fail "no-record: rc=$RC out=[$OUT] merges=$(merges)"
fi

ct_case head-moved
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_OTHER"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
run_merge "$CT_CORE"
if [ "$OUT" = "merge-refused:awaiting:head-moved" ] && [ "$(merges)" -eq 0 ] && [ "$(attempts)" = "$CT_CORE:merge-refused" ]; then
    pass "a live head that differs from the recorded one: awaiting:head-moved, no pr merge, recorded merge-refused"
else
    fail "head-moved: out=[$OUT] merges=$(merges) attempts=[$(attempts)]"
fi

# --- the squash message -----------------------------------------------------------------

msg_refused() { # msg_refused <label> <pr key=json>
    node_case "msg-$1" "$2"
    run_merge "$CT_CORE"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "merge-refused:squash-message" ] && [ "$(merges)" -eq 0 ] \
        && [ "$(attempts)" = "$CT_CORE:merge-refused" ]; then
        pass "$1: merge-refused:squash-message, no pr merge, recorded merge-refused"
    else
        fail "$1: rc=$RC out=[$OUT] merges=$(merges) attempts=[$(attempts)]"
    fi
}
msg_refused "an empty Part 1" 'body="---\n\nonly reviewer context\n"'
msg_refused "a title spanning lines" 'title="feat(t): a\nb"'
msg_refused "an AI attribution line" 'body="Implements it.\n\nCo-Authored-By: someone <x@example.com>\n\n---\n\nfields\n"'

node_case msg-content 'body="Implements the **parser**.\n\n---\n\nReviewer context the commit must not carry.\n"'
CT_GH_HOOK="$CT_WORK/keep-message.sh" run_merge "$CT_CORE"
if [ "$(cat "$CASE/merge-message.txt" 2>/dev/null)" = "Implements the parser." ]; then
    pass "the message's body is Part 1 as plain text, and nothing below the ---"
else
    fail "the node's message body: [$(cat "$CASE/merge-message.txt" 2>/dev/null)]"
fi

node_case rebase-only
jq '.repos["acme/repo-a"] |= (.allow_squash_merge = false | .allow_merge_commit = false)' "$CASE/scenario/gh/db.json" > "$CASE/db" \
    && mv "$CASE/db" "$CASE/scenario/gh/db.json"
run_merge "$CT_CORE"
MLINE=$(ct_calls | grep '^pr merge')
if [ "$MLINE" = "pr merge 11 --repo $CT_REPO --rebase --match-head-commit $CT_HEAD" ]; then
    pass "a rebase-only repository's merge carries no --subject or --body-file"
else
    fail "rebase-only: [$MLINE] out=[$OUT]"
fi

# --- ownership ------------------------------------------------------------------------

node_case foreign 'author="someone-else"'
run_merge "$CT_CORE"
if [ "$RC" -eq 73 ] && [ "$(merges)" -eq 0 ] && [ -z "$OUT" ]; then
    pass "a recorded PR by another author exits 73 with no pr merge"
else
    fail "foreign: rc=$RC out=[$OUT] merges=$(merges)"
fi

# --- the coordination PR -------------------------------------------------------------

# coord_case <name> [home visibility] [cascade: pushed|failed|none] -- both
# nodes merged and recorded, the cascade pushed at CT_HEAD unless told
# otherwise. The body still carries the index the merge-last gate reads.
coord_case() {
    ct_case "$1"
    CT_VIS_A="${2:-public}"
    ct_record_setup
    ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
    ct_record_node "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
    case "${3:-pushed}" in
        pushed) ct_record_cascade pushed "$CT_HEAD" ;;
        failed) ct_record_cascade failed execute:cascade ;;
    esac
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

MLINE=$(ct_calls | grep '^pr merge')
case "$MLINE" in
    "pr merge 10 --repo $CT_REPO --squash --match-head-commit $CT_HEAD --subject docs: t --body-file "*)
        pass "the coordination merge is pinned to run/cascade's pushed head, with --subject <title> and --body-file" ;;
    *) fail "coordination merge call: [$MLINE]" ;;
esac
if [ "$(ct_calls | grep -c '^pr edit 10 ')" = 1 ] && ! grep -q '^body=' <<<"$OUT"; then
    pass "the coordination PR's body is rendered once before its merge, and nothing is posted after it"
else
    fail "posts around the coordination merge: $(ct_calls | grep -c '^pr edit 10 ') edits, out=[$OUT]"
fi
FIRST_EDIT=$(awk '/^pr edit 10 / && !n { n = NR } END { print n }' "$GH_CALL_LOG")
FIRST_MERGE=$(awk '/^pr merge 10 / && !n { n = NR } END { print n }' "$GH_CALL_LOG")
[ -n "$FIRST_EDIT" ] && [ -n "$FIRST_MERGE" ] && [ "$FIRST_EDIT" -lt "$FIRST_MERGE" ] \
    && pass "the fresh render comes before the coordination merge" || fail "edit at [$FIRST_EDIT], merge at [$FIRST_MERGE]"

coord_case coord-message
CT_GH_HOOK="$CT_WORK/keep-message.sh" run_merge coordination
M=$(cat "$CASE/merge-message.txt" 2>/dev/null)
if [ -n "$M" ] && ! grep -qi -e 'PR Index' -e 'merge-order' -e 'topic=' -e 'run=' -e 'store=' -e 'coordination PR\*\*' -e 'head=' <<<"$M"; then
    pass "the coordination message is Part 1 only: no index, merge order, run lines or marker"
else
    fail "the coordination message: [$M]"
fi

coord_case coord-render-fails
GH_SHIM_FAIL='^pr edit 10 ' run_merge coordination
if [ "$RC" -eq 0 ] && [ "$OUT" = "merge-refused:body-stale" ] && [ "$(merges)" -eq 0 ] \
    && [ "$(attempts)" = "coordination:body-stale" ]; then
    pass "a render the stub fails before the coordination merge: no merge call, merge-refused:body-stale, recorded"
else
    fail "coord-render-fails: rc=$RC out=[$OUT] merges=$(merges) attempts=[$(attempts)]"
fi

coord_case coord-body-full
awk 'BEGIN { s = ""; while (length(s) < 60000) s = s "x"; printf "%s\n\n---\n", s }' > "$CASE/big.md"
jq --rawfile b "$CASE/big.md" '(.prs[] | select(.number == 10) | .body) = $b' "$CASE/scenario/gh/db.json" > "$CASE/db" \
    && mv "$CASE/db" "$CASE/scenario/gh/db.json"
run_merge coordination
if [ "$OUT" = "merge-refused:body-full" ] && [ "$(merges)" -eq 0 ] && [ "$(attempts)" = "coordination:body-full" ]; then
    pass "an oversize coordination body: merge-refused:body-full, recorded, no merge call"
else
    fail "coord-body-full: out=[$OUT] merges=$(merges) attempts=[$(attempts)]"
fi

coord_case coord-head-moved public pushed
jq --arg o "$CT_OTHER" '(.prs[] | select(.number == 10) | .headRefOid) = $o' "$CASE/scenario/gh/db.json" > "$CASE/db" \
    && mv "$CASE/db" "$CASE/scenario/gh/db.json"
run_merge coordination
[ "$OUT" = "merge-refused:awaiting:head-moved" ] && [ "$(merges)" -eq 0 ] \
    && pass "a coordination PR moved off run/cascade's head is refused with no merge call" \
    || fail "coord head moved: out=[$OUT] merges=$(merges)"

for v in none failed; do
    coord_case "coord-cascade-$v" public "$v"
    run_merge coordination
    if [ "$OUT" = "merge-refused:awaiting:head-moved" ] && [ "$(merges)" -eq 0 ] && [ "$(attempts)" = "coordination:merge-refused" ]; then
        pass "no pushed cascade ($v): the coordination merge is refused head-moved, no merge call, recorded merge-refused"
    else
        fail "cascade $v: out=[$OUT] merges=$(merges) attempts=[$(attempts)]"
    fi
done

coord_case coord-gate-fails
export CT_GATE_FAIL=1
run_merge coordination
unset CT_GATE_FAIL
if [ "$OUT" = "merge-refused:merge-gate" ] && [ "$(merges)" -eq 0 ] && [ "$(attempts)" = "coordination:merge-refused" ]; then
    pass "a merge gate that doesn't pass refuses the coordination merge, recorded merge-refused"
else
    fail "gate fails: out=[$OUT] merges=$(merges) attempts=[$(attempts)]"
fi

# The gate takes the coordination PR's own visibility, read live.
coord_case coord-public-home
run_merge coordination
GATE=$(grep -- '--merge-gate' "$CASE/shirabe-calls.log")
case "$GATE" in
    *--visibility*) fail "a public home's gate carried --visibility: [$GATE]" ;;
    *) pass "a public home's merge gate runs without --visibility (public, the strict default)" ;;
esac
coord_case coord-private-home private
run_merge coordination
GATE=$(grep -- '--merge-gate' "$CASE/shirabe-calls.log")
case "$GATE" in
    *"--visibility private"*"--pr acme/repo-a:docs/plans/PLAN-t.md#11"*) pass "a private home's merge gate runs with --visibility private" ;;
    *) fail "a private home's gate call: [$GATE]" ;;
esac
if [ "$OUT" = "merge-called:squash:$CT_HEAD
merged" ] && [ "$(merges)" -eq 1 ]; then
    pass "a private home's coordination PR merges once its gate passes"
else
    fail "private home: out=[$OUT]"; tail -3 "$CASE/stderr"
fi
coord_case coord-home-unread none
run_merge coordination
RC_UNREAD=$RC
if [ "$RC_UNREAD" -eq 72 ] && [ "$(merges)" -eq 0 ] && ! grep -q -- '--merge-gate' "$CASE/shirabe-calls.log"; then
    pass "a failed read of the home's visibility exits 72: no gate, no merge"
else
    fail "home unread: rc=$RC_UNREAD merges=$(merges) shirabe=[$(cat "$CASE/shirabe-calls.log")]"
fi

# Under the run's recorded switch omit the body is Part 1 alone and indexes
# nothing: the gate's refs come from the run record's node PRs.
CT_CONTENT=omit coord_case coord-omit
printf 'Plans the parser and its CLI.\n' > "$CASE/plain.md"
ct_write_db "$CASE/plain.md"
run_merge coordination
GATE=$(grep -- '--merge-gate' "$CASE/shirabe-calls.log")
BODY_NOW=$(jq -j '.prs[] | select(.number == 10) | .body' "$GH_CALL_LOG.d/db.json")
case "$OUT:$GATE" in
    *merged:*"--mode=ready"*"--pr acme/repo-a:docs/plans/PLAN-t.md#11"*"--pr acme/repo-a:docs/plans/PLAN-t.md#12"*)
        if [ "$BODY_NOW" = "Plans the parser and its CLI." ]; then
            pass "omit: the coordination PR merges with its gate over the record's node PRs, its body Part 1 alone"
        else
            fail "omit: the coordination body changed: [$BODY_NOW]"
        fi
        ;;
    *) fail "omit coordination merge: out=[$OUT] gate=[$GATE]"; tail -3 "$CASE/stderr" ;;
esac

# --- follow-ups ----------------------------------------------------------------------------

FU21="$CT_CORE/follow-up-21"
# fu_case <name> <node-state> [follow-up key=json ...] -- core's #11 recorded
# in <node-state>, and follow-up #21 recorded against it at CT_HEAD.
fu_case() {
    local name="$1" st="$2"
    shift 2
    ct_case "$name"
    ct_record_setup
    ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
    ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
    ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" "state=\"$st\""
    ct_follow_up_pr "$CT_REPO" 21 "$@"
    ct_write_db
}

fu_case fu-merge MERGED
run_merge "$FU21"
MLINE=$(ct_calls | grep '^pr merge')
FSHA=$(printf 'merge %s#%s' "$CT_REPO" 21 | git hash-object --stdin)
# The render also records the node's own merge, which no render had seen yet.
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | sed -n '1,2p')" = "merge-called:squash:$CT_HEAD
merged" ] && grep -qx "observed=$FU21:$FSHA" <<<"$OUT" && [ "$(printf '%s\n' "$OUT" | tail -1)" = body=posted ]; then
    pass "a follow-up whose node is MERGED: merged at the recorded head, then the body records it"
else
    fail "fu-merge: rc=$RC out=[$OUT]"; tail -3 "$CASE/stderr"
fi
case "$MLINE" in
    "pr merge 21 --repo $CT_REPO --squash --match-head-commit $CT_HEAD --subject fix(t): follow-up 21 --body-file "*)
        [ "$(merges)" -eq 1 ] && pass "one pr merge of the follow-up, with --match-head-commit, --subject and --body-file" \
            || fail "merges: $(merges)" ;;
    *) fail "the follow-up's merge call: [$MLINE]" ;;
esac
[ "$(jq -r .merged_head "$CASE/ctx/$S/run/follow-up/$CT_CORE/21")" = "$FSHA" ] \
    && pass "the follow-up's merge commit is recorded as its merged_head" || fail "follow-up record after merge"

# A follow-up a person already merged: no merge call, and the body records
# its merged head as after a merge the run confirmed.
FU_DONE_SHA=5555555555555555555555555555555555555555
fu_case fu-already-merged MERGED 'state="MERGED"' "merge_sha=\"$FU_DONE_SHA\""
run_merge "$FU21"
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | sed -n 1p)" = merged ] \
    && grep -qx "observed=$FU21:$FU_DONE_SHA" <<<"$OUT" && [ "$(printf '%s\n' "$OUT" | tail -1)" = body=posted ] \
    && [ "$(merges)" -eq 0 ] && [ "$(ct_calls | grep -c '^pr edit 10 ')" -eq 1 ]; then
    pass "a follow-up already MERGED prints merged, then the render's observed= and body=posted, with no merge call and one post"
else
    fail "fu-already-merged: rc=$RC out=[$OUT] merges=$(merges) edits=$(ct_calls | grep -c '^pr edit 10 ')"
fi
[ "$(jq -r .merged_head "$CASE/ctx/$S/run/follow-up/$CT_CORE/21")" = "$FU_DONE_SHA" ] \
    && pass "a follow-up already MERGED has its merge commit recorded as its merged_head" \
    || fail "fu-already-merged record: [$(cat "$CASE/ctx/$S/run/follow-up/$CT_CORE/21")]"

fu_case fu-node-open OPEN
run_merge "$FU21"
[ "$RC" -eq 0 ] && [ "$OUT" = "merge-refused:predecessor-unmerged" ] && [ "$(merges)" -eq 0 ] \
    && [ "$(attempts)" = "$FU21:merge-refused" ] \
    && pass "a follow-up whose node is open is refused predecessor-unmerged, recorded under its full id" \
    || fail "fu-node-open: rc=$RC out=[$OUT] attempts=[$(attempts)]"

fu_case fu-author MERGED 'author="someone-else"'
run_merge "$FU21"
[ "$OUT" = "merge-refused:follow-up-author" ] && [ "$(merges)" -eq 0 ] && [ "$(attempts)" = "$FU21:merge-refused" ] \
    && pass "a follow-up another author opened is refused at merge time" || fail "fu-author: rc=$RC out=[$OUT]"

fu_case fu-head-moved MERGED "headRefOid=\"$CT_OTHER\""
run_merge "$FU21"
[ "$OUT" = "merge-refused:awaiting:head-moved" ] && [ "$(merges)" -eq 0 ] \
    && pass "a follow-up whose live head moved off the recorded one: awaiting:head-moved, no merge" \
    || fail "fu-head-moved: out=[$OUT] merges=$(merges)"

fu_case fu-removed MERGED
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21 "$CT_HEAD" true
run_merge "$FU21"
[ "$RC" -eq 73 ] && [ "$(merges)" -eq 0 ] && pass "a removed follow-up exits 73" || fail "fu-removed: rc=$RC"
run_merge "$CT_CORE/follow-up-22"
[ "$RC" -eq 73 ] && [ "$(merges)" -eq 0 ] && pass "a follow-up never recorded exits 73" || fail "fu-absent: rc=$RC"

# The coordination merge's gate counts every live follow-up's line.
coord_case coord-follow-ups
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_record_follow_up "$CT_CORE" "$CT_REPO" 22
ct_follow_up_pr "$CT_REPO" 21 'state="MERGED"'
ct_follow_up_pr "$CT_REPO" 22 'state="MERGED"'
ct_write_db
run_merge coordination
GATE=$(grep -- '--merge-gate' "$CASE/shirabe-calls.log")
if grep -q -- "--pr acme/repo-a:docs/plans/PLAN-t.md#21" <<<"$GATE" && grep -q -- "--pr acme/repo-a:docs/plans/PLAN-t.md#22" <<<"$GATE" \
    && grep -q -- "--pr acme/repo-a:docs/plans/PLAN-t.md#11" <<<"$GATE"; then
    pass "the coordination merge's gate carries both follow-ups beside the nodes"
else
    fail "the gate with follow-ups: [$GATE] out=[$OUT]"
fi

# The gate reads the body this run just rendered, never a re-read: a hook
# puts back a body with no index line before every gh call, so any read of
# the live body after the post sees none, and the gate still runs over the
# rendered index and the merge lands.
coord_case coord-no-index
printf 'Coordination pull request for t.\n\n---\n\n> This is a **coordination PR** for a coordinated effort.\n' > "$CASE/fixed-body.md"
cat > "$CASE/reset-body.sh" <<'HOOK'
db="$GH_CALL_LOG.d/db.json"
[ -f "$db" ] || exit 0
jq --rawfile b "$KOTO_STORE/fixed-body.md" '(.prs[] | select(.number == 10) | .body) = $b' "$db" > "$db.reset" \
    && mv "$db.reset" "$db"
HOOK
CT_GH_HOOK="$CASE/reset-body.sh" run_merge coordination
GATE=$(grep -- '--merge-gate' "$CASE/shirabe-calls.log")
WANT_REFS=$(ct_calls | grep -c '^pr edit 10 ')
if [ "$OUT" = "merge-called:squash:$CT_HEAD
merged" ] && [ "$(merges)" -eq 1 ] && [ "$WANT_REFS" -eq 1 ]; then
    pass "a live body with no index line after the post: the coordination PR still merges"
else
    fail "coord-no-index: out=[$OUT] merges=$(merges) edits=$WANT_REFS"; tail -3 "$CASE/stderr"
fi
case "$GATE" in
    *"--mode=ready --pr acme/repo-a:docs/plans/PLAN-t.md#11 --pr acme/repo-a:docs/plans/PLAN-t.md#12")
        pass "the merge gate's refs are the rendered index's, not a re-read's" ;;
    *) fail "the gate over the rendered index: [$GATE]" ;;
esac

# --- usage ------------------------------------------------------------------------------

ct_case usage
ct_write_db
for args in "--session $S --slug t --home-repo $CT_REPO --coord-branch $CT_CB" \
            "--session $S --slug t --home-repo $CT_REPO --coord-branch $CT_CB --node Bad" \
            "--session $S --slug t --home-repo $CT_REPO --coord-branch $CT_CB --node core/follow-up-x" \
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
