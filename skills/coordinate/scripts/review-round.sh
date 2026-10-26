#!/usr/bin/env bash
# review-round.sh -- a worker records its review round in its own run session,
# where the coordinator's land step reads it (land-check.sh step 4, through
# board-lib.sh's bl_review_evidence), so the round needs no table in the pull
# request body.
#
# Usage: review-round.sh record --session <worker session> <round-file|->
#
# The round is one JSON object, the shape panel-evidence.sh --round reads:
#
#   {"reviewed_head": "<40-hex sha>",
#    "seats": [{"seat": "architect", "model": "sonnet",
#               "run": "<the seat's run id>", "verdict": "pass"}, ...]}
#
# It is judged by panel-evidence.sh --round before anything is written, so a
# round the land step would call malformed is refused here, with the rule it
# breaks, rather than stored. A well-formed round is stored as the session's
# context key review_round.json, replacing any round recorded before: the
# land step reads the latest one, at the head the worker reports ready. A
# round with a failing seat is well-formed and is stored; the land step
# refuses it as not unanimous.
#
# The session is the worker's own: the run the coordinator's leg is bound to,
# or on the message path the one its opener opened (its name, such as
# issue_<N>). The coordinator finds it through the leg; a worker with no leg
# reports it instead, since render-result.sh carries the stored round in the
# result block of its final report.
#
# Exit codes: 0 stored (prints `recorded <count> seats at <reviewed head>`);
# 1 the round is malformed (prints `malformed <reason> row <n>` on stderr);
# 2 the round couldn't be read or koto couldn't store it; 64 usage.
set -uo pipefail

PROG=review-round
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO=${KOTO_BIN:-koto}
RE_SESSION='^[A-Za-z0-9._-]+$'

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
[ $# -eq 4 ] && [ "$1" = record ] && [ "$2" = --session ] || usage
SESSION=$3 IN=$4
[[ $SESSION =~ $RE_SESSION ]] || usage
case "$IN" in --*) usage ;; esac

T=$(mktemp "${TMPDIR:-/tmp}/review-round.XXXXXX") || exit 2
trap 'rm -f "$T"' EXIT
if [ "$IN" = - ]; then
    cat > "$T" || exit 2
else
    [ -r "$IN" ] || { echo "$PROG: can't read $IN" >&2; exit 2; }
    cat "$IN" > "$T" || exit 2
fi

EV=$(bash "$HERE/panel-evidence.sh" --round "$T") || { echo "$PROG: the round couldn't be judged" >&2; exit 2; }
if [ "$(printf '%s' "$EV" | jq -r .status)" != ok ]; then
    echo "$PROG: $(printf '%s' "$EV" | jq -r '"malformed \(.reason) row \(.row)"')" >&2
    exit 1
fi
# The stored copy is the round as given, compacted, so the land step parses
# exactly what was judged here.
jq -c . "$T" | "$KOTO" context add "$SESSION" review_round.json >/dev/null || {
    echo "$PROG: could not store review_round.json in $SESSION" >&2; exit 2; }
printf '%s\n' "$EV" | jq -r '"recorded \(.count) seats at \(.reviewed_head)"'
