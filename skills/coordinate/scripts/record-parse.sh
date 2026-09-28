#!/usr/bin/env bash
# record-parse.sh -- parse a coordinator record body, or a discipline handoff
# file, into its JSON form, and check that it is canonical.
#
# A body is canonical when rendering what was parsed (with the parsed Written:
# time) reproduces it byte for byte, after CRLF becomes LF and trailing
# newlines are trimmed. That comparison is the record's section check: a
# missing or reordered section, an extra column, a hand-edited separator or a
# note between the tables all fail it, and the first differing line is named.
#
# Usage:
#   record-parse.sh [--format record|handoff] [--container issue|pr]
#                   [--expect-scope roadmap:<name>|discipline:<name>]
#                   [--no-canonical] [FILE|-]
#
# --container is the body's container, which decides the prefix a canonical
# body carries (a discipline record's pull request has a Part 1 line and a
# separator). --expect-scope refuses a record for any other scope, so a record
# for ROADMAP-x-v2 is never read as ROADMAP-x.
#
# Exit codes: 0 the JSON on stdout; 3 parsed but not canonical (the first
# differing line on stderr); 64 usage; 65 malformed, too large, or the wrong
# scope (the reason on stderr); 1 an internal failure.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FORMAT=record
CONTAINER=issue
EXPECT=
CANONICAL=1
INPUT=-
# GitHub's issue and pull request body limit.
MAX_BYTES=65536

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

while [ $# -gt 0 ]; do
    case "$1" in
        --format) [ $# -ge 2 ] || usage; FORMAT=$2; shift 2 ;;
        --container) [ $# -ge 2 ] || usage; CONTAINER=$2; shift 2 ;;
        --expect-scope) [ $# -ge 2 ] || usage; EXPECT=$2; shift 2 ;;
        --no-canonical) CANONICAL=0; shift ;;
        -h|--help) usage ;;
        --*) usage ;;
        *) INPUT=$1; shift ;;
    esac
done
case "$FORMAT" in record|handoff) ;; *) usage ;; esac
case "$CONTAINER" in issue|pr) ;; *) usage ;; esac
case "$EXPECT" in ''|roadmap:?*|discipline:?*) ;; *) usage ;; esac

T=$(mktemp -d "${TMPDIR:-/tmp}/record-parse.XXXXXX")
trap 'rm -rf "$T"' EXIT
if [ "$INPUT" = - ]; then cat > "$T/in"; else
    [ -e "$INPUT" ] || { echo "record-parse: no such file: $INPUT" >&2; exit 64; }
    cat "$INPUT" > "$T/in"
fi
SIZE=$(wc -c < "$T/in" | tr -d ' ')
if [ "$SIZE" -gt "$MAX_BYTES" ]; then
    echo "record-parse: refused: body is $SIZE bytes, over GitHub's $MAX_BYTES" >&2
    exit 65
fi

fn=parse_record
[ "$FORMAT" = handoff ] && fn=parse_handoff
set +e
jq -R -s -L "$HERE" "include \"record-codec\"; $fn" < "$T/in" > "$T/json" 2> "$T/err"
RC=$?
set -e
if [ $RC -ne 0 ]; then
    if grep -q 'refused: ' "$T/err"; then
        sed -n 's/.*refused: /record-parse: refused: /p' "$T/err" | head -1 >&2
        exit 65
    fi
    cat "$T/err" >&2
    exit 1
fi

if [ -n "$EXPECT" ]; then
    got=$(jq -r '.scope.kind + ":" + .scope.name' "$T/json")
    if [ "$got" != "$EXPECT" ]; then
        echo "record-parse: refused: the record is for $got, not $EXPECT" >&2
        exit 65
    fi
fi

if [ "$CANONICAL" = 1 ]; then
    if [ "$FORMAT" = record ]; then
        W=$(jq -r '.written' "$T/json")
        set +e
        jq 'del(.written)' "$T/json" | bash "$HERE/record-render.sh" --format record \
            --container "$CONTAINER" --written "$W" > "$T/re" 2> "$T/rerr"
        RC=$?
        set -e
    else
        set +e
        bash "$HERE/record-render.sh" --format handoff "$T/json" > "$T/re" 2> "$T/rerr"
        RC=$?
        set -e
    fi
    if [ $RC -ne 0 ]; then
        sed 's/^record-render:/record-parse: not canonical:/' "$T/rerr" >&2
        exit 3
    fi
    # Compare after CRLF -> LF and trimming trailing newlines, on both sides.
    norm() { tr -d '\r' < "$1" | awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] == "") n--; for (i = 1; i <= n; i++) print lines[i] }'; }
    norm "$T/in" > "$T/a"
    norm "$T/re" > "$T/b"
    if ! cmp -s "$T/a" "$T/b"; then
        line=$(awk 'NR == FNR { a[FNR] = $0; na = FNR; next } { if (!(FNR in a) || a[FNR] != $0) { print FNR; exit } } END { }' "$T/a" "$T/b")
        [ -n "$line" ] || line=$(( $(wc -l < "$T/b") + 1 ))
        printf 'record-parse: not canonical at line %s\n  body:     %s\n  expected: %s\n' \
            "$line" "$(sed -n "${line}p" "$T/a")" "$(sed -n "${line}p" "$T/b")" >&2
        exit 3
    fi
fi
cat "$T/json"
