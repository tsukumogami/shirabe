#!/usr/bin/env bash
# deliver-absent.sh -- the default action of /deliver's `scope_absent` and
# `execute_absent`: record that a child returned without ever recording a
# result, as the one fixed value /deliver writes to a leg.
#
# Two cases can leave a leg open with nothing to answer it: a --koto-leg that
# named no open leg (so koto recorded nothing), and a child too old to know
# the flag. The agent reports that the Skill call returned (`child_returned:
# yes`), and only on an open, unbound leg does the run come here. This script
# resolves that leg with
#
#   {"status": "failure", "summary": "...",
#    "payload": {"outcome": "error", "step": "deliver:child-absent"}}
#
# and nothing else: the value is fixed text, it takes no input from the agent,
# and it can reach only the run state's `explicit` arm, an error. The run
# routes on the result's source (`explicit`), never on its outcome.
#
# If the child bound the leg in the meantime, koto refuses the resolve (a
# self-attached leg answers only by promotion), and so it does when the leg
# was resolved or abandoned. That is not a failure here: the leg has moved on,
# and the run state re-reads it and keeps waiting or routes. The script exits
# non-zero only when the leg is still open and unbound after the attempt, so
# a resolve that failed for any other reason shows up as a failed action.
#
# It touches only koto's local request store.
#
# Usage:
#   deliver-absent.sh --request <id> --leg scope|execute
#
# Output: `absent=resolved` when this call resolved the leg, or
# `absent=moved-on:<disposition>` when the leg was no longer open and unbound.
#
# Exit codes:
#   0   resolved here, or the leg had already moved on
#   1   the leg is still open and unbound, or it could not be read
#   64  usage error; no koto call was made
#
# Environment: KOTO_BIN, the koto binary (default `koto`).
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=deliver-absent
RE_REQ='^[a-z0-9_][a-z0-9_-]{0,63}$'
KOTO="${KOTO_BIN:-koto}"

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: deliver-absent.sh --request <id> --leg scope|execute\n' >&2
    exit 64
}

REQ=""; LEG=""; SEEN=" "
while [ "$#" -gt 0 ]; do
    case "$1" in
        --request|--leg)
            [ "$#" -ge 2 ] || usage "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --request) REQ="$2" ;;
                --leg) LEG="$2" ;;
            esac
            shift ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
[[ "$REQ" =~ $RE_REQ ]] || usage "--request [$REQ] does not match $RE_REQ"
case "$LEG" in scope|execute) ;; *) usage "--leg must be scope or execute" ;; esac
command -v jq >/dev/null || { printf '%s: jq is not on PATH\n' "$PROG" >&2; exit 1; }

# The one value /deliver ever writes to a leg. Fixed text: nothing from the
# agent, the leg, or the environment is interpolated into it.
DATA='{"status":"failure","summary":"the child returned without recording a result","payload":{"outcome":"error","step":"deliver:child-absent"}}'

if "$KOTO" request resolve "$REQ" "$LEG" --with-data "$DATA" </dev/null >/dev/null; then
    printf 'absent=resolved\n'
    exit 0
fi

# The resolve was refused. Read the leg: anything but open-and-unbound means
# it moved on (bound, resolved, abandoned, or the request closed).
STATE=$("$KOTO" request get "$REQ" </dev/null \
    | jq -r --arg l "$LEG" '
        (.request_state // "") as $rs
        | (.legs[$l] // null) as $leg
        | if $leg == null then "missing"
          elif $rs != "open" then "closed"
          elif $leg.disposition != "open" then $leg.disposition
          elif $leg.bound_child != null then "bound"
          else "open" end')
case "$STATE" in
    ""|open|missing)
        printf '%s: could not resolve the %s leg of %s, and it is still %s\n' \
            "$PROG" "$LEG" "$REQ" "${STATE:-unreadable}" >&2
        exit 1
        ;;
esac
printf 'absent=moved-on:%s\n' "$STATE"
exit 0
