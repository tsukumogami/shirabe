#!/usr/bin/env bash
# record-render.sh -- render the coordinator record, or a discipline handoff
# file, from its JSON form.
#
# The record's visible tables are its only representation; record-codec.jq
# defines the sections, columns and cell grammars. This script refuses input
# that would record something GitHub can recompute (a status, CI or merge-state
# column), a worker named by anything but its dispatch topic, a malformed
# structured cell, or (with --private-repos) a repository-naming cell that
# names a repository which isn't public.
#
# Usage:
#   record-render.sh [--format record|handoff] [--container issue|pr]
#                    [--written YYYY-MM-DDTHH:MM:SSZ] [--private-repos a/b,c/d]
#                    [FILE|-]
#
# The JSON comes from FILE, or stdin when FILE is - or absent. --written stamps
# the record's Written: time (default: now, UTC); a handoff has none.
#
# Exit codes: 0 rendered on stdout; 64 usage; 65 input refused (the reason on
# stderr); 1 an internal failure.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FORMAT=record
CONTAINER=issue
WRITTEN=
PRIVATE=
INPUT=-

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

while [ $# -gt 0 ]; do
    case "$1" in
        --format) [ $# -ge 2 ] || usage; FORMAT=$2; shift 2 ;;
        --container) [ $# -ge 2 ] || usage; CONTAINER=$2; shift 2 ;;
        --written) [ $# -ge 2 ] || usage; WRITTEN=$2; shift 2 ;;
        --private-repos) [ $# -ge 2 ] || usage; PRIVATE=$2; shift 2 ;;
        -h|--help) usage ;;
        --*) usage ;;
        *) INPUT=$1; shift ;;
    esac
done

case "$FORMAT" in record|handoff) ;; *) usage ;; esac
case "$CONTAINER" in issue|pr) ;; *) usage ;; esac
[ -n "$WRITTEN" ] || WRITTEN=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$INPUT" = - ]; then
    DATA=$(cat)
else
    [ -e "$INPUT" ] || { echo "record-render: no such file: $INPUT" >&2; exit 64; }
    DATA=$(cat "$INPUT")
fi

if ! printf '%s' "$DATA" | jq empty >/dev/null 2>&1; then
    echo "record-render: refused: input is not JSON" >&2
    exit 65
fi

case "$FORMAT" in
    record) PROG='render_record($container; $written; $private)' ;;
    handoff) PROG='render_handoff($private)' ;;
esac

ERR=$(mktemp "${TMPDIR:-/tmp}/record-render.XXXXXX")
trap 'rm -f "$ERR"' EXIT
set +e
# Exactly one JSON document: -n with a counted `inputs` refuses empty input
# and a second document instead of rendering nothing or two bodies.
OUT=$(printf '%s' "$DATA" | jq -n -r -L "$HERE" \
    --arg container "$CONTAINER" --arg written "$WRITTEN" \
    --arg private "$PRIVATE" \
    'include "record-codec"; [inputs] as $docs | if ($docs | length) != 1 then refuse("expected one JSON document, got \($docs | length)") else $docs[0] end | ($private | split(",") | map(select(. != ""))) as $private | '"$PROG" 2>"$ERR")
RC=$?
set -e
if [ $RC -ne 0 ]; then
    if grep -q 'refused: ' "$ERR"; then
        sed -n 's/.*refused: /record-render: refused: /p' "$ERR" | head -1 >&2
        exit 65
    fi
    cat "$ERR" >&2
    exit 1
fi
printf '%s\n' "$OUT"
