#!/usr/bin/env bash
# merged-facts.sh -- the check action of merged_facts: a person merged a
# parked pull request after a hand-over; did it land the head this run
# verified? Read-only.
#
# Usage: merged-facts.sh --session S [--unit <topic>] [--pr N --repo R] [--no-seal]
#
# The unit is the one the `merged` event named: the `unit` field of the latest
# evidence_submitted in state `wait` in the session log. --unit overrides it
# (for tests and hand runs; one outside the Worker cell's grammar, RE_TOPIC,
# is a usage error there). A logged unit outside that grammar, or one that
# names no holding with a pull request
# link (a unit's title or tag submitted in place of its topic, say), is
# refused: the token `unknown-topic`, which sends the run back to `wait` to
# submit the event again, with the reason and the accepted topics on stderr
# and in context key coord/merged_facts.json.
#
# The unit's topic only locates the holding: record-holding.sh --read finds
# its row on GitHub, whose Pull request cell gives the number and the
# repository. The head comes from the unit's own verify capture in this run
# (VERIFIED naming #<pr>, sealed at verify_board at any visit, reading
# `verified <pr> <sha>`), never from the record or the coordinator. Then the
# same comparison as merge-confirm.sh: the pull request's state and, when
# MERGED, each changed file's blob on the default branch against <sha>.
#
# Token: `merged <pr> <sha>`, `unconfirmed <pr> <sha>` (merged, but the
# default branch doesn't hold the verified content), `not-merged <pr>`, or
# `unknown-topic`;
# sealed to the latest entry into merged_facts (captured as MERGED_FACTS).
# --pr with --repo skip the holding read, for tests; --no-seal (tests) prints
# the bare token.
#
# Exit codes: 0 a token printed; 2 no valid verify capture for the pull
# request in this run, or a read failed; 64 usage.
set -uo pipefail

PROG=merged-facts
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/board-lib.sh"

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
SESSION= UNIT= PR= REPO= NO_SEAL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --unit) [ $# -ge 2 ] || usage; UNIT=$2; shift 2 ;;
        --pr) [ $# -ge 2 ] || usage; PR=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
bl_session_ok "$SESSION" || usage
[ -z "$UNIT" ] || bl_topic_ok "$UNIT" || usage

# refuse_unit <why>: the unit names no holding a merge can be about. Nothing
# is read further and nothing is written but this state's own verdict:
# `unknown-topic`, sealed, which sends the run back to the hub to submit the
# event again, with the reason and the accepted values on stderr and in
# context key coord/merged_facts.json. Exits 2 when the holdings can't be
# listed, so the tick is retried rather than refused on a guess.
refuse_unit() {
    local known
    known=$(bash "$HERE/record-holding.sh" --session "$SESSION" --list 2>/dev/null \
        | jq -c -L "$HERE" 'include "record-codec"; [.[]? | select([(.pull_request // "") | pr_link] | length > 0) | .worker]') || {
        echo "$PROG: the record's holdings could not be read" >&2; exit 2; }
    DETAIL=$(mktemp "${TMPDIR:-/tmp}/merged-facts.XXXXXX") || exit 2
    # The script's only EXIT trap; lib_emit exits through it.
    trap 'rm -f "$DETAIL"' EXIT
    jq -n --arg u "${UNIT:0:80}" --arg why "$1" --argjson known "$known" \
        --arg lead "the merged event's unit" --arg want "unit takes the dispatch topic of a holding with a pull request (its Worker), one of" \
        '{verdict: "unknown-topic", field: "unit", value: $u, accepted: $known,
          reason: ($lead + " [" + $u + "] " + $why + "; " + $want + ": "
                   + (if ($known | length) == 0 then "none (no holding has a pull request yet)" else ($known | join(", ")) end))}' > "$DETAIL"
    echo "$PROG: refused: $(jq -r .reason "$DETAIL")" >&2
    lib_emit merged_facts unknown-topic coord/merged_facts.json "$DETAIL"
}

if [ -n "$PR$REPO" ]; then
    bl_pr_ok "$PR" && bl_repo_ok "$REPO" || usage
else
    if [ -z "$UNIT" ]; then
        EV=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state wait 2>/dev/null)
        [ $? -eq 2 ] && { echo "$PROG: no readable log for $SESSION" >&2; exit 2; }
        UNIT=$(printf '%s' "$EV" | jq -r '.fields.unit // ""')
        bl_topic_ok "$UNIT" || refuse_unit "is not a topic"
    fi
    ROW=$(bash "$HERE/record-holding.sh" --session "$SESSION" --topic "$UNIT" --read)
    case $? in
        0) ;;
        1) refuse_unit "names no holding in the record" ;;
        *) echo "$PROG: the holding read failed" >&2; exit 2 ;;
    esac
    if ! lib_pr_link "$(printf '%s' "$ROW" | jq -r '.pull_request // ""')" \
        || ! bl_pr_ok "$LINK_NUM" || ! bl_repo_ok "$LINK_REPO"; then
        refuse_unit "names a holding with no pull request link"
    fi
    REPO=$LINK_REPO
    PR=$LINK_NUM
fi

CAP=$(bl_capture "$SESSION" VERIFIED verify_board --any-visit --for "$PR") || {
    echo "$PROG: no valid verify capture for #$PR in this run" >&2; exit 2; }
set -f; set -- $CAP; set +f
if [ $# -ne 3 ] || [ "$1" != verified ] || [ "$2" != "$PR" ] || ! bl_sha_ok "$3"; then
    echo "$PROG: the verify capture for #$PR reads [$CAP], not a verified head" >&2
    exit 2
fi
SHA=$3

R=$(bl_merge_compare "$REPO" "$PR" "$SHA") || { echo "$PROG: a read failed" >&2; exit 2; }
case "$R" in
    merged) TOKEN="merged $PR $SHA" ;;
    unconfirmed) TOKEN="unconfirmed $PR $SHA" ;;
    not-merged) TOKEN="not-merged $PR" ;;
    *) exit 2 ;;
esac
bl_seal "$SESSION" merged_facts "$TOKEN" "$NO_SEAL" || exit 2
