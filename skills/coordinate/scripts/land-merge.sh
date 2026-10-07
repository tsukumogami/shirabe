#!/usr/bin/env bash
# land-merge.sh -- agent-run from land_merge (and, with --closeout, from a
# rotation's or predecessor's close-out step): merge the verified head, and
# only that, through skills/execute/scripts/merge-exec.sh.
#
# Usage: land-merge.sh --session S [--closeout] [--repo R]
#
# Before anything is merged, in order, each refusal exiting 10 with nothing
# called:
#   1. provenance: coord-log.sh provenance (the session came from this
#      plugin's coordinate.md);
#   2. no directed transition anywhere in the run (coord-log.sh
#      directed-since 0), since before koto 0.14.0 `koto next --to` skipped gates (koto#251);
#   3. the check's own capture, read from the log here, never taken as an
#      argument: LAND, sealed at the latest entry into land, reading
#      `permit <pr> <sha>`. With --closeout: the latest valid of
#      ROTATION_CLOSE and PREDECESSOR_CLOSE, sealed at the latest entry into
#      rotation_close or predecessor_close, reading `land <pr> <sha>`;
#   4. the merge posture, re-read now and narrowed by the start's read
#      (board-lib.sh's bl_merge_posture), must be permit. A hook that matches
#      the typed command never sees a script that merges inside itself, so
#      this asks the posture the question the hook would have answered.
#   4a. (not --closeout) the record's holds on the pull request, re-read live
#      (board-lib.sh's bl_holds_on): every one met. A hold recorded after
#      the land check stops the merge here;
#   5. the squash message: squash-message.sh over the pull request's live
#      title and body (gh pr view --json title,body) must build, so the
#      commit carries Part 1 and never the reviewer context below it. A
#      close-out's record pull request has a fixed Part 1, built the same way.
# Then it runs merge-exec.sh <repo> <pr> <sha> <message-file>, which
# recomputes its own verdict and merges with --match-head-commit <sha>, so
# GitHub refuses a head that moved after the check, and with the message as
# --subject and --body-file. This script never calls `gh pr merge` itself.
#
# The repository: a unit's is the one the record's Holdings row for #<pr>
# links; a close-out's is the host. --repo overrides either, for tests.
# merge-exec.sh is always the sibling skill's, found from this script's own
# directory; nothing in the environment can name another one.
#
# Exit codes: 0 merge-exec.sh reported merge-called (its line on stdout);
# 10 refused; 11 merge-exec.sh refused or failed (its line, if any, on
# stdout); 64 usage.
set -uo pipefail

PROG=land-merge
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/board-lib.sh"

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
refuse() { echo "$PROG: refused: $*" >&2; exit 10; }
SESSION= REPO= CLOSEOUT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --closeout) CLOSEOUT=1; shift ;;
        *) usage ;;
    esac
done
bl_session_ok "$SESSION" || usage
[ -z "$REPO" ] || bl_repo_ok "$REPO" || usage

bash "$HERE/coord-log.sh" provenance --session "$SESSION" >/dev/null 2>&1 \
    || refuse "the session's provenance doesn't check (coord-log.sh provenance)"
DIRECTED=$(bash "$HERE/coord-log.sh" directed-since --session "$SESSION" --from 0 2>/dev/null)
case $? in
    0) ;;
    1) refuse "the run has a directed transition ($(printf '%s' "$DIRECTED" | head -1)); restart the run" ;;
    *) refuse "the session log can't be read" ;;
esac

# capture_seq <NAME> <state>: the latest capture NAME, if its seal checks
# against the latest entry into <state> (coord-log.sh capture --state), as
# "<seq> <token>".
capture_seq() {
    local cap seal
    cap=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name "$1" --state "$2" 2>/dev/null) || return 1
    case "$cap" in *' sealed:'*) ;; *) return 1 ;; esac
    seal=${cap##* sealed:}
    printf '%s %s\n' "${seal%%:*}" "${cap% sealed:*}"
}

if [ "$CLOSEOUT" = 1 ]; then
    WANT=land
    BEST= BESTSEQ=-1
    for pair in ROTATION_CLOSE:rotation_close PREDECESSOR_CLOSE:predecessor_close; do
        got=$(capture_seq "${pair%%:*}" "${pair#*:}") || continue
        seq=${got%% *}
        case "$seq" in ''|*[!0-9]*) continue ;; esac
        if [ "$seq" -gt "$BESTSEQ" ]; then BESTSEQ=$seq; BEST=${got#* }; fi
    done
    [ -n "$BEST" ] || refuse "no close-out capture checks against the latest entry into its state"
    TOKEN=$BEST
else
    WANT=permit
    got=$(capture_seq LAND land) || refuse "land's capture is absent or stale (not sealed at the latest entry into land)"
    TOKEN=${got#* }
fi
set -f; set -- $TOKEN; set +f
if [ $# -ne 3 ] || [ "$1" != "$WANT" ] || ! bl_pr_ok "$2" || ! bl_sha_ok "$3"; then
    refuse "the capture reads [$TOKEN], not \`$WANT <pr> <sha>\`"
fi
PR=$2 SHA=$3

if [ -z "$REPO" ]; then
    if [ "$CLOSEOUT" = 1 ]; then
        REPO=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.HOST_REPO // ""')
        bl_repo_ok "$REPO" || refuse "no host repository in the session's variables"
    else
        REPO=$(bl_unit_repo "$SESSION" "$PR") || refuse "can't tell pull request #$PR's repository from the record"
    fi
fi

P=$(bl_merge_posture "$SESSION") || refuse "the posture re-read failed"
[ "$P" = permit ] || refuse "the merge posture is $P now; hand the merge to the human"

# The holds, re-read now as the posture is: one recorded after the land check
# still stops the merge. A close-out merges the coordinator's own record,
# which no hold is on.
if [ "$CLOSEOUT" = 0 ]; then
    HOLDS=$(bl_holds_on "$SESSION" "$REPO" "$PR") || refuse "the record's holds couldn't be re-read"
    STANDING=$(printf '%s' "$HOLDS" | jq -r '[.[] | select(.state != "met") | "\(.hold) (\(.until), \(.state))"] | join(", ")')
    [ -z "$STANDING" ] || refuse "a hold stands on #$PR now: $STANDING; go back through verify"
fi

# The squash message, built again from the live title and Part 1, so the
# commit carries Part 1 and never the reviewer context below it.
MS=$(mktemp "${TMPDIR:-/tmp}/land-merge.XXXXXX") || refuse "no temporary file"
trap 'rm -f "$MS" "$MS".*' EXIT
bl_gh "$MS" pr view "$PR" --repo "$REPO" --json title,body || refuse "the pull request's title and body couldn't be read"
jq -r '.body // ""' "$MS" > "$MS.body" || refuse "the pull request's body couldn't be read"
bash "$HERE/squash-message.sh" --title "$(jq -r '.title // ""' "$MS")" "$MS.body" > "$MS.msg" \
    || refuse "the squash message couldn't be built from the title and Part 1"

OUT=$(bash "$HERE/../../execute/scripts/merge-exec.sh" "$REPO" "$PR" "$SHA" "$MS.msg")
RC=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT"
if [ "$RC" -eq 0 ]; then
    case "$OUT" in merge-called:*) exit 0 ;; esac
fi
echo "$PROG: merge-exec.sh exited $RC" >&2
exit 11
