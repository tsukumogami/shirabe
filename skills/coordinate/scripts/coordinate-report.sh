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
#        coordinate-report.sh --session S --record-line
# Prints:
#   outcome=<closed|handed-over|stopped|not-active>
#   scope=<roadmap|discipline>
#   host=<owner/repo>
#   record=<the record's session name, coordinate-<slug>-<stamp>, or, from a
#          run that kept its record on GitHub, the record's issue or pull
#          request URL https://github.com/<owner>/<repo>/(issues|pull)/<n>>
#   events=<n>                 (with --session)
#   source_workspace=<path>, source_session=<session>, template_hash=<64 hex>
#                              (with --session, for a run imported from another
#                              host: record/host's import facts)
#
# --record-line prints the record line and nothing else: the one line every
# report starts with, naming the record's session, its host repository, this
# coordinator's address when the Run `coordinator` row differs from the
# session name, and the run's role (docs/designs/DESIGN-coordinator-named-roles.md,
# Decision 3). It reads no stdin. The values are read live from the record at
# each call, the Run rows through state-read.sh --run and the host through
# coord-log.sh run-facts, and reconcile-report.sh's line mode, which holds the
# line's template, prints it. reconcile-report-get.sh --md prints the same
# line as the first report's third line.
#
# Exit codes: 0 printed; 4 (--record-line) the record holds no Run `role` row,
# its stderr naming the handover gap no-role and its fix; 64 usage; 65 the
# input carries no result, or (--record-line) the record can't be read.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= INPUT=- LINE=
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || exit 64; SESSION=$2; shift 2 ;;
        --record-line) LINE=1; shift ;;
        --*) echo "coordinate-report: unknown option $1" >&2; exit 64 ;;
        *) INPUT=$1; shift ;;
    esac
done

if [ -n "$LINE" ]; then
    [ -n "$SESSION" ] && [ "$INPUT" = - ] || { echo "coordinate-report: --record-line takes --session S and nothing else" >&2; exit 64; }
    [[ $SESSION =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]] || { echo "coordinate-report: $SESSION is not a session name" >&2; exit 64; }
    FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION") \
        || { echo "coordinate-report: the record of $SESSION can't be read: its run holds no found record, or its log can't be read" >&2; exit 65; }
    RUN=$(bash "$HERE/state-read.sh" --session "$SESSION" --run) \
        || { echo "coordinate-report: the Run section of $SESSION's record can't be read" >&2; exit 65; }
    VALUES=$(jq -nc --arg s "$SESSION" --argjson f "$FACTS" --argjson r "$RUN" '
        {session: $s, host: $f.repo,
         address: ([$r[] | select(.key == "coordinator") | .value] | last),
         role: ([$r[] | select(.key == "role") | .value] | last)}') \
        || { echo "coordinate-report: the record of $SESSION can't be read as a run's facts and Run rows" >&2; exit 65; }
    if [ "$(printf '%s' "$VALUES" | jq -r '.role // empty')" = "" ]; then
        echo "coordinate-report: $SESSION's record holds no Run role row, so no record line is printed; it is the handover gap no-role, fix: state-stored-set.sh --run role <manager|director> --by <who named it>" >&2
        exit 4
    fi
    printf '%s' "$VALUES" | bash "$HERE/reconcile-report.sh" line || exit 65
    exit 0
fi
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
emit record '^(coordinate-[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z|https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+)$'
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
