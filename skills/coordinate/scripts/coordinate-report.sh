#!/usr/bin/env bash
# coordinate-report.sh -- /coordinate's closing lines, from the terminal
# result, so the coordinator never composes them.
#
# Reads `koto status <session>` JSON (or a terminal `koto next` response) on
# stdin or from FILE, takes the result payload, and prints each value only when
# it matches its closed pattern; anything else is dropped. With --session it
# also prints the session's event count, so a growing log is visible.
#
# Usage: koto status <session> | coordinate-report.sh [--session S] [FILE]
# Prints:
#   outcome=<closed|handed-over|stopped|not-active>
#   scope=<roadmap|discipline>
#   host=<owner/repo>
#   record=<https://github.com/<owner>/<repo>/(issues|pull)/<n>>
#   events=<n>                 (with --session)
#   source_workspace=<path>, source_session=<session>, template_hash=<64 hex>
#                              (with --session, for a run imported from another
#                              host: record/host's import facts)
# Exit codes: 0 printed; 64 usage; 65 the input carries no result.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= INPUT=-
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || exit 64; SESSION=$2; shift 2 ;;
        --*) echo "coordinate-report: unknown option $1" >&2; exit 64 ;;
        *) INPUT=$1; shift ;;
    esac
done
if [ "$INPUT" = - ]; then DOC=$(cat); else DOC=$(cat "$INPUT") || exit 64; fi

PAYLOAD=$(printf '%s' "$DOC" | jq -c '.result.payload // .result // empty')
[ -n "$PAYLOAD" ] && [ "$PAYLOAD" != null ] || { echo "coordinate-report: no terminal result in the input" >&2; exit 65; }

emit() { # emit <key> <pattern>
    local v
    v=$(printf '%s' "$PAYLOAD" | jq -r --arg k "$1" '.[$k] // empty | tostring')
    case "$v" in *'
'*) return 0 ;; esac
    grep -Eq "$2" <<<"$v" && printf '%s=%s\n' "$1" "$v"
    return 0
}
emit outcome '^(closed|handed-over|stopped|not-active)$'
emit scope '^(roadmap|discipline)$'
emit host '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
emit record '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+$'
if [ -n "$SESSION" ]; then
    N=$(bash "$HERE/coord-log.sh" count --session "$SESSION" 2>/dev/null) && printf 'events=%s\n' "$N"
    # An imported run names where its state came from (PRD R14), so the next
    # import, or a person reading the close, can find the source.
    # emit reads PAYLOAD, so the host facts take its place from here on.
    PAYLOAD=$(bash "$HERE/state-read.sh" --session "$SESSION" --host 2>/dev/null) || PAYLOAD='{}'
    if [ -n "$(printf '%s' "$PAYLOAD" | jq -r '.source_session // empty' 2>/dev/null)" ]; then
        emit source_workspace '^/[^[:cntrl:]]*$'
        emit source_session '^coordinate-[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z$'
        emit template_hash '^[0-9a-f]{64}$'
    fi
fi
exit 0
