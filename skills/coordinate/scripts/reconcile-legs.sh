#!/usr/bin/env bash
# reconcile-legs.sh -- give one holding's leg an end on a host whose request
# store doesn't hold it. After `koto session import` the coordinator's session
# and its legs/ keys are here, but the requests stayed in the old host's store
# (PRD R15; docs/designs/DESIGN-coordinator-session-record.md, Decision 7).
#
# reconcile-pass.sh launches it, as it launches reconcile-settle.sh, for a
# dispatched holding on a leg whose leg re-check read "request not found on
# this host", and only when its whole budget fits in the pass. The holding's
# leg gets one outcome:
#
#   watched      this host's store holds the request after all: nothing
#                changes
#   relegged     dispatch-worker.sh --releg-imported attached the worker's own
#                session, which came here with the import and is bound to no
#                leg, to a new request on this host, and the holding names it
#   unwatchable  anything else: the worker's session stayed on the old host,
#                is bound to another leg, was never recorded, or the holding
#                was dispatched before leg keys existed. The holding moves to
#                the message path and its key reads unwatchable; the
#                coordinator then re-briefs the worker (dispatch-worker.sh
#                --rebrief), so its brief gives this coordinator's address and
#                names this run as the dispatcher it records.
#
# The holding is re-read first and changed only while it is still the row the
# pass read: dispatched, on the same leg. Until every leg-bound holding is one
# of the three, state-handover.sh --check lists it as leg-unclassified.
#
# Usage:
#   reconcile-legs.sh --session S --topic T --return-path RP
#
# RP is the row's Return path as the pass read it (`leg <request>:<leg>`).
#
# Output: one JSON fact on stdout, exit 0, like every re-check:
#   {kind: "legs", status: "ok", outcome, now, reason, read_at}
#   {kind: "legs", status: "not_verified", reason, read_at}
# outcome is watched, relegged, unwatchable, or none when the holding is gone
# or no longer the row the pass read; now is the holding's Return path after
# the call. Exit 64 on usage.
#
# Requires: bash 3.2+, jq, gh, koto.
set -uo pipefail

PROG=reconcile-legs
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

usage() { echo "$PROG: usage: $PROG --session S --topic T --return-path RP" >&2; exit 64; }
SESSION="" TOPIC="" RP=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --session) SESSION=$2 ;;
        --topic) TOPIC=$2 ;;
        --return-path) RP=$2 ;;
        *) usage ;;
    esac
    shift 2
done
[ -n "$SESSION" ] && [ -n "$TOPIC" ] && [ -n "$RP" ] || usage
dc_valid_topic "$TOPIC" || usage
case "$RP" in "leg "*) ;; *) usage ;; esac

KOTO=${KOTO:-koto}
HOLDING="$HERE/state-holding.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-legs.XXXXXX") || { rd_not_verified legs "no temp directory"; exit 0; }
trap 'rm -rf "$T"' EXIT

fact() { # fact <outcome> <now> <reason>
    jq -nc --arg o "$1" --arg n "$2" --arg r "$3" --arg t "$(rd_now)" \
        '{kind: "legs", status: "ok", outcome: $o, now: $n, reason: $r, read_at: $t}'
    exit 0
}
nv() { rd_not_verified legs "$1"; exit 0; }

bash "$HOLDING" --session "$SESSION" --topic "$TOPIC" --read > "$T/row.json" 2>/dev/null
case $? in
    0) ;;
    1) fact none "" "no holding names $TOPIC now" ;;
    *) nv "the holding could not be read" ;;
esac
ST=$(jq -r '.dispatch_status // "" | strings' "$T/row.json")
NOW=$(jq -r '.return_path // "" | strings' "$T/row.json")
[ "$ST" = dispatched ] || fact none "$NOW" "the holding is ${ST:-without a status} now"
[ "$NOW" = "$RP" ] || fact none "$NOW" "the holding's return path changed since the pass read it"
SPEC=$(dc_rp_from_row "$RP")
REQ=${SPEC%%:*}
LEG=${SPEC#*:}
[[ $REQ =~ $DC_RE_REQ ]] && [[ $LEG =~ $DC_RE_LEG ]] || nv "unreadable return path in the record row"

# koto exits 2 for a request its store doesn't hold.
"$KOTO" request get "$REQ" < /dev/null > /dev/null
case $? in
    0) fact watched "$RP" "this host's store holds the request" ;;
    2) ;;
    *) nv "request $REQ could not be read" ;;
esac

# The worker's own session, if it came here unbound, is attached to a new
# request on this host. Every refusal of the re-leg (exit 9) leaves the leg
# unwatchable from here. This runs inside a koto tick, so it calls only
# --releg-imported, which exits before dispatch-worker.sh's niwa dispatch;
# scripts/check-tick-launches.allow records that, and a call in any other mode
# here would need KOTO_SESSION_* unset first.
bash "$HERE/dispatch-worker.sh" --session "$SESSION" --releg-imported "$TOPIC" > "$T/releg.out" 2> "$T/releg.err" < /dev/null
case $? in
    0)
        NEW=$(sed -n 's/^leg=//p' "$T/releg.out" | head -1)
        fact relegged "$(dc_rp_to_row "$NEW")" "its session came here with the import and is attached to a new leg"
        ;;
    9) WHY=$(tail -n 1 "$T/releg.err" | sed 's/^dispatch-worker: //' | cut -c1-200) ;;
    *) nv "the re-leg failed: $(tail -n 1 "$T/releg.err" | sed 's/^dispatch-worker: //' | cut -c1-200)" ;;
esac

# Unwatchable: the holding reports by message from here on.
jq -c '.return_path = "message"' "$T/row.json" > "$T/new.json" || nv "the row could not be rewritten"
# dc_record_write retries a record another writer changed under it.
DC_RECORD_HOLDING=$HOLDING dc_record_write "$SESSION" "$TOPIC" "$T/new.json" 2> "$T/err"
case $? in
    0) ;;
    10) nv "the record refused the write" ;;
    *) nv "writing the holding failed" ;;
esac
KEY=$(dc_leg_get "$SESSION" "$REQ" "$LEG")
if [ $? = 0 ]; then
    # A re-leg an earlier run left pending opened a request this host holds;
    # nothing will bind it now, so it is abandoned with the leg's end.
    PENDING=$(jq -r '.new_request // "" | strings' <<< "$KEY")
    if [ -n "$PENDING" ] && [[ $PENDING =~ $DC_RE_REQ ]]; then
        "$KOTO" request abandon-request "$PENDING" --rationale "the leg of $TOPIC ended unwatchable" < /dev/null > /dev/null \
            || echo "$PROG: the pending request $PENDING could not be abandoned" >&2
    fi
    dc_leg_put "$SESSION" "$REQ" "$LEG" "$(jq -c '.state = "unwatchable" | del(.new_request)' <<< "$KEY")" \
        || echo "$PROG: the leg key for $SPEC could not be marked unwatchable" >&2
fi
fact unwatchable message "${WHY:-its worker cannot be watched from this host}"
