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
#   {status: "found", scope: {kind, name, repo}, record: {written, source,
#    handoff_date}, holdings: [{row, source}], deferrals: [row],
#    side_effects: [row], unparseable: [{raw, reason}],
#    reasoning: null | "present" | "not_recorded" | "absent"}
# Rows keep the record's own keys. At discipline scope the handoff's rows are
# added with source "handoff" (the record's own rows first), and its
# reasoning, when present, is written verbatim to --reasoning-out; nothing
# here ever writes it on the predecessor's behalf.
#
# A body that isn't canonical is still read (record-parse.sh --no-canonical),
# and the first line that differs is listed under unparseable, so a
# hand-edited record is reported rather than trusted or dropped.
#
# Refusals print {status, reason} and exit:
#   3  none        the run has no found record
#   4  unreadable  the body isn't a record of this scope (or the handoff isn't
#                  a handoff), or the record is no longer open
#   5  failed      a read failed or ran past its deadline
#   64 usage
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

# parse FORMAT FILE OUT -- record-parse.sh for this scope. Sets NOTE to the
# first differing line when the body parsed only without the canonical check.
parse() {
    local rc
    NOTE=""
    "$RD_RECORD_PARSE" --format "$1" --container "$CONTAINER" --expect-scope "$SCOPE:$NAME" "$2" > "$3" 2> "$3.err"
    rc=$?
    if [ "$rc" -eq 3 ]; then
        NOTE=$(head -c 300 "$3.err" | tr -d '\000-\010\013-\037')
        [ -n "$NOTE" ] || NOTE="the body is not canonical"
        "$RD_RECORD_PARSE" --format "$1" --container "$CONTAINER" --expect-scope "$SCOPE:$NAME" --no-canonical "$2" > "$3" 2>/dev/null
        rc=$?
    fi
    return "$rc"
}

parse record "$T/body.md" "$T/record.json"
case $? in
    0) ;;
    65|3) refuse 4 unreadable "the body isn't a coordinator record for this scope" ;;
    *) refuse 5 failed "the record could not be parsed" ;;
esac
RECORD_NOTE=$NOTE

# The handoff, at discipline scope: the file the previous rotation
# committed, on the host's default branch.
HANDOFF=null
REASONING=null
HNOTE=""
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
            65|3) refuse 4 unreadable "the handoff file isn't a handoff for this discipline" ;;
            *) refuse 5 failed "the handoff could not be parsed" ;;
        esac
        HNOTE=$NOTE
        HANDOFF=$(cat "$T/handoff.json")
        # The predecessor's reasoning, verbatim, or its absence. A predecessor
        # copy carries a fixed sentence saying the reasoning wasn't recorded.
        if jq -e 'has("predecessor_copy") or ((.reasoning // "") | test("^\\s*$"))' "$T/handoff.json" >/dev/null 2>&1; then
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

jq -c --arg repo "$REPO" --arg rnote "$RECORD_NOTE" --arg hnote "$HNOTE" \
    --argjson handoff "$HANDOFF" --argjson reasoning "$REASONING" '
    {status: "found",
     scope: {kind: .scope.kind, name: .scope.name, repo: $repo},
     record: {written: .written,
              source: (if $handoff == null then "record" else "record and handoff" end),
              handoff_date: (if $handoff == null then null else $handoff.rotation.date end)},
     holdings: ([.holdings[] | {row: ., source: "record"}]
                + (if $handoff == null then [] else [$handoff.holdings[] | {row: ., source: "handoff"}] end)),
     deferrals: (.deferrals + (if $handoff == null then [] else $handoff.deferrals end)),
     side_effects: (.side_effects + (if $handoff == null then [] else $handoff.side_effects end)),
     unparseable: ([if $rnote != "" then {raw: $rnote, reason: "the record body is not canonical; read without the canonical check"} else empty end]
                   + [if $hnote != "" then {raw: $hnote, reason: "the handoff is not canonical; read without the canonical check"} else empty end]),
     reasoning: $reasoning}' "$T/record.json" \
    || refuse 5 failed "the record could not be assembled"
