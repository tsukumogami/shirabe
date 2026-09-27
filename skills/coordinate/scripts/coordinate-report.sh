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
    printf '%s' "$v" | grep -Eq "$2" && printf '%s=%s\n' "$1" "$v"
    return 0
}
emit outcome '^(closed|handed-over|stopped|not-active)$'
emit scope '^(roadmap|discipline)$'
emit host '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
emit record '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+$'
if [ -n "$SESSION" ]; then
    N=$(bash "$HERE/coord-log.sh" count --session "$SESSION" 2>/dev/null) && printf 'events=%s\n' "$N"
fi
exit 0
