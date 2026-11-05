#!/usr/bin/env bash
# alignment-call.sh -- a director's alignment call on a lane pull request, and
# the manager's copy of the hold a `diverges` call places. Agent-run; it
# writes only through state-entry.sh, state-hold.sh and state-stored-set.sh
# (docs/designs/DESIGN-director-alignment-review.md, Decision 1 and Key
# Interfaces).
#
# Usage:
#   alignment-call.sh --session S --on <owner/repo#n> --text-file F [--receiver ADDR]
#   alignment-call.sh --session S --lift-releasable --on <owner/repo#n>
#   alignment-call.sh --session S --copy --add --message-file F --event N --from ADDR
#   alignment-call.sh --session S --copy --lift --message-file F --event N --from ADDR
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
# follow-ups` call writes the entry and then runs the guarded lift (below).
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
# The guarded lift (the director's record). For each `align-` hold on the pull
# request with Until `lifted` and Lifted empty, it reads the live head from
# GitHub once and lifts the hold only when all three hold: the live head isn't
# the placed-on head in the hold's name; the latest call on the pull request
# for the live head is `fits` or `fits with follow-ups`; and that call's entry
# number is above the hold's `diverges` call, the latest `diverges` entry at
# the placed-on head. After a call, the latest call for the live head must
# also be the one just written or a later one, so a fits call at another head
# lifts nothing. It lifts through state-hold.sh --lift, the Lifted cell
# reading `<YYYY-MM-DDTHH:MMZ> by director at <address>, <call> at <live
# head>`, writes a `hold` entry naming the hold, the head and the call's entry
# number, and prints the lift message, one per hold, a blank line between:
#
#   Alignment lift: <owner/repo#n> at <40-hex head it was released on>
#   Hold: <the hold's name>
#   Call: <fits|fits with follow-ups>, entry <n>
#
# A hold that doesn't meet them stands, and why goes to stderr. When the live
# head can't be read, every such hold stands and the script exits 13 naming
# them; the call, if one was made, is already written. A fits call with an
# unlifted `align-` hold on its pull request needs the Run `coordinator` row,
# read before the entry is written (65, nothing written). --lift-releasable
# --on runs the same guard with no call, so it writes no `alignment` entry; on
# a hold that isn't releasable it lifts and prints nothing.
#
# The copy (the manager's record), run on a director-hold message. Every mode
# needs the record's Run `reports-to` row to hold an address (`<name> at
# <address>`); a message sent to a row with none changes nothing (65). For
# --copy --add and --copy --lift the sender, --from, must be that address.
# --copy --reports-to is the one exception: its sender is a successor, never
# the row's address yet, so it checks instead that the message names the
# row's address as the current one (below). --event is the log sequence of the event the message
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
# --copy --lift takes the lift message above. It refuses (65, nothing
# changed) a message that isn't those three lines in that order, whose head
# isn't 40 hex, whose hold name isn't `align-<repo name>-<n>-<40 hex>[-<k>]`
# for the pull request the first line names, or whose Call isn't one of the
# two values with an entry number; a hold this record doesn't hold on that
# pull request, or whose Until isn't `lifted`; and a lift whose head is the
# placed-on head. The head must then be the `verified_head` of the Holdings
# row that links the pull request, so a replayed lift naming an older head is
# refused (65). When no holding links it (a pull request the manager wrote),
# the head must be the pull request's live head from GitHub instead (65 when
# it isn't, 2 with the hold standing when the head can't be read). It lifts
# the copy through state-hold.sh --lift with the director's Lifted text,
# `director at <sender>, <call> at <head>`, and writes a `hold` entry naming
# the hold, the head, the call's entry number and the event. A hold already
# lifted changes nothing (exit 0). A person's lift on an unchanged head
# doesn't come this way: each side records it with state-hold.sh --lift.
#
# Exit codes: 0 written (or nothing to write); 2 a read failed; 10 refused
# (no found record); 11 a write failed (what was written is on stderr); 13
# the guarded lift couldn't read the live head (the holds it names stand);
# 14 the entry or hold was written but the account entry after it wasn't;
# 64 usage; 65 refused (the reason on stderr); any other code is the
# writer's own, passed on.
#
# GitHub calls: gh pr view <n> --repo <owner/repo> --json state (a diverges
# call that may place a hold); gh pr view <n> --repo <owner/repo> --json
# headRefOid (the guarded lift, and --copy --lift with no holding); and those
# of the writers it runs.
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
        --copy) [ "$MODE" = call ] || usage; MODE=copy; shift ;;
        --lift-releasable) [ "$MODE" = call ] || usage; MODE=releasable; shift ;;
        --add) [ -z "$COPY" ] || usage; COPY=add; shift ;;
        --lift) [ -z "$COPY" ] || usage; COPY=lift; shift ;;
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
elif [ "$MODE" = releasable ]; then
    [ -z "$COPY$MSGFILE$EVENT$FROM$TEXTFILE$RECEIVER" ] || usage
    [[ $ON =~ $RE_PR_REF ]] || { echo "$PROG: --on is owner/repo#n" >&2; exit 64; }
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
# placed_head <hold name>: the 40-hex head an align- hold's name carries.
placed_head() { [[ $1 =~ -([0-9a-f]{40})(-[1-9][0-9]*)?$ ]] && printf '%s' "${BASH_REMATCH[1]}"; }
# live_head <owner/repo> <n>: the pull request's head as GitHub has it now;
# fails, with why in $WD/gh.err, when it can't be read or isn't 40 hex.
live_head() {
    local h
    h=$(gh pr view "$2" --repo "$1" --json headRefOid --jq .headRefOid 2> "$WD/gh.err" < /dev/null) || return 1
    [[ $h =~ $RE_SHA40 ]] || { printf 'the head reads [%s]' "$h" > "$WD/gh.err"; return 1; }
    printf '%s' "$h"
}
# standing_align_holds: the names of the unlifted `lifted` align- holds on
# $ON in $WD/rec.json, one per line, into $WD/standing.
standing_align_holds() {
    jq -r --arg on "$(lc "$ON")" '(.holds // [])[] | select((.hold | startswith("align-")) and (.on | ascii_downcase) == $on
        and .until == "lifted" and .lifted == "") | .hold' "$WD/rec.json" > "$WD/standing" || lib_die2 "the record's holds are not JSON"
}

