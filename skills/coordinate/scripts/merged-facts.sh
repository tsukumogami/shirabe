#!/usr/bin/env bash
# merged-facts.sh -- the check action of merged_facts: a person merged a
# parked pull request after a hand-over; did it land the head this run
# verified? Read-only.
#
# Usage: merged-facts.sh --session S --unit <topic> [--pr N --repo R] [--no-seal]
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
# default branch doesn't hold the verified content), or `not-merged <pr>`;
# sealed to the latest entry into merged_facts (captured as MERGED_FACTS).
# --pr with --repo skip the holding read, for tests; --no-seal (tests) prints
# the bare token.
#
# Exit codes: 0 a token printed; 2 no holding for the topic, no valid verify
# capture for its pull request in this run, or a read failed; 64 usage.
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
bl_session_ok "$SESSION" && bl_topic_ok "$UNIT" || usage
if [ -n "$PR$REPO" ]; then
    bl_pr_ok "$PR" && bl_repo_ok "$REPO" || usage
else
    ROW=$(bash "$HERE/record-holding.sh" --session "$SESSION" --topic "$UNIT" --read)
    case $? in
        0) ;;
        1) echo "$PROG: the record has no holding for $UNIT" >&2; exit 2 ;;
        *) echo "$PROG: the holding read failed" >&2; exit 2 ;;
    esac
    PARTS=$(printf '%s' "$ROW" | jq -r '.pull_request // ""
        | capture("^\\[#(?<a>[0-9]+)\\]\\(https://github\\.com/(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?<b>[0-9]+)\\)$")?
        | select(.a == .b) | "\(.a) \(.r)"' 2>/dev/null)
    set -f; set -- $PARTS; set +f
    if [ $# -ne 2 ] || ! bl_pr_ok "$1" || ! bl_repo_ok "$2"; then
        echo "$PROG: the holding for $UNIT has no pull request link" >&2
        exit 2
    fi
    REPO=$2
    PR=$1
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
