#!/usr/bin/env bash
# alignment-call.sh -- a director's alignment call on a lane pull request, and
# the manager's copy of the hold a `diverges` call places. Agent-run; it
# writes only through state-entry.sh, state-hold.sh and state-stored-set.sh
# (docs/designs/DESIGN-director-alignment-review.md, Decision 1 and Key
# Interfaces).
#
# Usage:
#   alignment-call.sh --session S --on <owner/repo#n> --text-file F [--receiver ADDR]
#   alignment-call.sh --session S --copy --add --message-file F --event N --from ADDR
#   alignment-call.sh --session S --copy --reports-to --message-file F --event N --from ADDR
#
# The session gives the scope, name and host (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts).
#
# The call (the director's record). F is the seven-line `alignment` entry
# (references/state-keys.md, Entries), written with state-entry.sh --kind
# alignment --on, which checks it and refuses a malformed one (65) before
# anything is written. A `diverges` call places a hold when no unlifted
# `align-` hold on the pull request stands in this record and the pull
# request hasn't merged:
#
#   {"hold": "align-<repo name>-<n>-<40-hex placed-on head>[-<k>]",
#    "on": "<owner/repo#n>", "until": "lifted",
#    "set_by": "director at <address>, receiver manager at <address>",
#    "set": "<YYYY-MM-DDTHH:MMZ>", "lifted": ""}
#
# added through state-hold.sh --add. The placed-on head is the call's head;
# `-<k>` (from 2) is added only when a lifted hold already has the name. The
# director's address is the record's Run `coordinator` row; the receiver is
# the Worker of the Holdings row whose Pull request links the pull request,
# or --receiver. Both, and the pull request's state, are read before the
# entry is written, so a call that can't place its hold writes nothing (65
# with no address or receiver, 2 when the state can't be read). A second
# `diverges` call while a director's hold stands, and one on a merged pull
# request, write the entry and place nothing (R7, R9). A `fits` or `fits with
# follow-ups` call writes the entry and nothing else.
#
# When it places a hold it prints the message to send the manager, and
# nothing else, on stdout; what it wrote goes to stderr:
#
#   Alignment hold: <owner/repo#n> at <40-hex placed-on head>
#   Row: <the hold row, one line of JSON>
#   Sources: <the call's Sources>
#   Reason: <the call's Reason>
#   Receiver: manager at <address>
#   Release: a new head that the director re-reads and calls fits or fits with follow-ups
#
# The copy (the manager's record), run on a director-hold message. Both modes
# need the record's Run `reports-to` row to hold an address (`<name> at
# <address>`); a message sent to a row with none changes nothing (65). For
# --copy --add the sender, --from, must be that address. --copy --reports-to
# is the one exception: its sender is a successor, never the row's address
# yet, so it checks instead that the message names the row's address as the
# current one (below). --event is the log sequence of the event the message
# arrived on, named in the entry each mode writes.
#
# --copy --add takes the hold message above. It refuses (65, nothing changed)
# a message that isn't those six lines in that order, whose head isn't 40
# hex, whose row isn't a hold row with exactly those keys, `until` lifted and
# Lifted empty, whose hold name isn't `align-<repo name>-<n>-<that head>[-<k>]`
# for the pull request the first line names, or whose Set by doesn't name the
# sender as director. It adds the identical row through state-hold.sh --add
# and writes a `hold` entry naming the event, the sender, the Sources, the
# Reason and the release. A row of that name already in the record, identical,
# changes nothing (exit 0); a different one is refused (65).
#
# --copy --reports-to takes a successor's address message, one line:
#
#   Director address: <current address> is now <new address>
#
# The current address must be the row's and the new one --from. It rewrites
# the row to `<name> at <new address>` through state-stored-set.sh --run
# reports-to, --by `director at <new address>`, and writes a `hold` entry
# naming the event and both addresses, so the successor's hold message is
# accepted from then on. Any other current address changes nothing (65).
#
# Exit codes: 0 written (or nothing to write); 2 a read failed; 10 refused
# (no found record); 11 a write failed (what was written is on stderr); 14
# the entry or hold was written but the account entry after it wasn't; 64
# usage; 65 refused (the reason on stderr); any other code is the writer's
# own, passed on.
#
# GitHub calls: gh pr view <n> --repo <owner/repo> --json state (a diverges
# call that may place a hold), and those of the writers it runs.
set -uo pipefail

