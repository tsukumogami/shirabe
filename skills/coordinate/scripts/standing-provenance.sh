#!/usr/bin/env bash
# standing-provenance.sh -- the facts of one cited koto decision, read and
# never written (docs/designs/DESIGN-coordinator-standing-rule-provenance.md,
# as amended by docs/designs/DESIGN-decision-escalation-ladder.md).
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
#   reading       koto's `reading` of the decision, as `decisions show`
#                 prints it: `verified` for a person's answer to a prompt this
#                 host checked, `a remote session's answer` for one read from
#                 a store that didn't check it, null for a decision with no
#                 prompt behind it (a session's decision, a person judgment)
#   question      for an `answer`, the identity of the question it answers
#                 (`<raiser's session id>/<decision id>`, from koto's target),
#                 else null
#   standing      true only for an `answer` by person:owner whose question's
#                 stored content carries the standing mark on the question or
#                 on the option the answer chose (its text equal to that
#                 option's label); false for anything else
#   reversal      null, or for a reversed decision the winning reversal's
#                 {session, id, time, decider, standing, hop, fence}: `hop` is
#                 whether its standing path holds a supersede step, and
#                 `fence` lists each such step as {session, to, successor_id,
#                 actor, time}
#   quoted        the text koto hands on from a person or an agent:
#                 {subject, reason, link, handle, reversal_reason}, each string
#                 cut to 200 characters with control characters stripped
#
# It checks nothing itself. Whether a person's answer was given through a
# prompt the owner answered is koto's reading, and the mark is what the
# question's raiser stored; rule_class decides a row's class from `reading`
# and `standing` alone. Where the decision was entered, and whether the
# entering session had a dispatcher, isn't read: being the top coordinator
# makes no decision the owner's.
#
# Every koto call is a read: `decisions show <session> <id>`, then, for an
# answer by person:owner, `decisions content read <identity>`. Neither opens
# the harness record a prompt answer was checked against. They share one
# 5-second deadline, kept with reconcile-deps.sh's rd_deadline since macOS
# has no timeout(1). koto is ${KOTO_BIN:-koto}.
#
# Usage:
#   standing-provenance.sh <session> <id>
#
# Exit codes: 0 with the object printed, and that includes every failure to
# read: an argument outside the session-name or id grammar (no koto call is
# made), a koto call that exits non-zero or passes the deadline, a body that
# doesn't parse, lacks a status or reads koto's own `unreadable`, and an owner's
# answer whose question's content can't be read or isn't a JSON object, prints
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
RE_IDENTITY='^[A-Za-z0-9][A-Za-z0-9._-]{0,127}/[0-9]{12}$'

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

# ---- the question an owner's answer answers ----------------------------------
# Only an answer by person:owner is looked up: no other decision answers a
# question the owner was asked, so no other can carry the owner's mark.
QUESTION=
if jq -e '.decision | .kind == "answer" and .decider.kind == "person" and .decider.handle.value == "owner"' \
        "$D/show" > /dev/null; then
    QUESTION=$(jq -r '.decision.target | if type == "object" and (.id | type == "string") and (.decision | type == "string")
        then "\(.id)/\(.decision)" else "" end' "$D/show")
    [[ $QUESTION =~ $RE_IDENTITY ]] || unreadable "the owner's answer names no question koto's identity grammar holds"
    kread "$D/content" decisions content read "$QUESTION"
    rc=$?
    [ "$rc" = 0 ] || kfail "$rc" "decisions content read"
    jq -e 'type == "object"' "$D/content" > /dev/null || unreadable "the question's content is not a JSON object"
else
    echo null > "$D/content"
fi

# ---- the answer --------------------------------------------------------------
jq -c --slurpfile content "$D/content" --arg q "$QUESTION" '
    def clean: if type == "string" then explode | map(select(. >= 32 and (. < 127 or . > 159))) | implode | .[0:200] else null end;
    def str: if type == "string" then . else null end;
    def decider:
        if type != "object" then {kind: null}
        elif .kind == "session" then {kind: "session", session: (.session.value | clean)}
        elif .kind == "person" then {kind: "person", entering: (.entering.session.value | clean),
            surface: (.surface | if . == "terminal" or . == "forge" or . == "relay" then . else null end)}
        else {kind: (.kind | clean)} end;
    .decision as $d
    | $content[0] as $c
    | ($d.subject.text // null) as $chosen
    | {
        session, id, status,
        decider: ($d.decider | decider),
        time: ($d.time | str),
        reading: ((.reading // $d.reading) | clean),
        question: (if $q == "" then null else $q end),
        standing: ($c != null and (($c.standing == true)
            or any(($c.options // [])[]?; type == "object" and .standing == true
                and ($chosen | type) == "string" and .label == $chosen))),
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
