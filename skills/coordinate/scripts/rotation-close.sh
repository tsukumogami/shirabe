#!/usr/bin/env bash
# rotation-close.sh -- the rotation close-out's GitHub writes, one step per
# run. Agent-run from rotation_step, predecessor_step, rotation_done and
# predecessor_done; never a default action or a gate. Every step re-reads the
# record pull request first and refuses when the read disagrees with the write.
#
# The pull request is the run's own record (coord-log.sh run-facts) or, with
# --predecessor, the one the run's HANDOFF capture names. It must be a
# same-repository pull request from coordinate/discipline-<name>.
#
#   --step handoff --file F   F must be a canonical handoff for this discipline
#                             (record-parse.sh --format handoff). Own rotation:
#                             not a predecessor copy. --predecessor: equal to
#                             the handoff re-rendered from the predecessor's
#                             live body (predecessor-handoff.sh --out), so the
#                             copy is committed unedited. The pull request must
#                             be open. F is committed to the record branch
#                             through the contents API as
#                             docs/disciplines/<name>.md, with the existing
#                             blob's sha when it overwrites, and the message
#                             `docs(coordinate): <name> rotation handoff <date>`.
#   --step ready              the pull request is open and a draft; then
#                             gh pr ready.
#   --step delete-branch      the pull request is MERGED; then the branch ref
#                             is deleted. A branch already gone is done.
#
# Before any step (record-common.sh lib_write_guard): the session must pass
# coord-log.sh provenance, be the scope's one live session, and have no
# directed transition (`koto next --to`) in the run, else exit 10.
#
# Usage:
#   rotation-close.sh --session S --step handoff|ready|delete-branch [--file F] [--predecessor]
#   ... --scope discipline --name N --repo O/R --ref N [--skip-session-checks]   (tests)
#
# Exit codes: 0 done (one line on stdout says what); 10 refused by the
# pre-read, provenance, a session that isn't the live one, or a directed
# transition; 11 the write failed; 2 a read failed; 64 usage.
#
# GitHub reads: gh pr view <n> --repo R --json state,isDraft,headRefName,isCrossRepository;
# gh api --method GET "repos/R/contents/docs/disciplines/<name>.md?ref=<branch>" --jq .sha;
# gh api --method GET repos/R/branches/coordinate%2Fdiscipline-<name>.
# GitHub writes: gh api --method PUT repos/R/contents/docs/disciplines/<name>.md;
# gh pr ready <n> --repo R; gh api --method DELETE repos/R/git/refs/heads/coordinate/discipline-<name>.
set -uo pipefail

PROG=rotation-close
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= STEP= FILE=
SKIP_CHECKS=0 PRED=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --step) [ $# -ge 2 ] || usage; STEP=$2; shift 2 ;;
        --file) [ $# -ge 2 ] || usage; FILE=$2; shift 2 ;;
        --predecessor) PRED=1; shift ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$STEP" in
    handoff) [ -n "$FILE" ] && [ -r "$FILE" ] || usage ;;
    ready|delete-branch) [ -z "$FILE" ] || usage ;;
    *) usage ;;
esac
. "$HERE/record-common.sh"
lib_facts
[ "$SCOPE" = discipline ] || { echo "$PROG: a rotation close-out is discipline scope only" >&2; exit 64; }
lib_write_guard

refuse() { echo "$PROG: refused: $*" >&2; exit 10; }

if [ "$OVERRIDE" = 1 ]; then
    [[ $REF =~ $RE_NUM ]] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
elif [ "$PRED" = 1 ]; then
    [ -z "$REF" ] || usage
    HC=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name HANDOFF --state predecessor_handoff 2>/dev/null)
    case $? in
        0) ;;
        1) refuse "the run has no sealed predecessor_handoff capture" ;;
        *) lib_die2 "cannot read the session log" ;;
    esac
    set -f; set -- $HC; set +f
    [ "${1-}" = rendered ] || refuse "the predecessor's handoff was not rendered"
    REF=${2-}
    [[ $REF =~ $RE_NUM ]] || refuse "the HANDOFF capture names no pull request"
else
    lib_run_ref || refuse "the run has no found record"
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/rotation-close.XXXXXX")
trap 'rm -rf "$T"' EXIT

gh pr view "$REF" --repo "$REPO" --json state,isDraft,headRefName,isCrossRepository > "$T/pr.json" 2> "$T/pr.err" < /dev/null \
    || lib_die2 "cannot read pull request #$REF: $(lib_scrub < "$T/pr.err")"
