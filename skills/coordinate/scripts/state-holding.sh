#!/usr/bin/env bash
# state-holding.sh -- add, update or read one Holdings row by its dispatch
# topic. Agent-run; the dispatch path and reconcile change holding rows only
# through this script, so a row is never hand-edited into the record.
#
# Usage:
#   state-holding.sh --session S --topic T --row-file F    write the row
#   state-holding.sh --session S --topic T --pushed-head SHA
#                                                           set its pushed head
#   state-holding.sh --session S --topic T --read          print the row
#   state-holding.sh --session S --list                    print every row
#   state-holding.sh --session S --topic T --strand        mark it stranded
#   state-holding.sh --session S --topic T --retire        remove a stranded row
#   ... [--scope roadmap|discipline --name N --repo O/R
#        --skip-session-checks]                             (tests)
#
# The session gives the scope, name and host (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts); the override flags exist for
# tests only, with RS_SESSION naming the session that holds the record.
#
# Every mode reads the live record through state-read.sh. --read prints the
# row whose Worker equals T as one compact JSON
# object. --list prints every Holdings row as a JSON array in record order
# ([] when Holdings is None.). A write takes F holding the Holdings keys
# (unit, entry_point, mode, phase, dispatch_status, return_path, worker, repo,
# branch, verified_head, dispatched, pull_request) with worker equal to T,
# replaces the row whose Worker is T or appends it, drops deferrals already
# filed or closed when the run has dispatched, and writes the whole state
# through state-write.sh, which re-reads the target and checks provenance,
# directed transitions and repository visibility first.
#
# A row with a Verified head and a blank Pull request cell reads as merged and
# waiting for teardown (state-common.sh lib_row_merged): only the cleared
# cell after a confirmed merge writes that pair, so no other write may.
#
# A holding also keeps its last pushed head, the pull request's head as a
# report or a link last read it (PRD R17): 40 hex, never in the row.
# --pushed-head sets it, or clears it with an empty SHA, and changes nothing
# else; a row file may carry it as `pushed_head`. --pushed-head reads no state:
# the state doesn't change, so state-write.sh --pushed-head with no state file
# rewrites only the session key that keeps the head (shirabe#1094), and refuses
# it for a topic no holding has. --read and --list print it.
#
# --strand marks a holding `stranded`: the coordinator's choice to dispatch its
# unit again when the worker reports by message and the quiet checks reached
# the failure branch (PRD R15; shirabe#732). Only a `dispatched` holding whose
# Return path is `message` may be stranded; any other is refused (65), since a
# leg-bound worker's end still arrives on its leg. dispatch-worker.sh treats a
# stranded topic as it treats a failed one: the unit goes out again under a
# new topic, whose brief names this row's branch and last pushed head, and
# --retire removes the stranded row once the new worker is dispatched. A report
# that later arrives from the retired topic matches no holding and is refused.
# --retire refuses (65) a row that isn't stranded.
#
# Exit codes: 0 written (prints the session holding the record) or printed; 1
# no row for the topic (--read only); 2 a read failed; 10 refused (no found
# record, the session holds no record of this scope, provenance, or a directed
# transition); 12 the record changed
# between this script's read and its write (record-changed: run it again); 11
# the write failed; 64 usage; 65 the row was refused (the reason on stderr).
#
# The record is read through state-read.sh; writes happen only in
# state-write.sh.
set -uo pipefail

PROG=state-holding
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= TOPIC= ROWFILE= MODE= PUSHED=
SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --topic) [ $# -ge 2 ] || usage; TOPIC=$2; shift 2 ;;
        --row-file) [ $# -ge 2 ] || usage; [ -z "$MODE" ] || usage; MODE=write; ROWFILE=$2; shift 2 ;;
        --pushed-head) [ $# -ge 2 ] || usage; [ -z "$MODE" ] || usage; MODE=pushed; PUSHED=$2; shift 2 ;;
        --read) [ -z "$MODE" ] || usage; MODE=read; shift ;;
        --list) [ -z "$MODE" ] || usage; MODE=list; shift ;;
        --strand) [ -z "$MODE" ] || usage; MODE=strand; shift ;;
        --retire) [ -z "$MODE" ] || usage; MODE=retire; shift ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$MODE" in
    write) [ -n "$TOPIC" ] && [ -r "$ROWFILE" ] || usage ;;
    pushed|read|strand|retire) [ -n "$TOPIC" ] || usage ;;
    list) [ -z "$TOPIC" ] || usage ;;
    *) usage ;;
esac
. "$HERE/state-common.sh"
# The topic is a Worker cell: the dispatch-topic shape.
if [ -n "$TOPIC" ] && ! [[ $TOPIC =~ $RE_TOPIC ]]; then usage; fi
lib_facts
lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

if [ "$MODE" = pushed ]; then
    set -- --pushed-head "$TOPIC" "$PUSHED"
    [ -n "$SESSION" ] && set -- "$@" --session "$SESSION"
    if [ "$OVERRIDE" = 1 ]; then
        set -- "$@" --scope "$SCOPE" --name "$NAME" --repo "$REPO"
        [ "$SKIP_CHECKS" = 1 ] && set -- "$@" --skip-session-checks
    fi
    exec bash "$HERE/state-write.sh" "$@"
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/state-holding.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