# guard_lift <min entry>: the guarded lift (the header) on every standing
# align- hold on $ON. The latest call for the live head must be numbered at
# least <min entry>. Prints one lift message per hold it lifts; sets
# GUARD_RC to 14 when a lift's account entry wasn't written.
GUARD_RC=0
guard_lift() {
    local min=$1 live h placed keyed latest lid lcall printed=0
    read_record
    standing_align_holds
    [ -s "$WD/standing" ] || return 0
    DIRECTOR=$(run_value coordinator)
    [ -n "$DIRECTOR" ] || refuse "the record has no Run coordinator row, the director's address a lift names; $(paste -sd ' ' "$WD/standing") stands"
    if ! live=$(live_head "$ON_REPO" "$ON_NUM"); then
        echo "$PROG: lift blocked: $ON's live head can't be read ($(lib_scrub < "$WD/gh.err")), so $(paste -sd ' ' "$WD/standing") stands; alignment-call.sh --lift-releasable --on $ON runs the guard again" >&2
        exit 13
    fi
    # The calls on $ON, from each alignment entry's first line: {n, head, call}.
    bash "$HERE/state-entry.sh" --session "$SESSION" --list > "$WD/entries.json" 2> "$WD/entries.err" \
        || lib_die2 "cannot list the entries, so no lift is judged: $(lib_scrub < "$WD/entries.err" | head -1)"
    jq -c --arg on "$(lc "$ON")" '[.[] | select(.kind == "alignment")
        | .id as $n | (.text | split("\n")[0] | capture("^Alignment: (?<pr>[^ ]+) at (?<head>[0-9a-f]{40}) -- (?<call>.+)$"))
        | select((.pr | ascii_downcase) == $on) | {n: $n, head, call}]' "$WD/entries.json" > "$WD/calls.json" \
        || lib_die2 "the entries are not JSON"
    while IFS= read -r h <&3; do
        placed=$(placed_head "$h")
        if [ "$live" = "$placed" ]; then
            echo "$PROG: $h stands: $ON's live head is still $placed, the head it was placed on" >&2; continue
        fi
        keyed=$(jq -r --arg p "$placed" '[.[] | select(.head == $p and .call == "diverges") | .n] | max // ""' "$WD/calls.json")
        if [ -z "$keyed" ]; then
            echo "$PROG: $h stands: no diverges call at $placed is among this session's entries, so a later call can't be shown" >&2; continue
        fi
        latest=$(jq -r --arg l "$live" '[.[] | select(.head == $l)] | max_by(.n) // empty | "\(.n)\t\(.call)"' "$WD/calls.json")
        if [ -z "$latest" ]; then
            echo "$PROG: $h stands: $ON's live head $live has no call yet; it needs a re-read" >&2; continue
        fi
        lid=${latest%%	*} lcall=${latest#*	}
        case "$lcall" in
            fits|"fits with follow-ups") ;;
            *) echo "$PROG: $h stands: the latest call for the live head $live is $lcall (entry $lid)" >&2; continue ;;
        esac
        if [ "$lid" -lt "$min" ]; then
            echo "$PROG: $h stands: the call just written isn't for the live head $live" >&2; continue
        fi
        if [ "$lid" -le "$keyed" ]; then
            echo "$PROG: $h stands: the $lcall call at entry $lid doesn't come after the diverges call at entry $keyed" >&2; continue
        fi
        bash "$HERE/state-hold.sh" --session "$SESSION" --lift --hold "$h" --by "director at $DIRECTOR, $lcall at $live" > /dev/null
        case $? in
            0) ;;
            14) echo "$PROG: $h was lifted, but its state-hold.sh entry wasn't (above)" >&2; GUARD_RC=14 ;;
            *) echo "$PROG: $h wasn't lifted (state-hold.sh, above); it stands" >&2; exit 11 ;;
        esac
        printf 'Hold %s on %s released at %s, on the %s call at entry %s.\n' "$h" "$ON" "$live" "$lcall" "$lid" > "$WD/hold-entry"
        bash "$HERE/state-entry.sh" --session "$SESSION" --kind hold --text-file "$WD/hold-entry" > /dev/null \
            || { echo "$PROG: $h was lifted, but its entry wasn't written; write it with state-entry.sh --kind hold: $(cat "$WD/hold-entry")" >&2; GUARD_RC=14; }
        echo "$PROG: lifted $h on $ON at $live" >&2
        [ "$printed" = 0 ] || echo
        printf 'Alignment lift: %s at %s\nHold: %s\nCall: %s, entry %s\n' "$ON" "$live" "$h" "$lcall" "$lid"
        printed=1
    done 3< "$WD/standing"
}

