#!/usr/bin/env bash
# reconcile-read.sh -- read the coordinator's record, and at discipline scope
# the previous rotation's reasoning, as the claims reconcile re-checks.
#
# Reconcile never parses a record body itself. The run's record is the one
# the start states found (coord-log.sh run-facts), held in the run's koto
# session; it is read live through record-source.sh and parsed by the record
# feature's record-parse.sh, the same codec every record script uses.
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
#    escalated entries), unparseable: [{raw, reason}],
#    reasoning: null | "present" | "not_recorded" | "absent"}
# Rows keep the record's own keys, each with source "record". At discipline
# scope the predecessor's reasoning is read from the predecessor's session
# (this rotation's record/rotation names it): its record/reasoning, written
# verbatim to --reasoning-out when present; "not_recorded" when it is empty or
# the predecessor never wrote one; "absent" for a rotation with no
# predecessor. Nothing here ever writes reasoning on the predecessor's behalf.
# A predecessor's rows came across in the carry (record-open.sh --carry), so
# they are the record's own.
#
# A body the record feature's parser doesn't take as canonical, or refuses
# for one row, is read row by row (reconcile-salvage.jq, over that feature's
# own codec): a row that breaks the grammar is listed under unparseable with
# its raw line and the codec's reason, and every other row is still read.
# For a body that parses but doesn't render back as written, the first line
# that differs is listed.
#
# Refusals print {status, reason} and exit:
#   3  none        the run has no found record
#   4  unreadable  the body isn't a record of this scope
#   5  failed      a read failed or ran past its deadline (the reason says
#                  which)
#   64 usage
#
# Reads: coord-log.sh run-facts; the record, its host facts and the
# predecessor's reasoning through record-source.sh. Nothing on GitHub.
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

# The body through the seam (record-source.sh), under this reader's own
# deadline: rs_record, so a pass that began the step's one read
# (rs_once_begin) shares it with the settle and the legs classification. This
# reader keeps its row-by-row salvage of a body the codec refuses: rs_record's
# own parse is taken when it read the body as canonical (its code in
# $T/rec.rc), and only a body it refused (3 or 65, its raw body still read) is
# parsed again below, so a good body is parsed once.
session_view() {
    local rc
    RS_SESSION=$RS rs_record "$T/rec" json; rc=$?
    case $rc in 0|3|65) [ -s "$T/rec.raw" ] || return 5 ;; *) return $rc ;; esac
    echo "$rc" > "$T/rec.rc"
    cat "$T/rec.raw"
}
rd_deadline "$DEADLINE" session_view > "$T/view.json" 2>/dev/null
case $? in
    0) ;;
    124) refuse 5 failed "reading the record timed out" ;;
    *) refuse 5 failed "the record could not be read" ;;
esac
jq -e '(.body | type) == "string"' "$T/view.json" >/dev/null 2>&1 \
    || refuse 5 failed "the record's response is unreadable"
jq -j .body "$T/view.json" > "$T/body.md"

# codec_program EXPR -- a jq program file: the record feature's codec, the
# salvage definitions, then EXPR. One file rather than jq's include, because
# a function reached through two levels of include aborts jq 1.8.
codec_program() {
    { cat "$RD_HERE/record-codec.jq"
      sed '/^include "record-codec";$/d' "$RD_HERE/reconcile-salvage.jq"
      printf '\n%s\n' "$1"; } > "$T/program.jq"
    printf '%s' "$T/program.jq"
}

# parse FORMAT FILE OUT -- read FILE as FORMAT for this scope into OUT, with
# `unparseable` rows. The record feature's parser first; a body it doesn't
# take as canonical, or refuses for a row, is read row by row with
# reconcile-salvage.jq, so every other row is still re-checked. For a
# non-canonical body, the first line that differs is listed. Returns 0 read;
# 65 not a body of this scope and format (too large, wrong scope, wrong
# structure); 1 the parser itself failed.
parse() {
    local fmt=$1 in=$2 out=$3 rc fn line body got
    "$RD_RECORD_PARSE" --format "$fmt" --container issue --expect-scope "$SCOPE:$NAME" "$in" > "$out" 2> "$out.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        jq -c '. + {unparseable: []}' "$out" > "$out.t" && mv "$out.t" "$out" || return 1
        return 0
    fi
    [ "$rc" -eq 3 ] || [ "$rc" -eq 65 ] || return 1
    # Refusals no row can explain: size and scope.
    # Only the parser's own refusal line, and only on a refusal: a
    # non-canonical body's stderr echoes the body's line, which anyone who
    # edits the body controls.
    if [ "$rc" -eq 65 ] && grep -Eq '^record-parse: refused: (body is [0-9]+ bytes, over|the record is for )' "$out.err"; then
        return 65
    fi
    # No codec beside this script is a broken install, not a bad record.
    [ -f "$RD_HERE/record-codec.jq" ] || return 1
    fn=salvage_record
    jq -R -s -c -f "$(codec_program "$fn")" < "$in" > "$out" 2>/dev/null || return 65
    got=$(jq -r '.scope.kind + ":" + .scope.name' "$out")
    [ "$got" = "$SCOPE:$NAME" ] || return 65
    # The parser's own line for a body that parses but doesn't render back:
    # the body's line, never the parser's message (which can carry paths).
    line=$(sed -n 's/^record-parse: not canonical at line \([0-9]*\)$/\1/p' "$out.err" | head -1)
    if [ -n "$line" ]; then
        body=$(sed -n 's/^  body:     //p' "$out.err" | head -1 | tr -d '\000-\010\013-\037' | cut -c1-300)
        jq -c --arg raw "$body" --arg r "not canonical at line $line; the rest was read row by row" \
            '.unparseable += [{raw: $raw, reason: $r}]' "$out" > "$out.t" && mv "$out.t" "$out" || return 1
    elif jq -e '.unparseable == []' "$out" >/dev/null 2>&1; then
        # Not canonical, and no row explains it: the parser's own reason
        # (a cell outside the rows, the Written: line), without its prefix.
        body=$(sed -n 's/^record-parse: not canonical: refused: //p' "$out.err" | head -1 | tr -d '\000-\037' | cut -c1-200)
        [ -n "$body" ] || body="the body does not render back as written"
        jq -c --arg r "not canonical: $body; the rest was read row by row" \
            '.unparseable += [{raw: "", reason: $r}]' "$out" > "$out.t" && mv "$out.t" "$out" || return 1
    fi
    return 0
}

if [ "$(cat "$T/rec.rc" 2> /dev/null)" = 0 ]; then
    jq -c '. + {unparseable: []}' "$T/rec" > "$T/record.json"
else
    parse record "$T/body.md" "$T/record.json"
fi
case $? in
    0) ;;
    65) refuse 4 unreadable "the body isn't a coordinator record for this scope" ;;
    *) refuse 5 failed "the record could not be parsed" ;;
esac

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
