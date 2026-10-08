#!/usr/bin/env bash
# record-state.sh -- change the record's stored set (Run, Standing, Work) and
# append the entry that tells it, or list the set. Agent-run; the three
# sections change only through this script
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 3).
#
# Usage:
#   record-state.sh --session S --run KEY VALUE --by WHO
#   record-state.sh --session S --told WHO --by WHO
#   record-state.sh --session S --standing KIND [--on SCOPE] [--until COND] --what TEXT --owner WHO [--relayed-by WHO]
#   record-state.sh --session S --end ID --by WHO
#   record-state.sh --session S --work ITEM --kind holding|local-agent --who W --next TEXT
#   record-state.sh --session S --done ITEM
#   record-state.sh --session S --list
#   ... [--scope roadmap|discipline --name N --repo O/R --ref N
#        --skip-session-checks]                                  (tests)
#
# The session gives the scope, name, host and record number (coord-log.sh
# vars and run-facts); the override flags exist for tests only.
#
# --run sets one Run key: arguments (the run's arguments as given), cap (a
# number) or coordinator (the address messages to this coordinator reach, a
# dispatch topic). A new coordinator clears every `told` row, since nobody has
# been told the new address yet. --told records that WHO (a dispatch topic)
# was sent the current address; it needs a coordinator row.
#
# --standing records an event only a person owns that still binds the run:
# KIND is pause, go-ahead, approval or answer, OWNER is the person who decided
# it, and --relayed-by names who carried it here (leave it off when the owner
# told this coordinator directly). When a person says it in a comment on the
# record, or anywhere else, this is how it reaches the record: the reader
# never counts a comment without the entry marker. It gets the next id, s<n>.
# A pause takes --on, its scope (`all`, or one unit as pick lists it:
# `Feature 2`, `ED1`, `#12`, `owner/repo#12`), and --until, its resume
# condition (`lifted`, `time <YYYY-MM-DDTHH:MMZ>` in UTC, `merged
# owner/repo#n` or `tag owner/repo <tag>`); a go-ahead may take --on, the one
# unit it lets through a wider pause; the other kinds take neither. With a
# session whose pick facts (coord/pick.json) list units, --on must name one of
# them (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1).
# --end removes a Standing row (a resume ends a pause; a go-ahead or approval
# ends when used; an answer when withdrawn).
#
# --work writes the next step for ITEM: with --kind holding, ITEM is a
# holding's Unit and W its Worker, and the holding's first row also records W
# as told the current address, since its dispatch brief named it (a later
# update doesn't); with --kind local-agent, ITEM is
# the work and W who does it. --done removes ITEM's row. Every write also
# drops a holding row whose holding is gone, so a teardown leaves no orphan.
#
# A holding's row carries its Wakes: at each --work write, this run's wakes
# for the holding (coord-log.sh wakes: its worker's topic, and its leg's
# request) logged after the end of the minute in the row's Updated cell are
# added to the count; a new row counts this run's wakes from its start. When
# a holding's row leaves Work (--done, or dropped once its holding is gone),
# its final count, with the wakes since its last write, is appended as an
# entry. The count is a floor: a wake inside the minute after a write, or
# one a crashed run logged after its last write, isn't counted, and a holding
# torn down before its row leaves takes its leg's wakes with it. A row removed
# and written again in the same run counts that run's wakes again. A leg's
# request is one per holding (dispatch-worker.sh opens one per topic), so a
# leg wake is never credited to two holdings. Without a
# session (the override flags) nothing is added
# (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 4).
#
# Each change is written to the body first, through the record's write core
# (record-write-core.sh), with the minute and who, and then told as an entry
# with record-append.sh, kind run, told, the standing kind, end or work. The
# body is the state; the entry is its account.
#
# Exit codes: 0 written (prints the record's URL, then the entry's) or
# printed; 2 a read failed (the record, or the entries the next Standing id
# is chosen from); 10 refused: here, no found record or not a canonical
# record of this scope, and from the write core, not an open record,
# provenance or a directed transition; 11, 12 (the record changed between
# this script's read and its write) and 13 (the record is full) from the
# write core; 14
# the body was written but the entry wasn't posted (post it with
# record-append.sh; the change it names is on stderr); 64 usage; 65 refused
# (the reason on stderr).
#
# GitHub reads: gh issue view N --repo R --json body | gh pr view N --repo R
# --json body; the body write happens only in the write core it sources, and
# the entry through record-append.sh.
set -uo pipefail

