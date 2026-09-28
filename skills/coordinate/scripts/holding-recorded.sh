#!/usr/bin/env bash
# holding-recorded.sh -- the dispatch state's gate: is this topic's holding on
# the record?
#
# The coordinator can't leave the dispatch state with a worker the record
# doesn't show. This gate reads the record itself, through the record
# feature's reader, never a value the coordinator submits or a context key it
# could write. The topic it checks is dispatch_topic, which the pick edge
# writes fresh on every pass, so the gate never passes on an earlier topic's
# row.
#
# Usage:
#   holding-recorded.sh --session <koto-session>
#
# Exit codes (the gate routes on them; it's declared overridable: false):
#   0  the holding is dispatched
#   1  no holding for the topic
#   2  the record or the topic couldn't be read, or the record refused the
#      read (no open record, or a directed transition in the run log)
#   3  the holding says dispatch-failed
#   4  the holding says dispatching: an earlier dispatch-worker.sh run
#      stopped partway; run it again to settle it
#
# Read-only. bash 3.2; needs jq.
set -uo pipefail

PROG=holding-recorded
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

KOTO="${KOTO:-koto}"

SESSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || { printf 'usage: %s --session <s>\n' "$PROG" >&2; exit 2; }; SESSION="$2"; shift 2 ;;
        *) printf 'usage: %s --session <s>\n' "$PROG" >&2; exit 2 ;;
    esac
done
[ -n "$SESSION" ] || { printf 'usage: %s --session <s>\n' "$PROG" >&2; exit 2; }

TOPIC=$("$KOTO" context get "$SESSION" dispatch_topic) || {
    printf '%s: cannot read dispatch_topic\n' "$PROG" >&2
    exit 2
}
dc_valid_topic "$TOPIC" || { printf '%s: dispatch_topic is not a valid topic\n' "$PROG" >&2; exit 2; }

ROW=$(dc_record_read "$SESSION" "$TOPIC")
case "$?" in
    0) ;;
    1) printf '%s: no holding for %s\n' "$PROG" "$TOPIC" >&2; exit 1 ;;
    *) printf '%s: the record could not be read for %s\n' "$PROG" "$TOPIC" >&2; exit 2 ;;
esac

STATUS=$(printf '%s' "$ROW" | jq -r '.dispatch_status // "" | strings')
case "$STATUS" in
    dispatched) exit 0 ;;
    dispatch-failed) printf '%s: %s dispatch-failed\n' "$PROG" "$TOPIC" >&2; exit 3 ;;
    dispatching) printf '%s: %s still dispatching\n' "$PROG" "$TOPIC" >&2; exit 4 ;;
    *) printf '%s: %s has dispatch status [%s]\n' "$PROG" "$TOPIC" "$STATUS" >&2; exit 2 ;;
esac
