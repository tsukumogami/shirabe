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
# A holding a pause in the record holds (pause-read.sh over the record's
# Standing rows, read through state-stored-set.sh --list) is passed over: its leg
# stays unread and untaken, so nothing consumes a result whose follow-on the
# pause would refuse, and a `leg` tick after the resume offers it
# (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1). wait_target
# names the topics passed over as `passed_over`.
#
# A leg is read once. A leg's result can't change after it resolves, and the
# holding keeps naming the leg until the record drops the row, so a leg
# whose result the wait state has taken is kept in the context key
# `taken_legs` and never picked again; otherwise a report that routes to a
# fix or to the surface step would bring the same result back on the next
# pass. A worker re-briefed after a fix reports by message from then on
# (dispatch-worker.sh --rebrief moves its holding to the message path).
#
# Each worker leg is also a key of this session, legs/<request>/<leg>
# (dispatch-worker.sh writes it, dispatch-common.sh dc_leg_*), so a move to
# another host carries what a re-leg needs (PRD R13). Whenever select reads a
# request whose leg a session is bound to, it records that child's name in
# the leg's key, once: the context key `leg_children` lists the legs already
# recorded, so a later tick reads one key rather than every leg's. When a leg
# is no longer open, the leg mode (and select's mark of a consumed leg) writes
# its state before take_report classifies anything: `taken` with koto's result
# for a resolved leg, `spent` for an abandoned or missing one. A leg opened
# before leg keys existed gets its key there, with the topic and the result.
#
# A waiting run is not a result to take. A leg resolved with a result the
# worker's session promoted whose payload carries `question` (a worker that
# raised a question and stopped at its waiting terminal) names one question
# identity (<raiser session id>/<decision id>), or several separated by
# spaces, and each is read through `koto decisions history <identity>`.
# While koto reads every one of them open, the unit waits: select passes the
# leg over, takes nothing and marks nothing, so no report, redo or failure
# follows from it, and wait_target names it under `waiting` as {topic,
# request, leg, question}. A history koto can't read counts as open, with
# the failure on stderr: it is never read as an answer. Once koto reads any
# of them closed, the leg is offered like any resolved one, with disposition
# `answered` and the closed identities in wait_target's `question`; its
# report goes on to classification, and the unit's re-dispatch under a new
# leg is dispatch-worker.sh --rebrief's, which names the answered questions
# in the brief. A waiting result the wait_leg gate took while its questions
# were all still open (the leg resolved between two ticks) isn't marked
# taken, so it comes back as `answered` once one closes. A `question` that
# isn't identities is no question koto can read: the leg is taken as any
# resolved one, and stderr says so.
#
# Modes:
#
#   select --session <s>
#       Writes wait_target as {"path":"leg","topic","request","leg",
#       "disposition","passed_over","waiting"} (with "question" when the
#       disposition is `answered`) or {"path":"none","passed_over","waiting"}
#       and prints the request id or
#       `none`, whenever the record can be read. It always prints
#       a token: an empty capture would fail the action instead of letting the
#       state stop for evidence, which is the wait.
#
#       koto 0.14.0 records a wake on a resolved leg (koto#250), but this
#       workflow doesn't watch for it yet; the
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
# Reads the record, the request store and, for a waiting result, koto's
# history of the question it names; writes only this session's
# wait_target, taken_legs, leg_consumed, leg_children and report_topic context
# keys and its legs/ keys. bash 3.2; needs jq.
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
# One record read for select: the holdings and the Standing pauses come from
# one read of the sections the two listers print (state-read.sh
# rs_once_begin; shirabe#1315), which every script run below inherits.
if [ "$MODE" = select ]; then
    mkdir -p "$WORK/once" || exit 2
    export RS_ONCE="$WORK/once" RS_ONCE_FIELDS="holdings run standing work"
fi

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

# A waiting result's `question`: one question identity (<raiser session
# id>/<decision id>, the grammar shirabe question reads), or several
# separated by single spaces, as /execute names every question it waits on.
RE_QUESTIONS='^[0-9A-Za-z][0-9A-Za-z-]*/[0-9]+( [0-9A-Za-z][0-9A-Za-z-]*/[0-9]+)*$'