# ---- the guarded lift with no call ------------------------------------------
if [ "$MODE" = releasable ]; then
    ON_REPO=${ON%#*} ON_NUM=${ON##*#}
    guard_lift 0
    exit "$GUARD_RC"
fi

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
    elif [ "$CALL" = fits ] || [ "$CALL" = "fits with follow-ups" ]; then
        # A lift names the director's address, so it's read before the call.
        read_record
        standing_align_holds
        [ ! -s "$WD/standing" ] || [ -n "$(run_value coordinator)" ] \
            || refuse "the record has no Run coordinator row, the director's address a lift of $(paste -sd ' ' "$WD/standing") names; nothing written"
    fi

    KEY=$(bash "$HERE/state-entry.sh" --session "$SESSION" --kind alignment --on "$ON" --text-file "$WD/text")
    rc=$?
    [ $rc -eq 0 ] || exit $rc
    echo "$PROG: the call is written as $KEY" >&2
    if [ "$CALL" = fits ] || [ "$CALL" = "fits with follow-ups" ]; then
        guard_lift "$((10#${KEY##*/}))"
        exit "$GUARD_RC"
    fi
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

if [ "$COPY" = lift ]; then
    [ "$NLINES" -eq 3 ] || refuse "the lift message has $NLINES lines, not the three (Alignment lift, Hold, Call); nothing changed"
    [[ $(line 1) =~ ^Alignment\ lift:\ ([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*)\ at\ ([^\ ]+)$ ]] \
        || refuse "the message's first line isn't \`Alignment lift: <owner/repo#n> at <head>\`; nothing changed"
    PR=${BASH_REMATCH[1]} HEAD=${BASH_REMATCH[2]}
    [[ $HEAD =~ $RE_SHA40 ]] || refuse "the message's head $HEAD isn't 40 lower-case hex; nothing changed"
    [[ $(line 2) =~ ^Hold:\ ([^\ ]+)$ ]] || refuse "the message's line 2 isn't \`Hold: <hold name>\`; nothing changed"
    H=${BASH_REMATCH[1]}
    [[ $(line 3) =~ ^Call:\ (fits|fits\ with\ follow-ups),\ entry\ ([1-9][0-9]*)$ ]] \
        || refuse "the message's line 3 isn't \`Call: <fits|fits with follow-ups>, entry <n>\`; nothing changed"
    CALLV=${BASH_REMATCH[1]} CALLN=${BASH_REMATCH[2]}
    REPO_NAME=${PR%#*} REPO_NAME=${REPO_NAME#*/} NUM=${PR##*#}
    [[ $(lc "$H") =~ ^align-$(lc "$REPO_NAME" | sed 's/[.]/\\./g')-$NUM-[0-9a-f]{40}(-[1-9][0-9]*)?$ ]] \
        || refuse "the hold $H isn't of the form align-$REPO_NAME-$NUM-<40-hex head>[-<k>]; nothing changed"
    PLACED=$(placed_head "$H")
    HAVE=$(jq -c --arg h "$H" '[(.holds // [])[] | select(.hold == $h)][0] // empty' "$WD/rec.json")
    [ -n "$HAVE" ] || refuse "this record holds no hold named $H; nothing changed"
    [ "$(lc "$(printf '%s' "$HAVE" | jq -r .on)")" = "$(lc "$PR")" ] || refuse "$H is on $(printf '%s' "$HAVE" | jq -r .on), not $PR; nothing changed"
    [ "$(printf '%s' "$HAVE" | jq -r .until)" = lifted ] || refuse "$H waits on $(printf '%s' "$HAVE" | jq -r .until), not a lift; nothing changed"
    if [ -n "$(printf '%s' "$HAVE" | jq -r .lifted)" ]; then
        echo "$PROG: $H is already lifted ($(printf '%s' "$HAVE" | jq -r .lifted)); nothing changed" >&2
        exit 0
    fi
    [ "$HEAD" != "$PLACED" ] || refuse "the lift names $HEAD, the head $H was placed on, and a hold lifts only on a new head (a person's lift on an unchanged head is recorded with state-hold.sh --lift); nothing changed"
    # The head the lift names must be the one this record verified, or, with
    # no holding to have verified it, the pull request's live head.
    LINKED=$(jq -r -L "$HERE" --arg r "$(lc "${PR%#*}")" --arg n "$NUM" 'include "state-schema";
        [(.holdings // [])[] | select(((.pull_request // "") | pr_link | (.repo | ascii_downcase) == $r and (.number | tostring) == $n))
         | "linked " + (.verified_head // "")][0] // ""' "$WD/rec.json") || lib_die2 "the record's holdings are not JSON"
    if [ -n "$LINKED" ]; then
        VH=${LINKED#linked }
        [ "$HEAD" = "$VH" ] || refuse "the lift names $HEAD, but the holding for $PR has verified head ${VH:-none}, and a lift is taken only at this record's verified head; nothing changed"
    else
        LIVE=$(live_head "${PR%#*}" "$NUM") \
            || { echo "$PROG: the lift isn't taken: no holding links $PR, and its live head can't be read ($(lib_scrub < "$WD/gh.err")); $H stands" >&2; exit 2; }
        [ "$HEAD" = "$LIVE" ] || refuse "no holding links $PR, and the lift names $HEAD, but its live head is $LIVE; nothing changed"
    fi
    bash "$HERE/state-hold.sh" --session "$SESSION" --lift --hold "$H" --by "director at $FROM, $CALLV at $HEAD" > /dev/null
    rc=$?
    case $rc in
        0) ;;
        14) echo "$PROG: the hold was lifted; its state-hold.sh entry wasn't (above)" >&2 ;;
        *) echo "$PROG: the hold wasn't lifted (state-hold.sh exit $rc); $H stands" >&2; exit $rc ;;
    esac
    hold_entry "Hold $H on $PR lifted on the director at $FROM's message at event $EVENT: $CALLV at $HEAD, the call at entry $CALLN in the director's record."
    echo "$PROG: $H lifted on $PR at $HEAD" >&2
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
