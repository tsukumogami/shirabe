#!/usr/bin/env bash
# reconcile-read.sh -- read the coordinator's record, and at discipline scope
# the previous rotation's handoff, as the claims reconcile re-checks.
#
# Reconcile never parses a record body itself. The run's record is the one
# the start states found (coord-log.sh run-facts); its body is read live and
# parsed by the record feature's record-parse.sh, the same codec every record
# script uses. Which candidate is the record, and whether its author and last
# editor may write to the host, were settled by record_find before reconcile
# runs; this script inherits that and never looks at another candidate.
#
# Usage:
#   reconcile-read.sh --session S [--reasoning-out FILE]
#   reconcile-read.sh --scope roadmap|discipline --name N --repo O/R --ref N
#                     [--reasoning-out FILE]                         (tests)
#
# Output, exit 0: one JSON object --
#   {status: "found", scope: {kind, name, repo}, record: {written, source:
#    "record" | "record and handoff", handoff_date}, holdings: [{row,
#    source}], deferrals: [{row, source}], side_effects: [{row, source}],
#    unparseable: [{raw, reason}],
#    reasoning: null | "present" | "not_recorded" | "absent"}
# Rows keep the record's own keys. At discipline scope the handoff's rows
# follow the record's own with source "handoff", except rows the record
# already carries (the same worker; the same deferral raised at the same
# time; the same side effect attempted at the same time). The handoff's
# reasoning, when present, is written verbatim to --reasoning-out; a
# predecessor copy, an empty or missing section, or the record feature's
# fixed not-recorded sentence is "not_recorded", and nothing here ever
# writes reasoning on the predecessor's behalf.
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
#   4  unreadable  the body isn't a record of this scope, the record is no
#                  longer open, or the handoff isn't a handoff for this
#                  discipline on this host
#   5  failed      a read failed or ran past its deadline (the reason says
#                  which)
#   64 usage
# Two candidates and an undeclared candidate never reach this script:
# record_find refuses them before the run reaches reconcile.
#
# Reads: coord-log.sh run-facts; gh issue view / gh pr view --json
# state,body; gh api repos/R (default branch) and the handoff file raw from
# the contents API.
#
# Requires: bash 3.2+, jq, gh.
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

SESSION="" SCOPE="" NAME="" REPO="" REF="" REASONING_OUT=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --session) SESSION=$2 ;;
        --scope) SCOPE=$2 ;;
        --name) NAME=$2 ;;
        --repo) REPO=$2 ;;
        --ref) REF=$2 ;;
        --reasoning-out) REASONING_OUT=$2 ;;
        *) usage ;;
    esac
    shift 2
done

refuse() {  # refuse CODE STATUS REASON
    jq -nc --arg s "$2" --arg r "$3" '{status: $s, reason: $r}'
    exit "$1"
}

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-read.XXXXXX")
trap 'rm -rf "$T"' EXIT

# The run's facts: from the session, or all four override flags in tests.
if [ -n "$SCOPE$NAME$REPO$REF" ]; then
    [ -n "$SCOPE" ] && [ -n "$NAME" ] && [ -n "$REPO" ] && [ -n "$REF" ] || usage
    [ -z "$SESSION" ] || usage
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
    REF=$(printf '%s' "$FACTS" | jq -r '.ref // empty' 2>/dev/null)
fi
case "$SCOPE" in roadmap) CONTAINER=issue ;; discipline) CONTAINER=pr ;; *) refuse 5 failed "the run's scope is unreadable" ;; esac
[[ $NAME =~ ^[A-Za-z0-9._-]+$ ]] || refuse 5 failed "the run's scope name is unreadable"
rd_valid_repo "$REPO" || refuse 5 failed "the run's host is unreadable"
rd_valid_number "$REF" || refuse 5 failed "the run's record number is unreadable"

# The body, live. A record that is no longer open isn't this run's record.
rd_deadline "$DEADLINE" gh "$CONTAINER" view "$REF" --repo "$REPO" --json state,body > "$T/view.json" 2>/dev/null
case $? in
    0) ;;
    124) refuse 5 failed "reading the record timed out" ;;
    *) refuse 5 failed "the record could not be read" ;;
esac
jq -e '(.state | type) == "string" and (.body | type) == "string"' "$T/view.json" >/dev/null 2>&1 \
    || refuse 5 failed "the record's response is unreadable"
[ "$(jq -r .state "$T/view.json")" = OPEN ] || refuse 4 unreadable "the record is no longer open"
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
    "$RD_RECORD_PARSE" --format "$fmt" --container "$CONTAINER" --expect-scope "$SCOPE:$NAME" "$in" > "$out" 2> "$out.err"
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
    [ "$fmt" = handoff ] && fn=salvage_handoff
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