# leg_question <view> <leg>: the `question` a promoted result's payload names,
# or nothing for any other leg or a payload with none.
leg_question() {
    jq -r --arg l "$2" '(.request // .) | (.legs[$l] // {})
        | select(.disposition == "resolved" and .result_source == "promoted")
        | (.result.payload // {}) | if type == "object" then (.question // "") else "" end | strings' <<<"$1"
}

# closed_questions <questions>: those of the space-separated identities koto
# decisions history reads closed, space-separated, or nothing. One whose
# history can't be read, or says neither open nor closed, counts as open,
# with the failure on stderr: it is never read as answered.
closed_questions() {
    local q h st out=""
    for q in $1; do
        if ! h=$("$KOTO" decisions history "$q" </dev/null); then
            printf '%s: cannot read the history of question %s; it counts as open\n' "$PROG" "$q" >&2
            continue
        fi
        st=$(jq -r 'if .open == true then "open" elif .open == false then "closed" else "" end' <<<"$h") || st=""
        case "$st" in
            closed) out="${out:+$out }$q" ;;
            open) ;;
            *) printf '%s: the history of question %s says neither open nor closed; it counts as open\n' "$PROG" "$q" >&2 ;;
        esac
    done
    printf '%s\n' "$out"
}

# waiting_on <view> <leg> <where>: the questions a waiting leg is held on, or
# nothing when the leg holds no waiting result or one of its questions is
# closed. A value that isn't identities holds nothing (stderr says so).
waiting_on() {
    local q
    q=$(leg_question "$1" "$2")
    [ -n "$q" ] || return 0
    if ! grep -Eq "$RE_QUESTIONS" <<<"$q"; then
        printf '%s: %s names a question that is not an identity; its result is taken as any other\n' "$PROG" "$3" >&2
        return 0
    fi
    [ -n "$(closed_questions "$q")" ] || printf '%s\n' "$q"
    return 0
}

# leg_record <request> <leg> <topic> <view>: write the leg key's end from
# koto's view of the request: `taken` with the result for a result the
# worker's session promoted, `spent` otherwise. Only a key still `open` (or
# none yet) is written; one already marked keeps its state. Returns 2 when the
# key can't be read or written.
leg_record() {
    local req=$1 leg=$2 topic=$3 view=$4 key end
    end=$(jq -c --arg l "$leg" '(.request // .) as $r | ($r.legs[$l] // null) as $g
        | def res: if $g.result == null then null
            else {status: $g.result.status, final_state: $g.result_final_state, source: $g.result_source,
                  payload: ($g.result.payload | if type == "object" then . else {} end)} end;
        if $g != null and $g.disposition == "resolved" and $g.result_source == "promoted" then {state: "taken", result: res}
        elif $g == null then {state: "spent", result: null}
        else {state: "spent", result: res} end' <<<"$view") || return 2
    key=$(dc_leg_get "$SESSION" "$req" "$leg")
    case "$?" in
        0) [ "$(jq -r '.state // ""' <<<"$key")" = open ] || return 0 ;;
        1) key=$(jq -nc --arg r "$req" --arg l "$leg" --arg t "$topic" '{request: $r, leg: $l, topic: $t, state: "open"}') ;;
        *) printf '%s: cannot read the leg key for %s:%s\n' "$PROG" "$req" "$leg" >&2; return 2 ;;
    esac
    dc_leg_put "$SESSION" "$req" "$leg" "$(jq -c --argjson e "$end" '. + $e' <<<"$key")" ||
        { printf '%s: cannot write the leg key for %s:%s\n' "$PROG" "$req" "$leg" >&2; return 2; }
}

# mark_if_done <wait_target json>: add its leg to taken_legs, and write its
# leg key's end, when koto no longer shows it open. Returns 2 when the target,
# koto or the key can't be read.
mark_if_done() {
    local t="$1" req leg view disp taken
    req=$(printf '%s' "$t" | jq -r '.request // "" | strings')
    leg=$(printf '%s' "$t" | jq -r '.leg // "" | strings')
    grep -Eq "$RE_REQ" <<<"$req" || { printf '%s: wait_target holds a malformed request\n' "$PROG" >&2; return 2; }
    grep -Eq "$RE_LEG" <<<"$leg" || { printf '%s: wait_target holds a malformed leg\n' "$PROG" >&2; return 2; }
    view=$("$KOTO" request get "$req" </dev/null) || { printf '%s: cannot read request %s\n' "$PROG" "$req" >&2; return 2; }
    disp=$(printf '%s' "$view" | jq -r --arg l "$leg" "$LEG_DISP")
    [ "$disp" = open ] && return 0
    leg_record "$req" "$leg" "$(jq -r '.topic // "" | strings' <<<"$t")" "$view" || return 2
    # A waiting result whose question is still open comes back once it closes.
    [ -n "$(waiting_on "$view" "$leg" "$req:$leg")" ] && return 0
    taken=$(ctx_or_empty taken_legs) || return 2
    put taken_legs "$(printf '%s\n%s\n' "$taken" "$req:$leg" | sed '/^$/d' | sort -u)"
}

