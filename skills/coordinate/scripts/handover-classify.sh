#!/usr/bin/env bash
# handover-classify.sh -- what the handover can observe of each worker the
# current coordinator address hasn't reached, and what it records
# (docs/designs/DESIGN-coordinate-successor-continues.md, Decision 4; PRD R15).
# Agent-run at `reconcile`, before state-handover.sh --check.
#
# Usage: handover-classify.sh --session S
#
# First, a pending worker whose report reached this run turns told: a `wait`
# evidence of event report or progress naming it (coord-log.sh evidence), in
# the minute the Run `coordinator` row was set or later, means its message
# reached the current address, so it is recorded told
# (state-stored-set.sh --told). A worker started again after a takeover finds
# that address itself (resolve-coordinator.sh), so its first report is what
# shows it has it.
#
# Then each live holding's worker with neither a `told` row nor a `pending`
# row for the current address (state-handover.sh's workers) is classified by
# the liveness probe. That includes a carried worker, one whose `pending` row
# an earlier address left (state-handover.sh's `carried`): the read decides
# whether it is still pending. The probe (dispatch-common.sh dc_session_live)
# reads its instance, the one niwa lists for
# its topic (dc_find_session, from the workspace root), its Claude session the
# instance's session name, and its koto session the newest running root
# session under the instance's path (koto session list --execution-dir), or
# none when there is none, which leaves the Claude job to decide alone.
#
# Prints one line per worker it read:
#   told <worker>               a pending worker whose report reached this run;
#                               recorded told
#   live <worker> <address>     its session is live: send it a line naming the
#                               coordinator's address, then record it with
#                               state-stored-set.sh --told; a refused message
#                               records nothing, and the handover gate keeps
#                               its not-told gap
#   pending <worker>            its session isn't live while its instance is
#                               still there: recorded pending, so the gate
#                               passes; it reaches the run's newest member on
#                               its next start, and its first report turns it
#                               told. For a carried worker, also when niwa
#                               lists no instance for it: its carried row is
#                               confirmed for the current address. Every
#                               carried worker read so is confirmed in one
#                               write after the others are read
#                               (state-stored-set.sh --pending-confirm), and
#                               its line printed then
#   missing <worker>            niwa lists no instance for a worker with no
#                               pending row: nothing is recorded, and the gate
#                               keeps its not-told gap until the holding is
#                               dealt with as today
#   unknown <worker> <why>      its koto log couldn't be read: nothing is
#                               recorded, and a carried row stays carried
#
# A carried worker whose session is live prints `live` and keeps its carried
# row until --told replaces it, as a worker with no row does.
#
# Exit codes: 0 classified; 2 a read or a write failed, the record names no
# coordinator address, or there is no workspace root to look for instances
# from; 64 usage.
#
# Writes only through state-stored-set.sh (--told, --pending and
# --pending-confirm). Reads: the
# record (state-stored-set.sh --list, state-handover.sh), the run's log
# (coord-log.sh evidence), niwa list, koto session list and the workers' koto
# logs, and the Claude job directory (DC_CLAUDE_HOME).
set -uo pipefail

PROG=handover-classify
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO=${KOTO_BIN:-koto}
SESSION=
usage() { sed -n '/^# Usage:/,/^# First,/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh" || exit 64
die2() { echo "$PROG: $*" >&2; exit 2; }

# set_row <flag> <value> [<flag> <value>]...: the write, again while the
# record changes under it (11, 12); 14 is a state written whose entry is
# unposted.
set_row() {
    local try rc
    for try in 1 2 3; do
        bash "$HERE/state-stored-set.sh" --session "$SESSION" "$@" --by "the handover" > /dev/null
        rc=$?
        case $rc in
            0|14) return 0 ;;
            11|12) ;;
            *) die2 "state-stored-set.sh $* exited $rc" ;;
        esac
    done
    die2 "the record kept changing under state-stored-set.sh $*"
}

LIST=$(bash "$HERE/state-stored-set.sh" --session "$SESSION" --list) || die2 "cannot read the record's stored set"
SINCE=$(jq -r '[.run[] | select(.key == "coordinator") | .set][0] // "" | strings' <<<"$LIST") || die2 "jq failed"
[ -n "$SINCE" ] || die2 "the record names no coordinator address; set it with state-stored-set.sh --run coordinator first"
ADDR=$(jq -r '[.run[] | select(.key == "coordinator") | .value][0]' <<<"$LIST")

# A pending worker whose report reached this run since the address was set.
for W in $(jq -r '.run[] | select(.key == "pending") | .value' <<<"$LIST"); do
    EV=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state wait --where 'event=report|progress' --where "unit=$W")
    case $? in 0) ;; 1) continue ;; *) die2 "cannot read the run's log" ;; esac
    AT=$(jq -r '.timestamp // "" | strings | select(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}")) | .[0:16] + "Z"' <<<"$EV") \
        || die2 "jq failed"
    [ -n "$AT" ] || continue
    [[ "$AT" > "$SINCE" || "$AT" == "$SINCE" ]] || continue
    set_row --told "$W"
    printf 'told %s\n' "$W"
done

HAND=$(bash "$HERE/state-handover.sh" --session "$SESSION") || die2 "state-handover.sh couldn't read the record"
WORKERS=$(jq -r '.workers[] | select((.told or (.pending // false)) | not) | .worker' <<<"$HAND") || die2 "jq failed"
CARRIED=$(jq -r '.workers[] | select(.carried // false) | .worker' <<<"$HAND") || die2 "jq failed"
[ -n "$WORKERS" ] || exit 0
ROOT=$(dc_workspace_root) || die2 "no workspace root to look for the workers' instances from"
# is_carried <worker>: its pending row an earlier address left.
is_carried() { grep -qxF -- "$1" <<<"$CARRIED"; }
# The carried workers read stopped or missing, confirmed together after the
# loop: one --pending-confirm pair each, and the workers in the order read.
CONFIRM=() CONFIRMED=()
for W in $WORKERS; do
    FOUND=$(dc_find_session "$ROOT" "$W")
    case $? in
        0) ;;
        1) if is_carried "$W"; then CONFIRM+=(--pending-confirm "$W=missing"); CONFIRMED+=("$W")
           else printf 'missing %s\n' "$W"; fi
           continue ;;
        *) die2 "niwa list could not be read" ;;
    esac
    NAME=${FOUND%%	*} IPATH=${FOUND#*	}
    KS=
    if [ -n "$IPATH" ] && [ -d "$IPATH" ]; then
        KS=$("$KOTO" session list --execution-dir "$IPATH" </dev/null 2>/dev/null \
            | jq -r '[(.sessions // [])[] | select(.parent_workflow == null and .status == "running")] | sort_by(.created_at) | last | .id // "" | strings') \
            || die2 "koto session list could not be read for $IPATH"
    fi
    WHY=$(dc_session_live "$KS" "" "$NAME")
    case $? in
        0) printf 'live %s %s\n' "$W" "$ADDR" ;;
        1) if is_carried "$W"; then CONFIRM+=(--pending-confirm "$W=stopped"); CONFIRMED+=("$W")
           else set_row --pending "$W"; printf 'pending %s\n' "$W"; fi ;;
        *) printf 'unknown %s %s\n' "$W" "$WHY" ;;
    esac
done
if [ "${#CONFIRM[@]}" -gt 0 ]; then
    set_row "${CONFIRM[@]}"
    printf 'pending %s\n' "${CONFIRMED[@]}"
fi
exit 0
