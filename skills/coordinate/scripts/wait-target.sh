#!/usr/bin/env bash
# wait-target.sh -- pick which worker's request leg the wait state watches.
#
# A coordinator holds several workers at once, and a request-leg gate reads
# one leg. So the wait state's action picks one: a leg that has already
# resolved (or been abandoned, or gone missing) if any holding has one, since
# that worker's result is waiting; otherwise the oldest open leg, since that's
# the one the coordinator has waited on longest. The choice goes to the
# context key `wait_target`, and the state captures the request id; the next
# state, wait_leg, reads the leg name the same way, because a capture carries
# one value.
#
# Only holdings the record shows as dispatched, with a return path of the form
# <request-id>:<leg>, are candidates. Message-path workers aren't watched here:
# their reports arrive as messages the coordinator submits.
#
# A leg is read once. A leg's result can't change after it resolves, and the
# holding keeps naming the leg until the record drops the row, so a leg
# whose result the wait state has taken is kept in the context key
# `taken_legs` and never picked again; otherwise a report that routes to a
# fix or to the surface step would bring the same result back on the next
# pass. A worker re-briefed after a fix reports by message from then on
# (dispatch-worker.sh --rebrief moves its holding to the message path).
#
# Modes:
#
#   select --session <s>
#       Writes wait_target as {"path":"leg","topic","request","leg",
#       "disposition"} or {"path":"none"} and prints the request id or
#       `none`, whenever the record can be read. It always prints
#       a token: an empty capture would fail the action instead of letting the
#       state stop for evidence, which is the wait.
#
#       There is no wake on a resolved leg until koto#250 lands; the
#       coordinator ticks the workflow on each message or notification.
#
#   leg --session <s>
#       Prints the leg name from wait_target and writes its topic to
#       `report_topic`, so every later state knows whose result it holds.
#       When the picked leg is no longer open, wait_leg's gate is about to
#       take its result, so the leg joins `taken_legs`. Exits 1 when
#       wait_target names no leg.
#
# Exit codes: 0 done, 1 no leg (leg mode), 2 a failed read or write, 10 the
# record refused the read (no open record, or a directed transition in the
# run log), 64 usage.
#
# Reads the record and the request store; writes only this session's
# wait_target, taken_legs, leg_consumed and report_topic context keys. bash 3.2; needs jq.
set -uo pipefail

PROG=wait-target
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

KOTO="${KOTO:-koto}"
RE_REQ="$DC_RE_REQ"
RE_LEG="$DC_RE_LEG"

usage() { printf 'usage: %s select|leg --session <s>\n' "$PROG" >&2; exit 64; }