PROG=alignment-call
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= ON= TEXTFILE= RECEIVER= MODE=call COPY= MSGFILE= EVENT= FROM=

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --on) [ $# -ge 2 ] || usage; ON=$2; shift 2 ;;
        --text-file) [ $# -ge 2 ] || usage; TEXTFILE=$2; shift 2 ;;
        --receiver) [ $# -ge 2 ] || usage; RECEIVER=$2; shift 2 ;;
        --copy) MODE=copy; shift ;;
        --add) [ -z "$COPY" ] || usage; COPY=add; shift ;;
        --reports-to) [ -z "$COPY" ] || usage; COPY=reports-to; shift ;;
        --message-file) [ $# -ge 2 ] || usage; MSGFILE=$2; shift 2 ;;
        --event) [ $# -ge 2 ] || usage; EVENT=$2; shift 2 ;;
        --from) [ $# -ge 2 ] || usage; FROM=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
RE_PR_REF='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$'
# A messaging address: the Worker cell's shape (state-schema.jq's check_worker).
RE_ADDR='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_SHA40='^[0-9a-f]{40}$'
RELEASE='a new head that the director re-reads and calls fits or fits with follow-ups'
if [ "$MODE" = call ]; then
    [ -z "$COPY$MSGFILE$EVENT$FROM" ] && [ -r "$TEXTFILE" ] || usage
    [[ $ON =~ $RE_PR_REF ]] || { echo "$PROG: --on is owner/repo#n" >&2; exit 64; }
    [ -z "$RECEIVER" ] || [[ $RECEIVER =~ $RE_ADDR ]] || { echo "$PROG: --receiver is a messaging address" >&2; exit 64; }
else
    [ -n "$COPY" ] && [ -z "$ON$TEXTFILE$RECEIVER" ] && [ -r "$MSGFILE" ] || usage
    [[ $EVENT =~ ^[1-9][0-9]*$ ]] || { echo "$PROG: --event is the event's log sequence, a number" >&2; exit 64; }
    [[ $FROM =~ $RE_ADDR ]] || { echo "$PROG: --from is the sender's messaging address" >&2; exit 64; }
fi

. "$HERE/state-common.sh"
lib_facts
lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/alignment-call.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT

lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
refuse() { echo "$PROG: refused: $1" >&2; exit 65; }
# read_record: the live record, as state-read.sh reads it, into $WD/rec.json.
read_record() {
    rs_record "$WD/rec.json"
    case $? in
        0) ;;
        65) echo "$PROG: refused: $(lib_record_name) doesn't read back as a $SCOPE record for $NAME:" >&2; lib_scrub < "$WD/rec.json.err" >&2; echo >&2; exit 10 ;;
        4) lib_scrub < "$WD/rec.json.err" >&2; exit 10 ;;
        *) lib_die2 "cannot read the record: $(lib_scrub < "$WD/rec.json.err" | head -1)" ;;
    esac
}
run_value() { jq -r --arg k "$1" '[(.run // [])[] | select(.key == $k) | .value][0] // ""' "$WD/rec.json"; }
# hold_entry <text>: a `hold` entry in this record's account.
hold_entry() {
    printf '%s\n' "$1" > "$WD/hold-entry"
    bash "$HERE/state-entry.sh" --session "$SESSION" --kind hold --text-file "$WD/hold-entry" > /dev/null \
        || { echo "$PROG: the record was changed, but its entry wasn't written; write it with state-entry.sh --kind hold: $1" >&2; exit 14; }
}
# reports_to_address: the address in the Run reports-to row, or a refusal.
reports_to_address() {
    local row
    row=$(run_value reports-to)
    [ -n "$row" ] || refuse "this record has no Run reports-to row, so no director's message is accepted; nothing changed"
    case "$row" in *" at "*) ;; *) refuse "this record's Run reports-to row ($row) holds no address, so no director's message is accepted; nothing changed" ;; esac
    RT_NAME=${row% at *} RT_ADDR=${row##* at }
}

