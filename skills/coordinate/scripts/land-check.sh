#!/usr/bin/env bash
# land-check.sh -- the check action of land: may the verified head be merged,
# now? Read-only; the merge itself is land-merge.sh, run by the coordinator.
#
# Usage: land-check.sh --session S [--pr N] [--repo R] [--no-seal]
#
# 1. The unit's verify capture: the latest VERIFIED capture (with --pr, the
#    latest naming #N), whose seal must check against verify_board at any
#    visit, and which must read `verified <pr> <sha>`. No such capture means
#    the run can't be at land: exit 2.
# 2. The head, re-read live: board-verdict.sh --head-only. A head other than
#    <sha> is `moved <pr> <sha> <new>`.
# 3. The merge state (gh pr view --json mergeStateStatus): DIRTY is
#    `dirty <pr>`.
# 4. The merge posture: the start's POSTURE capture narrowed by a fresh
#    posture-read.sh (board-lib.sh's bl_merge_posture): `permit <pr> <sha>`,
#    `deny <pr> <sha>` or `confirm <pr> <sha>`.
# The token is sealed to the latest entry into land (captured as LAND).
#
# The repository is the one the record's Holdings row for #<pr> links;
# --repo overrides it, for tests. --no-seal (tests) prints the bare token.
#
# Exit codes: 0 a token printed; 2 no valid verify capture, or a read failed;
# 64 usage.
set -uo pipefail

PROG=land-check
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

if [ -n "$PR" ]; then
    CAP=$(bl_capture "$SESSION" VERIFIED verify_board --any-visit --for "$PR")
else
    CAP=$(bl_capture "$SESSION" VERIFIED verify_board --any-visit)
fi
[ $? -eq 0 ] || { echo "$PROG: no valid verify capture: this run can't be at land" >&2; exit 2; }
set -f; set -- $CAP; set +f
if [ $# -ne 3 ] || [ "$1" != verified ] || ! bl_pr_ok "$2" || ! bl_sha_ok "$3"; then
    echo "$PROG: the verify capture reads [$CAP], not a verified head" >&2
    exit 2
fi
PR=$2 SHA=$3

if [ -z "$REPO" ]; then
    REPO=$(bl_unit_repo "$SESSION" "$PR") || exit 2
fi

HO=$(bash "$HERE/board-verdict.sh" --repo "$REPO" --pr "$PR" --head-only) || { echo "$PROG: the head re-read failed" >&2; exit 2; }
V=$(printf '%s' "$HO" | jq -r '.verdict // ""')
NOW=$(printf '%s' "$HO" | jq -r '.head // ""')
case "$V" in
    head) ;;
    error:head-moved)
        # The ref moved while it was read: whichever of the two isn't the
        # verified head is the new one.
        [ "$NOW" = "$SHA" ] && NOW=$(printf '%s' "$HO" | jq -r '.ref // ""') ;;
    *) echo "$PROG: the head re-read ended in [$V]" >&2; exit 2 ;;
esac
bl_sha_ok "$NOW" || { echo "$PROG: the head re-read gave no sha" >&2; exit 2; }
if [ "$NOW" != "$SHA" ]; then
    bl_seal "$SESSION" land "moved $PR $SHA $NOW" "$NO_SEAL" || exit 2
    exit 0
fi

MS=$(mktemp "${TMPDIR:-/tmp}/land-check.XXXXXX") || exit 2
trap 'rm -f "$MS" "$MS.err" "$MS.fail"' EXIT
bl_gh "$MS" pr view "$PR" --repo "$REPO" --json mergeStateStatus || { echo "$PROG: the merge state read failed" >&2; exit 2; }
STATE=$(jq -r '.mergeStateStatus // ""' "$MS" 2>/dev/null)
[[ $STATE =~ ^[A-Z_]+$ ]] || { echo "$PROG: merge state [$STATE]" >&2; exit 2; }
if [ "$STATE" = DIRTY ]; then
    bl_seal "$SESSION" land "dirty $PR" "$NO_SEAL" || exit 2
    exit 0
fi

P=$(bl_merge_posture "$SESSION") || exit 2
bl_seal "$SESSION" land "$P $PR $SHA" "$NO_SEAL" || exit 2
