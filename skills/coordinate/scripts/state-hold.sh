#!/usr/bin/env bash
# state-hold.sh -- add, lift or list the record's holds on merges. Agent-run;
# the Holds section changes only through this script
# (docs/designs/current/DESIGN-coordinate-merge-policy.md, Decision 6).
#
# Usage:
#   state-hold.sh --session S --add --row-file F          add a hold
#   state-hold.sh --session S --lift --hold H --by WHO    lift a `lifted` hold
#   state-hold.sh --session S --list                      print every hold
#   ... [--scope roadmap|discipline --name N --repo O/R
#        --skip-session-checks]                            (tests)
#
# The session gives the scope, name and host (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts); the override flags exist for
# tests only, with RS_SESSION naming the session that holds the record.
#
# --add takes F holding a hold's keys (hold, on, until, set_by, set) with
# lifted empty, and appends it; a hold of the same name is refused. --lift
# stamps the named hold's Lifted cell with the current minute and WHO
# (`<YYYY-MM-DDTHH:MMZ> by <who>`); only a hold whose Until reads `lifted`
# is lifted by hand, since the other conditions are read live by the land
# check and lift themselves when GitHub says so. A hold is never deleted: its
# row is what the record says about who held what, and a merge made while it
# stood is written beside it as a Reversals row. --list prints the section as
# a JSON array ([] when there is none).
#
# Every write carries the written time of the version read and goes
# through the record's write core (state-write-core.sh), which re-reads the
# target and checks provenance, directed transitions and repository
# visibility first. This is the one script that sets HOLDS_WRITER=1; every
# other writer must carry the section as the live record has it.
#
# Each add and lift is also told as a `hold` entry in the account
# (state-entry.sh), since the record keeps no history of its own that would
# show it.
#
# Exit codes: 0 written (prints the session holding the record) or printed; 2
# a read failed; 10 refused (no found record, the session holds no record of
# this scope, provenance, or a directed transition); 11 the write failed; 12
# the record changed between
# this script's read and its write; 14 the hold was
# written but its session entry wasn't (the entry to post on stderr); 64 usage;
# 65 the hold was refused (the reason on stderr).
#
# The record is read through state-read.sh; the write happens only in the
# write core it sources (state-write-core.sh).
set -uo pipefail

PROG=state-hold
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= ROWFILE= MODE= HOLD= BY=
SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --row-file) [ $# -ge 2 ] || usage; ROWFILE=$2; shift 2 ;;
        --hold) [ $# -ge 2 ] || usage; HOLD=$2; shift 2 ;;
        --by) [ $# -ge 2 ] || usage; BY=$2; shift 2 ;;
        --add) [ -z "$MODE" ] || usage; MODE=add; shift ;;
        --lift) [ -z "$MODE" ] || usage; MODE=lift; shift ;;
        --list) [ -z "$MODE" ] || usage; MODE=list; shift ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$MODE" in
    add) [ -r "$ROWFILE" ] && [ -z "$HOLD$BY" ] || usage ;;
    lift) [ -n "$HOLD" ] && [ -n "$BY" ] && [ -z "$ROWFILE" ] || usage ;;
    list) [ -z "$ROWFILE$HOLD$BY" ] || usage ;;
    *) usage ;;
esac
. "$HERE/state-common.sh"
lib_facts
lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/state-hold.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT

# The live record, through the seam (state-read.sh), which reads it with
# the line endings the write core reads.
rs_record "$WD/parsed.json"
case $? in
    0) ;;
    65) echo "$PROG: refused: $(lib_record_name) doesn't read back as a $SCOPE record for $NAME:" >&2; lib_scrub < "$WD/parsed.json.err" >&2; echo >&2; exit 10 ;;
    4) lib_scrub < "$WD/parsed.json.err" >&2; exit 10 ;;
    12) lib_scrub < "$WD/parsed.json.err" >&2; exit 12 ;;
    *) lib_die2 "cannot read the record: $(lib_scrub < "$WD/parsed.json.err" | head -1)" ;;
esac

case "$MODE" in
list)
    jq -c '.holds // []' "$WD/parsed.json"
    exit 0
    ;;
add)
    jq -e 'type == "object"' "$ROWFILE" > /dev/null || { echo "$PROG: refused: the row file is not a JSON object" >&2; exit 65; }
    [ "$(jq -r '.lifted // ""' "$ROWFILE")" = "" ] || { echo "$PROG: refused: a new hold isn't lifted" >&2; exit 65; }
    H=$(jq -r '.hold // ""' "$ROWFILE")
    if jq -e --arg h "$H" 'any(.holds[]?; .hold == $h)' "$WD/parsed.json" > /dev/null; then
        echo "$PROG: refused: a hold named $H is already in the record" >&2; exit 65
    fi
    jq --slurpfile row "$ROWFILE" '.holds = ((.holds // []) + [$row[0] + {lifted: ""}])' \
        "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    ;;
lift)
    ROW=$(jq -c --arg h "$HOLD" '[.holds[]? | select(.hold == $h)][0] // empty' "$WD/parsed.json")
    [ -n "$ROW" ] || { echo "$PROG: refused: no hold named $HOLD" >&2; exit 65; }
    [ "$(printf '%s' "$ROW" | jq -r .until)" = lifted ] \
        || { echo "$PROG: refused: $HOLD waits on $(printf '%s' "$ROW" | jq -r .until), which the land check reads; only a \`lifted\` hold is lifted by hand" >&2; exit 65; }
    [ "$(printf '%s' "$ROW" | jq -r .lifted)" = "" ] || { echo "$PROG: refused: $HOLD is already lifted" >&2; exit 65; }
    NOW=$(date -u +%Y-%m-%dT%H:%MZ)
    jq --arg h "$HOLD" --arg l "$NOW by $BY" '.holds |= map(if .hold == $h then .lifted = $l else . end)' \
        "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    ;;
esac

# The state keeps the written time of the version just read: the write core
# compares it with the live record's and refuses when someone wrote in
# between, then stamps its own time. The file stays in this script's private
# directory, readable by its owner only, and goes with it after the write.
chmod 600 "$WD/next.json" || lib_die2 "cannot make the state file private"

# Through the write core, with the Holds section opened to this script alone:
# the core still refuses a write that drops or changes an existing hold
# beyond stamping its blank Lifted cell.
STATE_FILE="$WD/next.json" CORE_CLEANUP=$WD
lib_write_guard
. "$HERE/state-write-core.sh"
HOLDS_WRITER=1
core_write

# The record keeps no history of a hold's change, so each add and lift is also
# told as a `hold` entry in the account.
if [ "$MODE" = add ]; then
    jq -r '"Hold \(.hold) added on \(.on), until \(.until), set by \(.set_by)."' "$ROWFILE" > "$T/hold-entry" || lib_die2 "jq failed"
else
    printf 'Hold %s lifted by %s.\n' "$HOLD" "$BY" > "$T/hold-entry"
fi
if [ "$OVERRIDE" = 1 ]; then
    ADDR_ARGS=(--scope "$SCOPE" --name "$NAME" --repo "$REPO")
else
    ADDR_ARGS=(--session "$SESSION")
fi
if ! bash "$HERE/state-entry.sh" "${ADDR_ARGS[@]}" --kind hold --text-file "$T/hold-entry" > /dev/null; then
    echo "$PROG: the hold was written, but its entry wasn't; post it with state-entry.sh --kind hold: $(cat "$T/hold-entry")" >&2
    exit 14
fi