PROG=record-state
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= MODE=
KEY= VALUE= BY= WHO= KIND= WHAT= OWNER= RELAYED= ID= ITEM= NEXT= ON= UNTIL=
SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
setmode() { [ -z "$MODE" ] || usage; MODE=$1; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --run) [ $# -ge 3 ] || usage; setmode run; KEY=$2; VALUE=$3; shift 3 ;;
        --told) [ $# -ge 2 ] || usage; setmode told; WHO=$2; shift 2 ;;
        --standing) [ $# -ge 2 ] || usage; setmode standing; KIND=$2; shift 2 ;;
        --end) [ $# -ge 2 ] || usage; setmode end; ID=$2; shift 2 ;;
        --work) [ $# -ge 2 ] || usage; setmode work; ITEM=$2; shift 2 ;;
        --done) [ $# -ge 2 ] || usage; setmode done; ITEM=$2; shift 2 ;;
        --list) setmode list; shift ;;
        --by) [ $# -ge 2 ] || usage; BY=$2; shift 2 ;;
        --what) [ $# -ge 2 ] || usage; WHAT=$2; shift 2 ;;
        --owner) [ $# -ge 2 ] || usage; OWNER=$2; shift 2 ;;
        --relayed-by) [ $# -ge 2 ] || usage; RELAYED=$2; shift 2 ;;
        --on) [ $# -ge 2 ] || usage; ON=$2; shift 2 ;;
        --until) [ $# -ge 2 ] || usage; UNTIL=$2; shift 2 ;;
        --kind) [ $# -ge 2 ] || usage; KIND=$2; shift 2 ;;
        --who) [ $# -ge 2 ] || usage; WHO=$2; shift 2 ;;
        --next) [ $# -ge 2 ] || usage; NEXT=$2; shift 2 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$MODE" in
    run) [ -n "$BY" ] && [ -z "$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage
         case "$KEY" in arguments|cap|coordinator) ;; *) echo "$PROG: --run takes arguments, cap or coordinator" >&2; exit 64 ;; esac ;;
    told) [ -n "$BY" ] && [ -z "$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    standing) [ -n "$WHAT" ] && [ -n "$OWNER" ] && [ -z "$BY$WHO$NEXT" ] || usage ;;
    end) [ -n "$BY" ] && [ -z "$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    work) [ -n "$KIND" ] && [ -n "$WHO" ] && [ -n "$NEXT" ] && [ -z "$BY$WHAT$OWNER$RELAYED$ON$UNTIL" ] || usage ;;
    done) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    list) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    *) usage ;;
esac
. "$HERE/record-common.sh"
lib_facts
if [ "$OVERRIDE" = 1 ]; then
    [ -n "$REF" ] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
else
    [ -z "$REF" ] || usage
    FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION")
    case $? in
        0) REF=$(printf '%s' "$FACTS" | jq -r '.ref') ;;
        1) echo "$PROG: refused: the run has no found record" >&2; exit 10 ;;
        *) lib_die2 "cannot read the run's facts" ;;
    esac
fi
[[ $REF =~ $RE_NUM ]] || usage

WD=$(mktemp -d "${TMPDIR:-/tmp}/record-state.XXXXXX")
trap 'rm -rf "$WD"' EXIT

if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.raw" < /dev/null || lib_die2 "cannot read issue #$REF"
else
    gh pr view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.raw" < /dev/null || lib_die2 "cannot read pull request #$REF"
fi
tr -d '\r' < "$WD/live.raw" > "$WD/live.md"
lib_parse "$WD/live.md" "$WD/parsed.json"
case $? in
    0) ;;
    3|65) echo "$PROG: refused: #$REF is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$WD/parsed.json.err" >&2; echo >&2; exit 10 ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac

if [ "$MODE" = list ]; then
    jq -c '{run: (.run // []), standing: (.standing // []), work: (.work // [])}' "$WD/parsed.json"
    exit 0
fi

