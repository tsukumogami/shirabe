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
# Modes:
#
#   select --session <s> [--watch-secs <n>]
#       Writes wait_target as {"path":"leg","topic","request","leg"} or
#       {"path":"none"} and prints the request id or `none`. It always prints
#       a token: an empty capture would fail the action instead of letting the
#       state stop for evidence, which is the wait.
#
#       --watch-secs (default 0, off) first waits up to <n> seconds for a
#       wake on the coordinator's session through `koto request watch`, with
#       the cursor kept in the context key `wake_cursor`, when no leg has
#       resolved yet. That subscriber arrives with koto#250; on a koto without
#       it the watch is skipped and the coordinator ticks the workflow on each
#       message or notification instead. Keep <n> well under the 30 seconds a
#       default action gets.
#
#   leg --session <s>
#       Prints the leg name from wait_target and writes its topic to
#       `report_topic`, so every later state knows whose result it holds.
#       Exits 1 when wait_target names no leg.
#
# Exit codes: 0 done, 1 no leg (leg mode), 2 a failed read or write, 10 the
# record refused the read (no open record, or a directed transition in the
# run log), 64 usage.
#
# Reads the record and the request store; writes only this session's
# wait_target, wake_cursor and report_topic context keys. bash 3.2; needs jq.
set -uo pipefail

PROG=wait-target
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

KOTO="${KOTO:-koto}"
RE_REQ='^[a-z0-9_][a-z0-9_-]{0,63}$'
RE_LEG='^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$'

usage() { printf 'usage: %s select|leg --session <s> [--watch-secs <n>]\n' "$PROG" >&2; exit 64; }

MODE="${1:-}"
[ $# -gt 0 ] && shift
SESSION=""
WATCH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        --watch-secs) [ $# -ge 2 ] || usage; WATCH="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
case "$WATCH" in '' | *[!0-9]*) usage ;; esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/wait-target.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

put() {
    printf '%s\n' "$2" >"$WORK/v"
    "$KOTO" context add "$SESSION" "$1" --from-file "$WORK/v" || {
        printf '%s: cannot write %s\n' "$PROG" "$1" >&2
        exit 2
    }
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
    printf '%s\n' "$LEG"
    exit 0
fi
[ "$MODE" = select ] || usage

# --- select --------------------------------------------------------------------------------

# candidates: one "<disposition><TAB><topic><TAB><request><TAB><leg>" line per
# leg-bound, dispatched holding, in record order.
candidates() {
    local rows rc
    rows=$(dc_record_list "$SESSION")
    rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    local topic rp req leg view disp
    while IFS='	' read -r topic rp; do
        [ -n "$topic" ] || continue
        req=${rp%%:*}
        leg=${rp#*:}
        printf '%s' "$req" | grep -Eq "$RE_REQ" || continue
        printf '%s' "$leg" | grep -Eq "$RE_LEG" || continue
        dc_valid_topic "$topic" || continue
        if view=$("$KOTO" request get "$req" </dev/null); then
            disp=$(printf '%s' "$view" | jq -r --arg l "$leg" '(.request // .) | .legs[$l].disposition // "missing" | strings')
        else
            # A request koto can't read is left for the next tick rather than
            # routed as missing: one failed read says nothing about the leg.
            printf '%s: could not read request %s for %s\n' "$PROG" "$req" "$topic" >&2
            continue
        fi
        printf '%s\t%s\t%s\t%s\n' "$disp" "$topic" "$req" "$leg"
    done <<EOF
$(printf '%s' "$rows" | jq -r '.[] | select(.dispatch_status == "dispatched") | select((.return_path // "") | test("^[^:]+:[^:]+$")) | [.worker, .return_path] | @tsv')
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

# The bounded wake wait, when asked for and when there's an open leg but no
# result yet (koto#250's subscriber; skipped on a koto without it).
if [ "$WATCH" -gt 0 ] && [ "${LINE%%	*}" = open ] && "$KOTO" request watch --help >/dev/null 2>&1; then
    CURSOR=$("$KOTO" context get "$SESSION" wake_cursor 2>&1) || CURSOR=""
    if [ -n "$CURSOR" ]; then
        W=$("$KOTO" request watch --session "$SESSION" --timeout-secs "$WATCH" --since "$CURSOR" </dev/null)
    else
        W=$("$KOTO" request watch --session "$SESSION" --timeout-secs "$WATCH" </dev/null)
    fi && {
        NEW=$(printf '%s' "$W" | jq -r '.cursor // "" | tostring')
        [ -n "$NEW" ] && put wake_cursor "$NEW"
        LINE=$(pick) || exit $?
    }
fi

if [ -z "$LINE" ]; then
    put wait_target '{"path":"none"}'
    printf 'none\n'
    exit 0
fi

IFS='	' read -r DISP TOPIC REQ LEG <<EOF
$LINE
EOF
put wait_target "$(jq -nc --arg t "$TOPIC" --arg r "$REQ" --arg l "$LEG" '{path: "leg", topic: $t, request: $r, leg: $l}')"
printf '%s\n' "$REQ"
