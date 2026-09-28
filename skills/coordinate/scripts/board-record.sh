#!/usr/bin/env bash
# board-record.sh -- the check action of verify_board: read the board at a
# pull request's head with board-verdict.sh, keep the full JSON as data in
# koto context key coord/board.json, and print one sealed verdict token for
# the state's gate (captured as VERIFIED).
#
# Usage: board-record.sh --session S [--pr N] [--repo R] [--no-seal]
#
# The pull request is the one report_facts found for the report being
# verified: the latest REPORT capture, sealed at the latest entry into
# report_facts, reading `holding <pr> <topic>`. A capture reading `holding
# none <topic>` (no pull request yet), or a missing, stale or unsealed one,
# exits 2. --pr overrides it (tests, or a caller that names the pull request).
#
# It refuses (exit 2, nothing read from GitHub) unless the session log shows
# the prediction: an evidence_submitted in state `verify` after the latest
# entry into `verify`. The board is read after the prediction, never before.
#
# The repository is the one the record's Holdings row for #N links
# (record-holding.sh --list); --repo overrides it, for tests.
#
# Token, sealed to the latest entry into verify_board:
#   verified <pr> <head>   the board is green at <head>
#   unverified <pr> none   the board failed
#   pending <pr> none      the board is still running
#   unreadable <pr> none   the board or the record couldn't be read, or the
#                          read ran out of time
#   not-open <pr> none     the pull request is merged or closed
#   unlinked <pr> none     no single Holdings row links #<pr> (its holding
#                          was removed), so its repository is unknown
# Only a verified token carries a head, so nothing downstream can land an
# unverified one. Every token leaves verify_board, so one pull request whose
# board can't be read doesn't hold the run at this state; the reasons (and
# for a board read, the skipped jobs, superseded attempts, the source the
# checks came from and the pull request's state) are in coord/board.json.
#
# --no-seal (tests): print the bare token and write no context key.
#
# Exit codes: 0 a token printed; 2 refused (no prediction, no report
# capture), board-verdict.sh failed, or a write failed; 64 usage.
set -uo pipefail

PROG=board-record
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/board-lib.sh"

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
SESSION= PR= REPO= NO_SEAL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --pr) [ $# -ge 2 ] || usage; PR=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
bl_session_ok "$SESSION" || usage
[ -z "$PR" ] || bl_pr_ok "$PR" || usage
[ -z "$REPO" ] || bl_repo_ok "$REPO" || usage

no_prediction() {
    echo "$PROG: refused: the log shows no prediction submitted since the latest arrival at verify" >&2
    exit 2
}
ENT=$(bash "$HERE/coord-log.sh" entry --session "$SESSION" --state verify 2>/dev/null)
case $? in
    0) ;;
    1) no_prediction ;;
    *) echo "$PROG: no readable log for $SESSION" >&2; exit 2 ;;
esac
bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state verify --after "${ENT%% *}" >/dev/null 2>&1 || no_prediction

if [ -z "$PR" ]; then
    REP=$(bl_capture "$SESSION" REPORT report_facts) || {
        echo "$PROG: no valid REPORT capture from the latest entry into report_facts" >&2; exit 2; }
    set -f; set -- $REP; set +f
    if [ $# -ne 3 ] || [ "$1" != holding ] || ! bl_topic_ok "$3"; then
        echo "$PROG: the report capture reads [$REP], not a holding" >&2; exit 2
    fi
    if [ "$2" = none ]; then
        echo "$PROG: the holding for $3 has no pull request to verify yet" >&2; exit 2
    fi
    bl_pr_ok "$2" || { echo "$PROG: the report capture names [$2], not a pull request" >&2; exit 2; }
    PR=$2
fi

T=$(mktemp "${TMPDIR:-/tmp}/board-record.XXXXXX") || exit 2
trap 'rm -f "$T"' EXIT
# stopped <word> <code> <detail>: a verdict with no board read behind it.
stopped() {
    jq -nc --arg v "$1" --argjson pr "$PR" --arg c "$2" --arg d "$3" \
        '{verdict: $v, pull_request: $pr, head: null, reasons: [{code: $c, detail: $d}]}' > "$T"
    TOKEN="$1 $PR none"
}

TOKEN=
if [ -z "$REPO" ]; then
    REPO=$(bl_unit_repo "$SESSION" "$PR")
    case $? in
        0) ;;
        1) stopped unlinked unlinked "no single holding in the record links pull request #$PR, so its repository is unknown" ;;
        *) stopped unreadable record-read "the record's holdings could not be read" ;;
    esac
fi

if [ -z "$TOKEN" ]; then
    bash "$HERE/board-verdict.sh" --repo "$REPO" --pr "$PR" > "$T" || { echo "$PROG: board-verdict.sh failed" >&2; exit 2; }
    V=$(jq -r '.verdict // ""' "$T")
    H=$(jq -r '.head // ""' "$T")
    case "$V" in
        verified) bl_sha_ok "$H" || { echo "$PROG: verified without a head" >&2; exit 2; }
                  TOKEN="verified $PR $H" ;;
        unverified|pending) TOKEN="$V $PR none" ;;
        error:pr-state) TOKEN="not-open $PR none" ;;
        error:board-read|error:deadline) TOKEN="unreadable $PR none" ;;
        *) echo "$PROG: board-verdict.sh printed the verdict [$V]" >&2; exit 2 ;;
    esac
fi
case "$TOKEN" in
    verified\ *|unverified\ *|pending\ *) ;;
    *) echo "$PROG: $TOKEN: $(jq -c '[.reasons[]? | .code + (if .detail then ": " + .detail else "" end)]' "$T")" >&2 ;;
esac

if [ "$NO_SEAL" = 0 ]; then
    "$KOTO" context add "$SESSION" coord/board.json --from-file "$T" >/dev/null || {
        echo "$PROG: could not write coord/board.json" >&2; exit 2; }
fi
bl_seal "$SESSION" verify_board "$TOKEN" "$NO_SEAL" || exit 2
