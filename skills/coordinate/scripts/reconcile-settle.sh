#!/usr/bin/env bash
# reconcile-settle.sh -- reconcile's settling writes: a holding left at
# `dispatching` whose worker is live becomes `dispatched`, and (--successor)
# a pending Run `successor` row is settled against niwa's listing.
#
# dispatch-worker.sh writes a holding `dispatching` before it launches the
# worker and rewrites it `dispatched` after. When that second write is
# refused, or the coordinator stops between the two, the row stays
# `dispatching` with a live worker behind it, and dispatch_check refuses a
# second dispatch of the topic as duplicate-topic, so no dispatch can settle
# it. The pass settles it instead, once its own reads show the worker's
# session in the listing and, for a holding that reports on a leg, that leg
# bound to it (or already resolved). reconcile-pass.sh launches this only on
# those facts, and only when its whole budget fits in the pass, so a write
# isn't stopped partway by the pass's own clock. This script re-reads the row
# first and writes only when it is still the row the pass read.
#
# It takes no dispatch lock. A dispatch-worker.sh run confirming the same
# topic at the same moment writes the same row with the same status, and
# state-holding.sh refuses whichever write lands on a record changed since
# its read (exit 12), which this script reports as not verified for the next
# pass to read again.
#
# Usage:
#   reconcile-settle.sh --session S --topic T --return-path RP
#   reconcile-settle.sh --successor --session S
#
# RP is the row's Return path as the pass read it (`message` or
# `leg <request>:<leg>`). The row is rewritten through state-holding.sh,
# which checks provenance, directed transitions and the target before it
# writes.
#
# Output: one JSON fact on stdout, exit 0, like every re-check:
#   {kind: "settle", status: "ok", settled: true|false, now, reason, read_at}
#   {kind: "settle", status: "not_verified", reason, read_at}
# settled is true when this call wrote the row. now is the row's dispatch
# status after the call (empty when no row names the topic): `dispatched`
# either way once the row is settled, including by an earlier pass whose
# report was never sealed, so the report can say the row changed. settled is
# false, with the reason, when the row is gone or no longer the one the pass
# read (another status, another return path). Exit 64 on usage.
#
# --successor settles the run's Run `successor` row, which reconcile-pass.sh
# plans only when the record read finds it `dispatching` or `dispatched`. It
# takes the run's successor lock, `.niwa/dispatch-briefs/.successor.<S>.lock`
# under the workspace root (dispatch-common.sh dc_workspace_root), with the
# same noclobber create dispatch-worker.sh --successor uses, so a settle and
# a successor dispatch of the run never run at once. A held lock is never
# taken over, whoever holds it: the settle writes nothing and the next pass
# reads again. Under the lock it runs dc_successor_settle, the dispatch's own
# rule: a listed `dispatching` row becomes `dispatched`, an unlisted
# `dispatched` row becomes `stranded` only after a listing that was read,
# and every other row stays. The lock it made is removed when it ends.
#
# Its output is one JSON fact on stdout, exit 0:
#   {kind: "successor", status: "ok"|"not_verified", before, now, settled,
#    session, listing, reason, read_at}
# before is the row's value as read under the lock (empty for no row, or
# when the lock or the row couldn't be had), now its value afterwards,
# settled true when this call wrote it, session the listed session's name
# (empty when none is listed or the listing wasn't read), and listing what
# the listing showed: `listed`, `unlisted`, `unread` (it couldn't be read)
# or empty (not read: the row wasn't pending, or the lock or the row
# couldn't be had), so the report can say what a refused write left
# pending without mistaking it for an unread listing. A held lock, an unreadable
# listing, an unreadable row and a write the record refuses are each
# not_verified, with the reason and no write. Exit 64 on usage.
#
# Requires: bash 3.2+, jq, gh, koto.
set -uo pipefail

PROG=reconcile-settle
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

usage() { echo "$PROG: usage: $PROG --session S --topic T --return-path RP | --successor --session S" >&2; exit 64; }
SESSION="" TOPIC="" RP="" SUCCESSOR=0
while [ $# -gt 0 ]; do
    if [ "$1" = --successor ]; then SUCCESSOR=1; shift; continue; fi
    [ $# -ge 2 ] || usage
    case "$1" in
        --session) SESSION=$2 ;;
        --topic) TOPIC=$2 ;;
        --return-path) RP=$2 ;;
        *) usage ;;
    esac
    shift 2
