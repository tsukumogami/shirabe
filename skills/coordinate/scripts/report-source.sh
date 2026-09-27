#!/usr/bin/env bash
# report-source.sh -- take_report's gate: may this report stand for its worker?
#
# A worker bound to a request leg reports through the leg, where only its own
# session's terminal tick can promote a result. A message is text anyone can
# send and the coordinator relays, so a message must never stand in for a
# leg-bound worker's result. The gate reads the reporting topic's holding
# from the record: a message report is admitted only for a holding whose
# return path is `message`. A leg report came through wait_leg's gate on a
# promoted result and is admitted as is.
#
# Inputs, from the session's context: report_topic (whose report it is) and
# report_source (`leg` or `message`), both written by the transitions into
# take_report, never by the report.
#
# Usage:
#   report-source.sh --session <koto-session>
#
# Exit codes (overridable: false on the gate):
#   0  the report may stand for its worker
#   1  refused: a message for a leg-bound worker, or no holding for the topic
#   2  a read failed, the record refused the read, or an input is malformed
#
# Read-only. bash 3.2; needs jq.
set -uo pipefail

PROG=report-source
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

TOPIC=$("$KOTO" context get "$SESSION" report_topic) || { printf '%s: cannot read report_topic\n' "$PROG" >&2; exit 2; }
SOURCE=$("$KOTO" context get "$SESSION" report_source) || { printf '%s: cannot read report_source\n' "$PROG" >&2; exit 2; }
dc_valid_topic "$TOPIC" || { printf '%s: report_topic is not a valid topic\n' "$PROG" >&2; exit 2; }

case "$SOURCE" in
    leg) exit 0 ;;
    message) ;;
    *) printf '%s: report_source is [%s], not leg or message\n' "$PROG" "$SOURCE" >&2; exit 2 ;;
esac

ROW=$(dc_record_read "$SESSION" "$TOPIC")
case "$?" in
    0) ;;
    1) printf '%s: no holding for %s\n' "$PROG" "$TOPIC" >&2; exit 1 ;;
    *) printf '%s: the record could not be read for %s\n' "$PROG" "$TOPIC" >&2; exit 2 ;;
esac

RP=$(printf '%s' "$ROW" | jq -r '.return_path // "" | strings')
if [ "$RP" = message ]; then
    exit 0
fi
printf '%s: %s is bound to leg %s; its result comes through the leg, not a message\n' "$PROG" "$TOPIC" "$RP" >&2
exit 1
