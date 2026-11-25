#!/usr/bin/env bash
# standing-provenance.sh -- the facts of one cited koto decision, read and
# never written (docs/designs/DESIGN-coordinator-standing-rule-provenance.md).
#
# A standing rule row whose Source is `decision` cites a decision koto
# recorded, by session name and 12-digit id. This prints what rule_class and
# the --rules view need to know about it, as one JSON object:
#
#   session, id   the two arguments, as given
#   status        koto's: in-effect, reversed or refused
#   decider       {kind} plus, for a session decider, its `session`, and for
#                 a person, the `entering` session and the `surface`
#                 (terminal, forge or relay)
#   time          the decision's time, as koto recorded it
#   bound         whether the entering session was bound when the decision
#                 was entered: the decision's frozen chain names a session
#                 holding a coordinator record (record/meta) that isn't an
#                 earlier member of the entering session's run, or the
#                 entering session's Run section holds a `reports-to` row
#   bound_by      {sessions: the chain sessions that made it bound,
#                 reports_to: the reports-to row's value, or null}
#   reversal      null, or for a reversed decision the winning reversal's
#                 {session, id, time, decider, standing, hop, fence}: `hop` is
#                 whether its standing path holds a supersede step, and
#                 `fence` lists each such step as {session, to, successor_id,
#                 actor, time}
#   quoted        the text koto hands on from a person or an agent:
#                 {subject, reason, link, handle, reversal_reason}, each string
#                 cut to 200 characters with control characters stripped
#
# "An earlier member of the entering session's run": a chain session whose
# supersede marker, followed forward (at most 64 hops), reaches the entering
# session, the last hop's successor id being the entering session's id as the
# decision records it. A walk koto can't confirm stops there, and the session
# then counts toward bound.
#
# Every koto call is a read: `decisions show`, `decisions chain`, `context
# exists`, and the Run section's read, which goes through state-read.sh's
# rs_key (a `context list`, then `context get` when the key is there), since
# only the state seam reads a record's keys. They share one 5-second
# deadline, kept with reconcile-deps.sh's rd_deadline since macOS has no
# timeout(1). koto is ${KOTO_BIN:-koto}.
#
# Usage:
#   standing-provenance.sh <session> <id>
#
# Exit codes: 0 with the object printed, and that includes every failure to
# read: an argument outside the session-name or id grammar (no koto call is
# made), a koto call that exits non-zero or passes the deadline, a body that
# doesn't parse, lacks a status or reads koto's own `unreadable`, prints
# {session, id, status: "unreadable", why}, since unreadable is an answer,
# not an error. 64 for a wrong argument count.
#
# stdout is the answer alone. stderr carries koto's and jq's own diagnostics,
# untouched, for whoever reads it.
#
# Requires: bash 3.2+, jq, koto, mkfifo, pkill.
set -uo pipefail
PROG=standing-provenance

if [ "$#" -ne 2 ]; then
    echo "usage: $PROG <session> <id>" >&2
    exit 64
fi
SESSION=$1
ID=$2
DEADLINE=5
RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
RE_ID='^[0-9]{12}$'

# unreadable WHY -- print the unreadable answer and stop, exit 0.
unreadable() {
    if command -v jq > /dev/null; then
        jq -nc --arg s "$SESSION" --arg i "$ID" --arg w "$1" '
            def clean: explode | map(select(. >= 32 and (. < 127 or . > 159))) | implode | .[0:200];
            {session: ($s | clean), id: ($i | clean), status: "unreadable", why: $w}'
    else
        printf '%s\n' '{"session":null,"id":null,"status":"unreadable","why":"no jq"}'
    fi
    exit 0
}

[[ $SESSION =~ $RE_SESSION ]] || unreadable "the session is not a koto session name"
[[ $ID =~ $RE_ID ]] || unreadable "the id is not 12 digits"
command -v jq > /dev/null || unreadable "no jq"

