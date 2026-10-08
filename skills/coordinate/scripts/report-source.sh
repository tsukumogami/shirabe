#!/usr/bin/env bash
# report-source.sh -- take_report's gate: may this report stand for its worker?
#
# A worker bound to a request leg reports through the leg, where only its own
# session's terminal tick can promote a result. A message is text anyone can
# send and the coordinator relays, so a message must never stand in for a
# leg-bound worker's result, and a report claimed to come from a leg must be
# the leg the record names. The gate reads the reporting topic's holding from
# the record: a message report is admitted only for a holding whose return
# path is `message`; a leg report only when the holding's return path is the
# leg the wait state read (wait_target), which wait_leg's gate admitted on a
# promoted result, and only when koto's own record of the leg holds a
# promoted result whose text is exactly worker_report.
#
# A progress report (report_source `progress`, a checkpoint message from the
# hub's `progress` event) is admitted for any worker with a holding, on
# either return path: it is never a result, so it can't stand in for a
# leg-bound worker's, and report_facts sends it back to the hub without a
# classification (shirabe#491).
#
# Inputs, from the session's context: report_topic (whose report it is) and
# report_source (`leg`, `message` or `progress`), both written by the
# transitions into take_report, never by the report.
#
# Usage:
#   report-source.sh --session <koto-session>
#
# Exit codes (overridable: false on the gate):
#   0  the report may stand for its worker
#   1  refused message: a message for a leg-bound worker, or no holding for
#      the topic (a progress report with no holding too)
#   2  a read failed, the record refused the read, or an input is malformed
#   3  refused leg report: no holding for the topic, a leg other than the
#      one the record names, or a report that isn't the promoted result koto
#      holds for the leg. The leg is spent, so it goes to the human rather
#      than back to the hub, where nothing would bring it back.
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
    leg | message | progress) ;;
    *) printf '%s: report_source is [%s], not leg, message or progress\n' "$PROG" "$SOURCE" >&2; exit 2 ;;
esac
# A refused message goes back to the hub (1): a leg-bound worker's real result
# is still coming on its leg. A refused leg report goes to the human (3): the
# leg was consumed on the way here and won't come back to the hub.
REFUSED=1
[ "$SOURCE" = leg ] && REFUSED=3

ROW=$(dc_record_read "$SESSION" "$TOPIC")
case "$?" in
    0) ;;
    1) printf '%s: no holding for %s\n' "$PROG" "$TOPIC" >&2; exit "$REFUSED" ;;
    *) printf '%s: the record could not be read for %s\n' "$PROG" "$TOPIC" >&2; exit 2 ;;
esac
RP=$(dc_rp_from_row "$(printf '%s' "$ROW" | jq -r '.return_path // "" | strings')")

# Progress is never a result: any holding's worker may send it.
[ "$SOURCE" = progress ] && exit 0

if [ "$SOURCE" = message ]; then
    [ "$RP" = message ] && exit 0
    printf '%s: %s is bound to leg %s; its result comes through the leg, not a message\n' "$PROG" "$TOPIC" "$RP" >&2
    exit 1
fi

# A leg report is admitted only for the leg the record binds this worker to,
# and only when it is the leg the wait state actually read: report_source is
# context anyone in the session can write, so the claim is checked against the
# record and against wait_target, which wait-target.sh wrote from the record.
TARGET=$("$KOTO" context get "$SESSION" wait_target) || { printf '%s: cannot read wait_target\n' "$PROG" >&2; exit 2; }
READ=$(printf '%s' "$TARGET" | jq -r --arg t "$TOPIC" 'select(.path == "leg" and .topic == $t) | "\(.request):\(.leg)"')
if [ -z "$READ" ] || [ "$RP" != "$READ" ]; then
    printf '%s: a leg report for %s must come from its recorded leg [%s], read by the wait state [%s]\n' "$PROG" "$TOPIC" "$RP" "$READ" >&2
    exit 3
fi

# The context keys above say which leg; they can't say what the leg holds,
# since anyone in the session can rewrite them. So koto's own record of the leg
# is read here: it must have resolved with a result the worker's session
# promoted, and worker_report must be exactly the text wait_leg's edge builds
# from that result, so a rewritten report can't stand for the leg.
REQ=${READ%%:*}
LEG=${READ#*:}
VIEW=$("$KOTO" request get "$REQ" </dev/null) || { printf '%s: cannot read request %s\n' "$PROG" "$REQ" >&2; exit 2; }
WANT=$(printf '%s' "$VIEW" | jq -r --arg l "$LEG" '
    # As koto renders a gate value into an edge: null as empty, a string as
    # itself, anything else as compact JSON; a payload that is not an object
    # reads as empty.
    def r: if . == null then "" elif type == "string" then . else tojson end;
    (.request // .) | .legs[$l] // empty
    | select(.disposition == "resolved" and .result_source == "promoted")
    | .result as $res | ($res.payload | if type == "object" then . else {} end) as $p
    | "leg result: status \($res.status | r); final state \(.result_final_state | r); outcome \($p.outcome | r); step \($p.step | r); reason \($p.reason | r); pull request \($p.pr | r)"')
if [ -z "$WANT" ]; then
    printf '%s: leg %s has no result its worker'"'"'s session promoted\n' "$PROG" "$READ" >&2
    exit 3
fi
GOT=$("$KOTO" context get "$SESSION" worker_report) || { printf '%s: cannot read worker_report\n' "$PROG" >&2; exit 2; }
if [ "$GOT" != "$WANT" ]; then
    printf '%s: worker_report for %s is not the result leg %s holds\n' "$PROG" "$TOPIC" "$READ" >&2
    exit 3
fi
exit 0
