#!/usr/bin/env bash
# reconcile-settle.sh -- the one record write reconcile makes: a holding left
# at `dispatching` whose worker is live becomes `dispatched`.
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
# record-holding.sh refuses whichever write lands on a record changed since
# its read (exit 12), which this script reports as not verified for the next
# pass to read again.
#
# Usage:
#   reconcile-settle.sh --session S --topic T --return-path RP
#
# RP is the row's Return path as the pass read it (`message` or
# `leg <request>:<leg>`). The row is rewritten through record-holding.sh,
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
# Requires: bash 3.2+, jq, gh, koto.
set -uo pipefail

PROG=reconcile-settle
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

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

HOLDING="$HERE/record-holding.sh"
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
