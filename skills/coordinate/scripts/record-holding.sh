#!/usr/bin/env bash
# record-holding.sh -- add, update or read one Holdings row by its dispatch
# topic. Agent-run; the dispatch path and reconcile change holding rows only
# through this script, so a row is never hand-edited into the body.
#
# Usage:
#   record-holding.sh --session S --topic T --row-file F    write the row
#   record-holding.sh --session S --topic T --read          print the row
#   record-holding.sh --session S --list                    print every row
#   ... [--scope roadmap|discipline --name N --repo O/R --ref N
#        --skip-session-checks]                             (tests)
#
# The session gives the scope, name, host and record number (coord-log.sh
# vars and run-facts); the override flags exist for tests only.
#
# Every mode reads the live body (gh issue view / gh pr view) and parses it
# canonically. --read prints the row whose Worker equals T as one compact JSON
# object. --list prints every Holdings row as a JSON array in record order
# ([] when Holdings is None.). A write takes F holding the Holdings keys
# (unit, entry_point, mode, phase, dispatch_status, return_path, worker, repo,
# branch, verified_head, dispatched, pull_request) with worker equal to T,
# replaces the row whose Worker is T or appends it, drops deferrals already
# filed or closed when the run has dispatched, renders with a new Written:
# time, and writes the whole body through record-write.sh, which re-reads the
# target and checks provenance, directed transitions and repository
# visibility first.
#
# Exit codes: 0 written (prints the URL) or printed; 1 no row for the topic
# (--read only); 2 a read failed; 10 refused (the target isn't an open record
# of this scope, provenance, or a directed transition); 12 the record changed
# between this script's read and its write (record-changed: run it again); 11
# the write failed; 13 the record is full (record-full: the body would pass
# the write core's size budget); 64 usage; 65 the row was refused (the reason
# on stderr).
#
# GitHub reads: gh issue view N --repo R --json body | gh pr view N --repo R
# --json body; writes happen only in record-write.sh.
set -uo pipefail

PROG=record-holding
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= TOPIC= ROWFILE= MODE=
SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --topic) [ $# -ge 2 ] || usage; TOPIC=$2; shift 2 ;;
        --row-file) [ $# -ge 2 ] || usage; [ -z "$MODE" ] || usage; MODE=write; ROWFILE=$2; shift 2 ;;
        --read) [ -z "$MODE" ] || usage; MODE=read; shift ;;
        --list) [ -z "$MODE" ] || usage; MODE=list; shift ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$MODE" in
    write) [ -n "$TOPIC" ] && [ -r "$ROWFILE" ] || usage ;;
    read) [ -n "$TOPIC" ] || usage ;;
    list) [ -z "$TOPIC" ] || usage ;;
    *) usage ;;
esac
. "$HERE/record-common.sh"
# The topic is a Worker cell: the dispatch-topic shape.
if [ -n "$TOPIC" ] && ! [[ $TOPIC =~ $RE_TOPIC ]]; then usage; fi
lib_facts
if [ "$OVERRIDE" = 1 ]; then
    [ -n "$REF" ] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
else
    [ -z "$REF" ] || usage
    FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION" 2>/dev/null)
    case $? in
        0) REF=$(printf '%s' "$FACTS" | jq -r '.ref') ;;
        1) echo "$PROG: refused: the run has no found record" >&2; exit 10 ;;
        *) lib_die2 "cannot read the run's facts" ;;
    esac
fi
[[ $REF =~ $RE_NUM ]] || usage

T=$(mktemp -d "${TMPDIR:-/tmp}/record-holding.XXXXXX")
trap 'rm -rf "$T"' EXIT

if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json body --jq .body > "$T/live.md" 2> /dev/null < /dev/null || lib_die2 "cannot read issue #$REF"
else
    gh pr view "$REF" --repo "$REPO" --json body --jq .body > "$T/live.md" 2> /dev/null < /dev/null || lib_die2 "cannot read pull request #$REF"
fi
lib_parse "$T/live.md" "$T/parsed.json"
case $? in
    0) ;;
    3|65) echo "$PROG: refused: #$REF is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$T/parsed.json.err" >&2; echo >&2; exit 10 ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac

case "$MODE" in
read)
    ROW=$(jq -c --arg t "$TOPIC" '[.holdings[] | select(.worker == $t)][0] // empty' "$T/parsed.json")
    [ -n "$ROW" ] || exit 1
    printf '%s\n' "$ROW"
    exit 0
    ;;
list)
    jq -c '.holdings' "$T/parsed.json"
    exit 0
    ;;
esac

jq -e 'type == "object"' "$ROWFILE" > /dev/null 2>&1 || { echo "$PROG: refused: the row file is not a JSON object" >&2; exit 65; }
W=$(jq -r '.worker // ""' "$ROWFILE")
[ "$W" = "$TOPIC" ] || { echo "$PROG: refused: the row's worker ($W) is not the topic $TOPIC" >&2; exit 65; }
jq --slurpfile row "$ROWFILE" --arg t "$TOPIC" '
    if any(.holdings[]; .worker == $t)
    then .holdings |= map(if .worker == $t then $row[0] else . end)
    else .holdings += $row end | del(.written)' "$T/parsed.json" > "$T/next.json" || lib_die2 "jq failed"
if lib_dispatched; then
    lib_drop_disposed "$T/next.json" "$T/dropped.json"
    mv "$T/dropped.json" "$T/next.json"
fi
# The render keeps the Written: time of the version just read: record-write.sh
# compares it with the live body's and refuses when someone wrote in between,
# then stamps its own time.
bash "$HERE/record-render.sh" --container "$CONTAINER" --written "$(jq -r '.written' "$T/parsed.json")" "$T/next.json" > "$T/body.md" 2> "$T/render.err" \
    || { echo "$PROG: refused:" >&2; lib_scrub < "$T/render.err" >&2; echo >&2; exit 65; }

set -- --body-file "$T/body.md"
[ -n "$SESSION" ] && set -- "$@" --session "$SESSION"
if [ "$OVERRIDE" = 1 ]; then
    set -- "$@" --scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF"
    [ "$SKIP_CHECKS" = 1 ] && set -- "$@" --skip-session-checks
fi
bash "$HERE/record-write.sh" "$@"