HERE=$(cd "$(dirname "$0")" && pwd) || unreadable "the script's directory can't be read"
# shellcheck source=/dev/null
. "$HERE/reconcile-deps.sh" || unreadable "reconcile-deps.sh can't be loaded"
# shellcheck source=/dev/null
. "$HERE/state-read.sh" || unreadable "state-read.sh can't be loaded"

K=${KOTO_BIN:-koto}
D=$(mktemp -d "${TMPDIR:-/tmp}/standing-provenance.XXXXXX") || unreadable "no temporary directory could be made"
trap 'rm -rf "$D"' EXIT
rd_idle "$D" || unreadable "no deadline could be set"
SECONDS=0

# kread OUT ARGS... -- koto ARGS, its stdout in OUT, under what is left of the
# deadline. Returns koto's status, 124 past the deadline.
kread() {
    local out=$1 left
    shift
    left=$((DEADLINE - SECONDS))
    [ "$left" -ge 1 ] || return 124
    rd_deadline "$left" "$K" "$@" > "$out" < /dev/null
}

# kfail RC WHAT -- the unreadable answer for a koto read that failed.
kfail() {
    [ "$1" = 124 ] && unreadable "koto did not answer within ${DEADLINE}s ($2)"
    unreadable "koto exited $1 ($2)"
}

# ---- the decision ------------------------------------------------------------
kread "$D/show" decisions show "$SESSION" "$ID"
rc=$?
[ "$rc" = 0 ] || kfail "$rc" "decisions show"
jq -e 'type == "object"' "$D/show" > /dev/null || unreadable "decisions show printed no JSON object"
STATUS=$(jq -r '.status | if type == "string" then . else "" end' "$D/show")
case "$STATUS" in
    in-effect|reversed|refused) ;;
    "") unreadable "decisions show printed no status" ;;
    unreadable) unreadable "koto reads the decision as unreadable" ;;
    *) unreadable "decisions show printed a status this reader doesn't know" ;;
esac
jq -e --arg s "$SESSION" --arg i "$ID" '.session == $s and .id == $i and (.decision | type == "object")' \
    "$D/show" > /dev/null || unreadable "decisions show answered for another decision, or with no decision body"
if [ "$STATUS" = reversed ]; then
    jq -e '.reversed_by | type == "object" and (.session | type == "string") and (.id | type == "string")
        and ((.path // []) | type == "array")' "$D/show" > /dev/null \
        || unreadable "a reversed decision with no readable reversal"
fi
# The id koto recorded for the entering session, the last hop of an
# earlier-member walk must name.
SESSION_UUID=$(jq -r '.decision.session.id | if type == "string" then . else "" end' "$D/show")

# ---- bound: the frozen chain -------------------------------------------------
# earlier_member X -- 0 when X's supersede marker, followed forward, reaches
# this session with the successor id the decision records for it; 1 when it
# doesn't or a hop can't be confirmed; 2 when a read failed (KRC holds why).
KRC=
earlier_member() {
    local cur=$1 n=0 nm sid rc
    while [ "$n" -lt 64 ]; do
        n=$((n + 1))
        kread "$D/chain" decisions chain "$cur"
        rc=$?
        [ "$rc" = 0 ] || { KRC=$rc; return 2; }
        nm=$(jq -r --arg c "$cur" 'select(.session == $c) | .marker.successor.name | if type == "string" then . else "" end' "$D/chain")
        sid=$(jq -r '.marker.successor.id | if type == "string" then . else "" end' "$D/chain")
        [ -n "$nm" ] && [[ $nm =~ $RE_SESSION ]] || return 1
        if [ "$nm" = "$SESSION" ]; then
            [ -n "$SESSION_UUID" ] && [ "$sid" = "$SESSION_UUID" ] && return 0
            return 1
        fi
        cur=$nm
    done
    return 1
}

jq -r '.decision.chain.links // [] | if type == "array" then .[] | .session else error end' "$D/show" > "$D/links" \
    || unreadable "the decision's chain can't be read"
BOUND_SESSIONS=()
SEEN=" "
while IFS= read -r x; do
    [[ $x =~ $RE_SESSION ]] || unreadable "the decision's chain names something that isn't a session name"
    case "$SEEN" in *" $x "*) continue ;; esac
    SEEN="$SEEN$x "
    [ "$x" = "$SESSION" ] && continue
    kread "$D/exists" context exists "$x" record/meta
    rc=$?
    case "$rc" in
        0) ;;
        1) continue ;;
        *) kfail "$rc" "context exists record/meta" ;;
    esac
    earlier_member "$x"
    case "$?" in
        0) continue ;;
        1) BOUND_SESSIONS+=("$x") ;;
        *) kfail "$KRC" "decisions chain" ;;
    esac