# --- leg -----------------------------------------------------------------------------

if [ "$MODE" = leg ]; then
    T=$("$KOTO" context get "$SESSION" wait_target) || { printf '%s: cannot read wait_target\n' "$PROG" >&2; exit 2; }
    LEG=$(printf '%s' "$T" | jq -r 'select(.path == "leg") | .leg // "" | strings')
    TOPIC=$(printf '%s' "$T" | jq -r 'select(.path == "leg") | .topic // "" | strings')
    [ -n "$LEG" ] || { printf '%s: wait_target names no leg\n' "$PROG" >&2; exit 1; }
    grep -Eq "$RE_LEG" <<<"$LEG" || { printf '%s: wait_target holds a malformed leg\n' "$PROG" >&2; exit 2; }
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

# paused_topics <rows-json>: the Workers of the holdings a pause holds, one
# per line, into $WORK/paused. Returns 2 when the pauses can't be read.
paused_topics() {
    : >"$WORK/paused"
    bash "$DC_RECORD_STATE" --list --session "$SESSION" >"$WORK/state.json" 2>"$WORK/state.err" || {
        sed 's/^/  /' "$WORK/state.err" | head -n 3 >&2
        return 2
    }
    jq -e '[(.standing // [])[] | select(.kind == "pause")] | length > 0' "$WORK/state.json" >/dev/null
    case $? in 0) ;; 1) return 0 ;; *) return 2 ;; esac
    printf '%s' "$1" | jq -c '[.[].unit // empty]' >"$WORK/units.json" || return 2
    bash "$DC_HERE/pause-read.sh" --standing "$WORK/state.json" --units "$WORK/units.json" >"$WORK/pauses.json" || return 2
    printf '%s' "$1" | jq -r --slurpfile p "$WORK/pauses.json" '.[] | select(.unit != null and $p[0].covers[.unit] != null) | .worker' >"$WORK/paused" || return 2
}

# candidates: one "<disposition><TAB><topic><TAB><request><TAB><leg><TAB><questions>"
# line per leg-bound, dispatched holding, in record order, a paused holding's
# left out. A resolved leg holding a waiting result reads `waiting`, with the
# questions it names, while koto reads every one of them open (or can't read
# its history), and `answered`, with the closed ones, once any is closed;
# every other line's last field is empty.
candidates() {
    local rows rc
    rows=$(dc_record_list "$SESSION")
    rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    paused_topics "$rows" || { printf '%s: the record'"'"'s pauses could not be read\n' "$PROG" >&2; return 2; }
    local topic rp req leg view disp taken children child added="" q closed
    taken=$(ctx_or_empty taken_legs) || return 2
    children=$(ctx_or_empty leg_children) || return 2
    while IFS='	' read -r topic rp; do
        [ -n "$topic" ] || continue
        grep -Fqx -- "$topic" "$WORK/paused" && continue
        req=${rp%%:*}
        leg=${rp#*:}
        grep -Eq "$RE_REQ" <<<"$req" || continue
        grep -Eq "$RE_LEG" <<<"$leg" || continue
        dc_valid_topic "$topic" || continue
        grep -Fqx -- "$rp" <<<"$taken" && continue
        if view=$("$KOTO" request get "$req" </dev/null); then
            disp=$(printf '%s' "$view" | jq -r --arg l "$leg" "$LEG_DISP")
        else
            # A request koto can't read is left for the next tick rather than
            # routed as missing: one failed read says nothing about the leg.
            printf '%s: could not read request %s for %s\n' "$PROG" "$req" "$topic" >&2
            continue
        fi
        # The bound child's name, recorded once in the leg's key. A failed
        # write is left for the next tick: it costs no watch.
        child=$(jq -r --arg l "$leg" '(.request // .) | .legs[$l].bound_child // "" | strings' <<<"$view")
        if [ -n "$child" ] && ! grep -Fqx -- "$rp" <<<"$children"; then
            record_child "$req" "$leg" "$child" && added="$added$rp
"
        fi
        q=""
        if [ "$disp" = resolved ]; then
            q=$(leg_question "$view" "$leg")
            if [ -n "$q" ] && grep -Eq "$RE_QUESTIONS" <<<"$q"; then
                closed=$(closed_questions "$q")
                if [ -z "$closed" ]; then disp=waiting; else disp=answered q=$closed; fi
            elif [ -n "$q" ]; then
                printf '%s: %s names a question that is not an identity; its result is taken as any other\n' "$PROG" "$rp" >&2
                q=""
            fi
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$disp" "$topic" "$req" "$leg" "$q"
    done <<EOF
$(printf '%s' "$rows" | jq -r '.[] | select(.dispatch_status == "dispatched") | select((.return_path // "") | test("^leg [^: ]+:[^: ]+$")) | [.worker, (.return_path | ltrimstr("leg "))] | @tsv')
EOF
    if [ -n "$added" ]; then
        printf '%s\n%s' "$children" "$added" | sed '/^$/d' | sort -u >"$WORK/children"
        "$KOTO" context add "$SESSION" leg_children --from-file "$WORK/children" >/dev/null ||
            printf '%s: cannot write leg_children\n' "$PROG" >&2
    fi
}

# record_child <request> <leg> <child>: write the bound child's session name
# into the leg's key when it names another or none. A leg with no key (opened
# before leg keys existed) has nothing to record into, which counts as done.
# Returns 1 when the key can't be read or written.
record_child() {
    local key
    key=$(dc_leg_get "$SESSION" "$1" "$2")
    case "$?" in
        0) ;;
        1) return 0 ;;
        *) printf '%s: cannot read the leg key for %s:%s\n' "$PROG" "$1" "$2" >&2; return 1 ;;
    esac
    [ "$(dc_leg_field "$key" child)" = "$3" ] && return 0
    { key=$(dc_leg_field "$key" child "$3") && dc_leg_put "$SESSION" "$1" "$2" "$key"; } ||
        { printf '%s: cannot record the child of %s:%s\n' "$PROG" "$1" "$2" >&2; return 1; }
}

