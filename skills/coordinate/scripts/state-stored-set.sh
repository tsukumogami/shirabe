#!/usr/bin/env bash
# state-stored-set.sh -- change the record's stored set (Run, Standing, Work) and
# append the entry that tells it, or list the set. Agent-run; the three
# sections change only through this script
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 3).
#
# Usage:
#   state-stored-set.sh --session S --run KEY VALUE --by WHO
#   state-stored-set.sh --session S --host KEY VALUE [--host KEY VALUE]...
#   state-stored-set.sh --session S --rotation FILE
#   state-stored-set.sh --session S --reasoning-file FILE
#   state-stored-set.sh --session S --reasoning-check
#   state-stored-set.sh --session S --told WHO --by WHO
#   state-stored-set.sh --session S --standing KIND [--on SCOPE] [--until COND] --what TEXT --owner WHO [--relayed-by WHO]
#   state-stored-set.sh --session S --end ID --by WHO
#   state-stored-set.sh --session S --work ITEM --kind holding|local-agent|decision|follow-up --who W --next TEXT
#   state-stored-set.sh --session S --done ITEM [--kind K]
#   state-stored-set.sh --session S --list
#   ... [--scope roadmap|discipline --name N --repo O/R
#        --skip-session-checks]                                  (tests)
#
# The session gives the scope, name and host (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts); the override flags exist for
# tests only, with RS_SESSION naming the session that holds the record.
#
# --run sets one Run key: arguments (the run's arguments as given), cap (a
# number), coordinator (the address messages to this coordinator reach: a
# session name a worker can message, `_` allowed, or a dispatch topic; never
# an id or a path). `store` is no Run key here (65): the record's store is
# always the coordinator's session, and the legacy `store session` row a session
# opened before that holds is kept as written. A new
# coordinator clears every `told` row, since nobody has been told the new
# address yet. --told records that WHO (a worker's dispatch topic, or another
# party's session name) was sent the current address; it needs a coordinator
# row.
#
# The record also keeps the crash set
# (docs/designs/DESIGN-coordinator-session-record.md, Decision 9; PRD R17),
# what a replacement needs after a crash: --run rules and --run briefs, each
# `<label> sha256:<64 hex>`, the digest of a file this coordinator ran with
# (a second row with the same label replaces the first; other labels are
# kept); --run friction, a label; and --run reports-to, `<role>` or `<role>
# at <address>`, who this coordinator reports up to. Where those files live
# goes in record/host, through
# --host, never in the record's tables: KEY is rules:<label>, briefs:<label>
# or friction with an absolute path, or one of the import's facts,
# source_workspace (an absolute path), source_session (a coordinator session
# name) or template_hash (64 hex). --host merges into record/host and changes
# nothing else: it writes no table and posts no entry, since host facts never
# leave the host. A value with a control
# character or a token-shaped string is refused (65); a workspace path may be
# a home-directory path, which a table cell never is. It prints the record/host
# object.
#
# A discipline rotation keeps two keys of its own beside its tables (docs/designs/current/DESIGN-coordinator-record-teardown.md,
# Decision 3), and only this script writes them, with STATE_WRITER open:
# --rotation FILE writes record/rotation, the JSON object in FILE,
# {start, end, host_repo, predecessor}: start and end real dates, end not
# before start, host_repo this run's host, predecessor null (a first rotation)
# or the predecessor's session, coordinate-<slug>-<YYYYMMDDTHHMMSSZ> with this
# discipline's slug. --reasoning-file FILE writes record/reasoning, FILE's text
# as a JSON string: what this rotation leaves the next one, at most 16 KiB
# (16384 bytes) with no control character but a newline or a tab, and no
# token-shaped string or home-directory path (state-schema.jq's scan_strings,
# which also walks every string of a rotation). Writing it closes the rotation
# (the window rule reads a rotation holding it as ended). A value that breaks a
# rule, or a run that isn't a discipline rotation, is refused (65) before any
# key is written. Each prints the key's JSON as written. --reasoning-check exits 0
# when the rotation holds record/reasoning and 1 when it doesn't (the
# rotation_end state's gate).
#
# --standing records an event only a person owns that still binds the run:
# KIND is pause, go-ahead, approval, answer or assignment, OWNER is the person who decided
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
# An assignment is work a person assigned outside the scope: --on names it,
# an issue (`#12`, `owner/repo#12`) or `release owner/repo <tag>`, and pick
# lists it as a unit from then on (shirabe#607).
# --end removes a Standing row (a resume ends a pause; a go-ahead or approval
# ends when used; an answer when withdrawn; an assignment once its work is
# done).
#
# --work writes the next step for ITEM: with --kind holding, ITEM is a
# holding's Unit and W its Worker, and the holding's first row also records W
# as told the current address, since its dispatch brief named it (a later
# update doesn't); with --kind local-agent, ITEM is
# the work and W who does it. With --kind decision, ITEM is a unit pick parked
# on a decision for a person (pick's await_decision) and W is `decision <n>`,
# an unsettled entry in the Decisions section; with --kind follow-up, ITEM is
# a unit whose scoping alone landed (pick's scope route) and W the pull
# request that landed it, `owner/repo#n`, NEXT naming its execution. With a
# session whose pick facts list units, ITEM must be one of them for either
# kind. Such a row keeps the unit's later work in the record until a holding
# takes it: a holding's --work for ITEM removes ITEM's decision and follow-up
# rows, unless that holding is at Phase scoping (the one whose merge wrote the
# follow-up). An ITEM has at most one row per kind. --done removes ITEM's rows, or
# only its --kind K row. Every write also drops a holding row whose holding
# is gone, so a teardown leaves no orphan. A verdict-owed row (a milestone
# whose verdict is owed, docs/designs/DESIGN-milestone-verdicts.md) is listed
# and kept by every write here, but only roadmap-status.sh writes or removes
# it: --work refuses its kind, and --done leaves it. A rework row (a
# milestone a confirmed changes-needed verdict or reopen sent back) is
# written only by
# roadmap-status.sh --confirm, so --work refuses its kind too; --done
# --kind rework removes it, which dispatch-worker.sh does once a worker is
# dispatched for the milestone.
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
# (state-write-core.sh), with the minute and who, and then told as an entry
# with state-entry.sh, kind run, told, the standing kind, end or work. The
# body is the state; the entry is its account.
#
# Exit codes: 0 written (prints the record's URL, then the entry's) or
# printed; 2 a read failed (the record, or the entries the next Standing id
# is chosen from); 10 refused: here, no found record or a record that doesn't
# read back as this scope's, and from the write core, not an open record,
# provenance or a directed transition; 11 and 12 (the record changed between
# this script's read and its write) from the write core; 14
# the state was written but the entry wasn't posted (post it with
# state-entry.sh; the change it names is on stderr); 64 usage; 65 refused
# (the reason on stderr).
#
# The record is read through state-read.sh and written only in the write
# core it sources, and the entry through state-entry.sh.
set -uo pipefail