# --read and --list print Holdings alone, so they read that one section; a
# write's mode reads the whole record it writes back (shirabe#1315).
case "$MODE" in read|list) FIELDS=holdings ;; *) FIELDS= ;; esac
rs_record "$T/parsed.json" "$FIELDS"
case $? in
    0) ;;
    65) echo "$PROG: refused: $(lib_record_name) doesn't read back as a $SCOPE record for $NAME:" >&2; lib_scrub < "$T/parsed.json.err" >&2; echo >&2; exit 10 ;;
    4) lib_scrub < "$T/parsed.json.err" >&2; exit 10 ;;
    12) lib_scrub < "$T/parsed.json.err" >&2; exit 12 ;;
    *) lib_die2 "cannot read the record: $(lib_scrub < "$T/parsed.json.err" | head -1)" ;;
esac

# Each holding's pushed head, {worker: sha}, kept beside the row (the seam's
# <out>.pushed); {} when none is kept.
[ -s "$T/parsed.json.pushed" ] || echo '{}' > "$T/parsed.json.pushed"
case "$MODE" in
read)
    ROW=$(jq -c --arg t "$TOPIC" --slurpfile p "$T/parsed.json.pushed" \
        '[.holdings[] | select(.worker == $t) | if $p[0][$t] then . + {pushed_head: $p[0][$t]} else . end][0] // empty' "$T/parsed.json")
    [ -n "$ROW" ] || exit 1
    printf '%s\n' "$ROW"
    exit 0
    ;;
list)
    jq -c -L "$HERE" --slurpfile p "$T/parsed.json.pushed" \
        'include "state-schema"; holdings_list | map(.worker as $w | if $p[0][$w] then . + {pushed_head: $p[0][$w]} else . end)' "$T/parsed.json"
    exit 0
    ;;
strand|retire)
    ROW=$(jq -c --arg t "$TOPIC" '[.holdings[] | select(.worker == $t)][0] // empty' "$T/parsed.json")
    [ -n "$ROW" ] || { echo "$PROG: refused: no holding's Worker is $TOPIC" >&2; exit 65; }
    ST=$(jq -r '.dispatch_status' <<< "$ROW")
    if [ "$MODE" = strand ]; then
        [ "$ST" = dispatched ] || { echo "$PROG: refused: only a dispatched holding is stranded; $TOPIC is $ST" >&2; exit 65; }
        [ "$(jq -r '.return_path' <<< "$ROW")" = message ] \
            || { echo "$PROG: refused: only a holding on the message path is stranded; $TOPIC reports on $(jq -r '.return_path' <<< "$ROW")" >&2; exit 65; }
        jq --arg t "$TOPIC" '.holdings |= map(if .worker == $t then .dispatch_status = "stranded" else . end)' \
            "$T/parsed.json" > "$T/next.json" || lib_die2 "jq failed"
    else
        [ "$ST" = stranded ] || { echo "$PROG: refused: only a stranded holding is retired; $TOPIC is $ST" >&2; exit 65; }
        jq --arg t "$TOPIC" '.holdings |= map(select(.worker != $t))' "$T/parsed.json" > "$T/next.json" || lib_die2 "jq failed"
    fi
    ;;
write)
    jq -e 'type == "object"' "$ROWFILE" > /dev/null 2>&1 || { echo "$PROG: refused: the row file is not a JSON object" >&2; exit 65; }
    W=$(jq -r '.worker // ""' "$ROWFILE")
    [ "$W" = "$TOPIC" ] || { echo "$PROG: refused: the row's worker ($W) is not the topic $TOPIC" >&2; exit 65; }
    # A pushed head in the row goes beside it, through state-write.sh, never
    # into the row.
    if jq -e 'has("pushed_head")' "$ROWFILE" > /dev/null; then
        MODE=pushed PUSHED=$(jq -r '.pushed_head | tostring' "$ROWFILE")
    fi
    jq --slurpfile row "$ROWFILE" --arg t "$TOPIC" '($row[0] | del(.pushed_head)) as $r
        | if any(.holdings[]; .worker == $t)
        then .holdings |= map(if .worker == $t then $r else . end)
        else .holdings += [$r] end' "$T/parsed.json" > "$T/next.json" || lib_die2 "jq failed"
    ;;
esac
if lib_dispatched; then
    lib_drop_disposed "$T/next.json" "$T/dropped.json"
    mv "$T/dropped.json" "$T/next.json"
fi
# The state keeps the written time of the version just read: state-write.sh
# compares it with the live record's and refuses when someone wrote in
# between, then stamps its own time. The file stays in this script's private
# directory, readable by its owner only, and goes with it.
chmod 600 "$T/next.json" || lib_die2 "cannot make the state file private"

set -- --state-file "$T/next.json"
[ "$MODE" = pushed ] && set -- "$@" --pushed-head "$TOPIC" "$PUSHED"
[ -n "$SESSION" ] && set -- "$@" --session "$SESSION"
if [ "$OVERRIDE" = 1 ]; then
    set -- "$@" --scope "$SCOPE" --name "$NAME" --repo "$REPO"
    [ "$SKIP_CHECKS" = 1 ] && set -- "$@" --skip-session-checks
fi
bash "$HERE/state-write.sh" "$@"