NOW=$(date -u +%Y-%m-%dT%H:%MZ)
# wakes_since <topic> <return-path> <updated-or-empty>: this run's wakes for a
# holding after the end of the Updated minute (all of this run's when empty).
wakes_since() {
    [ "$OVERRIDE" = 1 ] && { echo 0; return 0; }
    local cut= w req
    if [ -n "$3" ]; then
        # Updated is always YYYY-MM-DDTHH:MMZ (the codec's grammar).
        cut=$(jq -rn --arg u "$3" '$u | strptime("%Y-%m-%dT%H:%MZ") | mktime + 60 | todate') || { echo "$PROG: jq failed" >&2; return 2; }
    fi
    w=$(bash "$HERE/coord-log.sh" wakes --session "$SESSION" ${cut:+--after-time "$cut"}) || { echo "$PROG: cannot read the run's wakes" >&2; return 2; }
    req=${2#leg }; req=${req%%:*}
    case "$2" in "leg "*) ;; *) req= ;; esac
    printf '%s' "$w" | jq -r --arg t "$1" --arg r "$req" '(.[$t] // 0) + (if $r == "" then 0 else (.["leg " + $r] // 0) end)'
}
# How record-append.sh addresses this record.
if [ "$OVERRIDE" = 1 ]; then
    ADDR_ARGS=(--scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF")
else
    ADDR_ARGS=(--session "$SESSION")
fi
P="$WD/parsed.json"
refuse() { echo "$PROG: refused: $*" >&2; exit 65; }
# The entry that tells the change: its kind and text.
EKIND= ETEXT=
case "$MODE" in
run)
    if [ "$KEY" = coordinator ]; then
        PROG_JQ='.run = ([(.run // [])[] | select(.key != "coordinator" and .key != "told")] + [{key: "coordinator", value: $v, set_by: $b, set: $t}])'
        ETEXT="The coordinator's address is now $VALUE, set by $BY. Nobody has been told it yet."
    else
        PROG_JQ='.run = ([(.run // [])[] | select(.key != $k)] + [{key: $k, value: $v, set_by: $b, set: $t}])'
        ETEXT="Run $KEY set to $VALUE by $BY."
    fi
    jq --arg k "$KEY" --arg v "$VALUE" --arg b "$BY" --arg t "$NOW" "$PROG_JQ" "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=run
    ;;
told)
    jq -e 'any((.run // [])[]; .key == "coordinator")' "$P" > /dev/null || refuse "the record names no coordinator address to have told anyone; set it with --run coordinator first"
    jq -e --arg w "$WHO" 'any((.run // [])[]; .key == "told" and .value == $w)' "$P" > /dev/null && refuse "$WHO has already been told the current address"
    ADDR=$(jq -r '[(.run // [])[] | select(.key == "coordinator") | .value][0]' "$P")
    jq --arg w "$WHO" --arg b "$BY" --arg t "$NOW" '.run = ((.run // []) + [{key: "told", value: $w, set_by: $b, set: $t}])' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=told ETEXT="$WHO was told the coordinator's address, $ADDR, by $BY."
    ;;
standing)
    case "$KIND" in pause|go-ahead|approval|answer) ;; *) echo "$PROG: --standing takes pause, go-ahead, approval or answer" >&2; exit 64 ;; esac
    case "$KIND" in
        pause) [ -n "$ON" ] && [ -n "$UNTIL" ] || { echo "$PROG: a pause takes --on and --until" >&2; exit 64; } ;;
        go-ahead) [ -z "$UNTIL" ] || { echo "$PROG: a go-ahead takes no --until; it ends when used" >&2; exit 64; } ;;
        *) [ -z "$ON$UNTIL" ] || { echo "$PROG: only a pause or a go-ahead takes --on or --until" >&2; exit 64; } ;;
    esac
    # The scope must be a unit pick reads, when this session's pick facts say
    # which units those are.
    if [ -n "$ON" ] && [ "$ON" != all ] && [ "$OVERRIDE" != 1 ] && [ -n "$SESSION" ]; then
        if "$KOTO" context exists "$SESSION" coord/pick.json; then
            "$KOTO" context get "$SESSION" coord/pick.json > "$WD/pick.json" || lib_die2 "cannot read coord/pick.json"
        else
            echo '{}' > "$WD/pick.json"
        fi
        if jq -e '(.units // []) | type == "array" and length > 0' "$WD/pick.json" > /dev/null; then
            jq -e --arg u "$ON" '.host as $h | any(.units[]; .unit == $u or ($h != null and ($h + .unit) == $u))' "$WD/pick.json" > /dev/null \
                || refuse "--on $ON is not a unit pick lists; it takes one of: $(jq -r '[.units[].unit] | join(", ")' "$WD/pick.json")"
        fi
    fi
    SID=$(jq -r '"s\(([(.standing // [])[] | .standing[1:] | tonumber] | max // 0) + 1)"' "$P")
    # The next id never reuses an ended one: the entries name ids, so the
    # highest id ever used is read from the stream too.
    ENTRIES=$(bash "$HERE/record-append.sh" "${ADDR_ARGS[@]}" --list 2> "$WD/list.err") \
        || lib_die2 "cannot read the record's entries to choose the next Standing id: $(lib_scrub < "$WD/list.err")"
    USED=$(printf '%s' "$ENTRIES" | jq -r '[.[] | .text | scan("^(s[1-9][0-9]*)") | .[0][1:] | tonumber] | max // 0') \
        || lib_die2 "the record's entries are not JSON"
    N=${SID#s}; [ "$USED" -ge "$N" ] && SID="s$((USED + 1))"
    jq --arg s "$SID" --arg k "$KIND" --arg on "$ON" --arg u "$UNTIL" --arg w "$WHAT" --arg o "$OWNER" --arg r "$RELAYED" --arg t "$NOW" \
        '.standing = ((.standing // []) + [{standing: $s, kind: $k, on: $on, until: $u, what: $w, owner: $o, relayed_by: $r, set: $t}])' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=$KIND
    ETEXT="$SID ($KIND${ON:+ on $ON}${UNTIL:+, until $UNTIL}): $WHAT. Owner: $OWNER.${RELAYED:+ Relayed by $RELAYED.}"
    ;;
end)
    ROW=$(jq -c --arg s "$ID" '[(.standing // [])[] | select(.standing == $s)][0] // empty' "$P")
    [ -n "$ROW" ] || refuse "no Standing row $ID"
    jq --arg s "$ID" '.standing = [(.standing // [])[] | select(.standing != $s)]' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=end
    ETEXT="$ID ($(printf '%s' "$ROW" | jq -r .kind): $(printf '%s' "$ROW" | jq -r .what)) ended by $BY."
    ;;