PROG=state-stored-set
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= MODE=
KEY= VALUE= BY= WHO= KIND= WHAT= OWNER= RELAYED= ID= ITEM= NEXT= ON= UNTIL= RFILE=
SKIP_CHECKS=0
# --host pairs, one `key<TAB>value` line each.
HOSTKV=

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
setmode() { [ -z "$MODE" ] || usage; MODE=$1; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --run) [ $# -ge 3 ] || usage; setmode run; KEY=$2; VALUE=$3; shift 3 ;;
        --host) [ $# -ge 3 ] || usage; [ "$MODE" = host ] || setmode host
                case "$2$3" in *$'\t'*|*$'\n'*) echo "$PROG: refused: a --host key or value holds a tab or a newline" >&2; exit 65 ;; esac
                HOSTKV="$HOSTKV$2"$'\t'"$3"$'\n'; shift 3 ;;
        --rotation) [ $# -ge 2 ] || usage; setmode rotation; RFILE=$2; shift 2 ;;
        --reasoning-file) [ $# -ge 2 ] || usage; setmode reasoning; RFILE=$2; shift 2 ;;
        --reasoning-check) setmode reasoning-check; shift ;;
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
    run) [ "$KEY" != store ] || { echo "$PROG: refused: run.key: store is not a Run key this script sets; the record's store is always the coordinator's session" >&2; exit 65; }
         [ -n "$BY" ] && [ -z "$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage
         case "$KEY" in arguments|cap|coordinator|rules|briefs|friction|reports-to) ;;
             *) echo "$PROG: --run takes arguments, cap, coordinator, rules, briefs, friction or reports-to" >&2; exit 64 ;; esac ;;
    host) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    rotation|reasoning) [ -r "$RFILE" ] && [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    reasoning-check) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    told) [ -n "$BY" ] && [ -z "$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    standing) [ -n "$WHAT" ] && [ -n "$OWNER" ] && [ -z "$BY$WHO$NEXT" ] || usage ;;
    end) [ -n "$BY" ] && [ -z "$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    work) [ -n "$KIND" ] && [ -n "$WHO" ] && [ -n "$NEXT" ] && [ -z "$BY$WHAT$OWNER$RELAYED$ON$UNTIL" ] || usage ;;
    done) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$ON$UNTIL" ] || usage ;;
    list) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    *) usage ;;