# ---- the director's call ----------------------------------------------------
if [ "$MODE" = call ]; then
    ON_REPO=${ON%#*} ON_NUM=${ON##*#}
    tr -d '\r' < "$TEXTFILE" > "$WD/text"
    FIRST=$(grep -v '^[[:space:]]*$' "$WD/text" | head -1)
    CALL= HEAD=
    if [[ $FIRST =~ ^Alignment:\ [^\ ]+\ at\ ([0-9a-f]{40})\ --\ (.*)$ ]]; then
        HEAD=${BASH_REMATCH[1]} CALL=${BASH_REMATCH[2]}
    fi
    PLACE=0
    if [ "$CALL" = diverges ]; then
        read_record
        STANDING=$(jq -r --arg on "$(lc "$ON")" '[(.holds // [])[] | select((.hold | startswith("align-")) and (.on | ascii_downcase) == $on and .lifted == "") | .hold][0] // ""' "$WD/rec.json")
        if [ -n "$STANDING" ]; then
            echo "$PROG: $STANDING still stands on $ON, so this call places no second hold" >&2
        else
            STATE=$(gh pr view "$ON_NUM" --repo "$ON_REPO" --json state --jq .state 2> "$WD/gh.err" < /dev/null) \
                || lib_die2 "cannot read $ON's state, so whether it can be held isn't known; nothing written: $(lib_scrub < "$WD/gh.err")"
            case "$STATE" in
                MERGED) echo "$PROG: $ON has merged, and a merged pull request can't be held; the call is written, with no hold" >&2 ;;
                OPEN|CLOSED) PLACE=1 ;;
                *) lib_die2 "$ON's state reads [$STATE]; nothing written" ;;
            esac
        fi
        if [ "$PLACE" = 1 ]; then
            DIRECTOR=$(run_value coordinator)
            [ -n "$DIRECTOR" ] || refuse "the record has no Run coordinator row, the director's address a hold names; nothing written"
            if [ -z "$RECEIVER" ]; then
                RECEIVER=$(jq -r -L "$HERE" --arg r "$(lc "$ON_REPO")" --arg n "$ON_NUM" 'include "state-schema";
                    [(.holdings // [])[] | select(((.pull_request // "") | pr_link | (.repo | ascii_downcase) == $r and (.number | tostring) == $n)) | .worker][0] // ""' \
                    "$WD/rec.json") || lib_die2 "the record's holdings are not JSON"
            fi
            [ -n "$RECEIVER" ] || refuse "no Holdings row links $ON, so the manager the hold goes to isn't known; name it with --receiver; nothing written"
        fi
    fi

    KEY=$(bash "$HERE/state-entry.sh" --session "$SESSION" --kind alignment --on "$ON" --text-file "$WD/text")
    rc=$?
    [ $rc -eq 0 ] || exit $rc
    echo "$PROG: the call is written as $KEY" >&2
    [ "$PLACE" = 1 ] || exit 0

    BASE="align-${ON_REPO#*/}-$ON_NUM-$HEAD" H=$BASE k=1
    while jq -e --arg h "$H" 'any((.holds // [])[]; .hold == $h)' "$WD/rec.json" > /dev/null; do
        k=$((k + 1)) H="$BASE-$k"
    done
    jq -n -c --arg h "$H" --arg on "$ON" --arg b "director at $DIRECTOR, receiver manager at $RECEIVER" --arg s "$(date -u +%Y-%m-%dT%H:%MZ)" \
        '{hold: $h, on: $on, until: "lifted", set_by: $b, set: $s, lifted: ""}' > "$WD/row.json" || lib_die2 "jq failed"
    bash "$HERE/state-hold.sh" --session "$SESSION" --add --row-file "$WD/row.json" > /dev/null
    case $? in
        0) echo "$PROG: placed $H on $ON" >&2 ;;
        14) echo "$PROG: placed $H on $ON, but its hold entry wasn't written (above)" >&2 ;;
        *) echo "$PROG: the call is written as $KEY, but its hold wasn't placed; add it with state-hold.sh --add, the row: $(cat "$WD/row.json")" >&2; exit 11 ;;
    esac
    printf 'Alignment hold: %s at %s\n' "$ON" "$HEAD"
    printf 'Row: %s\n' "$(cat "$WD/row.json")"
    grep -m1 '^Sources: ' "$WD/text"
    grep -m1 '^Reason: ' "$WD/text"
    printf 'Receiver: manager at %s\nRelease: %s\n' "$RECEIVER" "$RELEASE"
    exit 0
fi

# ---- the manager's copy -----------------------------------------------------
read_record
reports_to_address
# A successor's address message comes from an address the row doesn't hold
# yet; that mode checks the current address the message names instead.
[ "$FROM" = "$RT_ADDR" ] || [ "$COPY" = reports-to ] \
    || refuse "the message is from $FROM, but this record reports to $RT_NAME at $RT_ADDR; nothing changed"
# The message as it arrived, line endings normalised and blank edge lines dropped.
tr -d '\r' < "$MSGFILE" | awk '{ l[NR] = $0 } END { s = 1; while (s <= NR && l[s] ~ /^[ \t]*$/) s++
    e = NR; while (e >= s && l[e] ~ /^[ \t]*$/) e--; for (i = s; i <= e; i++) print l[i] }' > "$WD/msg"
NLINES=$(awk 'END { print NR }' "$WD/msg")
line() { sed -n "${1}p" "$WD/msg"; }