work)
    case "$KIND" in holding|local-agent) ;; *) echo "$PROG: --kind takes holding or local-agent" >&2; exit 64 ;; esac
    if [ "$KIND" = holding ]; then
        jq -e --arg u "$ITEM" --arg w "$WHO" 'any(.holdings[]; .unit == $u and .worker == $w)' "$P" > /dev/null \
            || refuse "no holding has Unit $ITEM and Worker $WHO"
    fi
    # A holding's first Work row is written at its dispatch, whose brief named
    # this coordinator's address, so it records the worker as told; a later
    # update records nothing of the kind, since after an address change the
    # worker has been told nothing until --told says so.
    FIRST=true
    jq -e --arg i "$ITEM" 'any((.work // [])[]; .item == $i)' "$P" > /dev/null && FIRST=false
    WAKES=0
    if [ "$KIND" = holding ]; then
        PREV=$(jq -c --arg i "$ITEM" '[(.work // [])[] | select(.item == $i)][0] // {}' "$P")
        RP=$(jq -r --arg u "$ITEM" --arg w "$WHO" '[.holdings[] | select(.unit == $u and .worker == $w) | .return_path][0] // ""' "$P")
        ADD=$(wakes_since "$WHO" "$RP" "$(printf '%s' "$PREV" | jq -r '.updated // ""')") || exit 2
        WAKES=$(( $(printf '%s' "$PREV" | jq -r '.wakes // "0" | if . == "" then "0" else . end') + ADD ))
    fi
    jq --arg i "$ITEM" --arg k "$KIND" --arg w "$WHO" --arg n "$NEXT" --arg t "$NOW" --arg c "$WAKES" --argjson first "$FIRST" '
        .work = ([(.work // [])[] | select(.item != $i)] + [{item: $i, kind: $k, who: $w, next: $n, wakes: $c, updated: $t}])
        | if $k == "holding" and $first and any((.run // [])[]; .key == "coordinator") and (any((.run // [])[]; .key == "told" and .value == $w) | not)
          then .run += [{key: "told", value: $w, set_by: ([.run[] | select(.key == "coordinator") | .value][0]), set: $t}]
          else . end' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=work ETEXT="Next step for $ITEM ($KIND, $WHO): $NEXT."
    [ "$KIND" = holding ] && ETEXT="$ETEXT Wakes so far: $WAKES."
    ;;
done)
    jq -e --arg i "$ITEM" 'any((.work // [])[]; .item == $i)' "$P" > /dev/null || refuse "no Work row for $ITEM"
    jq --arg i "$ITEM" '.work = [(.work // [])[] | select(.item != $i)]' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=work ETEXT="$ITEM is done and leaves Work."
    ;;
esac

# The holding rows that leave Work with this write, --done's or the ones whose
# holding is gone, each with its final count, told after the change's entry.
P_NEXT="$WD/next.json"
jq -c '([.holdings[] | "\(.unit)\u0000\(.worker)"]) as $h
    | [(.work // [])[] | select(.kind == "holding" and (("\(.item)\u0000\(.who)" as $k | $h | index($k)) | not))]' "$P_NEXT" > "$WD/leaving.json" || lib_die2 "jq failed"
if [ "$MODE" = done ]; then
    jq -c --arg i "$ITEM" '[(.work // [])[] | select(.item == $i and .kind == "holding")]' "$P" > "$WD/done.json" || lib_die2 "jq failed"
    jq -sc 'add | unique_by(.item)' "$WD/leaving.json" "$WD/done.json" > "$WD/leaving2.json" && mv "$WD/leaving2.json" "$WD/leaving.json"
fi
: > "$WD/leaving.txt"
n=$(jq length "$WD/leaving.json")
i=0
while [ "$i" -lt "$n" ]; do
    ROW=$(jq -c --argjson i "$i" '.[$i]' "$WD/leaving.json")
    LW=$(printf '%s' "$ROW" | jq -r .who)
    # The leg's request, when the holding is still in the version read (a
    # --done); a holding already gone takes its leg's wakes with it, a floor.
    LRP=$(jq -r --arg u "$(printf '%s' "$ROW" | jq -r .item)" --arg w "$LW" '[.holdings[] | select(.unit == $u and .worker == $w) | .return_path][0] // ""' "$P")
    LADD=$(wakes_since "$LW" "$LRP" "$(printf '%s' "$ROW" | jq -r '.updated // ""')") || exit 2
    LTOT=$(( $(printf '%s' "$ROW" | jq -r '.wakes // "0" | if . == "" then "0" else . end') + LADD ))
    printf '%s\n' "$(printf '%s' "$ROW" | jq -r .item) ($LW) left Work after $LTOT wakes." >> "$WD/leaving.txt"
    i=$((i + 1))
done

# Every write drops a holding's Work row whose holding is gone, and keeps the
# Written: time of the version read, which the write core compares with the
# live body's before it stamps its own.
jq '([.holdings[] | "\(.unit)\u0000\(.worker)"]) as $h
    | .work = [(.work // [])[] | select(.kind != "holding" or ("\(.item)\u0000\(.who)" as $k | $h | index($k)))]
    | if (.work | length) == 0 then del(.work) else . end
    | if ((.run // []) | length) == 0 then del(.run) else . end
    | if ((.standing // []) | length) == 0 then del(.standing) else . end
    | del(.written)' "$WD/next.json" > "$WD/final.json" || lib_die2 "jq failed"
bash "$HERE/record-render.sh" --container "$CONTAINER" --written "$(jq -r '.written' "$P")" "$WD/final.json" > "$WD/body.md" 2> "$WD/render.err" \
    || { echo "$PROG: refused:" >&2; lib_scrub < "$WD/render.err" >&2; echo >&2; exit 65; }
printf '%s\n' "$ETEXT" > "$WD/entry.txt"
# The write core takes over $T and the EXIT trap and removes $WD, so the
# entries' text is kept outside it.
ENTRY_FILE=$(mktemp "${TMPDIR:-/tmp}/record-state-entry.XXXXXX")
cp "$WD/entry.txt" "$ENTRY_FILE"
LEAVING_FILE=$(mktemp "${TMPDIR:-/tmp}/record-state-leaving.XXXXXX")
cp "$WD/leaving.txt" "$LEAVING_FILE"

BODY="$WD/body.md" END= CLOSE=0 CORE_CLEANUP=$WD
lib_write_guard
. "$HERE/record-write-core.sh"
STATE_WRITER=1
core_write

if ! bash "$HERE/record-append.sh" "${ADDR_ARGS[@]}" --kind "$EKIND" --text-file "$ENTRY_FILE"; then
    echo "$PROG: the record was written, but its entry wasn't posted; post it with record-append.sh --kind $EKIND: $(cat "$ENTRY_FILE")" >&2
    while IFS= read -r LINE; do
        [ -n "$LINE" ] && echo "$PROG: and post with record-append.sh --kind work: $LINE" >&2
    done < "$LEAVING_FILE"
    rm -f "$ENTRY_FILE" "$LEAVING_FILE"
    exit 14
fi
rm -f "$ENTRY_FILE"
# Each holding row that left Work, told with its final count. Every line is
# tried; any that didn't post are named together, for record-append.sh.
UNPOSTED=0
while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    printf '%s\n' "$LINE" > "$LEAVING_FILE.one"
    if ! bash "$HERE/record-append.sh" "${ADDR_ARGS[@]}" --kind work --text-file "$LEAVING_FILE.one"; then
        echo "$PROG: the record was written, but a final count wasn't posted; post it with record-append.sh --kind work: $LINE" >&2
        UNPOSTED=1
    fi
done < "$LEAVING_FILE"
rm -f "$LEAVING_FILE" "$LEAVING_FILE.one"
[ "$UNPOSTED" = 0 ] || exit 14
