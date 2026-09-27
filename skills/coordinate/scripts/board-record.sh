#!/usr/bin/env bash
# board-record.sh -- the check action of verify_board: read the board at a
# pull request's head with board-verdict.sh, keep the full JSON as data in
# koto context key coord/board.json, and print one sealed verdict token for
# the state's gate (captured as VERIFIED).
#
# Usage: board-record.sh --session S --pr N [--repo R] [--no-seal]
#
# It refuses (exit 2, nothing read from GitHub) unless the session log shows
# the prediction: an evidence_submitted in state `verify` after the latest
# entry into `verify`. The board is read after the prediction, never before.
#
# The repository is the one the record's Holdings row for #N links
# (record-holding.sh --list); --repo overrides it, for tests.
#
# Token: `verified <pr> <head>`, `unverified <pr> none` or `pending <pr>
# none`, sealed to the latest entry into verify_board. Only a verified token
# carries a head, so nothing downstream can land an unverified one; the
# reasons, skipped jobs and superseded attempts are in coord/board.json for
# the verify report. An error verdict (a read failed, the deadline, a pull
# request that isn't open) exits 2, so koto takes the action-failure path
# and the state re-runs the read.
#
# --no-seal (tests): print the bare token and write no context key.
#
# Exit codes: 0 a token printed; 2 refused, a read failed or an error
# verdict; 64 usage.
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
bl_session_ok "$SESSION" && bl_pr_ok "$PR" || usage
[ -z "$REPO" ] || bl_repo_ok "$REPO" || usage

LOG=$(bl_log "$SESSION") || { echo "$PROG: no readable log for $SESSION" >&2; exit 2; }
if ! jq -s -e '
    [ .[] | select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound") and .payload.to == "verify") | .seq ] as $e
    | ($e | max) as $last
    | $last != null and any(.[]; .type == "evidence_submitted" and .payload.state == "verify" and .seq > $last)' "$LOG" >/dev/null 2>&1; then
    echo "$PROG: refused: the log shows no prediction submitted since the latest arrival at verify" >&2
    exit 2
fi

if [ -z "$REPO" ]; then
    REPO=$(bl_unit_repo "$SESSION" "$PR") || exit 2
fi

T=$(mktemp "${TMPDIR:-/tmp}/board-record.XXXXXX") || exit 2
trap 'rm -f "$T"' EXIT
bash "$HERE/board-verdict.sh" --repo "$REPO" --pr "$PR" > "$T" || { echo "$PROG: board-verdict.sh failed" >&2; exit 2; }
V=$(jq -r '.verdict // ""' "$T" 2>/dev/null)
H=$(jq -r '.head // ""' "$T" 2>/dev/null)
case "$V" in
    verified) bl_sha_ok "$H" || { echo "$PROG: verified without a head" >&2; exit 2; }
              TOKEN="verified $PR $H" ;;
    unverified|pending) TOKEN="$V $PR none" ;;
    *) echo "$PROG: the board read ended in [$V]: $(jq -c '[.reasons[]? | .code + (if .detail then ": " + .detail else "" end)]' "$T" 2>/dev/null)" >&2
       exit 2 ;;
esac

if [ "$NO_SEAL" = 0 ]; then
    "$KOTO" context add "$SESSION" coord/board.json --from-file "$T" >/dev/null 2>&1 || {
        echo "$PROG: could not write coord/board.json" >&2; exit 2; }
fi
bl_seal "$SESSION" verify_board "$TOKEN" "$NO_SEAL" || exit 2
