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
# issue_<N>.<owner>.<repo> for an issue-backed /work-on run). The coordinator
# finds it through the leg; a worker with no leg
# reports it instead, since render-result.sh carries the stored round in the
# result block of its final report.
#
# Once stored, the round is also sent to koto's run journal as review
# telemetry: `koto review record <session> code-round` (koto 0.33.0 and
# later) writes one code review round record and one verdict per seat, with
# its seat, model and verdict, apart from the document review kinds. koto
# keeps a seat the session's template declares in review_vocabulary and
# records any other as `other`. koto doesn't number rounds, so the session's
# context key review_round_count holds how many this script has sent: the
# round goes as that count plus one (an absent or unreadable count is 0), and
# the count is raised only once koto has taken it. The telemetry is best
# effort: a koto without the verb, a refusal or a failed count write prints
# one `review-round:` notice on stderr and changes nothing else, so the exit
# code, the stdout line and the stored round are the same either way. A
# finished session takes no review events, so a round recorded on one is
# stored with no telemetry and no notice.
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
trap 'rm -f "$T" "$T.seats"' EXIT
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

# The telemetry, best effort (the header says why). koto's own message is
# kept for the notice rather than discarded, so a refusal says what koto
# refused.
telemetry() {
    local n out code
    n=$("$KOTO" context get "$SESSION" review_round_count 2>&1) || n=0
    [[ $n =~ ^[1-9][0-9]{0,8}$ ]] || n=0
    n=$((n + 1))
    jq -c '[.seats[] | {seat, model, verdict}]' "$T" > "$T.seats" || {
        echo "$PROG: the round is stored, but its seats couldn't be written for koto's review telemetry" >&2; return; }
    out=$("$KOTO" review record "$SESSION" code-round --round "$n" \
            --head "$(printf '%s' "$EV" | jq -r .reviewed_head)" --file "$T.seats" 2>&1) || {
        # koto records review events only while a run is live, and a round
        # recorded on a finished session (a /work-on child at done, which the
        # template's fix round records on) is refused as session_terminal:
        # expected, so it gets no notice. Only the first line of each is
        # read, through a here-string and an expansion rather than a pipe into
        # head, which would stop reading early under pipefail.
        code=$(jq -Rr 'fromjson? | .error.code? // empty' <<< "$out")
        [ "${code%%$'\n'*}" = session_terminal ] && return
        echo "$PROG: the round is stored, but koto didn't record it as review telemetry: ${out%%$'\n'*}" >&2
        return; }
    printf '%s\n' "$n" | "$KOTO" context add "$SESSION" review_round_count >/dev/null || \
        echo "$PROG: round $n went to koto's review telemetry, but review_round_count couldn't be stored in $SESSION" >&2
}
telemetry
printf '%s\n' "$EV" | jq -r '"recorded \(.count) seats at \(.reviewed_head)"'
