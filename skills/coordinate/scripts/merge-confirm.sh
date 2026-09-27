#!/usr/bin/env bash
# merge-confirm.sh -- the check action of merge_confirm: did the merge the
# coordinator attempted land the verified head? Read-only.
#
# Usage: merge-confirm.sh --session S [--pr N] [--repo R] [--no-seal]
#
# The pull request and the head come from land's own capture (LAND, sealed at
# the latest entry into land, reading `permit <pr> <sha>`), never from an
# argument; --pr only checks that the capture names that number. It reads
# the pull request (gh pr view --json state,files) and, when it is MERGED,
# compares every changed file's blob on the default branch with its blob at
# <sha> (a file the pull request deleted must be absent on both).
#
# Token: `merged <pr> <sha>` when MERGED and every blob matches, else
# `unconfirmed <pr> <sha>` (not merged yet, or the default branch doesn't
# hold the verified content); sealed to the latest entry into merge_confirm
# (captured as MERGE_CONFIRM). The repository is the one the record's
# Holdings row for #<pr> links; --repo overrides it, for tests. --no-seal
# (tests) prints the bare token.
#
# Exit codes: 0 a token printed; 2 no valid land capture, or a read failed;
# 64 usage.
set -uo pipefail

PROG=merge-confirm
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

CAP=$(bl_capture "$SESSION" LAND land) || { echo "$PROG: no valid land capture" >&2; exit 2; }
set -f; set -- $CAP; set +f
if [ $# -ne 3 ] || [ "$1" != permit ] || ! bl_pr_ok "$2" || ! bl_sha_ok "$3"; then
    echo "$PROG: land's capture reads [$CAP], not \`permit <pr> <sha>\`" >&2
    exit 2
fi
if [ -n "$PR" ] && [ "$PR" != "$2" ]; then
    echo "$PROG: land's capture names #$2, not #$PR" >&2
    exit 2
fi
PR=$2 SHA=$3

if [ -z "$REPO" ]; then
    REPO=$(bl_unit_repo "$SESSION" "$PR") || exit 2
fi

R=$(bl_merge_compare "$REPO" "$PR" "$SHA") || { echo "$PROG: a read failed" >&2; exit 2; }
case "$R" in
    merged) TOKEN="merged $PR $SHA" ;;
    *) TOKEN="unconfirmed $PR $SHA" ;;
esac
bl_seal "$SESSION" merge_confirm "$TOKEN" "$NO_SEAL" || exit 2