done < "$D/links"

# ---- bound: the Run section's reports-to row ---------------------------------
# rs_key, the seam's key read: 0 read, 1 the key is absent, 2 a read failed.
: > "$D/run"
left=$((DEADLINE - SECONDS))
if [ "$left" -ge 1 ]; then
    rd_deadline "$left" rs_key "$SESSION" record/run "$D/run" > /dev/null < /dev/null
    rc=$?
else
    rc=124
fi
case "$rc" in
    0) jq -e 'type == "array"' "$D/run" > /dev/null || unreadable "the Run section is not a list of rows" ;;
    1) echo '[]' > "$D/run" ;;
    124) kfail 124 "the Run section's read" ;;
    *) unreadable "the Run section could not be read" ;;
esac

# ---- the answer --------------------------------------------------------------
if [ "${#BOUND_SESSIONS[@]}" -gt 0 ]; then
    printf '%s\n' "${BOUND_SESSIONS[@]}" > "$D/bound"
else
    : > "$D/bound"
fi
jq -c --slurpfile run "$D/run" --rawfile bound "$D/bound" '
    def clean: if type == "string" then explode | map(select(. >= 32 and (. < 127 or . > 159))) | implode | .[0:200] else null end;
    def str: if type == "string" then . else null end;
    def decider:
        if type != "object" then {kind: null}
        elif .kind == "session" then {kind: "session", session: (.session.value | clean)}
        elif .kind == "person" then {kind: "person", entering: (.entering.session.value | clean),
            surface: (.surface | if . == "terminal" or . == "forge" or . == "relay" then . else null end)}
        else {kind: (.kind | clean)} end;
    ($bound | split("\n") | map(select(length > 0))) as $bs
    | ([$run[0][]? | select(type == "object" and .key == "reports-to")][0] // null) as $rt
    | .decision as $d
    | {
        session, id, status,
        decider: ($d.decider | decider),
        time: ($d.time | str),
        bound: (($bs | length) > 0 or $rt != null),
        bound_by: {sessions: $bs, reports_to: (if $rt == null then null else ($rt.value | clean) end)},
        reversal: (if .status != "reversed" then null else
            .reversed_by as $r
            | ([($r.path // [])[] | select(type == "object" and .via == "supersede")]) as $f
            | {session: $r.session, id: $r.id, time: ($r.time | str),
               decider: ($r.decider | decider), standing: ($r.standing | clean),
               hop: (($f | length) > 0),
               fence: [$f[] | {session: (.session | clean), to: (.to | clean),
                   successor_id: (.successor_id | clean),
                   actor: (.actor | if type == "object" then map_values(clean) else null end),
                   time: (.time | str)}]}
            end),
        quoted: {
            subject: ($d.subject | if type == "object"
                then with_entries(.key |= clean | .value |= (if type == "array" then map(clean) else clean end))
                else null end),
            reason: ($d.reason | clean),
            link: ($d.decider.link | clean),
            handle: ($d.decider.handle.value | clean),
            reversal_reason: (if .status == "reversed" then (.reversed_by.reason | clean) else null end)
        }
    }' "$D/show" > "$D/out" || unreadable "the decision's facts can't be put together"
cat "$D/out"