PRSTATE=$(jq -r '.state // ""' "$T/pr.json")
DRAFT=$(jq -r '.isDraft // false' "$T/pr.json")
[ "$(jq -r '.headRefName // ""' "$T/pr.json")" = "$BRANCH" ] && [ "$(jq -r '.isCrossRepository' "$T/pr.json")" = false ] \
    || refuse "#$REF is not a same-repository pull request from $BRANCH"
HANDOFF_PATH="docs/disciplines/$NAME.md"

case "$STEP" in
handoff)
    [ "$PRSTATE" = OPEN ] || refuse "#$REF is $PRSTATE, not open"
    bash "$HERE/record-parse.sh" --format handoff "$FILE" > "$T/file.json" 2> "$T/file.err" \
        || refuse "$FILE is not a canonical handoff: $(lib_scrub < "$T/file.err" | head -1)"
    [ "$(jq -r '.scope.name' "$T/file.json")" = "$NAME" ] || refuse "$FILE is the handoff of another discipline"
    if [ "$PRED" = 1 ]; then
        bash "$HERE/predecessor-handoff.sh" --scope discipline --name "$NAME" --repo "$REPO" --ref "$REF" \
            --out "$T/expected.md" --no-seal > "$T/expected.tok" 2> "$T/expected.err" \
            || lib_die2 "cannot re-render the predecessor's handoff: $(lib_scrub < "$T/expected.err")"
        case "$(cat "$T/expected.tok")" in rendered\ *) ;; *) refuse "the predecessor's live body no longer renders a handoff" ;; esac
        bash "$HERE/record-parse.sh" --format handoff "$T/expected.md" > "$T/expected.json" 2>/dev/null || lib_die2 "the re-rendered handoff does not parse"
        [ "$(jq -S -c . "$T/file.json")" = "$(jq -S -c . "$T/expected.json")" ] \
            || refuse "$FILE is not the predecessor's handoff as rendered from its live body; commit it unedited"
    else
        jq -e '.predecessor_copy == null' "$T/file.json" > /dev/null || refuse "the rotation's own handoff can't be a predecessor copy"
    fi
    DATE=$(jq -r '.rotation.date' "$T/file.json")
    SHA=
    if SHA=$(gh api --method GET "repos/$REPO/contents/$HANDOFF_PATH?ref=$BRANCH" --jq .sha 2> "$T/sha.err" < /dev/null); then
        [[ $SHA =~ ^[0-9a-f]{40}$ ]] || lib_die2 "the existing file's blob sha is not a sha"
    else
        grep -q 'HTTP 404' "$T/sha.err" || lib_die2 "cannot read $HANDOFF_PATH on $BRANCH: $(lib_scrub < "$T/sha.err")"
        SHA=
    fi
    base64 < "$FILE" | tr -d '\n\r ' > "$T/content"
    set -- --method PUT "repos/$REPO/contents/$HANDOFF_PATH" \
        -f "message=docs(coordinate): $NAME rotation handoff $DATE" \
        -f "content=$(cat "$T/content")" -f "branch=$BRANCH"
    [ -n "$SHA" ] && set -- "$@" -f "sha=$SHA"
    gh api "$@" > /dev/null 2> "$T/put.err" < /dev/null \
        || { echo "$PROG: the commit failed: $(lib_scrub < "$T/put.err")" >&2; exit 11; }
    echo "committed $HANDOFF_PATH to $BRANCH"
    ;;
ready)
    [ "$PRSTATE" = OPEN ] || refuse "#$REF is $PRSTATE, not open"
    [ "$DRAFT" = true ] || refuse "#$REF is not a draft"
    gh pr ready "$REF" --repo "$REPO" > /dev/null 2> "$T/ready.err" < /dev/null \
        || { echo "$PROG: gh pr ready failed: $(lib_scrub < "$T/ready.err")" >&2; exit 11; }
    echo "ready #$REF"
    ;;
delete-branch)
    [ "$PRSTATE" = MERGED ] || refuse "#$REF is $PRSTATE, not merged"
    if ! gh api --method GET "repos/$REPO/branches/coordinate%2Fdiscipline-$NAME" > /dev/null 2> "$T/br.err" < /dev/null; then
        grep -q 'HTTP 404' "$T/br.err" || lib_die2 "cannot read $BRANCH: $(lib_scrub < "$T/br.err")"
        echo "deleted $BRANCH (already gone)"
        exit 0
    fi
    gh api --method DELETE "repos/$REPO/git/refs/heads/$BRANCH" > /dev/null 2> "$T/del.err" < /dev/null \
        || { echo "$PROG: the branch delete failed: $(lib_scrub < "$T/del.err")" >&2; exit 11; }
    echo "deleted $BRANCH"
    ;;
esac