esac
. "$HERE/state-common.sh"
lib_facts
if [ "$MODE" = host ]; then
    # Each key and value checked, then merged into the current record/host.
    TOKEN_RE='(^|[^A-Za-z0-9_-])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,})'
    TAB=$'\t'
    while IFS="$TAB" read -r HK HV; do
        [ -n "$HK" ] || continue
        case "$HK" in
            source_workspace|friction|rules:*|briefs:*)
                case "$HK" in rules:*|briefs:*) [[ ${HK#*:} =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "$PROG: refused: --host $HK: the label is letters, digits, \`.\`, \`_\` and \`-\`" >&2; exit 65; } ;; esac
                case "$HV" in /*) ;; *) echo "$PROG: refused: --host $HK takes an absolute path" >&2; exit 65 ;; esac ;;
            source_session) [[ $HV =~ ^coordinate-[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z$ ]] || { echo "$PROG: refused: --host source_session takes a coordinator session name, coordinate-<slug>-<stamp>" >&2; exit 65; } ;;
            template_hash) [[ $HV =~ ^[0-9a-f]{64}$ ]] || { echo "$PROG: refused: --host template_hash takes 64 hex" >&2; exit 65; } ;;
            *) echo "$PROG: --host takes source_workspace, source_session, template_hash, rules:<label>, briefs:<label> or friction" >&2; exit 64 ;;
        esac
        if LC_ALL=C grep -q '[[:cntrl:]]' <<<"$HV"; then echo "$PROG: refused: --host $HK: a control character" >&2; exit 65; fi
        if grep -Eq "$TOKEN_RE" <<< "$HV"; then echo "$PROG: refused: --host $HK: a token-shaped string" >&2; exit 65; fi
    done <<EOF
$HOSTKV
EOF
    WD=$(mktemp -d "${TMPDIR:-/tmp}/state-stored-set.XXXXXX") || lib_die2 "cannot make a temporary directory"
    trap 'rm -rf "$WD"' EXIT
    rs_host "${RS_SESSION:-$SESSION}" "$WD/host" || lib_die2 "cannot read record/host: $(lib_scrub < "$WD/host.err")"
    printf '%s' "$HOSTKV" | jq -R -s --slurpfile cur "$WD/host" \
        '$cur[0] + (split("\n") | map(select(. != "") | split("\t") | {(.[0]): (.[1:] | join("\t"))}) | add // {})' \
        > "$WD/host.next" || lib_die2 "jq failed"
    lib_write_guard
    . "$HERE/state-write-core.sh"
    core_write_host "$WD/host.next"
    jq -c . "$WD/host.next"
    exit 0
fi
# A discipline rotation's own keys: its window and its
# reasoning for the next rotation. Every rule is checked before any key is
# written.
if [ "$MODE" = rotation ] || [ "$MODE" = reasoning ] || [ "$MODE" = reasoning-check ]; then
    [ "$SCOPE" = discipline ] || { echo "$PROG: refused: record/rotation and record/reasoning are kept only by a discipline rotation" >&2; exit 65; }
    WD=$(mktemp -d "${TMPDIR:-/tmp}/state-stored-set.XXXXXX") || lib_die2 "cannot make a temporary directory"
    trap 'rm -rf "$WD"' EXIT
    RS=${RS_SESSION:-$SESSION}
    if [ "$MODE" = reasoning-check ]; then
        rs_reasoning "$RS" "$WD/reasoning"
        case $? in 0) exit 0 ;; 1) echo "$PROG: the rotation holds no record/reasoning yet" >&2; exit 1 ;; *) lib_die2 "cannot read record/reasoning" ;; esac
    fi
    if [ "$MODE" = rotation ]; then
        SLUG=$(bash "$HERE/coord-log.sh" slug --scope "$SCOPE" --name "$NAME") || lib_die2 "cannot derive the scope's slug"
        jq -e 'type == "object"' "$RFILE" > /dev/null 2>&1 || { echo "$PROG: refused: the rotation is not a JSON object" >&2; exit 65; }
        EXTRA=$(jq -r '[keys[] | select(IN("start", "end", "host_repo", "predecessor") | not)] | first // ""' "$RFILE")
        [ -z "$EXTRA" ] || { echo "$PROG: refused: rotation.$EXTRA is not a field of a rotation (start, end, host_repo, predecessor)" >&2; exit 65; }
        for f in start end host_repo; do
            jq -e --arg f "$f" '(.[$f] | type) == "string" and .[$f] != ""' "$RFILE" > /dev/null \
                || { echo "$PROG: refused: rotation.$f is missing" >&2; exit 65; }
        done
        R_START=$(jq -r .start "$RFILE") R_END=$(jq -r .end "$RFILE") R_HOST=$(jq -r .host_repo "$RFILE")
        lib_valid_date "$R_START" || { echo "$PROG: refused: rotation.start is not a YYYY-MM-DD date" >&2; exit 65; }
        lib_valid_date "$R_END" || { echo "$PROG: refused: rotation.end is not a YYYY-MM-DD date" >&2; exit 65; }
        [ "$R_END" \< "$R_START" ] && { echo "$PROG: refused: rotation.end $R_END is before its start $R_START" >&2; exit 65; }
        [ "$(printf '%s' "$R_HOST" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" ] \
            || { echo "$PROG: refused: rotation.host_repo $R_HOST is not this run's host, $REPO" >&2; exit 65; }
        if ! jq -e '.predecessor == null' "$RFILE" > /dev/null; then
            R_PRED=$(jq -r '.predecessor | if type == "string" then . else "" end' "$RFILE")
            [[ $R_PRED =~ ^coordinate-${SLUG}-[0-9]{8}T[0-9]{6}Z$ ]] \
                || { echo "$PROG: refused: rotation.predecessor is not a session of this discipline, coordinate-$SLUG-<YYYYMMDDTHHMMSSZ>" >&2; exit 65; }
        fi
        jq -c '{start, end, host_repo, predecessor: (.predecessor // null)}' "$RFILE" > "$WD/value.json" || lib_die2 "jq failed"
        KEYNAME=record/rotation
    else
        # 16 KiB: the reasoning is prose a person reads in every carry report.
        RSIZE=$(wc -c < "$RFILE" | tr -d ' ')
        [ "$RSIZE" -le 16384 ] || { echo "$PROG: refused: the reasoning is $RSIZE bytes, over the 16384-byte (16 KiB) limit" >&2; exit 65; }
        [ -n "$(tr -d ' \t\n\r' < "$RFILE")" ] || { echo "$PROG: refused: the reasoning is empty" >&2; exit 65; }
        LC_ALL=C tr -d '\n\t' < "$RFILE" > "$WD/flat" || lib_die2 "cannot read the reasoning"
        if LC_ALL=C grep -q '[[:cntrl:]]' "$WD/flat"; then
            echo "$PROG: refused: the reasoning holds a control character" >&2; exit 65
        fi
        TOKEN_RE='(^|[^A-Za-z0-9_-])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,})'
        if grep -Eq "$TOKEN_RE" "$RFILE"; then echo "$PROG: refused: the reasoning holds a token-shaped string" >&2; exit 65; fi
        jq -R -s -c . "$RFILE" > "$WD/value.json" || lib_die2 "jq failed"
        KEYNAME=record/reasoning
    fi
    # Every string the key holds, through the state's own scan.
    if ! jq -L "$HERE" 'include "state-schema"; scan_strings([]) | empty' "$WD/value.json" 2> "$WD/scan.err"; then
        grep -q 'refused: ' "$WD/scan.err" || lib_die2 "state-schema.jq failed: $(lib_scrub < "$WD/scan.err")"
        echo "$PROG: refused: ${KEYNAME#record/}: $(sed -n 's/.*refused: //p' "$WD/scan.err" | head -1 | lib_scrub)" >&2; exit 65
    fi
    lib_write_guard
    . "$HERE/state-write-core.sh"
    STATE_WRITER=1
    core_write_rotation "$KEYNAME" "$WD/value.json"
    cat "$WD/value.json"
    exit 0
fi
lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/state-stored-set.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT

rs_record "$WD/parsed.json"
case $? in
    0) ;;
    65) echo "$PROG: refused: $(lib_record_name) doesn't read back as a $SCOPE record for $NAME:" >&2; lib_scrub < "$WD/parsed.json.err" >&2; echo >&2; exit 10 ;;
    4) lib_scrub < "$WD/parsed.json.err" >&2; exit 10 ;;
    12) lib_scrub < "$WD/parsed.json.err" >&2; exit 12 ;;
    *) lib_die2 "cannot read the record: $(lib_scrub < "$WD/parsed.json.err" | head -1)" ;;
esac

if [ "$MODE" = list ]; then
    jq -c -L "$HERE" 'include "state-schema"; state_list' "$WD/parsed.json"
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
# How state-entry.sh addresses this record.
if [ "$OVERRIDE" = 1 ]; then
    ADDR_ARGS=(--scope "$SCOPE" --name "$NAME" --repo "$REPO")
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
    elif [ "$KEY" = rules ] || [ "$KEY" = briefs ]; then
        # One row per label: a new digest for a label replaces its row.
        PROG_JQ='($v | split(" ")[0]) as $l
            | .run = ([(.run // [])[] | select((.key == $k and (.value | split(" ")[0]) == $l) | not)] + [{key: $k, value: $v, set_by: $b, set: $t}])'
        ETEXT="Run $KEY $VALUE set by $BY."
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
    case "$KIND" in pause|go-ahead|approval|answer|assignment) ;; *) echo "$PROG: --standing takes pause, go-ahead, approval, answer or assignment" >&2; exit 64 ;; esac
    case "$KIND" in
        pause) [ -n "$ON" ] && [ -n "$UNTIL" ] || { echo "$PROG: a pause takes --on and --until" >&2; exit 64; } ;;
        go-ahead) [ -z "$UNTIL" ] || { echo "$PROG: a go-ahead takes no --until; it ends when used" >&2; exit 64; } ;;
        assignment) [ -n "$ON" ] && [ -z "$UNTIL" ] || { echo "$PROG: an assignment takes --on, the unit assigned, and no --until" >&2; exit 64; } ;;
        *) [ -z "$ON$UNTIL" ] || { echo "$PROG: only a pause, a go-ahead or an assignment takes --on, and only a pause --until" >&2; exit 64; } ;;
    esac
    # The scope must be a unit pick reads, when this session's pick facts say
    # which units those are; an assignment names one pick doesn't list yet.
    if [ -n "$ON" ] && [ "$ON" != all ] && [ "$KIND" != assignment ] && [ "$OVERRIDE" != 1 ] && [ -n "$SESSION" ]; then
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
    ENTRIES=$(bash "$HERE/state-entry.sh" "${ADDR_ARGS[@]}" --list 2> "$WD/list.err") \
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
    case "$KIND" in
        holding|local-agent|decision|follow-up) ;;
        verdict-owed) echo "$PROG: a verdict-owed row is written only by roadmap-status.sh --unit, on a milestone roadmap" >&2; exit 64 ;;
        rework) echo "$PROG: a rework row is written only by roadmap-status.sh --confirm, from a confirmed changes-needed verdict or reopen" >&2; exit 64 ;;
        *) echo "$PROG: --kind takes holding, local-agent, decision or follow-up" >&2; exit 64 ;;
    esac
    if [ "$KIND" = holding ]; then
        jq -e --arg u "$ITEM" --arg w "$WHO" 'any(.holdings[]; .unit == $u and .worker == $w)' "$P" > /dev/null \
            || refuse "no holding has Unit $ITEM and Worker $WHO"
    fi
    # A unit parked on a decision waits on an entry that is still open.
    if [ "$KIND" = decision ]; then
        [[ $WHO =~ ^decision\ [1-9][0-9]*$ ]] || refuse "a decision row's --who is 'decision <n>'"
        jq -e --arg n "${WHO#decision }" 'any((.decisions.entries // [])[]; .decision == $n and .state != "settled")' "$P" > /dev/null \
            || refuse "decision ${WHO#decision } is not an unsettled entry in the record's Decisions section"
    fi
    # Either row names a unit pick lists, when this session's pick facts say
    # which units those are, as a pause's --on does.
    if { [ "$KIND" = decision ] || [ "$KIND" = follow-up ]; } && [ "$OVERRIDE" != 1 ] && [ -n "$SESSION" ] \
        && "$KOTO" context exists "$SESSION" coord/pick.json; then
        "$KOTO" context get "$SESSION" coord/pick.json > "$WD/pick.json" || lib_die2 "cannot read coord/pick.json"
        if jq -e '(.units // []) | type == "array" and length > 0' "$WD/pick.json" > /dev/null; then
            jq -e --arg u "$ITEM" '.host as $h | any(.units[]; .unit == $u or ($h != null and ($h + .unit) == $u))' "$WD/pick.json" > /dev/null \
                || refuse "$ITEM is not a unit pick lists; a $KIND row takes one of: $(jq -r '[.units[].unit] | join(", ")' "$WD/pick.json")"
        fi
    fi
    # A holding's first Work row is written at its dispatch, whose brief named
    # this coordinator's address, so it records the worker as told; a later
    # update records nothing of the kind, since after an address change the
    # worker has been told nothing until --told says so.
    FIRST=true
    jq -e --arg i "$ITEM" 'any((.work // [])[]; .item == $i and .kind == "holding")' "$P" > /dev/null && FIRST=false
    WAKES=0
    if [ "$KIND" = holding ]; then
        PREV=$(jq -c --arg i "$ITEM" '[(.work // [])[] | select(.item == $i and .kind == "holding")][0] // {}' "$P")
        RP=$(jq -r --arg u "$ITEM" --arg w "$WHO" '[.holdings[] | select(.unit == $u and .worker == $w) | .return_path][0] // ""' "$P")
        PREV_UPD=$(printf '%s' "$PREV" | jq -r '.updated // ""') || lib_die2 "jq failed"
        ADD=$(wakes_since "$WHO" "$RP" "$PREV_UPD")
        [ -n "$ADD" ] || lib_die2 "cannot count the run's wakes for $WHO"
        WAKES=$(( $(printf '%s' "$PREV" | jq -r '.wakes // "0" | if . == "" then "0" else . end') + ADD ))
    fi
    # A holding takes over the decision and follow-up rows of its unit, unless
    # it is the scoping holding whose merge wrote the follow-up.
    TAKES=false
    [ "$KIND" = holding ] && ! jq -e --arg u "$ITEM" --arg w "$WHO" 'any(.holdings[]; .unit == $u and .worker == $w and .phase == "scoping")' "$P" > /dev/null && TAKES=true
    jq --arg i "$ITEM" --arg k "$KIND" --arg w "$WHO" --arg n "$NEXT" --arg t "$NOW" --arg c "$WAKES" --arg h "$REPO" --argjson first "$FIRST" --argjson takes "$TAKES" '
        # The row ITEM has under this kind is replaced, and the ones a
        # holding takes over: its unit by tag, a Unit cell `<tag>: <title>`
        # read as its tag, an issue as `#<n>` or `<host>#<n>`.
        ($i | split(": ")[0]) as $tag
        | def same_unit: . == $tag or ($h + .) == $tag or . == ($h + $tag);
        .work = ([(.work // [])[] | select((.item == $i and .kind == $k)
                    or ($takes and (.kind == "decision" or .kind == "follow-up") and (.item | same_unit)) | not)]
                 + [{item: $i, kind: $k, who: $w, next: $n, wakes: $c, updated: $t}])
        | if $k == "holding" and $first and any((.run // [])[]; .key == "coordinator") and (any((.run // [])[]; .key == "told" and .value == $w) | not)
          then .run += [{key: "told", value: $w, set_by: ([.run[] | select(.key == "coordinator") | .value][0]), set: $t}]
          else . end' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=work ETEXT="Next step for $ITEM ($KIND, $WHO): $NEXT."
    [ "$KIND" = holding ] && ETEXT="$ETEXT Wakes so far: $WAKES."
    ;;
done)
    # A verdict-owed row leaves only when its verdict's roadmap edit is
    # confirmed (roadmap-status.sh --confirm), never by hand.
    [ "$KIND" != verdict-owed ] || refuse "a verdict-owed row leaves Work only through roadmap-status.sh --confirm, once its verdict's roadmap edit is on the default branch"
    jq -e --arg i "$ITEM" --arg k "$KIND" 'any((.work // [])[]; .item == $i and .kind != "verdict-owed" and ($k == "" or .kind == $k))' "$P" > /dev/null \
        || refuse "no Work row for $ITEM${KIND:+ of kind $KIND}"
    jq --arg i "$ITEM" --arg k "$KIND" '.work = [(.work // [])[] | select(.item != $i or .kind == "verdict-owed" or ($k != "" and .kind != $k))]' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=work ETEXT="$ITEM${KIND:+ ($KIND)} is done and leaves Work."
    ;;
esac

# The holding rows that leave Work with this write, --done's or the ones whose
# holding is gone, each with its final count, told after the change's entry.
P_NEXT="$WD/next.json"
jq -c '([.holdings[] | "\(.unit)\u0000\(.worker)"]) as $h
    | [(.work // [])[] | select(.kind == "holding" and (("\(.item)\u0000\(.who)" as $k | $h | index($k)) | not))]' "$P_NEXT" > "$WD/leaving.json" || lib_die2 "jq failed"
if [ "$MODE" = done ]; then
    jq -c --arg i "$ITEM" --arg k "$KIND" '[(.work // [])[] | select(.item == $i and .kind == "holding" and ($k == "" or $k == "holding"))]' "$P" > "$WD/done.json" || lib_die2 "jq failed"
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
    LUPD=$(printf '%s' "$ROW" | jq -r '.updated // ""') || lib_die2 "jq failed"
    LADD=$(wakes_since "$LW" "$LRP" "$LUPD")
    [ -n "$LADD" ] || lib_die2 "cannot count the run's wakes for $LW"
    LTOT=$(( $(printf '%s' "$ROW" | jq -r '.wakes // "0" | if . == "" then "0" else . end') + LADD ))
    printf '%s\n' "$(printf '%s' "$ROW" | jq -r .item) ($LW) left Work after $LTOT wakes." >> "$WD/leaving.txt"
    i=$((i + 1))
done

# Every write drops a holding's Work row whose holding is gone, and keeps the
# written time of the version read, which the write core compares with the
# live record's before it stamps its own. The state file stays in this
# script's private directory, readable by its owner only, and goes with it.
jq --arg w "$(jq -r '.written' "$P")" '([.holdings[] | "\(.unit)\u0000\(.worker)"]) as $h
    | .work = [(.work // [])[] | select(.kind != "holding" or ("\(.item)\u0000\(.who)" as $k | $h | index($k)))]
    | if (.work | length) == 0 then del(.work) else . end
    | if ((.run // []) | length) == 0 then del(.run) else . end
    | if ((.standing // []) | length) == 0 then del(.standing) else . end
    | .written = $w' "$WD/next.json" > "$WD/final.json" || lib_die2 "jq failed"
chmod 600 "$WD/final.json" || lib_die2 "cannot make the state file private"
printf '%s\n' "$ETEXT" > "$WD/entry.txt"
# The write core takes over $T and the EXIT trap and removes $WD, so the
# entries' text is kept outside it.
ENTRY_FILE=$(mktemp "${TMPDIR:-/tmp}/record-state-entry.XXXXXX") || lib_die2 "cannot make a temporary file"
cp "$WD/entry.txt" "$ENTRY_FILE"
LEAVING_FILE=$(mktemp "${TMPDIR:-/tmp}/record-state-leaving.XXXXXX") \
    || { rm -f "$ENTRY_FILE"; lib_die2 "cannot make a temporary file"; }
cp "$WD/leaving.txt" "$LEAVING_FILE"

STATE_FILE="$WD/final.json" CORE_CLEANUP=$WD
lib_write_guard
. "$HERE/state-write-core.sh"
STATE_WRITER=1
core_write

if ! bash "$HERE/state-entry.sh" "${ADDR_ARGS[@]}" --kind "$EKIND" --text-file "$ENTRY_FILE"; then
    echo "$PROG: the record was written, but its entry wasn't posted; post it with state-entry.sh --kind $EKIND: $(cat "$ENTRY_FILE")" >&2
    while IFS= read -r LINE; do
        [ -n "$LINE" ] && echo "$PROG: and post with state-entry.sh --kind work: $LINE" >&2
    done < "$LEAVING_FILE"
    rm -f "$ENTRY_FILE" "$LEAVING_FILE"
    exit 14
fi
rm -f "$ENTRY_FILE"
# Each holding row that left Work, told with its final count. Every line is
# tried; any that didn't post are named together, for state-entry.sh.
UNPOSTED=0
while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    printf '%s\n' "$LINE" > "$LEAVING_FILE.one"
    if ! bash "$HERE/state-entry.sh" "${ADDR_ARGS[@]}" --kind work --text-file "$LEAVING_FILE.one"; then
        echo "$PROG: the record was written, but a final count wasn't posted; post it with state-entry.sh --kind work: $LINE" >&2
        UNPOSTED=1
    fi
done < "$LEAVING_FILE"
rm -f "$LEAVING_FILE" "$LEAVING_FILE.one"
[ "$UNPOSTED" = 0 ] || exit 14
