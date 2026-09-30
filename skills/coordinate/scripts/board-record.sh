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
# none <topic>` (no pull request yet), or a missing, stale, unsealed or
# other-shaped one, gives `no-pr none none`; only a capture the log can't read
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
#   verified <pr> <head>         the board is green at <head>, read from the
#                                checks
#   actions-green <pr> none      the board is green judged from the Actions
#                                jobs, because the token can't read checks;
#                                the required set may be short, so it is for
#                                a person, never for landing
#   unverified <pr> none         the board failed
#   pending <pr> none            the board is still running
#   board-unreadable <pr> none   the board or the record couldn't be read, or
#                                the read ran out of time: no verdict on the
#                                code
#   not-open <pr> none           the pull request is merged or closed
#   unlinked <pr> none           no single Holdings row links #<pr> (its
#                                holding was removed, two rows disagree, or
#                                the link is malformed), so its repository
#                                is unknown
#   no-pr none none              the report being verified names no pull
#                                request (classify_report doesn't send such
#                                a report here; this is the exit if one
#                                arrives anyway)
# (`board-unreadable`, not `unreadable`: the verdict table is one word list
# for every check state.)
# Only a verified token carries a head, so nothing downstream can land any
# other. Every token leaves verify_board, so one pull request whose board
# can't be read doesn't hold the run at this state. coord/board.json has
# board-verdict.sh's shape either way: its full JSON after a board read, and
# for board-unreadable, unlinked or no-pr reached without one, the same fields
# with only the reason set.
#
# --no-seal (tests): print the bare token and write no context key.
#
# Exit codes: 0 a token printed; 2 refused (no prediction), the report capture
# couldn't be read, board-verdict.sh failed, or a write failed; 64 usage.
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

T=$(mktemp "${TMPDIR:-/tmp}/board-record.XXXXXX") || exit 2
trap 'rm -f "$T"' EXIT
# stopped <word> <code> <detail>: a verdict with no board read behind it,
# written in board-verdict.sh's shape (nothing read: no head, source, state,
# jobs or required set) so coord/board.json has one shape.
stopped() {
    jq -nc --arg v "$1" --arg c "$2" --arg d "$3" \
        '{verdict: $v, head: null, source: null, pr_state: null, merge_state: null,
          reasons: [{code: $c, detail: $d}], skipped: [], superseded: [], required: [],
          counts: {runs: 0, jobs: 0, jobs_ran: 0, required: 0}, notes: []}' > "$T"
    TOKEN="$1 $PR none"
}

TOKEN=
# no_pr <code> <detail>: nothing to verify. The state leaves on a sealed
# verdict rather than failing its action on every tick, since what it read
# (report_facts' sealed capture) can't change while the run stays here.
no_pr() { stopped no-pr "$1" "$2"; TOKEN="no-pr none none"; }
if [ -z "$PR" ]; then
    REP=$(bl_capture "$SESSION" REPORT report_facts)
    case $? in
        0) set -f; set -- $REP; set +f
           if [ $# -ne 3 ] || [ "$1" != holding ] || ! bl_topic_ok "$3"; then
               no_pr not-a-holding "the report capture reads [$REP], not a holding with a pull request"
           elif [ "$2" = none ]; then
               no_pr no-pull-request "the holding for $3 has no pull request to verify yet"
           elif bl_pr_ok "$2"; then
               PR=$2
           else
               no_pr not-a-holding "the report capture names [$2], not a pull request"
           fi ;;
        1) no_pr no-report "no valid REPORT capture from the latest entry into report_facts" ;;
        *) echo "$PROG: the REPORT capture could not be read" >&2; exit 2 ;;
    esac
fi
if [ -z "$TOKEN" ] && [ -z "$REPO" ]; then
    REPO=$(bl_unit_repo "$SESSION" "$PR")
    case $? in
        0) ;;
        1) stopped unlinked no-holding "no holding in the record links pull request #$PR (it may have been removed), so its repository is unknown" ;;
        3) stopped unlinked several-holdings "holdings link pull request #$PR in more than one repository, so it can't be told which" ;;
        4) stopped unlinked bad-link "the holding linking pull request #$PR names a repository that isn't owner/repo" ;;
        *) stopped board-unreadable record-read "the record's holdings could not be read" ;;
    esac
fi

if [ -z "$TOKEN" ]; then
    bash "$HERE/board-verdict.sh" --repo "$REPO" --pr "$PR" > "$T" || { echo "$PROG: board-verdict.sh failed" >&2; exit 2; }
    V=$(jq -r '.verdict // ""' "$T")
    H=$(jq -r '.head // ""' "$T")
    case "$V" in
        verified) bl_sha_ok "$H" || { echo "$PROG: verified without a head" >&2; exit 2; }
                  TOKEN="verified $PR $H" ;;
        unverified|pending|actions-green) TOKEN="$V $PR none" ;;
        error:pr-state) TOKEN="not-open $PR none" ;;
        error:board-read|error:deadline) TOKEN="board-unreadable $PR none" ;;
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