done
if [ "$SUCCESSOR" = 1 ]; then
    [ -n "$SESSION" ] && [ -z "$TOPIC$RP" ] || usage
    succ_fact() { # succ_fact <status> <before> <now> <settled> <session> <listing> <reason>
        jq -nc --arg st "$1" --arg b "$2" --arg n "$3" --argjson s "$4" --arg ss "$5" --arg l "$6" --arg r "$7" --arg t "$(rd_now)" \
            '{kind: "successor", status: $st, before: $b, now: $n, settled: $s, session: $ss, listing: $l, reason: $r, read_at: $t}'
        exit 0
    }
    # shellcheck source=dispatch-common.sh
    . "$HERE/dispatch-common.sh" || succ_fact not_verified "" "" false "" "" "dispatch-common.sh could not be loaded"
    ROOT=$(dc_workspace_root) || succ_fact not_verified "" "" false "" "" "no workspace root found from $(pwd)"
    LOCK="$ROOT/.niwa/dispatch-briefs/.successor.$SESSION.lock"
    mkdir -p "$ROOT/.niwa/dispatch-briefs" 2>/dev/null
    # The lock dispatch-worker.sh --successor takes; one held is left as it is.
    (set -C && printf '%s\n' "$$" >"$LOCK") 2>/dev/null ||
        succ_fact not_verified "" "" false "" "" "another process holds the run's successor lock ($LOCK); nothing written"
    trap 'rm -f "$LOCK"' EXIT
    succ_row() {
        local st
        st=$(bash "$DC_RECORD_STATE" --list --session "$SESSION" 2>/dev/null) || return 2
        printf '%s' "$st" | jq -r '[(.run // [])[] | select(.key == "successor") | .value][0] // "" | strings' || return 2
    }
    BEFORE=$(succ_row) || succ_fact not_verified "" "" false "" "" "the Run successor row could not be read; nothing written"
    OUT=$(dc_successor_settle "$SESSION" "$ROOT" 2>/dev/null)
    RC=$?
    NOW=${OUT%%	*}
    NAME=${OUT#*	}
    [ "$NAME" != "$OUT" ] || NAME=""
    case "${BEFORE%% *}" in
        dispatching | dispatched) if [ -n "$NAME" ]; then LISTING=listed; else LISTING=unlisted; fi ;;
        *) LISTING="" ;;
    esac
    case "$RC" in
        0)
            SETTLED=false
            [ "$NOW" = "$BEFORE" ] || SETTLED=true
            succ_fact ok "$BEFORE" "$NOW" "$SETTLED" "$NAME" "$LISTING" "" ;;
        3) succ_fact not_verified "$BEFORE" "$BEFORE" false "" unread "the listing couldn't be read (niwa list); nothing written" ;;
        2) succ_fact not_verified "$BEFORE" "$BEFORE" false "" "" "the Run successor row could not be read; nothing written" ;;
        *) succ_fact not_verified "$BEFORE" "$BEFORE" false "$NAME" "$LISTING" "the record refused settling the successor row (exit $RC)" ;;
    esac
fi
[ -n "$SESSION" ] && [ -n "$TOPIC" ] && [ -n "$RP" ] || usage

HOLDING="$HERE/state-holding.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-settle.XXXXXX") || { rd_not_verified settle "no temp directory"; exit 0; }
trap 'rm -rf "$T"' EXIT

fact() { # fact <settled> <now> <reason>
    jq -nc --argjson s "$1" --arg n "$2" --arg r "$3" --arg t "$(rd_now)" \
        '{kind: "settle", status: "ok", settled: $s, now: $n, reason: $r, read_at: $t}'
    exit 0
}

bash "$HOLDING" --session "$SESSION" --topic "$TOPIC" --read > "$T/row.json" 2>/dev/null
case $? in
    0) ;;
    1) fact false "" "no holding names $TOPIC now" ;;
    *) rd_not_verified settle "the holding could not be read"; exit 0 ;;
esac
ST=$(jq -r '.dispatch_status // "" | strings' "$T/row.json")
[ "$ST" = dispatching ] || fact false "$ST" "the holding is ${ST:-without a status} now"
[ "$(jq -r '.return_path // "" | strings' "$T/row.json")" = "$RP" ] || fact false "$ST" "the holding's return path changed since the pass read it"
jq -c '.dispatch_status = "dispatched"' "$T/row.json" > "$T/new.json" || { rd_not_verified settle "the row could not be rewritten"; exit 0; }
bash "$HOLDING" --session "$SESSION" --topic "$TOPIC" --row-file "$T/new.json" >/dev/null 2>"$T/err"
rc=$?
case $rc in
    0) fact true dispatched "" ;;
    12) rd_not_verified settle "the record changed under the write; the next pass reads it again" ;;
    10) rd_not_verified settle "the record refused the write" ;;
    *) rd_not_verified settle "writing the holding failed (exit $rc)" ;;
esac
exit 0
