#!/usr/bin/env bash
# reconcile-read.sh -- read the coordinator's record, and at discipline scope
# the previous rotation's reasoning, as the claims reconcile re-checks.
#
# The run's record is the one the start states found (coord-log.sh
# run-facts), held in the run's koto session; it is read live through
# state-read.sh, the reader every record script uses, which checks it
# against state-schema.jq.
#
# Usage:
#   reconcile-read.sh --session S [--reasoning-out FILE]
#   reconcile-read.sh --scope roadmap|discipline --name N --repo O/R
#                     [--reasoning-out FILE]                         (tests)
#
# The override flags are for tests, which name the session holding the record
# in RS_SESSION.
#
# Output, exit 0: one JSON object --
#   {status: "found", scope: {kind, name, repo}, record: {written, source:
#    "record", handoff_date: null, import: null |
#    {source_workspace, source_session, template_hash}}, holdings: [{row,
#    source}], deferrals: [{row, source}], side_effects: [{row, source}],
#    decisions: [{decision, question, recommendation, reason, target}] (the
#    escalated entries), unparseable: [{raw, reason}] (only a written time
#    that isn't YYYY-MM-DDTHH:MM:SSZ: the record is JSON, read whole or not
#    at all), reasoning: null | "present" | "not_recorded" | "absent"}
# Rows keep the record's own keys, each with source "record". At discipline
# scope the predecessor's reasoning is read from the predecessor's session
# (this rotation's record/rotation names it): its record/reasoning, written
# verbatim to --reasoning-out when present; "not_recorded" when it is empty or
# the predecessor never wrote one; "absent" for a rotation with no
# predecessor. Nothing here ever writes reasoning on the predecessor's behalf.
# A predecessor's rows came across in the carry (state-open.sh --carry), so
# they are the record's own.
#
# Refusals print {status, reason} and exit:
#   3  none        the run has no found record
#   4  unreadable  the session's record isn't one of this scope, or breaks a
#                  rule of state-schema.jq
#   5  failed      a read failed or ran past its deadline (the reason says
#                  which)
#   64 usage
#
# Reads: coord-log.sh run-facts; the record, its host facts and the
# predecessor's reasoning through state-read.sh. Nothing on GitHub.
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=reconcile-read
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

DEADLINE=${RECONCILE_READ_DEADLINE:-8}
rd_valid_secs "$DEADLINE" && [ "$DEADLINE" -le 60 ] || DEADLINE=8

usage() {
    awk '/^# Usage:/{on=1} on&&/^# Output/{exit} on' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 64
}

SESSION="" SCOPE="" NAME="" REPO="" REASONING_OUT=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --session) SESSION=$2 ;;
        --scope) SCOPE=$2 ;;
        --name) NAME=$2 ;;
        --repo) REPO=$2 ;;
        --reasoning-out) REASONING_OUT=$2 ;;
        *) usage ;;
    esac
    shift 2
done

refuse() {  # refuse CODE STATUS REASON
    jq -nc --arg s "$2" --arg r "$3" '{status: $s, reason: $r}'
    exit "$1"
}

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-read.XXXXXX") || refuse 5 failed "no temporary directory could be made"
trap 'rm -rf "$T"' EXIT
# Before the first read, in this shell: command substitutions inherit the
# FIFO, where one opened inside a `$(...)` would be opened again by every
# read. If it can't be opened, every read returns 125 and reads as failed.
rd_idle "$T"

# The run's facts: from the session, or all three override flags in tests.
if [ -n "$SCOPE$NAME$REPO" ]; then
    [ -n "$SCOPE" ] && [ -n "$NAME" ] && [ -n "$REPO" ] || usage
    [ -z "$SESSION" ] || usage
    RS=${RS_SESSION:-}
else
    [ -n "$SESSION" ] || usage
    FACTS=$(rd_deadline "$DEADLINE" "$RD_COORD_LOG" run-facts --session "$SESSION" 2>/dev/null)
    case $? in
        0) ;;
        1) refuse 3 none "the run has no found record" ;;
        124) refuse 5 failed "reading the run's facts timed out" ;;
        *) refuse 5 failed "the run's facts could not be read" ;;
    esac
    SCOPE=$(printf '%s' "$FACTS" | jq -r '.scope // empty' 2>/dev/null)
    NAME=$(printf '%s' "$FACTS" | jq -r '.name // empty' 2>/dev/null)
    REPO=$(printf '%s' "$FACTS" | jq -r '.repo // empty' 2>/dev/null)
    RS=$SESSION