MODE="${1:-}"
[ $# -gt 0 ] && shift
SESSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage

WORK=$(mktemp -d "${TMPDIR:-/tmp}/wait-target.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

put() {
    printf '%s\n' "$2" >"$WORK/v"
    "$KOTO" context add "$SESSION" "$1" --from-file "$WORK/v" || {
        printf '%s: cannot write %s\n' "$PROG" "$1" >&2
        exit 2
    }
}

# ctx_or_empty <key>: the key's value, or nothing when the key isn't set yet
# (the normal first case); a read that fails is an error.
ctx_or_empty() {
    "$KOTO" context exists "$SESSION" "$1" || return 0
    "$KOTO" context get "$SESSION" "$1"
}

# LEG_DISP: a leg's disposition as koto's request-leg gate sees it. A leg still
# open on a request that is no longer open can't resolve, and the gate calls
# it abandoned; reading it as open would offer it again on every pass.
LEG_DISP='(.request // .) as $r
    | ($r.legs[$l].disposition // "missing") as $d
    | if $d == "open" and (($r.request_state // "open") != "open") then "abandoned" else $d end
    | strings'

# mark_if_done <wait_target json>: add its leg to taken_legs when koto no
# longer shows it open. Returns 2 when the target or koto can't be read.
mark_if_done() {
    local t="$1" req leg view disp taken
    req=$(printf '%s' "$t" | jq -r '.request // "" | strings')
    leg=$(printf '%s' "$t" | jq -r '.leg // "" | strings')
    printf '%s' "$req" | grep -Eq "$RE_REQ" || { printf '%s: wait_target holds a malformed request\n' "$PROG" >&2; return 2; }
    printf '%s' "$leg" | grep -Eq "$RE_LEG" || { printf '%s: wait_target holds a malformed leg\n' "$PROG" >&2; return 2; }
    view=$("$KOTO" request get "$req" </dev/null) || { printf '%s: cannot read request %s\n' "$PROG" "$req" >&2; return 2; }
    disp=$(printf '%s' "$view" | jq -r --arg l "$leg" "$LEG_DISP")
    [ "$disp" = open ] && return 0
    taken=$(ctx_or_empty taken_legs) || return 2
    put taken_legs "$(printf '%s\n%s\n' "$taken" "$req:$leg" | sed '/^$/d' | sort -u)"
}

# --- leg -----------------------------------------------------------------------------

if [ "$MODE" = leg ]; then
    T=$("$KOTO" context get "$SESSION" wait_target) || { printf '%s: cannot read wait_target\n' "$PROG" >&2; exit 2; }
    LEG=$(printf '%s' "$T" | jq -r 'select(.path == "leg") | .leg // "" | strings')
    TOPIC=$(printf '%s' "$T" | jq -r 'select(.path == "leg") | .topic // "" | strings')
    [ -n "$LEG" ] || { printf '%s: wait_target names no leg\n' "$PROG" >&2; exit 1; }
    printf '%s' "$LEG" | grep -Eq "$RE_LEG" || { printf '%s: wait_target holds a malformed leg\n' "$PROG" >&2; exit 2; }
    dc_valid_topic "$TOPIC" || { printf '%s: wait_target holds a malformed topic\n' "$PROG" >&2; exit 2; }
    put report_topic "$TOPIC"
    # The leg's disposition now, not the one select saw: koto re-runs this
    # action on every blocked tick, and a leg that resolves in between is
    # taken by the gate that follows, so it has to be marked on that tick.
    mark_if_done "$T" || exit 2
    printf '%s\n' "$LEG"
    exit 0
fi
[ "$MODE" = select ] || usage

# The leg the last pick named is marked taken here too when wait_leg's gate
# consumed it: an evidence tick at wait_leg (rescan or back) doesn't run its
# action, so a leg that resolved between two ticks can be taken by the gate
# without the mark above. wait_leg's consuming edges set leg_consumed, and
# every route back to a leg passes this pick first.
CONSUMED=$(ctx_or_empty leg_consumed) || exit 2
if [ "$CONSUMED" = yes ]; then
    PREV=$(ctx_or_empty wait_target) || exit 2
    if [ "$(printf '%s' "$PREV" | jq -r '.path // "" | strings')" = leg ]; then
        mark_if_done "$PREV" || exit 2
    fi
    put leg_consumed ""
fi

# --- select --------------------------------------------------------------------------------

# candidates: one "<disposition><TAB><topic><TAB><request><TAB><leg>" line per
# leg-bound, dispatched holding, in record order.
candidates() {
    local rows rc
    rows=$(dc_record_list "$SESSION")
    rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    local topic rp req leg view disp taken
    taken=$(ctx_or_empty taken_legs) || return 2
    while IFS='	' read -r topic rp; do
        [ -n "$topic" ] || continue
        req=${rp%%:*}
        leg=${rp#*:}
        printf '%s' "$req" | grep -Eq "$RE_REQ" || continue
        printf '%s' "$leg" | grep -Eq "$RE_LEG" || continue
        dc_valid_topic "$topic" || continue
        printf '%s\n' "$taken" | grep -Fqx -- "$rp" && continue
        if view=$("$KOTO" request get "$req" </dev/null); then
            disp=$(printf '%s' "$view" | jq -r --arg l "$leg" "$LEG_DISP")
        else
            # A request koto can't read is left for the next tick rather than
            # routed as missing: one failed read says nothing about the leg.
            printf '%s: could not read request %s for %s\n' "$PROG" "$req" "$topic" >&2
            continue
        fi
        printf '%s\t%s\t%s\t%s\n' "$disp" "$topic" "$req" "$leg"
    done <<EOF
$(printf '%s' "$rows" | jq -r '.[] | select(.dispatch_status == "dispatched") | select((.return_path // "") | test("^leg [^: ]+:[^: ]+$")) | [.worker, (.return_path | ltrimstr("leg "))] | @tsv')
EOF
}

pick() {
    local list
    list=$(candidates)
    local rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    # Anything not open first (its result, or its abandonment, is waiting),
    # then the oldest open one.
    printf '%s\n' "$list" | awk -F'\t' '$1 != "" && $1 != "open" { print; exit }' >"$WORK/pick"
    if [ ! -s "$WORK/pick" ]; then
        printf '%s\n' "$list" | awk -F'\t' '$1 == "open" { print; exit }' >"$WORK/pick"
    fi
    cat "$WORK/pick"
}

LINE=$(pick)
RC=$?
[ "$RC" -eq 0 ] || { printf '%s: the record could not be read\n' "$PROG" >&2; exit "$RC"; }

if [ -z "$LINE" ]; then
    put wait_target '{"path":"none"}'
    printf 'none\n'
    exit 0
fi

IFS='	' read -r DISP TOPIC REQ LEG <<EOF
$LINE
EOF
put wait_target "$(jq -nc --arg t "$TOPIC" --arg r "$REQ" --arg l "$LEG" --arg d "$DISP" '{path: "leg", topic: $t, request: $r, leg: $l, disposition: $d}')"
printf '%s\n' "$REQ"