parse record "$T/body.md" "$T/record.json"
case $? in
    0) ;;
    65) refuse 4 unreadable "the body isn't a coordinator record for this scope" ;;
    *) refuse 5 failed "the record could not be parsed" ;;
esac

# The handoff, at discipline scope: the file the previous rotation
# committed, on the host's default branch.
HANDOFF=null
REASONING=null
# A reasoning file from an earlier read is not left to be taken as this one.
[ -n "$REASONING_OUT" ] && [ -f "$REASONING_OUT" ] && rm -f "$REASONING_OUT"
if [ "$SCOPE" = discipline ]; then
    DEF=$(rd_deadline "$DEADLINE" gh api "repos/$REPO" --jq .default_branch 2>/dev/null) \
        || refuse 5 failed "the host's default branch could not be read"
    rd_valid_branch "$DEF" || refuse 5 failed "the host's default branch is unreadable"
    out=$(rd_deadline "$DEADLINE" gh api -H "Accept: application/vnd.github.raw" \
            "repos/$REPO/contents/docs/disciplines/$NAME.md?ref=$DEF" 2> "$T/h.err" > "$T/handoff.md"; echo $?)
    if [ "$out" = 0 ]; then
        parse handoff "$T/handoff.md" "$T/handoff.json"
        case $? in
            0) ;;
            65) refuse 4 unreadable "the handoff file isn't a handoff for this discipline" ;;
            *) refuse 5 failed "the handoff could not be parsed" ;;
        esac
        [ "$(jq -r '.rotation.host_repo | ascii_downcase' "$T/handoff.json")" = "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" ] \
            || refuse 4 unreadable "the handoff names another host repository"
        HANDOFF=$(cat "$T/handoff.json")
        # The predecessor's reasoning, verbatim, or its absence. A predecessor
        # copy, an empty or missing section, and the record feature's fixed
        # not-recorded sentence all read as not recorded.
        SENTENCE=$(jq -n -r -f "$(codec_program predecessor_sentence)" 2>/dev/null) \
            || refuse 5 failed "the record feature's codec could not be read"
        if jq -e --arg s "$SENTENCE" 'has("predecessor_copy") or ((.reasoning // "") | test("^\\s*$"))
                or ((.reasoning // "") | gsub("^\\s+|\\s+$"; "") == $s)' "$T/handoff.json" >/dev/null 2>&1; then
            REASONING='"not_recorded"'
        else
            REASONING='"present"'
            if [ -n "$REASONING_OUT" ]; then
                jq -j .reasoning "$T/handoff.json" > "$REASONING_OUT" || refuse 5 failed "the reasoning could not be written"
            fi
        fi
    elif grep -q 'HTTP 404' "$T/h.err"; then
        REASONING='"absent"'
    elif [ "$out" = 124 ]; then
        refuse 5 failed "reading the handoff timed out"
    else
        refuse 5 failed "the handoff could not be read"
    fi
fi

# The handoff's rows follow the record's own, each labelled with its source.
# A handoff row the record already carries (the same worker, the same
# deferral raised at the same time, the same side effect attempted at the
# same time) is the record's, and is not listed twice.
jq -c --arg repo "$REPO" --argjson handoff "$HANDOFF" --argjson reasoning "$REASONING" '
    def labelled($rows; $src): [$rows[] | {row: ., source: $src}];
    def add_new($mine; $theirs; key):
        ([$mine[] | key]) as $seen
        | labelled($mine; "record") + labelled([$theirs[] | select((key) as $k | ($seen | index([$k])) == null)]; "handoff");
    ($handoff // {}) as $h
    | ($h.rotation.date // null) as $d
    | {status: "found",
       scope: {kind: .scope.kind, name: .scope.name, repo: $repo},
       record: {written: .written,
                source: (if $handoff == null then "record" else "record and handoff" end),
                handoff_date: (if $d != null and ($d | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then $d else null end)},
       holdings: add_new(.holdings; ($h.holdings // []); [.worker, .unit]),
       deferrals: add_new(.deferrals; ($h.deferrals // []); [.deferral, .raised]),
       side_effects: add_new(.side_effects; ($h.side_effects // []); [.action, .target, .attempted]),
       unparseable: (.unparseable
                     + [($h.unparseable // [])[] | .reason = "handoff: " + .reason]
                     + (if $d != null and ($d | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not)
                        then [{raw: $d, reason: "handoff: its heading date is not YYYY-MM-DD"}] else [] end)),
       reasoning: $reasoning}' "$T/record.json" \
    || refuse 5 failed "the record could not be assembled"