fi
case "$SCOPE" in roadmap|discipline) ;; *) refuse 5 failed "the run's scope is unreadable" ;; esac
[[ $NAME =~ ^[A-Za-z0-9._-]+$ ]] || refuse 5 failed "the run's scope name is unreadable"
rd_valid_repo "$REPO" || refuse 5 failed "the run's host is unreadable"
[ -n "$RS" ] || refuse 5 failed "no session holds the record"

# The record through the seam (state-read.sh), under this reader's own
# deadline: rs_record, so a pass that began the step's one read
# (rs_once_begin) shares it with the settle and the legs classification.
session_view() {
    RS_SESSION=$RS rs_record "$T/rec" || return $?
    cat "$T/rec"
}
rd_deadline "$DEADLINE" session_view > "$T/view.json" 2>/dev/null
case $? in
    0) ;;
    124) refuse 5 failed "reading the record timed out" ;;
    65) refuse 4 unreadable "the session's record isn't a coordinator record for this scope" ;;
    *) refuse 5 failed "the record could not be read" ;;
esac
jq -c '. + {unparseable: []}' "$T/view.json" > "$T/record.json" 2>/dev/null \
    || refuse 5 failed "the record's response is unreadable"

# Where an imported record's state came from (PRD R14): record/host's import
# facts. A run that was never imported has none.
IMPORT=null
if [ -n "$SESSION" ]; then
    rs_host "$SESSION" "$T/host" || refuse 5 failed "the record's host facts could not be read"
    IMPORT=$(jq -c 'if (.source_session // "") == "" then null
        else {source_workspace: (.source_workspace // ""), source_session, template_hash: (.template_hash // "")} end' "$T/host") \
        || refuse 5 failed "the record's host facts are unreadable"
fi

# The predecessor's reasoning, at discipline scope: the previous rotation's
# session, which this rotation's record/rotation names, holds it in
# record/reasoning; present, or not_recorded when it never closed. With no
# predecessor the reasoning is absent.
REASONING=null
# A reasoning file from an earlier read is not left to be taken as this one.
[ -n "$REASONING_OUT" ] && [ -f "$REASONING_OUT" ] && rm -f "$REASONING_OUT"
if [ "$SCOPE" = discipline ]; then
    REASONING='"absent"'
    rs_rotation "$RS" "$T/rotation"
    case $? in
        0) PRED=$(jq -r '.predecessor // ""' "$T/rotation") ;;
        1) PRED= ;;
        *) refuse 5 failed "the rotation's window (record/rotation) could not be read" ;;
    esac
    if [ -n "$PRED" ]; then
        rs_reasoning "$PRED" "$T/reasoning"
        case $? in
            0) if jq -e 'gsub("^\\s+|\\s+$"; "") == ""' "$T/reasoning" > /dev/null; then
                   REASONING='"not_recorded"'
               else
                   REASONING='"present"'
                   if [ -n "$REASONING_OUT" ]; then
                       jq -j . "$T/reasoning" > "$REASONING_OUT" || refuse 5 failed "the reasoning could not be written"
                   fi
               fi ;;
            1) REASONING='"not_recorded"' ;;
            *) refuse 5 failed "the predecessor's reasoning (record/reasoning) could not be read" ;;
        esac
    fi
fi

# The record's rows, each labelled with its source.
jq -c --arg repo "$REPO" --argjson reasoning "$REASONING" --argjson import "$IMPORT" '
    def labelled($rows; $src): [$rows[] | {row: ., source: $src}];
    # Every string that leaves this script is free of control characters
    # other than the newline and tab a cell may hold (the codec writes a
    # newline as <br>).
    def clean: if type == "string" then gsub("[\u0000-\u0008\u000b-\u001f\u007f]"; "")
               elif type == "object" then map_values(clean)
               elif type == "array" then map(clean) else . end;
    clean
    | ((.written // "") | gsub("^\\s+|\\s+$"; "")) as $wr
    | ($wr | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) as $wok
    | .unparseable += (if $wok then [] else [{raw: $wr, reason: "the Written: line is not YYYY-MM-DDTHH:MM:SSZ"}] end)
    | {status: "found",
       scope: {kind: .scope.kind, name: .scope.name, repo: $repo},
       record: {written: (if $wok then $wr else null end), source: "record", handoff_date: null,
                import: ($import | clean)},
       holdings: labelled(.holdings; "record"),
       deferrals: labelled(.deferrals; "record"),
       side_effects: labelled(.side_effects; "record"),
       # The escalated entries, the only decisions that wait on anyone outside
       # this run.
       decisions: ([(.decisions.entries // [])[]]
                   | unique_by(.decision) | map(select(.state == "escalated")
                   | {decision, question, recommendation: (.recommendation // ""), reason: (.reason // ""), target: (.target // "")})),
       unparseable: .unparseable,
       reasoning: $reasoning}' "$T/record.json" \
    || refuse 5 failed "the record could not be assembled"