pick() {
    local list
    list=$(candidates)
    local rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    # A leg waiting on an open question is never picked; it is listed.
    printf '%s\n' "$list" | awk -F'\t' '$1 == "waiting" { print }' >"$WORK/waiting"
    # Anything not open first (its result, or its abandonment, is waiting),
    # then the oldest open one.
    printf '%s\n' "$list" | awk -F'\t' '$1 != "" && $1 != "open" && $1 != "waiting" { print; exit }' >"$WORK/pick"
    if [ ! -s "$WORK/pick" ]; then
        printf '%s\n' "$list" | awk -F'\t' '$1 == "open" { print; exit }' >"$WORK/pick"
    fi
    cat "$WORK/pick"
}

: >"$WORK/paused"
: >"$WORK/waiting"
LINE=$(pick)
RC=$?
[ "$RC" -eq 0 ] || { printf '%s: the record could not be read\n' "$PROG" >&2; exit "$RC"; }

# The topics passed over go to jq from a file, not argv: nothing caps how many
# holdings a pause holds, and one argument may hold only 128 KiB on Linux.
PASSED="$WORK/passed.json"
jq -R -s -c 'split("\n") | map(select(. != ""))' "$WORK/paused" > "$PASSED" || { printf '%s: cannot read the topics passed over\n' "$PROG" >&2; exit 2; }
# The legs held on an open question, from a file for the same reason.
WAITING="$WORK/waiting.json"
jq -R -s -c 'split("\n") | map(select(. != "") | split("\t") | {topic: .[1], request: .[2], leg: .[3], question: .[4]})' "$WORK/waiting" > "$WAITING" ||
    { printf '%s: cannot read the legs waiting on a question\n' "$PROG" >&2; exit 2; }
if [ -z "$LINE" ]; then
    put wait_target "$(jq -nc --slurpfile p "$PASSED" --slurpfile w "$WAITING" '{path: "none", passed_over: $p[0], waiting: $w[0]}')"
    printf 'none\n'
    exit 0
fi

IFS='	' read -r DISP TOPIC REQ LEG QUESTION <<EOF
$LINE
EOF
put wait_target "$(jq -nc --arg t "$TOPIC" --arg r "$REQ" --arg l "$LEG" --arg d "$DISP" --arg q "$QUESTION" --slurpfile p "$PASSED" --slurpfile w "$WAITING" \
    '{path: "leg", topic: $t, request: $r, leg: $l, disposition: $d, passed_over: $p[0], waiting: $w[0]}
     + (if $d == "answered" then {question: $q} else {} end)')"
printf '%s\n' "$REQ"