if [ "$COPY" = reports-to ]; then
    [ "$NLINES" -eq 1 ] && [[ $(line 1) =~ ^Director\ address:\ ([^\ ]+)\ is\ now\ ([^\ ]+)$ ]] \
        || refuse "the message isn't one line, \`Director address: <current address> is now <new address>\`; nothing changed"
    OLD=${BASH_REMATCH[1]} NEW=${BASH_REMATCH[2]}
    [ "$OLD" = "$RT_ADDR" ] || refuse "the message names $OLD as the current address, but this record reports to $RT_NAME at $RT_ADDR; nothing changed"
    [ "$NEW" = "$FROM" ] || refuse "the message names $NEW as the new address, but it is from $FROM; nothing changed"
    [ "$NEW" != "$OLD" ] || refuse "the message names $OLD as both addresses; nothing changed"
    bash "$HERE/state-stored-set.sh" --session "$SESSION" --run reports-to "$RT_NAME at $NEW" --by "director at $NEW" > /dev/null
    rc=$?
    [ $rc -eq 0 ] || { echo "$PROG: the reports-to row wasn't rewritten (state-stored-set.sh exit $rc); nothing changed" >&2; exit $rc; }
    hold_entry "Reports-to rewritten from $RT_NAME at $OLD to $RT_NAME at $NEW, on the director's address message from $NEW at event $EVENT."
    echo "$PROG: this record now reports to $RT_NAME at $NEW" >&2
    exit 0
fi

# --copy --add
[ "$NLINES" -eq 6 ] || refuse "the hold message has $NLINES lines, not the six (Alignment hold, Row, Sources, Reason, Receiver, Release); nothing changed"
[[ $(line 1) =~ ^Alignment\ hold:\ ([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*)\ at\ ([^\ ]+)$ ]] \
    || refuse "the message's first line isn't \`Alignment hold: <owner/repo#n> at <head>\`; nothing changed"
PR=${BASH_REMATCH[1]} HEAD=${BASH_REMATCH[2]}
[[ $HEAD =~ $RE_SHA40 ]] || refuse "the message's head $HEAD isn't 40 lower-case hex; nothing changed"
i=1
for want in Row Sources Reason Receiver Release; do
    i=$((i + 1))
    case "$(line "$i")" in "$want: "*[![:space:]]*) ;; *) refuse "the message's line $i isn't \`$want: <value>\`; nothing changed" ;; esac
done
ROW=$(line 2); ROW=${ROW#Row: }
printf '%s' "$ROW" | jq -c 'select(type == "object")' > "$WD/row.json" 2> /dev/null && [ -s "$WD/row.json" ] \
    || refuse "the message's Row isn't a JSON object; nothing changed"
jq -e '(keys | sort) == ["hold", "lifted", "on", "set", "set_by", "until"] and all(.[]; type == "string")' "$WD/row.json" > /dev/null \
    || refuse "the message's Row isn't a hold row (hold, on, until, set_by, set, lifted); nothing changed"
H=$(jq -r .hold "$WD/row.json")
REPO_NAME=${PR%#*} REPO_NAME=${REPO_NAME#*/} NUM=${PR##*#}
[[ $(lc "$H") =~ ^align-$(lc "$REPO_NAME" | sed 's/[.]/\\./g')-$NUM-$HEAD(-[1-9][0-9]*)?$ ]] \
    || refuse "the hold $H isn't of the form align-$REPO_NAME-$NUM-${HEAD}[-<k>]; nothing changed"
[ "$(lc "$(jq -r .on "$WD/row.json")")" = "$(lc "$PR")" ] || refuse "the hold is on $(jq -r .on "$WD/row.json"), not $PR; nothing changed"
[ "$(jq -r '.until + "|" + .lifted' "$WD/row.json")" = "lifted|" ] || refuse "the hold isn't an unlifted \`lifted\` hold; nothing changed"
case "$(jq -r .set_by "$WD/row.json")" in
    "director at $FROM, receiver "*) ;;
    *) refuse "the hold's Set by doesn't name the sender, director at $FROM; nothing changed" ;;
esac
[[ $(jq -r .set "$WD/row.json") =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$ ]] || refuse "the hold's Set isn't YYYY-MM-DDTHH:MMZ; nothing changed"
HAVE=$(jq -c --arg h "$H" '[(.holds // [])[] | select(.hold == $h)][0] // empty' "$WD/rec.json")
if [ -n "$HAVE" ]; then
    if [ "$(printf '%s' "$HAVE" | jq -cS .)" = "$(jq -cS . "$WD/row.json")" ]; then
        echo "$PROG: $H is already in this record as sent; nothing changed" >&2
        exit 0
    fi
    refuse "a different hold named $H is already in this record; nothing changed"
fi
bash "$HERE/state-hold.sh" --session "$SESSION" --add --row-file "$WD/row.json" > /dev/null
rc=$?
case $rc in
    0) ;;
    14) echo "$PROG: the hold was added; its state-hold.sh entry wasn't (above)" >&2 ;;
    *) echo "$PROG: the hold wasn't added (state-hold.sh exit $rc)" >&2; exit $rc ;;
esac
hold_entry "Hold $H on $PR copied from the director at $FROM, on its message at event $EVENT. $(line 3). $(line 4). $(line 6)."
echo "$PROG: $H added on $PR" >&2
exit 0
