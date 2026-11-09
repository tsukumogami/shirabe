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
#   state-holding.sh --session S --topic T --retire        remove a stranded row,
#                                                           a merged one torn
#                                                           down outside the pass,
#                                                           or a dispatch-failed
#                                                           one with no worker
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
#
# --retire also removes a merged holding (lib_row_merged) whose worker was torn
# down outside the pass, at destroy, once `teardown-pass.sh check --session S
# --topic T` confirms the run's removed verdict for T (shirabe#1593): a
# leg-bound holding can never be stranded, so without it the row would stay.
# The check is read-only; STATE_HOLDING_TEARDOWN_PASS names a stand-in for it
# (tests). --retire refuses (65) a row that is neither stranded nor merged, and
# a merged one the check doesn't confirm, with the check's reason.
#
# --retire also removes a `dispatch-failed` holding (shirabe#1612): a launch
# that failed leaves its row, and once the run has moved past the dispatch state
# for that topic (a run continued by a takeover, say) nothing else removes it,
# while pick still counts it against the cap. It goes only when no worker exists
# for its topic: niwa lists no session for it (dc_find_session, the test
# dispatch-worker.sh made before it wrote the row dispatch-failed), and no
# Claude job under DC_CLAUDE_HOME (default $HOME/.claude) whose name is the
# topic's session name is unfinished (dc_job_finished). A job state file whose
# name can't be read refuses too, since it can't be ruled out. Either one found
# refuses the retire (65) with what was found; a listing that can't be read, or
# no workspace root to read it from, exits 2 with nothing written. Both checks
# see only this host: the niwa listing of the workspace the current directory
# is in, and the jobs under DC_CLAUDE_HOME. NIWA names a stand-in for niwa
# (tests).
# Its removal is also told as an `entry` entry naming the topic; when the row
# was removed but the entry wasn't written, it exits 14 with the entry's text.
#
# Exit codes: 0 written (prints the session holding the record) or printed; 1
# no row for the topic (--read only); 2 a read failed, --retire's teardown
# check couldn't run, or its worker listing couldn't be read; 10 refused (no found
# record, the session holds no record of this scope, provenance, or a directed
# transition); 12 the record changed
# between this script's read and its write (record-changed: run it again); 11
# the write failed; 14 a dispatch-failed row was removed but its entry wasn't
# written; 64 usage; 65 the row was refused (the reason on stderr).
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
        if [ "$ST" = dispatch-failed ]; then
            # A failed launch's row goes only once no worker exists for its
            # topic (shirabe#1612): no niwa session, then no unfinished job.
            . "$HERE/dispatch-common.sh" || lib_die2 "cannot source dispatch-common.sh"
            WS_ROOT=$(dc_workspace_root) || lib_die2 "no workspace root to look for $TOPIC's instance from"
            FOUND=$(dc_find_session "$WS_ROOT" "$TOPIC")
            case $? in
                0)
                    echo "$PROG: refused: niwa lists $TOPIC's session $(printf '%s' "${FOUND%%	*}" | lib_scrub) at $(printf '%s' "${FOUND#*	}" | lib_scrub); a dispatch-failed holding is retired only when no worker exists for it" >&2
                    exit 65 ;;
                1) ;;
                *) lib_die2 "niwa's listing can't be read, so $TOPIC's worker can't be ruled out" ;;
            esac
            JOBS_HOME=${DC_CLAUDE_HOME:-$HOME/.claude}
            for JF in "$JOBS_HOME"/jobs/*/state.json; do
                [ -f "$JF" ] || continue
                JOB=${JF%/state.json} JOB=${JOB##*/}
                # Fail closed: a state file that isn't JSON, or has no string
                # name, could be this topic's worker, so it refuses the retire.
                if ! JNAME=$(jq -er '.name | strings' "$JF" 2>/dev/null); then
                    echo "$PROG: refused: Claude job $(printf '%s' "$JOB" | lib_scrub) has no readable name in its state file, so it can't be ruled out as $TOPIC's worker; a dispatch-failed holding is retired only when no worker exists for it" >&2
                    exit 65
                fi
                dc_session_matches "$TOPIC" "$JNAME" || continue
                if ! WHY=$(dc_job_finished "$JOBS_HOME" "$JOB" '{}'); then
                    echo "$PROG: refused: Claude job $(printf '%s' "$JOB" | lib_scrub) carries $TOPIC's session and isn't finished ($(printf '%s' "$WHY" | lib_scrub)); a dispatch-failed holding is retired only when no worker exists for it" >&2
                    exit 65
                fi
            done
            jq -r '"Holding \(.worker) (unit \(.unit)) retired: its dispatch failed, and no niwa session or unfinished Claude job exists for it."' \
                <<< "$ROW" > "$T/retire-entry" || lib_die2 "jq failed"
        elif [ "$ST" != stranded ]; then
            # A merged holding whose worker was torn down outside the pass
            # goes once teardown-pass.sh check confirms its removed verdict
            # (shirabe#1593); a live one never does.
            lib_row_merged "$ROW" \
                || { echo "$PROG: refused: only a stranded holding, a merged one whose removed teardown is confirmed, or a dispatch-failed one with no worker, is retired; $TOPIC is $ST" >&2; exit 65; }
            CHECK_OUT=$(bash "${STATE_HOLDING_TEARDOWN_PASS:-$HERE/teardown-pass.sh}" check \
                --session "${RS_SESSION:-${SESSION:-}}" --topic "$TOPIC" 2>&1)
            case $? in
                0) ;;
                1) echo "$PROG: refused: $TOPIC's removed teardown is not confirmed: $CHECK_OUT" >&2; exit 65 ;;
                *) lib_die2 "the teardown check could not run: $(printf '%s\n' "$CHECK_OUT" | tail -1)" ;;
            esac
        fi
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
RC=$?
# The record keeps no history of a removed row, so a dispatch-failed holding's
# retirement is also told as an entry in the account (shirabe#1612).
[ "$RC" = 0 ] && [ -s "$T/retire-entry" ] || exit "$RC"
if [ "$OVERRIDE" = 1 ]; then
    ADDR_ARGS=(--scope "$SCOPE" --name "$NAME" --repo "$REPO")
else
    ADDR_ARGS=(--session "$SESSION")
fi
if ! bash "$HERE/state-entry.sh" "${ADDR_ARGS[@]}" --kind entry --text-file "$T/retire-entry" > /dev/null; then
    echo "$PROG: the holding was retired, but its entry wasn't written; post it with state-entry.sh --kind entry: $(cat "$T/retire-entry")" >&2
    exit 14
fi
