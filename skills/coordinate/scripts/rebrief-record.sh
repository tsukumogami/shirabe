#!/usr/bin/env bash
# rebrief-record.sh -- the check action of state rebrief_record: what a
# re-brief's outcome records about the worker and the coordinator's address,
# so neither dispatch-worker.sh --rebrief nor the agent records it by hand
# (tsukumogami/shirabe#1245).
#
# Usage: rebrief-record.sh --session S
#
# Reads the `sent` field of the latest evidence submitted at rebrief
# (coord-log.sh evidence) and the worker from the context key report_topic,
# never an argument:
#   sent         the worker was messaged its new brief, which names the
#                current address: it is recorded told
#                (state-stored-set.sh --told), unless it already is
#   worker_gone  the worker's session no longer exists. When niwa still lists
#                an instance for it (dc_find_session from the workspace root),
#                it can be told on its next start and is recorded pending
#                (state-stored-set.sh --pending), unless it is already told or
#                pending; with no instance, or no workspace root to look from,
#                nothing is recorded
# A `refused` re-brief never reaches this state: rebrief routes it to wait,
# and the handover gate keeps its not-told gap for the worker.
#
# Verdicts (sealed to this visit): `rebrief-told` (sent), `rebrief-pending`
# (worker_gone, an instance listed) or `rebrief-gone` (worker_gone, none). A
# record the write finds changed (11, 12) is read and written again, up to
# three tries. Exit codes: 0 a verdict was printed; 2 a read or a write failed,
# or the record names no coordinator address (nothing sealed; the state's
# fallback says to fix the cause and tick again); 64 usage.
set -uo pipefail

PROG=rebrief-record
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO=${KOTO_BIN:-koto}
SESSION=
usage() { sed -n '/^# Usage:/,/^# Reads the/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
. "$HERE/dispatch-common.sh"
die2() { echo "$PROG: $*" >&2; exit 2; }
seal() { bash "$HERE/coord-log.sh" seal --session "$SESSION" --state rebrief_record --token "$1" || die2 "cannot seal the verdict"; exit 0; }

EV=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state rebrief)
case $? in 0) ;; 1) die2 "no evidence was submitted at rebrief" ;; *) die2 "cannot read the session log" ;; esac
SENT=$(printf '%s' "$EV" | jq -r '.fields.sent // ""') || die2 "the rebrief evidence is not JSON"
TOPIC=$("$KOTO" context get "$SESSION" report_topic) || die2 "cannot read report_topic"
dc_valid_topic "$TOPIC" || die2 "report_topic [$TOPIC] is not a dispatch topic"

# run_has <key>: the record's Run section has a <key> row for the worker.
LIST=$(bash "$HERE/state-stored-set.sh" --session "$SESSION" --list) || die2 "cannot read the record's stored set"
jq -e 'any(.run[]; .key == "coordinator")' <<<"$LIST" > /dev/null \
    || die2 "the record names no coordinator address to tell $TOPIC; set it with state-stored-set.sh --run coordinator and tick again"
run_has() { jq -e --arg k "$1" --arg w "$TOPIC" 'any(.run[]; .key == $k and .value == $w)' <<<"$LIST" > /dev/null; }

# record <--told|--pending>: the write, again while the record changes under it.
record() {
    local try rc
    for try in 1 2 3; do
        bash "$HERE/state-stored-set.sh" --session "$SESSION" "$1" "$TOPIC" --by "the re-brief" > /dev/null
        rc=$?
        case $rc in
            0) return 0 ;;
            # The state is written; only its entry is unposted, which the
            # script's stderr names.
            14) return 0 ;;
            11|12) ;;
            *) die2 "state-stored-set.sh $1 $TOPIC exited $rc" ;;
        esac
    done
    die2 "the record kept changing under state-stored-set.sh $1 $TOPIC"
}

case "$SENT" in
    sent)
        if run_has told; then
            echo "$PROG: $TOPIC was already told the current address" >&2
        else
            record --told
        fi
        seal rebrief-told ;;
    worker_gone)
        ROOT=$(dc_workspace_root) || { echo "$PROG: no workspace root to look for $TOPIC's instance from; nothing recorded" >&2; seal rebrief-gone; }
        dc_find_session "$ROOT" "$TOPIC" > /dev/null
        case $? in
            0) ;;
            1) echo "$PROG: niwa lists no instance for $TOPIC; nothing recorded" >&2; seal rebrief-gone ;;
            *) die2 "niwa list could not be read" ;;
        esac
        if run_has told; then
            echo "$PROG: $TOPIC was already told the current address" >&2
        elif run_has pending; then
            echo "$PROG: $TOPIC is already pending" >&2
        else
            record --pending
        fi
        seal rebrief-pending ;;
    *) die2 "the rebrief evidence's sent is [$SENT], neither sent nor worker_gone" ;;
esac
