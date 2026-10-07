#!/usr/bin/env bash
# record-hold.sh -- add, lift or list the record's holds on merges. Agent-run;
# the Holds section changes only through this script
# (docs/designs/current/DESIGN-coordinate-merge-policy.md, Decision 6).
#
# Usage:
#   record-hold.sh --session S --add --row-file F          add a hold
#   record-hold.sh --session S --lift --hold H --by WHO    lift a `lifted` hold
#   record-hold.sh --session S --list                      print every hold
#   ... [--scope roadmap|discipline --name N --repo O/R --ref N
#        --skip-session-checks]                            (tests)
#
# The session gives the scope, name, host and record number (coord-log.sh
# vars and run-facts); the override flags exist for tests only.
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
# Every write renders with the Written: time of the version read and goes
# through the record's write core (record-write-core.sh), which re-reads the
# target and checks provenance, directed transitions and repository
# visibility first. This is the one script that sets HOLDS_WRITER=1; every
# other writer must carry the section as the live record has it.
#
# Exit codes: 0 written (prints the URL) or printed; 2 a read failed; 10
# refused (the target isn't an open record of this scope, provenance, or a
# directed transition); 11 the write failed; 12 the record changed between
# this script's read and its write; 13 the record is full; 64 usage; 65 the
# hold was refused (the reason on stderr).
#
# GitHub reads: gh issue view N --repo R --json body | gh pr view N --repo R
# --json body; writes happen only in record-write.sh.
set -uo pipefail

PROG=record-hold
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= ROWFILE= MODE= HOLD= BY=
SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
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

WD=$(mktemp -d "${TMPDIR:-/tmp}/record-hold.XXXXXX")
trap 'rm -rf "$WD"' EXIT

if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.md" < /dev/null || lib_die2 "cannot read issue #$REF"
else
    gh pr view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.md" < /dev/null || lib_die2 "cannot read pull request #$REF"
fi
lib_parse "$WD/live.md" "$WD/parsed.json"
case $? in
    0) ;;
    3|65) echo "$PROG: refused: #$REF is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$WD/parsed.json.err" >&2; echo >&2; exit 10 ;;
    *) lib_die2 "record-parse.sh failed" ;;
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
    jq --slurpfile row "$ROWFILE" '.holds = ((.holds // []) + [$row[0] + {lifted: ""}]) | del(.written)' \
        "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    ;;
lift)
    ROW=$(jq -c --arg h "$HOLD" '[.holds[]? | select(.hold == $h)][0] // empty' "$WD/parsed.json")
    [ -n "$ROW" ] || { echo "$PROG: refused: no hold named $HOLD" >&2; exit 65; }
    [ "$(printf '%s' "$ROW" | jq -r .until)" = lifted ] \
        || { echo "$PROG: refused: $HOLD waits on $(printf '%s' "$ROW" | jq -r .until), which the land check reads; only a \`lifted\` hold is lifted by hand" >&2; exit 65; }
    [ "$(printf '%s' "$ROW" | jq -r .lifted)" = "" ] || { echo "$PROG: refused: $HOLD is already lifted" >&2; exit 65; }
    NOW=$(date -u +%Y-%m-%dT%H:%MZ)
    jq --arg h "$HOLD" --arg l "$NOW by $BY" '.holds |= map(if .hold == $h then .lifted = $l else . end) | del(.written)' \
        "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    ;;
esac

# The render keeps the Written: time of the version just read: the write core
# compares it with the live body's and refuses when someone wrote in between,
# then stamps its own time.
bash "$HERE/record-render.sh" --container "$CONTAINER" --written "$(jq -r '.written' "$WD/parsed.json")" "$WD/next.json" > "$WD/body.md" 2> "$WD/render.err" \
    || { echo "$PROG: refused:" >&2; lib_scrub < "$WD/render.err" >&2; echo >&2; exit 65; }

# Through the write core, with the Holds section opened to this script alone:
# the core still refuses a write that drops or changes an existing hold
# beyond stamping its blank Lifted cell.
BODY="$WD/body.md" END= CLOSE=0 CORE_CLEANUP=$WD
lib_write_guard
. "$HERE/record-write-core.sh"
HOLDS_WRITER=1
core_write
